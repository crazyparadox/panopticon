# Panopticon MCP server

Hosted MCP server + sync ingest for Panopticon. The Mac app pushes timeline
cards and daily recaps here; your agents read them back over MCP
(Streamable HTTP). Deploys to Vercel, stores data in Neon Postgres.

```
Mac app ──POST /sync/days, /sync/recaps──▶  Vercel fn  ──▶ Neon
agents  ──POST /mcp (Streamable HTTP)  ──▶  Vercel fn  ──▶ Neon
```

Auth is one shared bearer token (`PANOPTICON_TOKEN`) — this is a personal,
single-user deployment; there is no OAuth.

## Setup

1. **Neon**: create a database, then apply the schema:

   ```sh
   psql "$DATABASE_URL" -f sql/schema.sql
   ```

2. **Deploy to Vercel** (root directory: `mcp/`):

   ```sh
   cd mcp
   npm install
   vercel deploy --prod
   ```

   Environment variables (Vercel project settings):

   | Name | Value |
   | --- | --- |
   | `DATABASE_URL` | Neon connection string |
   | `PANOPTICON_TOKEN` | a long random secret (`openssl rand -hex 24`) |

3. **App side**: in Panopticon → Settings → Export, set the sync endpoint to
   `https://<your-deployment>.vercel.app` and paste the same token, then
   enable sync.

4. **Agents**: point any MCP client at `https://<your-deployment>.vercel.app/mcp`
   with header `Authorization: Bearer <PANOPTICON_TOKEN>`. For Claude Code:

   ```sh
   claude mcp add --transport http panopticon https://<deployment>.vercel.app/mcp \
     --header "Authorization: Bearer <token>"
   ```

## Tools

| Tool | What it returns |
| --- | --- |
| `list_days` | Recent synced days, card counts, freshness (`pushed_at`) |
| `get_timeline` | A day's cards in order: title, summary, category, times, apps/sites, distractions |
| `search_timeline` | Substring search over titles/summaries, optionally day-bounded |
| `get_recap` | The generated daily standup for a day |
| `category_breakdown` | Minutes per category over a day range |

## Sync protocol

The app pushes **day snapshots** — the analysis pipeline regenerates a day's
cards in place, so the server replaces whole days rather than upserting
cards:

- `POST /sync/days` `{deviceId, days: [{day, cards: [...]}]}`
- `POST /sync/recaps` `{deviceId, recaps: [{day, payload}]}`
- `GET /sync/state?deviceId=…` → what the server has, for incremental sync

## Local dev

```sh
npm install
cp .env.example .env   # fill in DATABASE_URL + PANOPTICON_TOKEN
npm run dev
```
