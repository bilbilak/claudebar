//! Usage snapshot fetch — mirrors the GNOME extension's api.ts exactly.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;

use crate::auth;
use crate::oauth;

const USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";
const ANTHROPIC_BETA: &str = "oauth-2025-04-20";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum Status {
    Ok,
    Offline,
    #[serde(rename = "rate-limited")]
    RateLimited,
    Unauthenticated,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bucket {
    pub percent: f64,
    pub resets_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Snapshot {
    pub session: Bucket,
    pub weekly: Bucket,
    pub status: Status,
    pub fetched_at: DateTime<Utc>,
}

impl Snapshot {
    pub fn empty(status: Status) -> Self {
        Self {
            session: Bucket { percent: 0.0, resets_at: None },
            weekly: Bucket { percent: 0.0, resets_at: None },
            status,
            fetched_at: Utc::now(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct UsageResponse {
    five_hour: Option<ResponseBucket>,
    seven_day: Option<ResponseBucket>,
}

#[derive(Debug, Deserialize)]
struct ResponseBucket {
    utilization: Option<f64>,
    resets_at: Option<String>,
}

enum CallResult {
    Ok(UsageResponse),
    Unauthorized,
    RateLimited,
    Offline,
}

pub fn fetch_snapshot() -> Snapshot {
    let mut tokens = match auth::load() {
        Ok(Some(t)) => t,
        Ok(None) => return Snapshot::empty(Status::Unauthenticated),
        Err(_) => return Snapshot::empty(Status::Unauthenticated),
    };

    let mut result = call(&tokens.access_token);

    if matches!(result, CallResult::Unauthorized) {
        if let Some(refresh) = tokens.refresh_token.clone() {
            match oauth::refresh_access_token(&refresh) {
                Ok(refreshed) => {
                    let _ = auth::store(&refreshed);
                    tokens = refreshed;
                    result = call(&tokens.access_token);
                }
                Err(_) => return Snapshot::empty(Status::Unauthenticated),
            }
        }
    }

    match result {
        CallResult::Ok(body) => map(body),
        CallResult::Unauthorized => Snapshot::empty(Status::Unauthenticated),
        CallResult::RateLimited => Snapshot::empty(Status::RateLimited),
        CallResult::Offline => Snapshot::empty(Status::Offline),
    }
}

fn call(access_token: &str) -> CallResult {
    let client = match reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("claudebar-helper/0.1")
        .build()
    {
        Ok(c) => c,
        Err(_) => return CallResult::Offline,
    };
    let resp = match client
        .get(USAGE_URL)
        .bearer_auth(access_token)
        .header("anthropic-beta", ANTHROPIC_BETA)
        .header("Accept", "application/json")
        .send()
    {
        Ok(r) => r,
        Err(_) => return CallResult::Offline,
    };
    let status = resp.status();
    if status.as_u16() == 401 {
        return CallResult::Unauthorized;
    }
    if status.as_u16() == 429 {
        return CallResult::RateLimited;
    }
    if !status.is_success() {
        return CallResult::Offline;
    }
    match resp.json::<UsageResponse>() {
        Ok(body) => CallResult::Ok(body),
        Err(_) => CallResult::Offline,
    }
}

fn map(body: UsageResponse) -> Snapshot {
    Snapshot {
        session: Bucket {
            percent: body.five_hour.as_ref().and_then(|b| b.utilization).unwrap_or(0.0),
            resets_at: body.five_hour.as_ref().and_then(|b| b.resets_at.as_deref()).and_then(parse_dt),
        },
        weekly: Bucket {
            percent: body.seven_day.as_ref().and_then(|b| b.utilization).unwrap_or(0.0),
            resets_at: body.seven_day.as_ref().and_then(|b| b.resets_at.as_deref()).and_then(parse_dt),
        },
        status: Status::Ok,
        fetched_at: Utc::now(),
    }
}

fn parse_dt(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s).ok().map(|d| d.with_timezone(&Utc))
}
