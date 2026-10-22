"use client";

import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import styles from "./login.module.css";

/** Email magic link, plus the GitHub and Apple providers the backend enables. */
export function LoginForm() {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">(
    "idle",
  );

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const supabase = createClient();
    if (!supabase) return;
    setState("sending");
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin },
    });
    setState(error ? "error" : "sent");
  }

  async function oauth(provider: "github" | "apple") {
    await createClient()?.auth.signInWithOAuth({
      provider,
      options: { redirectTo: window.location.origin },
    });
  }

  if (state === "sent") {
    return (
      <p role="status" className="secondary">
        Check {email} for a sign-in link.
      </p>
    );
  }

  return (
    <div className={styles.form}>
      <form onSubmit={onSubmit} className={styles.row}>
        <label htmlFor="email" className="visually-hidden">
          Email
        </label>
        <input
          id="email"
          type="email"
          required
          autoComplete="email"
          placeholder="you@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className={styles.field}
        />
        <button
          type="submit"
          className={styles.primary}
          disabled={state === "sending"}
        >
          {state === "sending" ? "Sending…" : "Email me a link"}
        </button>
      </form>
      {state === "error" && (
        <p role="alert" className={styles.error}>
          Couldn&apos;t send the link. Try again.
        </p>
      )}
      <div className={styles.providers}>
        <button
          type="button"
          className={styles.secondary}
          onClick={() => oauth("github")}
        >
          Continue with GitHub
        </button>
        <button
          type="button"
          className={styles.secondary}
          onClick={() => oauth("apple")}
        >
          Continue with Apple
        </button>
      </div>
    </div>
  );
}
