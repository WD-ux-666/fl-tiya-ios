# ZZZ Guides and Initial Game Resources

## Try the native entries

Stop the old app and Run the updated FLTiya or FLTiyaStoreKitTesting scheme yourself in Xcode. Use **Continue with email**.

1. Games > Zenless Zone Zero > Guides loads eight reviewed source-linked guides and references. Pull to refresh; open Read at source to read the original publisher page.
2. Games > My Card > Game resources opens the official Steam page preview, Anby Demara / Nicole Demara / Billy Kid references and the same Guides destination. The card editor also links to these resources.
3. Games > select another game > Videos loads only that game's approved clips and real covers. Opening a clip uses the private native player.
4. Check switching games/accounts, sign-out, refresh, error retry and back navigation. Game-card saves still use manually entered player name, days and progress; these resources do not bind an external game account or claim ownership of characters.

The official game cover is a native LinkPresentation preview of the publisher's Steam page, with retry and a source link if metadata is unavailable. It is not a copied asset in Storage. Character references use names/faction facts and the official character link, without copied character portraits. Actual preview rendering, native compilation and device playback have not been tested by the assistant.

## First published references

The [eight-entry manifest](content/development-zzz-guides-2026-11-04.json) records exact titles, original English summaries, publisher/author links, publication dates and editorial limits. It includes five gameplay/system introductions, one Steam account-support tutorial, the official character roster and one explicitly historical Bangboo world reference. Original dates stay in the visible attribution; Added refers to FL-Tiya publication, not the original article date. Version-specific and historical entries are not presented as current optimized combat builds.

Only summaries and source metadata are imported. Full articles and publisher images are read at their original source. A trusted editor reviewed the initial eight drafts and appended eight private review records before publishing them in the development cohort. Draft/approve SQL files are exact one-time snapshots; do not replay them blindly. Beta HTTPS checks confirmed zero visible drafts, eight exact published rows, anonymous read denial and client write denial.

## Scheduled discovery

- Authorized project: gpstwmffctwqlcakmvgw, independent FL-Tiya, account tely.
- Source: [official ZZZ Steam RSS](https://steamcommunity.com/games/4162040/rss/), app4162040. The collector checks robots guidance and requests only this fixed source, without following redirects.
- Schedule: fltiya-guide-discovery, `0 */6 * * *`, GMT/UTC. In Asia/Shanghai this is02:00,08:00,14:00,20:00.
- Edge Function: collect-guide-candidates, version1. Its gateway JWT check is disabled because it verifies a private256-bit Cron token through service-only SQL. A publishable key or user JWT cannot start a run. No token is embedded in the Cron command, client or repository.
- Each run is bounded by timeout, streamed byte limit,20-item limit, canonical Steam URLs, sanitized text/error codes, a serialized five-minute cooldown and an active-run lease.
- The first real run returned HTTP200 and inserted9 unique candidates. One already-published support URL was skipped. All9 remain private and pending; the published count stayed8.
- Subsequent discovery deduplicates against existing candidates and published sources. Replaying a completed finish returns already_finished. Discovery never inserts or updates public.guides, never stores article HTML/images and never auto-publishes news as guides.

Schema history: migrations20261104044306,20261104044942 and20261104045332. The latter two put the newly installed pg_net extension in extensions and index the discovery foreign keys. Function and schedule sources are under functions/collect-guide-candidates and content/guide-crawl-2026-11-04-enable.sql.

## Review and maintenance

New candidates are in private.guide_candidates, with runs/errors in private.guide_crawl_runs. A trusted backend editor must open the original, decide whether it is a useful guide/reference, verify publisher/author/date, write an original summary, and review any separate artwork permission. News can be rejected or kept pending. Publication requires an explicit review record and an exact development-cohort public.guides write. There is no review administration screen or automatic promotion endpoint in this increment.

More sources can be added through reviewed source configuration/parser/schema changes while retaining the same candidate-review-publication separation. This initial collector is intentionally limited to the requested official ZZZ feed. The seven additional video imports are a separate reviewed batch, not an unrestricted video scraper.

## Managed queue security boundary

Supabase owns pg_net tables and grants PUBLIC access inside Postgres. A REVOKE executed as postgres can appear successful without removing those managed grants. The early migration contains that ineffective statement as deployment history; the current canonical schema documents the real boundary. See [Supabase's explanation](https://supabase.com/kb/troubleshooting/revoking-access-to-pg_net-objects-has-no-effect).

The net schema is excluded from the Data API. Both authenticated and anonymous HTTP probes returned406/PGRST106; app roles are NOLOGIN. The enqueue/claim/finish functions are service-only and the app has no arbitrary SQL or privileged network wrapper. Direct database login roles and administrators remain trusted and can read briefly queued headers. Do not expose net/Vault/private schemas or issue direct database credentials to ordinary app users. config.toml explicitly keeps the API schemas to public and graphql_public; no broad config push was performed.

## Verification and remaining limits

Real HTTPS checks verify published guide fields, draft hiding, permissions, private video hashes and the actual first discovery run. All72 backend tests passed. Native project metadata and53 Swift files passed grammar-only checks; native tests, compilation, LinkPresentation and AVPlayer behavior were not executed. See the frozen phase9 records in .planning/2026-11-03-supabase-backend.

The security advisor has11 informational entries for deliberately server-only private tables and the existing leaked-password-protection warning. The pg_net public-schema warning and five missing-FK-index entries found during this work were fixed. Final performance advice is unused-index information only. Existing password-protection [remediation guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains separate from this content work.
