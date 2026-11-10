# Live Development Implementation Plan

**Goal:** Let the user manually test existing real Supabase data paths through Debug-only real test login.
**Spec:** `docs/superpowers/specs/2026-11-03-live-development-design.md`.
**Architecture:** Reserved test identities and permanent server-owned cohorts; access-code Edge login issues real Auth sessions; Debug verifies context while Release rejects test sessions. Production Apple and payment requirements remain intact.

## Tasks
- [x] Backend schema: cohort authorization, server login context, session context, isolated wallet and rollback fixtures. Worker owns new schema/test files; root deploys real migration snapshots.
- [x] Native: Debug access-code login, service/session lifecycle, Release refusal, live banner and Games My Card. Worker owns native files/tests; root owns project metadata.
- [x] Edge: bounded code-auth endpoint, exact reserved Admin user provisioning, Auth session verification, negative tests. Root owns functions and private credential generation.
- [x] Deploy reviewed schema/function; provision two clean real accounts; verify HTTP/RLS without exposing tokens.
- [x] Independent review, static verification, setup/manual test checklist and task records.

No native build/typecheck/XCTest execution/launch, commits/pushes, paid resources or real Apple payment. Test credentials live only outside the repository in a0600 private file.
