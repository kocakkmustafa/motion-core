// Browser access for a function the YULAlab site calls directly (for example
// the parental consent page). Only listed origins receive CORS headers; no
// wildcard. Requests without an Origin header (apps, server-to-server) are
// unaffected.

export const DEFAULT_ALLOWED_ORIGINS = ["https://yulalab.com"];

const ALLOW_METHODS = "POST, OPTIONS";
const ALLOW_HEADERS = "authorization, x-client-info, apikey, content-type";
const MAX_AGE_SECONDS = "600";

/** Comma-separated origins, e.g. "https://yulalab.com,https://www.yulalab.com". */
export function allowedOrigins(raw: string | undefined): Set<string> {
  const listed = (raw ?? "")
    .split(",")
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter((origin) => origin.length > 0);
  return new Set(listed.length > 0 ? listed : DEFAULT_ALLOWED_ORIGINS);
}

/** The request's origin when it is allowed, otherwise null. */
export function matchedOrigin(
  request: Request,
  allowed: Set<string>,
): string | null {
  const origin = request.headers.get("Origin");
  return origin !== null && allowed.has(origin) ? origin : null;
}

/** Preflight answer: 204 with CORS headers, or 403 for an unlisted origin. */
export function preflight(request: Request, allowed: Set<string>): Response {
  const origin = matchedOrigin(request, allowed);
  if (origin === null) {
    return new Response(null, { status: 403, headers: { Vary: "Origin" } });
  }
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": ALLOW_METHODS,
      "Access-Control-Allow-Headers": ALLOW_HEADERS,
      "Access-Control-Max-Age": MAX_AGE_SECONDS,
      Vary: "Origin",
    },
  });
}

/** Adds `Vary: Origin` to every response and ACAO for an allowed origin. */
export function withCors(
  request: Request,
  response: Response,
  allowed: Set<string>,
): Response {
  const headers = new Headers(response.headers);
  headers.append("Vary", "Origin");
  const origin = matchedOrigin(request, allowed);
  if (origin !== null) headers.set("Access-Control-Allow-Origin", origin);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
