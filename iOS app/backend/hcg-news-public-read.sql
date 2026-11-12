-- HCG News — public read access for native apps (HCG News iOS/iPadOS).
--
-- FOR MANUAL DEPLOYMENT ONLY, after review. Nothing in the app applies this.
-- Apply only if tools/verify-hcg-news-access.sh shows that anonymous readers
-- can't read published articles, or can read editorial columns.
-- Read HCG-NEWS-PUBLIC-READ.md first: step 2 changes column privileges for the
-- `anon` role, which the website's public pages may also use.
--
-- Target: the shared HCG project (qggdyzoydveafkmjgkpq), schema public.

begin;

-- 1. Rows: anonymous readers see only published articles whose time has come.
alter table public.news_articles enable row level security;
drop policy if exists hcg_news_public_read_published on public.news_articles;
create policy hcg_news_public_read_published on public.news_articles
  for select to anon
  using (status = 'published' and published_at is not null and published_at <= now());

alter table public.news_categories enable row level security;
drop policy if exists hcg_news_public_read_sections on public.news_categories;
create policy hcg_news_public_read_sections on public.news_categories
  for select to anon
  using (coalesce(is_visible, true));

alter table public.news_authors enable row level security;
drop policy if exists hcg_news_public_read_authors on public.news_authors;
create policy hcg_news_public_read_authors on public.news_authors
  for select to anon
  using (true);

-- 2. Columns: anonymous readers get reader-facing columns only (never created_by,
--    SEO fields, view counts or user links). Skip this step if the website's
--    public pages read these tables as `anon` with select('*') — see the notes.
revoke select on public.news_articles from anon;
grant select (id, title, subtitle, slug, excerpt, body, status, content_type, published_at, updated_at,
              featured_image_url, featured_image_alt, featured_image_caption, featured_image_credit,
              is_featured, is_breaking, is_demo, reading_time, category_id, author_id, sources, correction_notes)
  on public.news_articles to anon;

revoke select on public.news_categories from anon;
grant select (id, name, slug, description, sort_order, is_visible, image_url) on public.news_categories to anon;

revoke select on public.news_authors from anon;
grant select (id, name, slug, title, bio, avatar_url) on public.news_authors to anon;

commit;

-- Rollback (restores table-wide SELECT for anon and removes the three policies):
-- begin;
-- drop policy if exists hcg_news_public_read_published on public.news_articles;
-- drop policy if exists hcg_news_public_read_sections on public.news_categories;
-- drop policy if exists hcg_news_public_read_authors on public.news_authors;
-- grant select on public.news_articles, public.news_categories, public.news_authors to anon;
-- commit;
