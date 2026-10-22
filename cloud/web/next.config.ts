import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  // `@ghostties/contract` lives in ../contract, shared with the mobile app.
  turbopack: { root: path.join(__dirname, "..") },
};

export default nextConfig;
