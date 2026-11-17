export function siteUrl() {
  const value = process.env.NEXT_PUBLIC_SITE_URL
    || (process.env.NODE_ENV === "development" ? "http://localhost:3000" : undefined);
  if (!value) return null;
  const url = new URL(value);
  if (!["http:", "https:"].includes(url.protocol)) return null;
  return url.origin;
}
