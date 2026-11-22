"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { login, signup, requestPasswordReset, updatePassword, type AuthState } from "@/app/auth/actions";

type Mode = "login" | "signup" | "forgot" | "reset";

function Eye({ visible }: { visible: boolean }) {
  return <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z" /><circle cx="12" cy="12" r="3" />{visible && <path d="m3 3 18 18" />}</svg>;
}

export function AuthForm({ mode = "login", notice, joining = false }: { mode?: Mode; notice?: string; joining?: boolean }) {
  const action = mode === "forgot" ? requestPasswordReset : mode === "reset" ? updatePassword : mode === "signup" ? signup : login;
  const newPassword = mode === "reset" || mode === "signup";
  const [state, formAction, pending] = useActionState<AuthState, FormData>(action, {});
  const [visible, setVisible] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const copy = {
    login: { title: "Welcome back.", description: joining ? "Sign in with your invited email to review your team invitation." : "Sign in to your restaurant workspace.", button: "Sign in", busy: "Signing you in…" },
    signup: { title: "Start with a clearer picture.", description: joining ? "Create and verify your account to join your restaurant team." : "Create your account to apply for a restaurant workspace or accept your team invitation.", button: "Create account", busy: "Creating your account…" },
    forgot: { title: "Forgot your password?", description: "Enter your account email and we’ll send you a link to reset your password.", button: "Send reset link", busy: "Sending reset link…" },
    reset: { title: "A fresh start.", description: "Choose a new password to keep your account secure.", button: "Save new password", busy: "Updating password…" },
  }[mode];

  return (
    <>

      <h1 className="auth-title">{copy.title}</h1>
      <p className="auth-description">{copy.description}</p>
      {notice && !state.error && !state.success && <p role="status" className="auth-notice">{notice}</p>}
      {state.error && <p role="alert" className="auth-alert">{state.error}</p>}
      {state.success ? (
        <div className="recovery-success" role="status"><span aria-hidden="true">✓</span><h3>Check your inbox</h3><p>{state.success}</p><Link href="/login" className="auth-button">Back to sign in <span aria-hidden="true">→</span></Link></div>
      ) : (
        <form action={formAction} className="auth-form" aria-busy={pending}>
          {mode !== "reset" && <div className="auth-field">
            <label htmlFor="email">Email address</label>
            <input id="email" name="email" type="email" autoComplete="email" inputMode="email" autoCapitalize="none" spellCheck={false} placeholder="you@restaurant.com" required maxLength={254} value={email} onChange={(event) => setEmail(event.target.value)} aria-invalid={!!state.fieldErrors?.email} aria-describedby={state.fieldErrors?.email ? "email-error" : undefined} />
            {state.fieldErrors?.email && <p id="email-error" className="field-error">{state.fieldErrors.email}</p>}
          </div>}
          {mode !== "forgot" && <div className="auth-field">
            <div className="field-label-row"><label htmlFor="password">{mode === "reset" ? "New password" : "Password"}</label>{mode === "login" && <Link href="/forgot-password">Forgot password?</Link>}</div>
            <div className="password-input"><input id="password" name="password" type={visible ? "text" : "password"} autoComplete={newPassword ? "new-password" : "current-password"} placeholder={newPassword ? "At least 8 characters" : "Enter your password"} required minLength={newPassword ? 8 : undefined} value={password} onChange={(event) => setPassword(event.target.value)} aria-invalid={!!state.fieldErrors?.password} aria-describedby={state.fieldErrors?.password ? "password-error" : undefined} /><button type="button" aria-label={visible ? "Hide password" : "Show password"} aria-pressed={visible} onClick={() => setVisible(!visible)}><Eye visible={visible} /></button></div>
            {state.fieldErrors?.password && <p id="password-error" className="field-error">{state.fieldErrors.password}</p>}
          </div>}
          {newPassword && <div className="auth-field"><label htmlFor="confirmPassword">{mode === "signup" ? "Confirm password" : "Confirm new password"}</label><input id="confirmPassword" name="confirmPassword" type={visible ? "text" : "password"} autoComplete="new-password" required minLength={8} placeholder="Enter your password again" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} aria-invalid={!!state.fieldErrors?.confirmPassword} aria-describedby={state.fieldErrors?.confirmPassword ? "confirmation-error" : undefined} />{state.fieldErrors?.confirmPassword && <p id="confirmation-error" className="field-error">{state.fieldErrors.confirmPassword}</p>}</div>}
          <button type="submit" className="auth-button" disabled={pending}>{pending ? <><span className="button-spinner" aria-hidden="true" />{copy.busy}</> : <>{copy.button}<span aria-hidden="true">→</span></>}</button>
          <span className="sr-only" role="status">{pending ? copy.busy : ""}</span>
        </form>
      )}
      {mode !== "login" && mode !== "signup" && !state.success && <Link href="/login" className="auth-back">Back to sign in</Link>}
      {mode === "login" && <p className="auth-invitation">New to ProfitPlate? <Link href="/signup" className="inline-link">Create your account</Link></p>}
      {mode === "signup" && <p className="auth-invitation">Already have an account? <Link href="/login" className="inline-link">Sign in</Link></p>}
    </>
  );
}
