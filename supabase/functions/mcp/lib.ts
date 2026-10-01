import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@5";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
export const ISSUER = `${SUPABASE_URL}/auth/v1`;
export const MCP_URL = `${SUPABASE_URL}/functions/v1/mcp`;
export const RESOURCE_METADATA_URL = `${MCP_URL}/.well-known/oauth-protected-resource`;

function publicKey(): string {
  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys);
      if (parsed.default) return parsed.default;
      const first = Object.values(parsed)[0];
      if (typeof first === "string") return first;
    } catch { /* fall through */ }
  }
  return Deno.env.get("SUPABASE_ANON_KEY")!;
}

const PUBLIC_KEY = publicKey();
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks.json`));

// Comma-separated auth user ids allowed to use this server (defense in depth on top of RLS
// and disabled sign-ups). If unset, nobody is allowed.
const ALLOWED_USER_IDS = (Deno.env.get("CAREER_RAG_ALLOWED_USER_IDS") ?? "")
  .split(",").map((s) => s.trim()).filter(Boolean);

export type Claims = JWTPayload & { email?: string; client_id?: string };
export type AuthResult =
  | { ok: true; token: string; claims: Claims }
  | { ok: false; status: number; error: string; description: string };

export async function authenticate(req: Request): Promise<AuthResult> {
  const header = req.headers.get("authorization") ?? "";
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) return { ok: false, status: 401, error: "invalid_request", description: "Missing bearer token" };
  const token = m[1].trim();
  try {
    const { payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: "authenticated" });
    if (payload.role !== "authenticated" || !payload.sub) {
      return { ok: false, status: 401, error: "invalid_token", description: "Token is not a user token" };
    }
    if (!ALLOWED_USER_IDS.includes(payload.sub)) {
      return { ok: false, status: 403, error: "insufficient_scope", description: "This user is not allowed to use this server" };
    }
    return { ok: true, token, claims: payload as Claims };
  } catch (_e) {
    return { ok: false, status: 401, error: "invalid_token", description: "Invalid or expired token" };
  }
}

// Database client acting AS the user: every query goes through RLS. No service-role key is used.
export function userClient(token: string): SupabaseClient {
  return createClient(SUPABASE_URL, PUBLIC_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// ---------------------------------------------------------------------------
// Embeddings: Supabase built-in gte-small (384 dims, English). No external AI APIs.
// ---------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
const model = new (globalThis as any).Supabase.ai.Session("gte-small");

export async function embed(text: string): Promise<string> {
  const out = await model.run(text.slice(0, 2000), { mean_pool: true, normalize: true });
  return `[${(out as number[]).join(",")}]`;
}

/** Embed chunks whose embedding is missing/stale. Persists in small batches and stops at a
 *  count/time budget to stay within edge worker CPU/memory limits; callers re-run to continue. */
export async function embedPending(db: SupabaseClient, max = 8, budgetMs = 15000) {
  const started = Date.now();
  const { data, error } = await db.from("knowledge_chunks")
    .select("id, title, content, content_hash").is("embedding", null).limit(max);
  if (error) throw new Error(`embedPending: ${error.message}`);
  let embedded = 0;
  for (const c of data ?? []) {
    if (Date.now() - started > budgetMs) break;
    const item = { id: c.id, content_hash: c.content_hash, embedding: await embed(`${c.title ?? ""}. ${c.content}`) };
    const { error: e2 } = await db.rpc("set_chunk_embeddings", { items: [item] });
    if (e2) throw new Error(`set_chunk_embeddings: ${e2.message}`);
    embedded++;
  }
  const { count } = await db.from("knowledge_chunks").select("id", { count: "exact", head: true }).is("embedding", null);
  return { embedded, remaining: count ?? 0 };
}

// ---------------------------------------------------------------------------
// Light heuristics (no LLM): flag text that does not look like English.
// ---------------------------------------------------------------------------
const NON_EN_WORDS = new Set([
  "el", "la", "los", "las", "del", "que", "y", "en", "con", "para", "por", "una", "un", "se", "al", "lo",
  "como", "más", "pero", "sus", "fue", "trabajé", "hice", "proyecto", "empresa", "equipo", "desarrollé",
  "der", "die", "und", "mit", "für", "le", "les", "des", "et", "avec", "pour", "il", "di", "che", "per",
]);
export function looksNonEnglish(s?: string | null): boolean {
  if (!s) return false;
  if (/[ñ¿¡]/i.test(s)) return true;
  const words = s.toLowerCase().match(/[\p{L}]+/gu) ?? [];
  if (words.length < 4) return false;
  const hits = words.filter((w) => NON_EN_WORDS.has(w)).length;
  return hits >= 3 && hits / words.length > 0.12;
}

export const json = (data: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", ...CORS, ...extra } });

export const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-allow-headers": "authorization, content-type, accept, mcp-session-id, mcp-protocol-version, last-event-id",
  "access-control-expose-headers": "www-authenticate, mcp-session-id, mcp-protocol-version",
};

export function toolResult(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 1) }] };
}

export function toolError(message: string, details?: unknown) {
  return {
    isError: true,
    content: [{ type: "text" as const, text: JSON.stringify({ error: message, ...(details ? { details } : {}) }, null, 1) }],
  };
}
