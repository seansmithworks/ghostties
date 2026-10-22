import "server-only";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { supabaseKey, supabaseUrl } from "./env";

/**
 * Server client bound to the request's auth cookies. Reads `cookies()`, so
 * with Cache Components any component calling it must sit behind <Suspense>.
 */
export async function createClient() {
  if (!supabaseUrl || !supabaseKey) return null;
  const cookieStore = await cookies();
  return createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (toSet) => {
        try {
          toSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Called from a Server Component: the proxy refreshes the session.
        }
      },
    },
  });
}
