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

/** Minutes between two display times like "3:45 PM", wrapping past midnight
 *  (a 4 AM day can run 11:50 PM → 12:10 AM). null when either won't parse. */
function displaySpanMinutes(start: string, end: string): number | null {
  const toMin = (t: string): number | null => {
    const m = t.trim().match(/^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$/);
    if (!m) return null;
    const h = (Number(m[1]) % 12) + (m[3]?.toUpperCase() === "PM" ? 12 : 0);
    return h * 60 + Number(m[2]);
  };
  const a = toMin(start);
  const b = toMin(end);
  if (a === null || b === null) return null;
  return (b - a + 1440) % 1440;
}

interface Distraction {
  startTime?: string;
  endTime?: string;
  title?: string;
  summary?: string;
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
        "and category_breakdown for how time was spent. Use now to check what the user is doing " +
        "and how fresh the data is, get_range for several days of cards at once, app_usage for " +
        "time per app or site, and distractions for what pulled them off task. All times are the user's local time; a " +
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

  server.registerTool(
    "now",
    {
      title: "Latest activity",
      description:
        "The most recent timeline card and when the Mac last synced. Call this first to answer \"what am I doing / what was I just doing\" and to judge how stale the synced data is.",
      inputSchema: {},
    },
    async () => {
      const [card] = (await sql`
        select day, start_time, end_time, start_ts, end_ts, category, subcategory,
               title, summary, app_sites
        from timeline_cards
        order by end_ts desc
        limit 1
      `) as Record<string, unknown>[];
      const [state] = (await sql`
        select day, pushed_at from sync_state order by pushed_at desc limit 1
      `) as Record<string, unknown>[];
      return json({
        server_time: new Date().toISOString(),
        last_synced_at: state?.pushed_at ?? null,
        last_synced_day: state?.day ?? null,
        latest_card: card ?? null,
      });
    },
  );

  server.registerTool(
    "get_range",
    {
      title: "Get timeline cards for a day range",
      description:
        "Timeline cards across several days in one call, oldest first: the input for weekly reviews and timesheets. Returns summaries, not detailed summaries, to stay compact; use get_timeline for one day in full.",
      inputSchema: {
        from: DAY,
        to: DAY,
        category: z.string().optional().describe("Only cards in this category (case-insensitive)"),
        limit: z.number().int().min(1).max(1000).optional().describe("Max cards (default 300)"),
      },
    },
    async ({ from, to, category, limit }) => {
      const rows = (await sql`
        select day, start_time, end_time, category, subcategory, title, summary, app_sites
        from timeline_cards
        where day >= ${from} and day <= ${to}
          and (${category ?? null}::text is null or lower(category) = lower(${category ?? null}))
        order by start_ts asc
        limit ${limit ?? 300}
      `) as Record<string, unknown>[];
      const days: Record<string, unknown[]> = {};
      for (const { day, ...card } of rows) (days[day as string] ??= []).push(card);
      return json({ from, to, card_count: rows.length, days });
    },
  );

  server.registerTool(
    "app_usage",
    {
      title: "Time by app or site",
      description:
        "Minutes per app or website over a day range. Each card names a primary app/site (credited with the card's full duration) and optionally a secondary one (counted in secondary_minutes). Answers \"how long was I in Figma / on YouTube\".",
      inputSchema: {
        from: DAY,
        to: DAY,
        limit: z.number().int().min(1).max(200).optional().describe("Max apps/sites (default 25)"),
      },
    },
    async ({ from, to, limit }) => {
      const rows = await sql`
        with sites as (
          select lower(trim(app_sites->>'primary')) as name, 'primary' as role,
                 end_ts - start_ts as secs
          from timeline_cards
          where day >= ${from} and day <= ${to} and coalesce(app_sites->>'primary', '') <> ''
          union all
          select lower(trim(app_sites->>'secondary')), 'secondary', end_ts - start_ts
          from timeline_cards
          where day >= ${from} and day <= ${to} and coalesce(app_sites->>'secondary', '') <> ''
        )
        select name,
               round(sum(secs) filter (where role = 'primary') / 60.0)::int as primary_minutes,
               round(coalesce(sum(secs) filter (where role = 'secondary'), 0) / 60.0)::int as secondary_minutes,
               count(*)::int as cards
        from sites
        group by name
        order by primary_minutes desc nulls last, secondary_minutes desc
        limit ${limit ?? 25}
      `;
      return json({ from, to, apps: rows });
    },
  );

  server.registerTool(
    "distractions",
    {
      title: "Distractions over a range",
      description:
        "Distractions the timeline flagged inside cards over a day range, grouped by title with counts and total minutes, most time-consuming first, plus each occurrence (day, time, what the user was meant to be doing).",
      inputSchema: {
        from: DAY,
        to: DAY,
        limit: z.number().int().min(1).max(100).optional().describe("Max distraction groups (default 20)"),
      },
    },
    async ({ from, to, limit }) => {
      const rows = (await sql`
        select day, title as card_title, distractions
        from timeline_cards
        where day >= ${from} and day <= ${to}
          and case when jsonb_typeof(distractions) = 'array'
                   then jsonb_array_length(distractions) > 0 else false end
        order by start_ts asc
      `) as { day: string; card_title: string; distractions: Distraction[] }[];

      type Group = { title: string; count: number; minutes: number; occurrences: unknown[] };
      const groups = new Map<string, Group>();
      for (const row of rows) {
        for (const d of row.distractions) {
          const title = (d.title ?? "").trim() || "Untitled";
          const minutes =
            d.startTime && d.endTime ? displaySpanMinutes(d.startTime, d.endTime) : null;
          const g = groups.get(title.toLowerCase()) ?? { title, count: 0, minutes: 0, occurrences: [] };
          g.count += 1;
          g.minutes += minutes ?? 0;
          g.occurrences.push({
            day: row.day,
            start_time: d.startTime,
            end_time: d.endTime,
            summary: d.summary,
            during: row.card_title,
          });
          groups.set(title.toLowerCase(), g);
        }
      }
      const ranked = [...groups.values()]
        .sort((a, b) => b.minutes - a.minutes || b.count - a.count)
        .slice(0, limit ?? 20);
      const total = [...groups.values()].reduce(
        (acc, g) => ({ count: acc.count + g.count, minutes: acc.minutes + g.minutes }),
        { count: 0, minutes: 0 },
      );
      return json({ from, to, total, distractions: ranked });
    },
  );

  return server;
}
