import type { NextConfig } from "next";
import { networkInterfaces } from "node:os";

// Permit phone previews through this laptop's current private LAN addresses.
const lanHosts = Object.values(networkInterfaces()).flatMap(entries =>
  (entries ?? []).filter(entry => entry.family === "IPv4" && !entry.internal && (
    entry.address.startsWith("192.168.") || entry.address.startsWith("10.") ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(entry.address)
  )).map(entry => entry.address)
);

const nextConfig: NextConfig = {
  allowedDevOrigins: lanHosts,
  /* config options here */
  experimental: {
    agentFeedback: true,
    serverActions: { bodySizeLimit: "2mb" },
  },
  cacheComponents: true,
  partialPrefetching: true,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
