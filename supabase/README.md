# 🗄️ RTC Hub - Supabase Configuration

This folder contains the database architecture and migrations that power the "Verifiable Proof of Work" system.

## 📊 Database Schema
- **profiles**: Extended user data (Richfield Student ID, Logic Points, Bio).
- **snippets**: Native code blocks with language tags and "fork" counts.
- **bounties**: Open bug-fix requests linked to specific Richfield Modules.
- **badges**: Verified Skill Badges (SQL, Python, etc.) mapped to module completion.

## ⚡ Features Used
- **Auth:** Handles student registration and secure sessions.
- **Realtime:** Powers the live "Bounty" alerts for immediate peer-to-peer help.
- **Storage:** Hosts the "Shadow-a-Senior" project documentation archives.

## 🛠️ How to Sync
Use the `supabase/migrations/` files to replicate the schema on a new project instance.