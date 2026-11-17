/** Classify authentication failures without exposing account or provider details. */
export function signInErrorMessage(error: { code?: string; status?: number; name?: string }): string {
  if (error.status === 0 || error.name === "AuthRetryableFetchError") {
    return "We couldn't reach the sign-in service. Please try again shortly.";
  }
  if (error.status === 429) return "Too many attempts. Please wait a moment and try again.";
  if (error.status && error.status >= 500) return "Sign-in is temporarily unavailable. Please try again.";
  if (error.code === "email_not_confirmed") return "Confirm your email address before signing in.";
  if (error.code === "invalid_credentials") return "The email or password is incorrect. Please try again.";
  return "Sign-in is temporarily unavailable. Please try again.";
}
