-- Career RAG: structured career data (source of truth) + derived search chunks.
-- Every row belongs to an auth user; RLS restricts all access to the owner.

create extension if not exists vector with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Normalized key used for exact matching of names (skills, companies...).
-- "FastAPI" / "Fast API" / "fast-api" -> "fastapi"; keeps + and # (C++, C#).
create or replace function public.norm_key(t text)
returns text language sql immutable parallel safe
set search_path = ''
as $$ select nullif(regexp_replace(lower(coalesce(t, '')), '[^[:alnum:]+#]+', '', 'g'), '') $$;

create or replace function public.norm_keys(t text[])
returns text[] language sql immutable parallel safe
set search_path = ''
as $$ select coalesce(array_agg(distinct public.norm_key(x)) filter (where public.norm_key(x) is not null), '{}')
      from unnest(coalesce(t, '{}')) as x $$;

-- Partial dates ("2019", "2019-05", "2019-05-17") to concrete bounds.
create or replace function public.career_date_lo(d text)
returns date language sql immutable parallel safe
set search_path = ''
as $$ select case
  when d is null then null
  when d ~ '^\d{4}$' then make_date(d::int, 1, 1)
  when d ~ '^\d{4}-\d{2}$' then make_date(left(d, 4)::int, right(d, 2)::int, 1)
  else d::date end $$;

create or replace function public.career_date_hi(d text)
returns date language sql immutable parallel safe
set search_path = ''
as $$ select case
  when d is null then null
  when d ~ '^\d{4}$' then make_date(d::int, 12, 31)
  when d ~ '^\d{4}-\d{2}$' then (make_date(left(d, 4)::int, right(d, 2)::int, 1) + interval '1 month - 1 day')::date
  else d::date end $$;

create or replace function public.set_updated_at()
returns trigger language plpgsql
set search_path = ''
as $$ begin new.updated_at = now(); return new; end $$;

-- ---------------------------------------------------------------------------
-- Ingestion drafts (two-step write flow)
-- ---------------------------------------------------------------------------

create table public.ingestion_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'committed', 'discarded')),
  source_text text,                -- what the user actually said (any language)
  source_language text,
  operations jsonb not null,       -- validated operations to apply on commit
  summary jsonb,
  warnings jsonb not null default '[]',
  result jsonb,
  created_at timestamptz not null default now(),
  committed_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Core entities
-- ---------------------------------------------------------------------------

create domain public.career_date as text
  check (value is null or value ~ '^\d{4}(-(0[1-9]|1[0-2])(-(0[1-9]|[12]\d|3[01]))?)?$');

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 200),
  name_norm text generated always as (public.norm_key(name)) stored,
  industry text,
  location text,
  website text,
  description_en text,
  source_text text,
  draft_id uuid references public.ingestion_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, name_norm)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  title text not null check (length(title) between 1 and 200),
  employment_type text check (employment_type in
    ('full_time', 'part_time', 'contract', 'freelance', 'consulting', 'internship', 'founder', 'volunteer', 'other')),
  seniority text,
  location text,
  start_date public.career_date,
  end_date public.career_date,
  is_current boolean not null default false,
  summary_en text,
  source_text text,
  draft_id uuid references public.ingestion_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  role_id uuid references public.roles(id) on delete set null,
  company_id uuid references public.companies(id) on delete set null,
  kind text not null default 'work' check (kind in ('work', 'personal', 'open_source', 'freelance', 'academic', 'other')),
  name text not null check (length(name) between 1 and 300),
  summary_en text not null,
  description_en text,
  my_role_en text,
  team_size int check (team_size is null or team_size between 1 and 100000),
  start_date public.career_date,
  end_date public.career_date,
  is_current boolean not null default false,
  url text,
  source_text text,
  draft_id uuid references public.ingestion_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.education (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null default 'degree' check (kind in ('degree', 'certification', 'course', 'bootcamp', 'other')),
  title text not null check (length(title) between 1 and 300),
  institution text,
  field text,
  start_date public.career_date,
  end_date public.career_date,
  credential_url text,
  description_en text,
  source_text text,
  draft_id uuid references public.ingestion_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Evidence: one concrete thing done / achieved / designed / implemented / led.
create table public.evidence (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  role_id uuid references public.roles(id) on delete cascade,
  education_id uuid references public.education(id) on delete cascade,
  kind text not null default 'implementation' check (kind in
    ('achievement', 'responsibility', 'implementation', 'design', 'leadership', 'mentoring',
     'business', 'research', 'communication', 'other')),
  statement_en text not null check (length(statement_en) between 3 and 4000),
  impact_en text,
  metrics jsonb not null default '[]' check (jsonb_typeof(metrics) = 'array'),
  certainty text not null default 'explicit' check (certainty in ('explicit', 'inferred')),
  inference_note text,
  source_text text,
  start_date public.career_date,
  end_date public.career_date,
  draft_id uuid references public.ingestion_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.skills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 120),
  name_norm text generated always as (public.norm_key(name)) stored,
  category text not null default 'technology' check (category in
    ('technology', 'practice', 'capability', 'domain', 'language', 'other')),
  aliases text[] not null default '{}',
  aliases_norm text[] generated always as (public.norm_keys(aliases)) stored,
  description_en text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, name_norm)
);

