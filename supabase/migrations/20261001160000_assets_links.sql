-- Assets (phase 1: links). A URL with an English description, attached to at most one
-- company / role / project / evidence / education item (none = profile-level link, e.g. GitHub profile).
-- Searchable through its own knowledge chunk; parents list their links in their chunk text.

create table public.assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null default 'link' check (kind in
    ('repo', 'demo', 'website', 'article', 'talk', 'video', 'image', 'document', 'certificate', 'publication', 'link', 'other')),
  url text not null check (length(url) <= 2000 and url ~* '^https?://[^[:space:]]+$'),
  title text not null check (length(title) between 1 and 300),
  description_en text,
  source_text text,
  published_on public.career_date,
  company_id uuid references public.companies(id) on delete cascade,
  role_id uuid references public.roles(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  evidence_id uuid references public.evidence(id) on delete cascade,
  education_id uuid references public.education(id) on delete cascade,
  draft_id uuid references public.ingestion_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(company_id, role_id, project_id, evidence_id, education_id) <= 1)
);

create index on public.assets (user_id);
create index on public.assets (company_id);
create index on public.assets (role_id);
create index on public.assets (project_id);
create index on public.assets (evidence_id);
create index on public.assets (education_id);
create index on public.assets (draft_id);

create trigger trg_assets_updated before update on public.assets for each row execute function public.set_updated_at();

alter table public.assets enable row level security;
alter table public.assets force row level security;
revoke all on public.assets from anon, public;
grant select, insert, update, delete on public.assets to authenticated;
create policy owner_all on public.assets for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

alter table public.knowledge_chunks drop constraint knowledge_chunks_entity_type_check;
alter table public.knowledge_chunks add constraint knowledge_chunks_entity_type_check
  check (entity_type in ('company', 'role', 'project', 'evidence', 'education', 'asset'));
