import { createClient } from "npm:@supabase/supabase-js@2.117.1";

// A common Motion account belongs to the caller, never to an app ID supplied
// in the request body. The service key remains on the Edge Function only.
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "invalid_request" }, { status: 400 });
  }
  if (
    typeof body !== "object" ||
    body === null ||
    !("confirmation" in body) ||
    body.confirmation !== "DELETE"
  ) {
    return Response.json({ error: "confirmation_required" }, { status: 400 });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceKey) {
    return Response.json({ error: "server_unavailable" }, { status: 503 });
  }

  const auth = createClient(url, publishable, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.slice("Bearer ".length);
  const { data, error: authError } = await auth.auth.getUser(token);
  if (authError || !data.user) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: deleteError } = await admin.auth.admin.deleteUser(
    data.user.id,
  );
  if (deleteError) {
    return Response.json({ error: "deletion_failed" }, { status: 500 });
  }
  return Response.json({ deleted: true });
});
