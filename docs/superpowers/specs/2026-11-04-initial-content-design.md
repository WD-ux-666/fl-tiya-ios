# Initial Content and Scheduled Discovery

## User request

Populate the initial video and guide catalog, then collect more source-backed material periodically. Zenless Zone Zero personal game-card resources include a game cover, character references and guide entry points, as explicitly selected by the user. English UI and content remain required.

## Implementation choices

- Target ten distinct hosted development clips (three existing plus seven newly researched), across correctly identified games. Preserve creator, original source, exact license, derivative notice, immutable private objects and review-before-publish. No invented engagement or relabeling unrelated games as ZZZ.
- Seed a reviewed ZZZ guide/reference catalog from verified official pages. Store original short English summaries and source metadata/links, not copied full articles. Distinguish actual gameplay guides, historical information, account help and character references in titles and summaries.
- Connect Games Videos and Guides to real per-game server-filtered queries, refresh, retry and source opening. Preserve manual game-card save/read semantics. A Game resources destination exposes the official cover page preview, factual character references and the same guides.
- Use native source-page link presentation for the official cover; do not turn unlicensed official character art into a rehosted asset library. Character reference facts and source links are distinct from the user's owned characters or account progress.
- A bounded six-hour Supabase Cron job invokes an authenticated Edge Function. Initially its only enabled adapter is the official ZZZ Steam RSS metadata feed. HoYo website HTML scraping and article-body/image ingestion are disabled. Later sources can be added as separately reviewed adapters.
- Discovery writes deduplicated pending candidates, never auto-publishes, changes an approved summary, or copies source bodies. The official RSS currently includes announcements and account help as well as game information; pending items are not falsely labeled gameplay guides.

## Data and authorization

Reuse public.guides and its existing published/same-cohort SELECT policy. Seed development explicitly. New crawler settings, runs, candidates and reviews are server-only tables with RLS and no anon/authenticated access. Privileged RPCs are executable only by service_role. Cron's random token is generated inside the database and held in Vault; the Edge Function verifies its hash through a service-only claim RPC. No token/service key enters client code, repository or logs.

## Scope and verification

Only the already authorized FL-Tiya project is modified. No paid resource, account switch, real game-account integration, Apple setup, commit or push. Native verification remains grammar/metadata/source review only; no build, type checking, native tests or simulator launch. Backend checks must cover authenticated published reads, draft/cohort isolation, denied client writes, crawler authentication, deduplication and no automatic publication. Record source/version/hash evidence and user-run steps in the existing backend plan.
