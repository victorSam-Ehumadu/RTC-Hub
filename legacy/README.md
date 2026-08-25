# Archived web version

This directory holds the React + Express implementation of RTC Hub that
preceded the Flutter app. It is **not built, run, or imported** by anything.

- `frontend/` — Vite + React SPA
- `backend/` — Express API that held a Supabase service-role key
- `web-src/` — a stray root-level `src/` from the old tree

It was mid-refactor when it was archived and does not run: the middleware
directory is misspelled, several route and service files are empty, and the
React entry point imports pages that had already been deleted. Do not try to
revive it.

It is kept for one reason: the route handlers are the clearest record of the
business rules the app implements. When the Dart code says "replaces
`/api/posts`", the original is here. Note that the rules were reimplemented, not
transliterated — the bounty payout in particular was changed, because the
Express version let a commenter mark their own answer as the solution and award
themselves the points.
