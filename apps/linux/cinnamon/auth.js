// SPDX-License-Identifier: GPL-3.0-or-later
// Token storage via libsecret — same attributes as the GNOME extension, so
// both can coexist and share the stored tokens.

const Gio = imports.gi.Gio;
const Secret = imports.gi.Secret;

var SCHEMA = new Secret.Schema(
    "org.bilbilak.claudebar",
    Secret.SchemaFlags.NONE,
    { field: Secret.SchemaAttributeType.STRING }
);

var ATTR_TOKENS = { field: "oauth-tokens" };
var LABEL = "ClaudeBar OAuth tokens";

Gio._promisify(Secret, "password_store", "password_store_finish");
Gio._promisify(Secret, "password_lookup", "password_lookup_finish");
Gio._promisify(Secret, "password_clear", "password_clear_finish");

function storeTokens(tokens) {
    return Secret.password_store(
        SCHEMA,
        ATTR_TOKENS,
        Secret.COLLECTION_DEFAULT,
        LABEL,
        JSON.stringify(tokens),
        null
    );
}

function loadTokens() {
    return Secret.password_lookup(SCHEMA, ATTR_TOKENS, null).then((val) => {
        if (!val) return null;
        try {
            const parsed = JSON.parse(val);
            if (typeof parsed.access_token !== "string") return null;
            return {
                access_token: parsed.access_token,
                refresh_token: typeof parsed.refresh_token === "string" ? parsed.refresh_token : null,
                expires_at: typeof parsed.expires_at === "number" ? parsed.expires_at : null,
            };
        } catch (_e) {
            return { access_token: val, refresh_token: null, expires_at: null };
        }
    });
}

function clearTokens() {
    return Secret.password_clear(SCHEMA, ATTR_TOKENS, null);
}
