// Career RAG remote MCP server (Streamable HTTP, stateless).
// Auth: OAuth 2.1 via Supabase Auth (authorization server) — this function is the protected resource.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { WebStandardStreamableHTTPServerTransport } from "npm:@modelcontextprotocol/sdk@1.25.3/server/webStandardStreamableHttp.js";
import { authenticate, CORS, ISSUER, json, MCP_URL, RESOURCE_METADATA_URL, userClient } from "./lib.ts";
import { buildServer } from "./tools.ts";

const protectedResourceMetadata = {
  resource: MCP_URL,
  authorization_servers: [ISSUER],
  bearer_methods_supported: ["header"],
  scopes_supported: ["openid", "email", "profile"],
  resource_name: "Career RAG",
};

Deno.serve(async (req) => {
  const url = new URL(req.url);
  // Path inside the function: "/mcp", "/mcp/.well-known/...". Normalize.
  const path = url.pathname.replace(/^\/functions\/v1/, "").replace(/^\/mcp/, "") || "/";

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  if (path.startsWith("/.well-known/oauth-protected-resource")) {
    return json(protectedResourceMetadata, 200, { "cache-control": "public, max-age=3600" });
  }
  if (path.startsWith("/.well-known/oauth-authorization-server") || path.startsWith("/.well-known/openid-configuration")) {
    // Convenience for clients that look for AS metadata next to the resource.
    const r = await fetch(`${ISSUER}/.well-known/oauth-authorization-server`);
    return json(await r.json(), r.status);
  }
  if (path !== "/" && path !== "") return json({ error: "not_found" }, 404);

  const auth = await authenticate(req);
  if (!auth.ok) {
    return json({ error: auth.error, error_description: auth.description }, auth.status, {
      "www-authenticate":
        `Bearer resource_metadata="${RESOURCE_METADATA_URL}", error="${auth.error}", error_description="${auth.description}"`,
    });
  }

  const server = buildServer(userClient(auth.token));
  const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  await server.connect(transport);
  try {
    const res = await transport.handleRequest(req);
    const headers = new Headers(res.headers);
    for (const [k, v] of Object.entries(CORS)) headers.set(k, v);
    return new Response(res.body, { status: res.status, headers });
  } catch (e) {
    console.error("mcp error", e);
    return json({ jsonrpc: "2.0", error: { code: -32603, message: "Internal error" }, id: null }, 500);
  }
});
