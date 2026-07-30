// The Panopticon MCP server: read-only tools over the synced activity
// timeline. Stateless: a fresh server+transport per request (see app.ts),
// which is what Vercel functions need.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import type { Sql } from "./db.js";

const DAY = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .describe('Logical day as "yyyy-MM-dd". Days run 4 AM → 4 AM local time on the recording Mac.');

function json(value: unknown): CallToolResult {
  return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
}

export function buildMcpServer(sql: Sql): McpServer {
  const server = new McpServer(
    { name: "panopticon", version: "0.1.0" },
    {
      instructions:
        "Panopticon is a personal screen recorder: it captures the user's Mac activity, an LLM " +
        "turns captures into timeline cards (title, summary, category, apps/sites, distractions), " +
        "and a daily recap is generated each morning. This server reads the synced copy of that " +
        "data. Start with list_days to see what exists, get_timeline for a day's cards, " +
        "search_timeline to find specific activity, get_recap for the generated daily standup, " +
        "and category_breakdown for how time was spent. All times are the user's local time; a " +
        '"day" runs 4 AM to 4 AM. Data freshness: each list_days row carries pushed_at, the ' +
        "moment the Mac last synced that day.",
    },
  );

  server.registerTool(
    "list_days",
    {
      title: "List recorded days",
      description:
        "Recent days that have synced timeline data, newest first, with card counts and when each day was last pushed from the Mac.",
      inputSchema: {
        limit: z.number().int().min(1).max(400).optional().describe("Max days to return (default 30)"),
      },
    },
    async ({ limit }) => {
      const rows = await sql`
        select s.day, s.cards_count, s.pushed_at,
               exists(select 1 from daily_recaps r where r.day = s.day) as has_recap
        from sync_state s
        order by s.day desc
        limit ${limit ?? 30}
      `;
      return json(rows);
    },
  );

  server.registerTool(
    "get_timeline",
    {
      title: "Get a day's timeline",
      description:
        "All timeline cards for one day, in chronological order: title, summary, detailed summary, category, time range, apps/sites used, and distractions.",
      inputSchema: { day: DAY },
    },
    async ({ day }) => {
      const rows = await sql`
        select start_time, end_time, start_ts, end_ts, category, subcategory,
               title, summary, detailed_summary, distractions, app_sites
        from timeline_cards
        where day = ${day}
        order by start_ts asc
      `;
      return json({ day, cards: rows });
    },
  );

  server.registerTool(
    "search_timeline",
    {
      title: "Search the timeline",
      description:
        "Case-insensitive substring search over card titles, summaries, and detailed summaries, newest first. Optionally bounded to a day range.",
      inputSchema: {
        query: z.string().min(2).describe("Text to search for"),
        from: DAY.optional().describe("Earliest day to include"),
        to: DAY.optional().describe("Latest day to include"),
        limit: z.number().int().min(1).max(200).optional().describe("Max cards (default 25)"),
      },
    },
    async ({ query, from, to, limit }) => {
      const pattern = `%${query.replaceAll("\\", "\\\\").replaceAll("%", "\\%").replaceAll("_", "\\_")}%`;
      const rows = await sql`
        select day, start_time, end_time, category, subcategory, title, summary
        from timeline_cards
        where (title ilike ${pattern} or summary ilike ${pattern} or detailed_summary ilike ${pattern})
          and (${from ?? null}::text is null or day >= ${from ?? null})
          and (${to ?? null}::text is null or day <= ${to ?? null})
        order by start_ts desc
        limit ${limit ?? 25}
      `;
      return json({ query, matches: rows });
    },
  );

  server.registerTool(
    "get_recap",
    {
      title: "Get a day's recap",
      description:
        "The generated daily recap (standup draft) for a day: yesterday's highlights, today's tasks, and blockers. Recaps are keyed by the day they were generated FOR (the morning after the recorded day).",
      inputSchema: { day: DAY },
    },
    async ({ day }) => {
      const rows = (await sql`
        select day, payload, updated_at from daily_recaps where day = ${day}
      `) as Record<string, unknown>[];
      return json(rows[0] ?? { day, recap: null });
    },
  );

  server.registerTool(
    "category_breakdown",
    {
      title: "Time by category",
      description:
        "Total recorded minutes per category over a day range: how time was actually spent.",
      inputSchema: {
        from: DAY,
        to: DAY,
      },
    },
    async ({ from, to }) => {
      const rows = await sql`
        select category,
               round(sum(end_ts - start_ts) / 60.0)::int as minutes,
               count(*)::int as cards
        from timeline_cards
        where day >= ${from} and day <= ${to}
        group by category
        order by minutes desc
      `;
      return json({ from, to, categories: rows });
    },
  );

  return server;
}
