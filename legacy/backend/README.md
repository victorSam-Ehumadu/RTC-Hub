# 🚀 RTC Hub - Backend (Node/Express)

This is the core API for the Richfield Tech-Connect Hub. It handles the logic for "Logic Points," Code Snippet management, and verified Skill-Graph data.

## 📁 Structure
- `/src/controllers`: Handles incoming requests (Feed, Bounties, Profiles).
- `/src/services`: Core business logic (XP calculations, Skill-Graph generation).
- `/src/routes`: Express URL mapping for the API.
- `/src/middleware`: JWT authentication via Supabase and request validation.
- `/src/utils`: Helper functions, including Code Execution logic.

## 🛠️ Setup
1. Run `npm install`.
2. Create a `.env` file with `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. Start the dev server: `npm run dev`.

## 📡 Key Endpoints
- `GET /api/feed`: Returns the "Live-Logic" technical feed.
- `POST /api/bounties`: Submit a new bug-fix request.
- `GET /api/profile/:id`: Returns the user's Verified Skill-Graph.