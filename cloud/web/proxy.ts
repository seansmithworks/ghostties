import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import {
  supabaseConfigured,
  supabaseKey,
  supabaseUrl,
} from "@/lib/supabase/env";

// Refreshes the Supabase auth cookie on every request. It does not gate
// routes yet: until the backend lands every page renders stub data, signed
// in or not. Add the redirect to /login here when auth is real.
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  if (!supabaseConfigured) return response;

  const supabase = createServerClient(supabaseUrl!, supabaseKey!, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (toSet) => {
        toSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        toSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });
  await supabase.auth.getUser();
  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|ico)$).*)",
  ],
};
