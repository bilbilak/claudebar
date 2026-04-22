//! Token storage via the FreeDesktop Secret Service API.
//!
//! Works with GNOME Keyring, KWallet, KeePassXC, and anything else that
//! implements `org.freedesktop.secrets`.

use anyhow::{anyhow, Context, Result};
use secret_service::blocking::SecretService;
use secret_service::EncryptionType;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

const SERVICE_LABEL: &str = "ClaudeBar (claudebar)";
const SCHEMA: &str = "org.bilbilak.claudebar";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tokens {
    #[serde(rename = "access_token")]
    pub access_token: String,
    #[serde(
        rename = "refresh_token",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub refresh_token: Option<String>,
    #[serde(
        rename = "expires_at",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub expires_at: Option<i64>,
}

fn attrs() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    m.insert("xdg:schema", SCHEMA);
    m.insert("field", "oauth-tokens");
    m
}

pub fn store(tokens: &Tokens) -> Result<()> {
    let ss = SecretService::connect(EncryptionType::Dh).context("connecting to Secret Service")?;
    let collection = ss
        .get_default_collection()
        .context("getting default collection")?;
    if collection.is_locked().unwrap_or(true) {
        collection
            .unlock()
            .context("unlocking default collection")?;
    }
    let json = serde_json::to_vec(tokens).context("serializing tokens")?;
    collection
        .create_item(SERVICE_LABEL, attrs(), &json, true, "application/json")
        .context("creating secret item")?;
    Ok(())
}

pub fn load() -> Result<Option<Tokens>> {
    let ss = SecretService::connect(EncryptionType::Dh).context("connecting to Secret Service")?;
    let items = ss.search_items(attrs()).context("searching secret items")?;
    let item = items
        .unlocked
        .into_iter()
        .next()
        .or_else(|| items.locked.into_iter().next());
    let Some(item) = item else { return Ok(None) };
    if item.is_locked().unwrap_or(false) {
        item.unlock().context("unlocking secret item")?;
    }
    let secret = item.get_secret().context("reading secret value")?;
    let tokens: Tokens = serde_json::from_slice(&secret)
        .map_err(|e| anyhow!("stored tokens are not valid JSON: {e}"))?;
    Ok(Some(tokens))
}

pub fn clear() -> Result<()> {
    let ss = SecretService::connect(EncryptionType::Dh).context("connecting to Secret Service")?;
    let items = ss.search_items(attrs()).context("searching secret items")?;
    for item in items.unlocked.into_iter().chain(items.locked) {
        item.delete().context("deleting secret item")?;
    }
    Ok(())
}
