import Gio from 'gi://Gio';
import Secret from 'gi://Secret?version=1';

const gioAny = Gio as unknown as { _promisify: (proto: any, asyncFn: string, finishFn?: string) => void };
gioAny._promisify(Secret, 'password_store', 'password_store_finish');
gioAny._promisify(Secret, 'password_lookup', 'password_lookup_finish');
gioAny._promisify(Secret, 'password_clear', 'password_clear_finish');

const SCHEMA = new Secret.Schema(
  'org.bilbilak.claudebar',
  Secret.SchemaFlags.NONE,
  { field: Secret.SchemaAttributeType.STRING },
);

const ATTR_TOKENS = { field: 'oauth-tokens' } as const;
const LABEL = 'ClaudeBar OAuth tokens';

export type TokenSet = {
  access_token: string;
  refresh_token: string | null;
  expires_at: number | null;
};

export async function storeTokens(tokens: TokenSet): Promise<void> {
  await (Secret.password_store as any)(
    SCHEMA,
    ATTR_TOKENS,
    Secret.COLLECTION_DEFAULT,
    LABEL,
    JSON.stringify(tokens),
    null,
  );
}

export async function loadTokens(): Promise<TokenSet | null> {
  const val = await (Secret.password_lookup as any)(SCHEMA, ATTR_TOKENS, null);
  if (!val) return null;
  try {
    const parsed = JSON.parse(val) as Partial<TokenSet>;
    if (typeof parsed.access_token !== 'string') return null;
    return {
      access_token: parsed.access_token,
      refresh_token: typeof parsed.refresh_token === 'string' ? parsed.refresh_token : null,
      expires_at: typeof parsed.expires_at === 'number' ? parsed.expires_at : null,
    };
  } catch {
    return { access_token: val, refresh_token: null, expires_at: null };
  }
}

export async function clearTokens(): Promise<void> {
  await (Secret.password_clear as any)(SCHEMA, ATTR_TOKENS, null);
}
