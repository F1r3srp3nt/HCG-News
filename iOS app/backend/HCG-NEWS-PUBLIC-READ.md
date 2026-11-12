# Backend handoff — public reading for the HCG News apps

**Status:** needed only if the verification script says so. Nothing has been deployed. Deployment is manual and is yours to decide.

## Why

The app reads the publication from the same tables the HCG News website uses (`news_articles`, `news_categories`, `news_authors` in the shared HCG project). It reads as the anonymous role, with the public key the website already ships.

The website's own public pages read through server functions, so it isn't known from the outside whether the `anon` role is allowed to read published rows. The automated check from the development environment was blocked. You can run it yourself:

```bash
cd "iOS app/tools" && ./verify-hcg-news-access.sh
```

| Result | Meaning | Action |
|---|---|---|
| `PASS published articles are readable anonymously`, and every other line PASS | Public reading already works safely | None |
| `FAIL no published articles readable anonymously` | The app's Home will say "No articles yet" | Apply step 1 of `hcg-news-public-read.sql` |
| `NOTE editorial column … is readable anonymously` | Rows are protected, columns aren't. The app never asks for them, but anyone with the public key could | Apply step 2 (see the caution below) |
| Any `FAIL … readable` for drafts, scheduled articles, versions, audit, media or subscribers | A leak that exists today, regardless of the app | Fix the row-level security for that table first |

## What the SQL does

1. **Row policies for `anon`:**
   - articles only when `status = 'published'` and `published_at <= now()`;
   - visible sections;
   - author records.
2. **Column privileges for `anon`:** reader-facing columns only.

The policies are additive (`for select to anon`). Existing staff policies (`authenticated`) are untouched, and nothing is granted to `authenticated`.

## Caution before step 2

If the website's public server functions query these tables as `anon` with `select('*')`, revoking table-wide `SELECT` would break those pages. Before applying step 2:
- check how the server functions connect (service role, or the anon key);
- or apply step 1 only.

A rollback is at the end of the SQL file.

## After deploying

1. Run `./verify-hcg-news-access.sh` again. Every line should PASS.
2. Open the app and pull to refresh on Home.
