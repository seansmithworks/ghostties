import { supabaseConfigured } from "@/lib/supabase/env";
import { Ghost } from "@/components/Ghost";
import { LoginForm } from "./LoginForm";
import styles from "./login.module.css";

export const metadata = { title: "Sign in" };

export default function LoginPage() {
  return (
    <div className="canvas-scroll">
      <div className={styles.wrap}>
        <Ghost name="blinky" size={32} />
        <h1 className={styles.title}>Sign in to Ghostties</h1>
        {supabaseConfigured ? (
          <LoginForm />
        ) : (
          <p className="secondary">
            Supabase isn&apos;t configured, so the app is running on stub data.
            Set NEXT_PUBLIC_SUPABASE_URL and
            NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY to turn sign-in on.
          </p>
        )}
      </div>
    </div>
  );
}