create table public.evidence_skills (
  evidence_id uuid not null references public.evidence(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  certainty text not null default 'explicit' check (certainty in ('explicit', 'inferred')),
  primary key (evidence_id, skill_id)
);

create table public.project_skills (
  project_id uuid not null references public.projects(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  certainty text not null default 'explicit' check (certainty in ('explicit', 'inferred')),
  primary key (project_id, skill_id)
);

create table public.education_skills (
  education_id uuid not null references public.education(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  certainty text not null default 'explicit' check (certainty in ('explicit', 'inferred')),
  primary key (education_id, skill_id)
);

-- ---------------------------------------------------------------------------
-- Knowledge chunks: DERIVED search index (rebuildable from the tables above)
-- ---------------------------------------------------------------------------

create table public.knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('company', 'role', 'project', 'evidence', 'education')),
  entity_id uuid not null,
  title text,
  content text not null,
  content_hash text not null,
  fts tsvector,
  embedding extensions.vector(384),
  embedded_at timestamptz,
  company_id uuid,
  role_id uuid,
  project_id uuid,
  project_kind text,
  certainty text not null default 'explicit',
  start_date text,
  end_date text,
  is_current boolean not null default false,
  skill_ids uuid[] not null default '{}',
  skill_names text[] not null default '{}',
  updated_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index on public.ingestion_drafts (user_id, status, created_at desc);
create index on public.companies (user_id);
create index on public.roles (user_id);
create index on public.roles (company_id);
create index on public.projects (user_id);
create index on public.projects (role_id);
create index on public.projects (company_id);
create index on public.education (user_id);
create index on public.evidence (user_id);
create index on public.evidence (project_id);
create index on public.evidence (role_id);
create index on public.evidence (education_id);
create index on public.skills (user_id);
create index on public.skills using gin (aliases_norm);
create index on public.evidence_skills (skill_id);
create index on public.evidence_skills (user_id);
create index on public.project_skills (skill_id);
create index on public.project_skills (user_id);
create index on public.education_skills (skill_id);
create index on public.education_skills (user_id);
create index on public.companies (draft_id);
create index on public.roles (draft_id);
create index on public.projects (draft_id);
create index on public.education (draft_id);
create index on public.evidence (draft_id);
create index on public.knowledge_chunks (user_id);
create index on public.knowledge_chunks using gin (fts);
create index on public.knowledge_chunks using gin (skill_ids);
create index on public.knowledge_chunks using hnsw (embedding extensions.vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

create trigger trg_companies_updated before update on public.companies for each row execute function public.set_updated_at();
create trigger trg_roles_updated before update on public.roles for each row execute function public.set_updated_at();
create trigger trg_projects_updated before update on public.projects for each row execute function public.set_updated_at();
create trigger trg_education_updated before update on public.education for each row execute function public.set_updated_at();
create trigger trg_evidence_updated before update on public.evidence for each row execute function public.set_updated_at();
create trigger trg_skills_updated before update on public.skills for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security: owner-only access, no anonymous access at all
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['ingestion_drafts', 'companies', 'roles', 'projects', 'education', 'evidence',
                           'skills', 'evidence_skills', 'project_skills', 'education_skills', 'knowledge_chunks']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format($p$create policy owner_all on public.%I for all to authenticated
                     using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))$p$, t);
  end loop;
end $$;

revoke execute on all functions in schema public from anon, public;
alter default privileges in schema public revoke execute on functions from anon, public;
grant execute on function public.norm_key(text), public.norm_keys(text[]),
  public.career_date_lo(text), public.career_date_hi(text) to authenticated;
