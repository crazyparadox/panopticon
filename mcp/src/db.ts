// Neon access. The serverless driver speaks HTTP per query, so no pooling to
// manage, which is exactly right for Vercel functions.

import { neon } from "@neondatabase/serverless";

export type Sql = ReturnType<typeof neon>;

let cached: Sql | null = null;

export function db(databaseUrl: string): Sql {
  if (!cached) cached = neon(databaseUrl);
  return cached;
}

export interface CardRow {
  day: string;
  start_ts: number;
  end_ts: number;
  start_time: string;
  end_time: string;
  category: string;
  subcategory: string;
  title: string;
  summary: string;
  detailed_summary: string;
  distractions: unknown;
  app_sites: unknown;
}
