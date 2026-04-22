// SPDX-License-Identifier: GPL-3.0-or-later
// Usage snapshot fetch — identical to the GNOME extension's api.ts.

const GLib = imports.gi.GLib;
const Soup = imports.gi.Soup;
const Auth = imports.ui.appletManager.applets["claudebar@bilbilak.org"].auth;
const OAuth = imports.ui.appletManager.applets["claudebar@bilbilak.org"].oauth;

var USAGE_URL = "https://api.anthropic.com/api/oauth/usage";
var ANTHROPIC_BETA = "oauth-2025-04-20";

function emptySnapshot(status) {
    return {
        session: { percent: 0, resetsAt: null },
        weekly: { percent: 0, resetsAt: null },
        status,
        fetchedAt: new Date(),
    };
}

function parseResetsAt(v) {
    if (!v) return null;
    const d = new Date(v);
    return Number.isFinite(d.getTime()) ? d : null;
}

function mapResponse(body) {
    return {
        session: {
            percent: body.five_hour?.utilization ?? 0,
            resetsAt: parseResetsAt(body.five_hour?.resets_at),
        },
        weekly: {
            percent: body.seven_day?.utilization ?? 0,
            resetsAt: parseResetsAt(body.seven_day?.resets_at),
        },
        status: "ok",
        fetchedAt: new Date(),
    };
}

function ClaudeBarSource() {
    this._init();
}

ClaudeBarSource.prototype = {
    _init: function() {
        this._session = new Soup.Session();
        this._session.user_agent = "claudebar-cinnamon/0.1";
        this._session.timeout = 15;
    },

    fetch: async function() {
        let tokens = await Auth.loadTokens();
        if (!tokens) return emptySnapshot("unauthenticated");

        let result = await this._call(tokens.access_token);

        if (result.kind === "unauthorized" && tokens.refresh_token) {
            try {
                const refreshed = await OAuth.refreshAccessToken(tokens.refresh_token);
                tokens = refreshed;
                await Auth.storeTokens(refreshed);
                result = await this._call(refreshed.access_token);
            } catch (_e) {
                return emptySnapshot("unauthenticated");
            }
        }

        switch (result.kind) {
            case "ok": return mapResponse(result.body);
            case "unauthorized": return emptySnapshot("unauthenticated");
            case "rate-limited": return emptySnapshot("rate-limited");
            case "offline": return emptySnapshot("offline");
        }
    },

    _call: function(accessToken) {
        return new Promise((resolve) => {
            const msg = Soup.Message.new("GET", USAGE_URL);
            if (!msg) { resolve({ kind: "offline" }); return; }
            const headers = msg.get_request_headers();
            headers.append("Authorization", `Bearer ${accessToken}`);
            headers.append("anthropic-beta", ANTHROPIC_BETA);
            headers.append("Accept", "application/json");

            this._session.send_and_read_async(msg, GLib.PRIORITY_DEFAULT, null, (_s, res) => {
                try {
                    const bytes = this._session.send_and_read_finish(res);
                    const status = msg.get_status();
                    if (status === 401) { resolve({ kind: "unauthorized" }); return; }
                    if (status === 429) { resolve({ kind: "rate-limited" }); return; }
                    if (status < 200 || status >= 300) { resolve({ kind: "offline" }); return; }
                    const text = new TextDecoder("utf-8").decode(bytes.get_data() ?? new Uint8Array());
                    const body = JSON.parse(text);
                    resolve({ kind: "ok", body });
                } catch (_e) {
                    resolve({ kind: "offline" });
                }
            });
        });
    },
};
