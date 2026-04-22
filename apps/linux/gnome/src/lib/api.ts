import Soup from 'gi://Soup?version=3.0';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import { refreshAccessToken } from './oauth.js';
import { loadTokens, storeTokens } from './auth.js';

export type UsageStatus = 'ok' | 'offline' | 'rate-limited' | 'unauthenticated';

export type UsageSnapshot = {
  session: { percent: number; resetsAt: Date | null };
  weekly: { percent: number; resetsAt: Date | null };
  status: UsageStatus;
  fetchedAt: Date;
};

export interface UsageSource {
  fetch(): Promise<UsageSnapshot>;
}

const USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
const ANTHROPIC_BETA = 'oauth-2025-04-20';

type UsageResponse = {
  five_hour?: { utilization: number; resets_at: string } | null;
  seven_day?: { utilization: number; resets_at: string } | null;
};

function emptySnapshot(status: UsageStatus): UsageSnapshot {
  return {
    session: { percent: 0, resetsAt: null },
    weekly: { percent: 0, resetsAt: null },
    status,
    fetchedAt: new Date(),
  };
}

function parseResetsAt(v?: string | null): Date | null {
  if (!v) return null;
  const d = new Date(v);
  return Number.isFinite(d.getTime()) ? d : null;
}

function mapResponse(body: UsageResponse): UsageSnapshot {
  return {
    session: {
      percent: body.five_hour?.utilization ?? 0,
      resetsAt: parseResetsAt(body.five_hour?.resets_at),
    },
    weekly: {
      percent: body.seven_day?.utilization ?? 0,
      resetsAt: parseResetsAt(body.seven_day?.resets_at),
    },
    status: 'ok',
    fetchedAt: new Date(),
  };
}

export class ClaudeBarSource implements UsageSource {
  private _session: Soup.Session;

  constructor() {
    this._session = new Soup.Session();
    this._session.user_agent = 'claudebar-gnome-extension/0.1';
    this._session.timeout = 15;
  }

  async fetch(): Promise<UsageSnapshot> {
    let tokens = await loadTokens();
    if (!tokens) return emptySnapshot('unauthenticated');

    let result = await this._call(tokens.access_token);

    if (result.kind === 'unauthorized' && tokens.refresh_token) {
      try {
        const refreshed = await refreshAccessToken(tokens.refresh_token);
        tokens = refreshed;
        await storeTokens(refreshed);
        result = await this._call(refreshed.access_token);
      } catch (_e) {
        return emptySnapshot('unauthenticated');
      }
    }

    switch (result.kind) {
      case 'ok':
        return mapResponse(result.body);
      case 'unauthorized':
        return emptySnapshot('unauthenticated');
      case 'rate-limited':
        return emptySnapshot('rate-limited');
      case 'offline':
        return emptySnapshot('offline');
    }
  }

  private _call(accessToken: string): Promise<
    | { kind: 'ok'; body: UsageResponse }
    | { kind: 'unauthorized' }
    | { kind: 'rate-limited' }
    | { kind: 'offline' }
  > {
    return new Promise((resolve) => {
      const msg = Soup.Message.new('GET', USAGE_URL);
      if (!msg) {
        resolve({ kind: 'offline' });
        return;
      }
      const headers = msg.get_request_headers();
      headers.append('Authorization', `Bearer ${accessToken}`);
      headers.append('anthropic-beta', ANTHROPIC_BETA);
      headers.append('Accept', 'application/json');

      this._session.send_and_read_async(
        msg,
        GLib.PRIORITY_DEFAULT,
        null,
        (_session: Soup.Session | null, res: Gio.AsyncResult) => {
          try {
            const bytes = this._session.send_and_read_finish(res);
            const status = msg.get_status();
            if (status === Soup.Status.UNAUTHORIZED) {
              resolve({ kind: 'unauthorized' });
              return;
            }
            if (status === Soup.Status.TOO_MANY_REQUESTS) {
              resolve({ kind: 'rate-limited' });
              return;
            }
            if (status < 200 || status >= 300) {
              resolve({ kind: 'offline' });
              return;
            }
            const text = new TextDecoder('utf-8').decode(bytes.get_data() ?? new Uint8Array());
            const body = JSON.parse(text) as UsageResponse;
            resolve({ kind: 'ok', body });
          } catch (_e) {
            resolve({ kind: 'offline' });
          }
        },
      );
    });
  }
}
