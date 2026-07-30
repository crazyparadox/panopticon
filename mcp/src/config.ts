// Environment configuration. Two secrets:
//   DATABASE_URL     — Neon Postgres connection string (server-side only)
//   PANOPTICON_TOKEN — shared bearer token; the Mac app uses it to push data
//                      and MCP clients use it to read. Personal deployment,
//                      one user, so a single static token instead of OAuth.

export interface Config {
  databaseUrl: string;
  token: string;
  port: number;
}

export function loadConfig(): Config {
  const databaseUrl = process.env.DATABASE_URL;
  const token = process.env.PANOPTICON_TOKEN;
  if (!databaseUrl) throw new Error("DATABASE_URL is required (Neon connection string)");
  if (!token || token.length < 16) {
    throw new Error("PANOPTICON_TOKEN is required and must be at least 16 characters");
  }
  return {
    databaseUrl,
    token,
    port: Number(process.env.PORT ?? 3939),
  };
}
