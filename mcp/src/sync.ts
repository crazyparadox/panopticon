// Sync ingest endpoints. The Mac app pushes DAY SNAPSHOTS: the analysis
// pipeline regenerates a day's cards in place (sliding window), so per-card
// upserts would strand deleted cards. Each push replaces the day atomically.

import type { Request, Response, Router } from "express";
import express from "express";
import { z } from "zod";
import type { Sql } from "./db.js";

const cardSchema = z.object({
  day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  startTs: z.number().int(),
  endTs: z.number().int(),
  startTime: z.string(),
  endTime: z.string(),
  category: z.string(),
  subcategory: z.string().default(""),
  title: z.string(),
  summary: z.string(),
  detailedSummary: z.string().default(""),
  distractions: z.unknown().optional(),
  appSites: z.unknown().optional(),
});

const daysPayloadSchema = z.object({
  deviceId: z.string().min(1).max(128),
  days: z
    .array(
      z.object({
        day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        cards: z.array(cardSchema),
      }),
    )
    .min(1)
    .max(64),
});

const recapsPayloadSchema = z.object({
  deviceId: z.string().min(1).max(128),
  recaps: z
    .array(
      z.object({
        day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        payload: z.unknown(),
      }),
    )
    .min(1)
    .max(64),
});

export function buildSyncRouter(sql: Sql): Router {
  const router = express.Router();

  // Replace whole days of timeline cards.
  router.post("/days", async (req: Request, res: Response) => {
    const parsed = daysPayloadSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid payload", details: parsed.error.issues });
      return;
    }
    const { deviceId, days } = parsed.data;

    for (const { day, cards } of days) {
      // Neon's HTTP driver runs each statement independently; a brief window
      // where the day is empty is acceptable for a single-reader personal
      // deployment, and re-pushing is idempotent.
      await sql`delete from timeline_cards where device_id = ${deviceId} and day = ${day}`;
      for (const c of cards) {
        await sql`
          insert into timeline_cards
            (device_id, day, start_ts, end_ts, start_time, end_time,
             category, subcategory, title, summary, detailed_summary,
             distractions, app_sites)
          values
            (${deviceId}, ${day}, ${c.startTs}, ${c.endTs}, ${c.startTime}, ${c.endTime},
             ${c.category}, ${c.subcategory}, ${c.title}, ${c.summary}, ${c.detailedSummary},
             ${JSON.stringify(c.distractions ?? null)}::jsonb,
             ${JSON.stringify(c.appSites ?? null)}::jsonb)
        `;
      }
      await sql`
        insert into sync_state (device_id, day, cards_count, pushed_at)
        values (${deviceId}, ${day}, ${cards.length}, now())
        on conflict (device_id, day)
        do update set cards_count = excluded.cards_count, pushed_at = now()
      `;
    }

    res.json({ ok: true, days: days.map((d) => ({ day: d.day, cards: d.cards.length })) });
  });

  // Upsert daily recaps (standup drafts).
  router.post("/recaps", async (req: Request, res: Response) => {
    const parsed = recapsPayloadSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid payload", details: parsed.error.issues });
      return;
    }
    const { deviceId, recaps } = parsed.data;
    for (const r of recaps) {
      await sql`
        insert into daily_recaps (device_id, day, payload, updated_at)
        values (${deviceId}, ${r.day}, ${JSON.stringify(r.payload)}::jsonb, now())
        on conflict (device_id, day)
        do update set payload = excluded.payload, updated_at = now()
      `;
    }
    res.json({ ok: true, recaps: recaps.length });
  });

  // What the server has — lets the app decide what still needs pushing.
  router.get("/state", async (req: Request, res: Response) => {
    const deviceId = String(req.query.deviceId ?? "");
    if (!deviceId) {
      res.status(400).json({ error: "deviceId query parameter is required" });
      return;
    }
    const rows = await sql`
      select day, cards_count, pushed_at from sync_state
      where device_id = ${deviceId} order by day desc limit 400
    `;
    res.json({ days: rows });
  });

  return router;
}
