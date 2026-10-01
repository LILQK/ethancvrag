-- Career RAG functions v2: adds assets (links). All are SECURITY INVOKER: they run with the caller's
-- privileges, so RLS keeps every read/write scoped to the authenticated owner.

-- ---------------------------------------------------------------------------
-- refresh_chunks(): rebuild the derived search text for the caller's data.
-- Chunks whose text changed get embedding = null (re-embedded by the edge function).
-- ---------------------------------------------------------------------------
create or replace function public.refresh_chunks()
returns jsonb
language plpgsql
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_deleted int;
  v_stale int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  create temp table if not exists _chunks (
    entity_type text, entity_id uuid, title text, content text,
    company_id uuid, role_id uuid, project_id uuid, project_kind text, certainty text,
    start_date text, end_date text, is_current boolean, skill_ids uuid[], skill_names text[]
  ) on commit drop;
  truncate _chunks;

  -- Evidence (primary retrieval unit)
  insert into _chunks
  select 'evidence', e.id,
    coalesce(p.name, ed.title, r.title, 'Career evidence'),
    concat_ws(' ',
      e.statement_en,
      'Impact: ' || nullif(e.impact_en, ''),
      case when jsonb_array_length(e.metrics) > 0 then 'Metrics: ' || (
        select string_agg(concat_ws(' ', m->>'name', m->>'value'), '; ') from jsonb_array_elements(e.metrics) m) end,
      case when e.certainty = 'inferred' then '(Inferred, not stated explicitly.)' end,
      'Project: ' || p.name || coalesce(' - ' || p.summary_en, ''),
      'Role: ' || r.title || coalesce(' at ' || c.name, ''),
      'Company: ' || c.name || coalesce(' (' || c.industry || ')', ''),
      'Education: ' || ed.title || coalesce(' at ' || ed.institution, ''),
      'Links: ' || nullif((select string_agg(a.title || ' (' || a.kind || ')', '; ') from assets a where a.evidence_id = e.id), ''),
      'Skills: ' || nullif(array_to_string(sk.names, ', '), '')),
    c.id, r.id, p.id, p.kind, e.certainty,
    coalesce(e.start_date, p.start_date, r.start_date, ed.start_date),
    coalesce(e.end_date, p.end_date, r.end_date, ed.end_date),
    coalesce(p.is_current, r.is_current, false) and e.end_date is null,
    coalesce(sk.ids, '{}'), coalesce(sk.names, '{}')
  from evidence e
  left join projects p on p.id = e.project_id
  left join roles r on r.id = coalesce(e.role_id, p.role_id)
  left join companies c on c.id = coalesce(p.company_id, r.company_id)
  left join education ed on ed.id = e.education_id
  left join lateral (
    select array_agg(s.id order by s.name) ids, array_agg(s.name order by s.name) names
    from evidence_skills es join skills s on s.id = es.skill_id where es.evidence_id = e.id
  ) sk on true;

  -- Projects
  insert into _chunks
  select 'project', p.id, p.name,
    concat_ws(' ',
      'Project: ' || p.name || ' (' || p.kind || ').',
      p.summary_en, p.description_en,
      'My role: ' || nullif(p.my_role_en, ''),
      'Team size: ' || p.team_size,
      'Role: ' || r.title || coalesce(' at ' || c.name, ''),
      'Company: ' || c.name || coalesce(' (' || c.industry || ')', ''),
      'Links: ' || nullif((select string_agg(a.title || ' (' || a.kind || ')', '; ') from assets a where a.project_id = p.id), ''),
      'Skills: ' || nullif(array_to_string(sk.names, ', '), '')),
    c.id, r.id, p.id, p.kind, 'explicit',
    coalesce(p.start_date, r.start_date), coalesce(p.end_date, r.end_date), p.is_current,
    coalesce(sk.ids, '{}'), coalesce(sk.names, '{}')
  from projects p
  left join roles r on r.id = p.role_id
  left join companies c on c.id = coalesce(p.company_id, r.company_id)
  left join lateral (
    select array_agg(distinct s.id) ids, array_agg(distinct s.name) names
    from skills s
    where s.id in (select skill_id from project_skills where project_id = p.id
                   union select es.skill_id from evidence_skills es join evidence e on e.id = es.evidence_id where e.project_id = p.id)
  ) sk on true;

  -- Roles
  insert into _chunks
  select 'role', r.id, r.title || coalesce(' at ' || c.name, ''),
    concat_ws(' ',
      r.title || coalesce(' at ' || c.name, '') || '.',
      'Employment: ' || replace(r.employment_type, '_', ' ') || '.',
      'Seniority: ' || nullif(r.seniority, ''),
      r.summary_en,
      'Company: ' || c.name || coalesce(' - ' || c.industry, '') || coalesce('. ' || c.description_en, ''),
      'Projects: ' || nullif((select string_agg(p.name, ', ') from projects p where p.role_id = r.id), ''),
      'Links: ' || nullif((select string_agg(a.title || ' (' || a.kind || ')', '; ') from assets a where a.role_id = r.id), ''),
      'Skills: ' || nullif(array_to_string(sk.names, ', '), '')),
    c.id, r.id, null, null, 'explicit', r.start_date, r.end_date, r.is_current,
    coalesce(sk.ids, '{}'), coalesce(sk.names, '{}')
  from roles r
  left join companies c on c.id = r.company_id
  left join lateral (
    select array_agg(distinct s.id) ids, array_agg(distinct s.name) names
    from skills s
    where s.id in (select ps.skill_id from project_skills ps join projects p on p.id = ps.project_id where p.role_id = r.id
                   union select es.skill_id from evidence_skills es join evidence e on e.id = es.evidence_id
                     left join projects p on p.id = e.project_id
                     where e.role_id = r.id or p.role_id = r.id)
  ) sk on true;

  -- Companies
  insert into _chunks
  select 'company', c.id, c.name,
    concat_ws(' ', 'Company: ' || c.name || '.', 'Industry: ' || c.industry || '.', 'Location: ' || c.location || '.', c.description_en,
      'Roles: ' || nullif((select string_agg(r.title, ', ') from roles r where r.company_id = c.id), ''),
      'Links: ' || nullif((select string_agg(a.title || ' (' || a.kind || ')', '; ') from assets a where a.company_id = c.id), '')),
    c.id, null, null, null, 'explicit',
    (select min(r.start_date) from roles r where r.company_id = c.id),
    (select max(r.end_date) from roles r where r.company_id = c.id),
    exists (select 1 from roles r where r.company_id = c.id and r.is_current),
    '{}', '{}'
  from companies c;

  -- Education
  insert into _chunks
  select 'education', ed.id, ed.title,
    concat_ws(' ',
      initcap(ed.kind) || ': ' || ed.title || coalesce(' at ' || ed.institution, '') || '.',
      'Field: ' || nullif(ed.field, ''),
      ed.description_en,
      'Links: ' || nullif((select string_agg(a.title || ' (' || a.kind || ')', '; ') from assets a where a.education_id = ed.id), ''),
      'Skills: ' || nullif(array_to_string(sk.names, ', '), '')),
    null, null, null, null, 'explicit', ed.start_date, ed.end_date, false,
    coalesce(sk.ids, '{}'), coalesce(sk.names, '{}')
  from education ed
  left join lateral (
    select array_agg(distinct s.id) ids, array_agg(distinct s.name) names
    from skills s
    where s.id in (select skill_id from education_skills where education_id = ed.id
                   union select es.skill_id from evidence_skills es join evidence e on e.id = es.evidence_id where e.education_id = ed.id)
  ) sk on true;

  -- Assets (links)
  insert into _chunks
  select 'asset', a.id, a.title,
    concat_ws(' ',
      initcap(a.kind) || ': ' || a.title || '.',
      a.description_en,
      'Source: ' || substring(a.url from '^[a-zA-Z]+://(?:www\.)?([^/:?#]+)') || '.',
      'Evidence: ' || e.statement_en,
      'Project: ' || p.name || coalesce(' - ' || p.summary_en, ''),
      'Role: ' || r.title || coalesce(' at ' || c.name, ''),
      'Company: ' || c.name,
      'Education: ' || ed.title || coalesce(' at ' || ed.institution, ''),
      'Skills: ' || nullif(array_to_string(sk.names, ', '), '')),
    c.id, r.id, p.id, p.kind, coalesce(e.certainty, 'explicit'),
    coalesce(a.published_on, e.start_date, p.start_date, r.start_date, ed.start_date),
    coalesce(a.published_on, e.end_date, p.end_date, r.end_date, ed.end_date),
    false,
    coalesce(sk.ids, '{}'), coalesce(sk.names, '{}')
  from assets a
  left join evidence e on e.id = a.evidence_id
  left join projects p on p.id = coalesce(a.project_id, e.project_id)
  left join roles r on r.id = coalesce(a.role_id, e.role_id, p.role_id)
  left join companies c on c.id = coalesce(a.company_id, p.company_id, r.company_id)
  left join education ed on ed.id = coalesce(a.education_id, e.education_id)
  left join lateral (
    select array_agg(distinct s.id) ids, array_agg(distinct s.name) names
    from skills s
    where s.id in (select skill_id from evidence_skills where evidence_id = a.evidence_id
                   union select skill_id from project_skills where project_id = coalesce(a.project_id, e.project_id)
                   union select es.skill_id from evidence_skills es join evidence e2 on e2.id = es.evidence_id
                     where a.project_id is not null and e2.project_id = a.project_id
                   union select skill_id from education_skills where education_id = a.education_id)
  ) sk on true;

  insert into knowledge_chunks as kc (user_id, entity_type, entity_id, title, content, content_hash, fts,
    company_id, role_id, project_id, project_kind, certainty, start_date, end_date, is_current, skill_ids, skill_names)
  select v_uid, t.entity_type, t.entity_id, t.title, t.content, md5(coalesce(t.title, '') || '|' || t.content),
    setweight(to_tsvector('english', coalesce(t.title, '')), 'A')
      || setweight(to_tsvector('simple', array_to_string(t.skill_names, ' ')), 'A')
      || setweight(to_tsvector('english', t.content), 'B'),
    t.company_id, t.role_id, t.project_id, t.project_kind, t.certainty, t.start_date, t.end_date, t.is_current,
    t.skill_ids, t.skill_names
  from _chunks t
  on conflict (user_id, entity_type, entity_id) do update set
    title = excluded.title, content = excluded.content, fts = excluded.fts,
    company_id = excluded.company_id, role_id = excluded.role_id, project_id = excluded.project_id,
    project_kind = excluded.project_kind, certainty = excluded.certainty,
    start_date = excluded.start_date, end_date = excluded.end_date, is_current = excluded.is_current,
    skill_ids = excluded.skill_ids, skill_names = excluded.skill_names,
    embedding = case when kc.content_hash = excluded.content_hash then kc.embedding end,
    embedded_at = case when kc.content_hash = excluded.content_hash then kc.embedded_at end,
    content_hash = excluded.content_hash,
    updated_at = now()
  where kc.content_hash is distinct from excluded.content_hash
     or kc.skill_ids is distinct from excluded.skill_ids
     or kc.company_id is distinct from excluded.company_id
     or kc.role_id is distinct from excluded.role_id
     or kc.project_id is distinct from excluded.project_id
     or kc.start_date is distinct from excluded.start_date
     or kc.end_date is distinct from excluded.end_date
     or kc.is_current is distinct from excluded.is_current;

  delete from knowledge_chunks kc
  where kc.user_id = v_uid
    and not exists (select 1 from _chunks t where t.entity_type = kc.entity_type and t.entity_id = kc.entity_id);
  get diagnostics v_deleted = row_count;

  select count(*) into v_stale from knowledge_chunks where user_id = v_uid and embedding is null;

  return jsonb_build_object('chunks', (select count(*) from _chunks), 'deleted', v_deleted, 'pending_embeddings', v_stale);
end $$;

-- Store embeddings computed by the edge function (gte-small, 384 dims).
create or replace function public.set_chunk_embeddings(items jsonb)
returns int
language sql
set search_path = public, extensions
as $$
  with upd as (
    update knowledge_chunks kc
    set embedding = (i.embedding)::extensions.vector(384), embedded_at = now()
    from jsonb_to_recordset(items) as i(id uuid, content_hash text, embedding text)
    where kc.id = i.id and kc.content_hash = i.content_hash
    returning 1
  ) select count(*)::int from upd
$$;

-- Force re-embedding of everything (e.g. after a model change).
create or replace function public.invalidate_embeddings()
returns int
language sql
set search_path = public
as $$
  with upd as (update knowledge_chunks set embedding = null, embedded_at = null
               where user_id = auth.uid() returning 1)
  select count(*)::int from upd
$$;

-- ---------------------------------------------------------------------------
-- Skill term extraction for exact technology/skill matching
-- ---------------------------------------------------------------------------
create or replace function public.query_skill_ids(query_text text, extra_skill_names text[] default null)
returns table (skill_id uuid, skill_name text)
language sql stable
set search_path = public
as $$
  with toks as (
    select t, ord from regexp_split_to_table(coalesce(query_text, ''), '[\s,;/|()\[\]"''!?:]+') with ordinality as x(t, ord)
    where t <> ''
  ),
  terms as (
    select norm_key(query_text) k
    union select norm_key(t) from toks
    union select norm_key(a.t || b.t) from toks a join toks b on b.ord = a.ord + 1
    union select norm_key(a.t || b.t || c.t) from toks a join toks b on b.ord = a.ord + 1 join toks c on c.ord = b.ord + 1
    union select norm_key(x) from unnest(coalesce(extra_skill_names, '{}')) x
  )
  select s.id, s.name from skills s
  where s.user_id = auth.uid()
    and exists (select 1 from terms where terms.k is not null and length(terms.k) >= 1
                and (terms.k = s.name_norm or terms.k = any (s.aliases_norm)))
$$;

-- ---------------------------------------------------------------------------
-- hybrid_search: Reciprocal Rank Fusion of
--   (1) pgvector cosine similarity, (2) Postgres FTS, (3) exact skill/technology matches
-- with structured filters.
-- ---------------------------------------------------------------------------
create or replace function public.hybrid_search(
  query_text text,
  query_embedding text default null,          -- '[0.1,...]' 384 dims (gte-small)
  match_count int default 10,
  entity_types text[] default null,
  company_ids uuid[] default null,
  role_ids uuid[] default null,
  project_ids uuid[] default null,
  project_kinds text[] default null,
  required_skills text[] default null,        -- chunk must be linked to at least one of these skills
  date_from text default null,
  date_to text default null,
  include_inferred boolean default true,
  semantic_weight float default 1.0,
  fts_weight float default 1.0,
  skill_weight float default 1.5,
  rrf_k int default 40
)
returns table (
  chunk_id uuid, entity_type text, entity_id uuid, title text, content text,
  score float, semantic_similarity float, fts_rank float, matched_skills text[],
  company_id uuid, role_id uuid, project_id uuid, project_kind text, certainty text,
  start_date text, end_date text, is_current boolean, skill_names text[]
)
language plpgsql stable
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  qe extensions.vector(384) := case when query_embedding is null then null else query_embedding::extensions.vector(384) end;
  q_or tsquery;
  q_skill uuid[];
  q_skill_names text[];
  req_skill uuid[];
  n int := least(greatest(coalesce(match_count, 10), 1), 50);
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select to_tsquery('english', string_agg(quote_literal(lex), ' | '))
    into q_or
  from unnest(tsvector_to_array(to_tsvector('english', coalesce(query_text, '')))) lex;

  select array_agg(qs.skill_id), array_agg(qs.skill_name) into q_skill, q_skill_names
  from query_skill_ids(query_text) qs;

  if required_skills is not null and cardinality(required_skills) > 0 then
    select coalesce(array_agg(qs.skill_id), '{00000000-0000-0000-0000-000000000000}') into req_skill
    from query_skill_ids(null, required_skills) qs;
  end if;

  return query
  with base as (
    select kc.* from knowledge_chunks kc
    where kc.user_id = auth.uid()
      and (entity_types is null or kc.entity_type = any (entity_types))
      and (company_ids is null or kc.company_id = any (company_ids))
      and (role_ids is null or kc.role_id = any (role_ids))
      and (project_ids is null or kc.project_id = any (project_ids))
      and (project_kinds is null or kc.project_kind = any (project_kinds))
      and (req_skill is null or kc.skill_ids && req_skill)
      and (include_inferred or kc.certainty = 'explicit')
      and (date_from is null or kc.is_current or kc.end_date is null and kc.start_date is null
           or coalesce(career_date_hi(kc.end_date), 'infinity'::date) >= career_date_lo(date_from))
      and (date_to is null or coalesce(career_date_lo(kc.start_date), '-infinity'::date) <= career_date_hi(date_to))
  ),
  sem as (
    select b.id, 1 - (b.embedding <=> qe) as sim,
           row_number() over (order by b.embedding <=> qe) as r
    from base b
    where qe is not null and b.embedding is not null
    order by b.embedding <=> qe
    limit n * 4
  ),
  fts as (
    select b.id, ts_rank_cd(b.fts, q_or, 32) as rk,
           row_number() over (order by ts_rank_cd(b.fts, q_or, 32) desc) as r
    from base b
    where q_or is not null and b.fts @@ q_or
    order by rk desc
    limit n * 4
  ),
  sk as (
    select b.id,
           array(select unnest(b.skill_names) intersect select unnest(q_skill_names)) as names,
           row_number() over (order by cardinality(array(select unnest(b.skill_ids) intersect select unnest(q_skill))) desc,
                              case b.entity_type when 'evidence' then 0 when 'project' then 1 else 2 end) as r
    from base b
    where q_skill is not null and b.skill_ids && q_skill
    order by r
    limit n * 4
  ),
  fused as (
    select coalesce(sem.id, fts.id, sk.id) as id,
           coalesce(semantic_weight / (rrf_k + sem.r), 0)
         + coalesce(fts_weight / (rrf_k + fts.r), 0)
         + coalesce(skill_weight / (rrf_k + sk.r), 0) as s,
           sem.sim, fts.rk, sk.names
    from sem
    full outer join fts on fts.id = sem.id
    full outer join sk on sk.id = coalesce(sem.id, fts.id)
  )
  select b.id, b.entity_type, b.entity_id, b.title, b.content,
         (f.s * case b.entity_type when 'evidence' then 1.0 when 'project' then 1.0
                                   when 'education' then 0.9 when 'asset' then 0.9 when 'role' then 0.85 else 0.6 end)::float as score,
         f.sim::float, f.rk::float, coalesce(f.names, '{}'),
         b.company_id, b.role_id, b.project_id, b.project_kind, b.certainty,
         b.start_date, b.end_date, b.is_current, b.skill_names
  from fused f join base b on b.id = f.id
  order by 6 desc
  limit n;
end $$;

-- ---------------------------------------------------------------------------
-- Draft commit: applies a validated operation list atomically.
-- ---------------------------------------------------------------------------

-- Resolve {"id": "..."} or {"ref": "..."} to an owned entity id of the expected type.
create or replace function public._resolve_ref(v jsonb, refs jsonb, expected text)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_id uuid;
  v_found boolean;
begin
  if v is null or jsonb_typeof(v) = 'null' then return null; end if;
  if v ? 'ref' then
    if not refs ? (v->>'ref') then raise exception 'Unknown ref "%" (refs must be created earlier in the same draft)', v->>'ref'; end if;
    if refs->(v->>'ref')->>'type' <> expected then
      raise exception 'Ref "%" is a %, expected %', v->>'ref', refs->(v->>'ref')->>'type', expected;
    end if;
    return (refs->(v->>'ref')->>'id')::uuid;
  end if;
  v_id := (v->>'id')::uuid;
  execute format('select exists (select 1 from public.%I where id = $1)',
                 case expected when 'company' then 'companies' when 'role' then 'roles' when 'project' then 'projects'
                   when 'education' then 'education' when 'evidence' then 'evidence' when 'skill' then 'skills'
                   when 'asset' then 'assets' end)
    into v_found using v_id;
  if not v_found then raise exception '% id % does not exist', expected, v_id; end if;
  return v_id;
end $$;

-- Upsert skills by normalized name and link them to an entity.
create or replace function public._attach_skills(p_type text, p_id uuid, p_skills jsonb, p_replace boolean)
returns void
language plpgsql
set search_path = public
as $$
declare
  s jsonb;
  v_skill uuid;
  v_cert text;
  v_keep uuid[] := '{}';
begin
  for s in select * from jsonb_array_elements(coalesce(p_skills, '[]')) loop
    insert into skills (name, category, aliases, description_en)
    values (s->>'name', coalesce(s->>'category', 'technology'),
            coalesce(array(select jsonb_array_elements_text(s->'aliases')), '{}'), s->>'description_en')
    on conflict (user_id, name_norm) do update
      set aliases = (select array(select distinct x from unnest(skills.aliases || excluded.aliases) x))
    returning id into v_skill;
    v_cert := coalesce(s->>'certainty', 'explicit');
    v_keep := v_keep || v_skill;
    if p_type = 'evidence' then
      insert into evidence_skills (evidence_id, skill_id, certainty) values (p_id, v_skill, v_cert)
      on conflict (evidence_id, skill_id) do update set certainty = excluded.certainty;
    elsif p_type = 'project' then
      insert into project_skills (project_id, skill_id, certainty) values (p_id, v_skill, v_cert)
      on conflict (project_id, skill_id) do update set certainty = excluded.certainty;
    elsif p_type = 'education' then
      insert into education_skills (education_id, skill_id, certainty) values (p_id, v_skill, v_cert)
      on conflict (education_id, skill_id) do update set certainty = excluded.certainty;
    end if;
  end loop;
  if p_replace then
    if p_type = 'evidence' then delete from evidence_skills where evidence_id = p_id and skill_id <> all (v_keep);
    elsif p_type = 'project' then delete from project_skills where project_id = p_id and skill_id <> all (v_keep);
    elsif p_type = 'education' then delete from education_skills where education_id = p_id and skill_id <> all (v_keep);
    end if;
  end if;
end $$;

create or replace function public.commit_draft(p_draft_id uuid)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  d record;
  op jsonb;
  v_op text; v_type text; v_data jsonb; v_id uuid; v_ref text;
  refs jsonb := '{}';
  created jsonb := '[]'; updated jsonb := '[]'; deleted jsonb := '[]';
  v_company uuid; v_role uuid; v_project uuid; v_education uuid;
  v_table text; v_sets text[]; k text; v_col_type text; v_found boolean;
  v_refresh jsonb;
  -- updatable columns per entity type, with SQL types
  cols constant jsonb := '{
    "company":   {"name":"text","industry":"text","location":"text","website":"text","description_en":"text","source_text":"text"},
    "role":      {"title":"text","employment_type":"text","seniority":"text","location":"text","start_date":"text","end_date":"text","is_current":"boolean","summary_en":"text","source_text":"text"},
    "project":   {"name":"text","kind":"text","summary_en":"text","description_en":"text","my_role_en":"text","team_size":"int","start_date":"text","end_date":"text","is_current":"boolean","url":"text","source_text":"text"},
    "education": {"kind":"text","title":"text","institution":"text","field":"text","start_date":"text","end_date":"text","credential_url":"text","description_en":"text","source_text":"text"},
    "evidence":  {"kind":"text","statement_en":"text","impact_en":"text","metrics":"jsonb","certainty":"text","inference_note":"text","source_text":"text","start_date":"text","end_date":"text"},
    "skill":     {"name":"text","category":"text","aliases":"text[]","description_en":"text"},
    "asset":     {"kind":"text","url":"text","title":"text","description_en":"text","source_text":"text","published_on":"text"}
  }';
begin
  select * into d from ingestion_drafts where id = p_draft_id for update;
  if not found then raise exception 'Draft % not found', p_draft_id; end if;
  if d.status <> 'pending' then raise exception 'Draft % is already %', p_draft_id, d.status; end if;

  for op in select * from jsonb_array_elements(d.operations) loop
    v_op := op->>'op'; v_type := op->>'type'; v_data := coalesce(op->'data', '{}'); v_ref := op->>'ref';
    v_table := case v_type when 'company' then 'companies' when 'role' then 'roles' when 'project' then 'projects'
                 when 'education' then 'education' when 'evidence' then 'evidence' when 'skill' then 'skills'
                 when 'asset' then 'assets' end;
    if v_table is null then raise exception 'Unknown entity type %', v_type; end if;

    if v_op = 'create' then
      if v_type = 'company' then
        insert into companies (name, industry, location, website, description_en, source_text, draft_id)
        values (v_data->>'name', v_data->>'industry', v_data->>'location', v_data->>'website',
                v_data->>'description_en', v_data->>'source_text', d.id)
        on conflict (user_id, name_norm) do update set
          industry = coalesce(companies.industry, excluded.industry),
          location = coalesce(companies.location, excluded.location),
          website = coalesce(companies.website, excluded.website),
          description_en = coalesce(companies.description_en, excluded.description_en)
        returning id into v_id;

      elsif v_type = 'role' then
        v_company := _resolve_ref(v_data->'company', refs, 'company');
        insert into roles (company_id, title, employment_type, seniority, location, start_date, end_date, is_current,
                           summary_en, source_text, draft_id)
        values (v_company, v_data->>'title', v_data->>'employment_type', v_data->>'seniority', v_data->>'location',
                v_data->>'start_date', v_data->>'end_date', coalesce((v_data->>'is_current')::boolean, false),
                v_data->>'summary_en', v_data->>'source_text', d.id)
        returning id into v_id;

      elsif v_type = 'project' then
        v_role := _resolve_ref(v_data->'role', refs, 'role');
        v_company := _resolve_ref(v_data->'company', refs, 'company');
        if v_company is null and v_role is not null then select company_id into v_company from roles where id = v_role; end if;
        insert into projects (role_id, company_id, kind, name, summary_en, description_en, my_role_en, team_size,
                              start_date, end_date, is_current, url, source_text, draft_id)
        values (v_role, v_company, coalesce(v_data->>'kind', case when v_role is null and v_company is null then 'personal' else 'work' end),
                v_data->>'name', v_data->>'summary_en', v_data->>'description_en', v_data->>'my_role_en',
                (v_data->>'team_size')::int, v_data->>'start_date', v_data->>'end_date',
                coalesce((v_data->>'is_current')::boolean, false), v_data->>'url', v_data->>'source_text', d.id)
        returning id into v_id;
        perform _attach_skills('project', v_id, v_data->'skills', false);

      elsif v_type = 'education' then
        insert into education (kind, title, institution, field, start_date, end_date, credential_url, description_en, source_text, draft_id)
        values (coalesce(v_data->>'kind', 'degree'), v_data->>'title', v_data->>'institution', v_data->>'field',
                v_data->>'start_date', v_data->>'end_date', v_data->>'credential_url', v_data->>'description_en',
                v_data->>'source_text', d.id)
        returning id into v_id;
        perform _attach_skills('education', v_id, v_data->'skills', false);

      elsif v_type = 'evidence' then
        v_project := _resolve_ref(v_data->'project', refs, 'project');
        v_role := _resolve_ref(v_data->'role', refs, 'role');
        v_education := _resolve_ref(v_data->'education', refs, 'education');
        insert into evidence (project_id, role_id, education_id, kind, statement_en, impact_en, metrics, certainty,
                              inference_note, source_text, start_date, end_date, draft_id)
        values (v_project, v_role, v_education, coalesce(v_data->>'kind', 'implementation'), v_data->>'statement_en',
                v_data->>'impact_en', coalesce(v_data->'metrics', '[]'), coalesce(v_data->>'certainty', 'explicit'),
                v_data->>'inference_note', v_data->>'source_text', v_data->>'start_date', v_data->>'end_date', d.id)
        returning id into v_id;
        perform _attach_skills('evidence', v_id, v_data->'skills', false);

      elsif v_type = 'skill' then
        insert into skills (name, category, aliases, description_en)
        values (v_data->>'name', coalesce(v_data->>'category', 'technology'),
                coalesce(array(select jsonb_array_elements_text(v_data->'aliases')), '{}'), v_data->>'description_en')
        on conflict (user_id, name_norm) do update set
          aliases = (select array(select distinct x from unnest(skills.aliases || excluded.aliases) x)),
          description_en = coalesce(skills.description_en, excluded.description_en)
        returning id into v_id;
      elsif v_type = 'asset' then
        insert into assets (kind, url, title, description_en, source_text, published_on,
                            company_id, role_id, project_id, evidence_id, education_id, draft_id)
        values (coalesce(v_data->>'kind', 'link'), v_data->>'url', v_data->>'title', v_data->>'description_en',
                v_data->>'source_text', v_data->>'published_on',
                _resolve_ref(v_data->'company', refs, 'company'), _resolve_ref(v_data->'role', refs, 'role'),
                _resolve_ref(v_data->'project', refs, 'project'), _resolve_ref(v_data->'evidence', refs, 'evidence'),
                _resolve_ref(v_data->'education', refs, 'education'), d.id)
        returning id into v_id;
      end if;

      if v_ref is not null then
        refs := refs || jsonb_build_object(v_ref, jsonb_build_object('id', v_id, 'type', v_type));
      end if;
      created := created || jsonb_build_object('type', v_type, 'ref', v_ref, 'id', v_id);

    elsif v_op = 'update' then
      v_id := _resolve_ref(coalesce(op->'target', jsonb_build_object('id', op->>'id')), refs, v_type);
      v_sets := '{}';
      for k in select jsonb_object_keys(v_data) loop
        v_col_type := cols->v_type->>k;
        if v_col_type is not null then
          if v_col_type = 'jsonb' then
            v_sets := v_sets || format('%I = %L::jsonb', k, v_data->k);
          elsif v_col_type = 'text[]' then
            v_sets := v_sets || format('%I = %L::text[]', k, array(select jsonb_array_elements_text(v_data->k)));
          else
            v_sets := v_sets || format('%I = %L::%s', k, v_data->>k, v_col_type);
          end if;
        end if;
      end loop;
      -- relationship changes
      if v_type = 'role' and v_data ? 'company' then
        v_sets := v_sets || format('company_id = %L::uuid', _resolve_ref(v_data->'company', refs, 'company'));
      end if;
      if v_type = 'project' and v_data ? 'role' then
        v_role := _resolve_ref(v_data->'role', refs, 'role');
        v_sets := v_sets || format('role_id = %L::uuid', v_role);
        if not v_data ? 'company' and v_role is not null then
          v_sets := v_sets || format('company_id = %L::uuid', (select company_id from roles where id = v_role));
        end if;
      end if;
      if v_type = 'project' and v_data ? 'company' then
        v_sets := v_sets || format('company_id = %L::uuid', _resolve_ref(v_data->'company', refs, 'company'));
      end if;
      if v_type = 'evidence' then
        if v_data ? 'project' then v_sets := v_sets || format('project_id = %L::uuid', _resolve_ref(v_data->'project', refs, 'project')); end if;
        if v_data ? 'role' then v_sets := v_sets || format('role_id = %L::uuid', _resolve_ref(v_data->'role', refs, 'role')); end if;
        if v_data ? 'education' then v_sets := v_sets || format('education_id = %L::uuid', _resolve_ref(v_data->'education', refs, 'education')); end if;
      end if;
      if v_type = 'asset' and (v_data ?| array['company', 'role', 'project', 'evidence', 'education']) then
        -- re-attach: exactly the given parent (others cleared)
        v_sets := v_sets
          || format('company_id = %L::uuid', _resolve_ref(v_data->'company', refs, 'company'))
          || format('role_id = %L::uuid', _resolve_ref(v_data->'role', refs, 'role'))
          || format('project_id = %L::uuid', _resolve_ref(v_data->'project', refs, 'project'))
          || format('evidence_id = %L::uuid', _resolve_ref(v_data->'evidence', refs, 'evidence'))
          || format('education_id = %L::uuid', _resolve_ref(v_data->'education', refs, 'education'));
      end if;
      if cardinality(v_sets) > 0 then
        execute format('update public.%I set %s where id = %L returning true', v_table, array_to_string(v_sets, ', '), v_id)
          into v_found;
        if v_found is null then raise exception '% % not found', v_type, v_id; end if;
      end if;
      if v_data ? 'skills' and v_type in ('evidence', 'project', 'education') then
        perform _attach_skills(v_type, v_id, v_data->'skills', coalesce((op->>'replace_skills')::boolean, true));
      end if;
      updated := updated || jsonb_build_object('type', v_type, 'id', v_id, 'fields',
                   (select coalesce(jsonb_agg(x), '[]') from jsonb_object_keys(v_data) x));

    elsif v_op = 'delete' then
      v_id := _resolve_ref(jsonb_build_object('id', op->>'id'), refs, v_type);
      execute format('delete from public.%I where id = %L returning true', v_table, v_id) into v_found;
      if v_found is null then raise exception '% % not found', v_type, v_id; end if;
      deleted := deleted || jsonb_build_object('type', v_type, 'id', v_id);

    elsif v_op = 'unlink_skill' then
      -- remove one skill from an evidence/project/education
      v_id := _resolve_ref(jsonb_build_object('id', op->>'id'), refs, v_type);
      execute format('delete from public.%I where %I = %L and skill_id = (select id from public.skills where name_norm = norm_key(%L))',
        v_type || '_skills', case v_type when 'evidence' then 'evidence_id' when 'project' then 'project_id' else 'education_id' end,
        v_id, v_data->>'skill');
      updated := updated || jsonb_build_object('type', v_type, 'id', v_id, 'unlinked_skill', v_data->>'skill');
    else
      raise exception 'Unknown op %', v_op;
    end if;
  end loop;

  -- remove skills no longer used anywhere
  delete from skills s where not exists (select 1 from evidence_skills where skill_id = s.id)
    and not exists (select 1 from project_skills where skill_id = s.id)
    and not exists (select 1 from education_skills where skill_id = s.id)
    and s.created_at < now();

  v_refresh := refresh_chunks();

  update ingestion_drafts set status = 'committed', committed_at = now(),
    result = jsonb_build_object('created', created, 'updated', updated, 'deleted', deleted)
  where id = d.id;

  return jsonb_build_object('draft_id', d.id, 'created', created, 'updated', updated, 'deleted', deleted,
                            'index', v_refresh);
end $$;

-- ---------------------------------------------------------------------------
-- Read helpers
-- ---------------------------------------------------------------------------

create or replace function public._skills_of(p_type text, p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'category', s.category, 'certainty', l.certainty) order by s.name), '[]')
  from (
    select skill_id, certainty from evidence_skills where p_type = 'evidence' and evidence_id = p_id
    union all select skill_id, certainty from project_skills where p_type = 'project' and project_id = p_id
    union all select skill_id, certainty from education_skills where p_type = 'education' and education_id = p_id
  ) l join skills s on s.id = l.skill_id
$$;

create or replace function public._assets_of(p_col text, p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'title', a.title, 'url', a.url,
           'description_en', a.description_en, 'published_on', a.published_on) order by a.created_at), '[]')
  from assets a
  where (p_col = 'company' and a.company_id = p_id) or (p_col = 'role' and a.role_id = p_id)
     or (p_col = 'project' and a.project_id = p_id) or (p_col = 'evidence' and a.evidence_id = p_id)
     or (p_col = 'education' and a.education_id = p_id)
     or (p_col = 'none' and num_nonnulls(a.company_id, a.role_id, a.project_id, a.evidence_id, a.education_id) = 0)
$$;

create or replace function public._evidence_json(e public.evidence)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'kind', e.kind, 'statement_en', e.statement_en, 'impact_en', e.impact_en, 'metrics', e.metrics,
    'certainty', e.certainty, 'inference_note', e.inference_note, 'source_text', e.source_text,
    'start_date', e.start_date, 'end_date', e.end_date, 'project_id', e.project_id, 'role_id', e.role_id,
    'education_id', e.education_id, 'skills', _skills_of('evidence', e.id), 'links', _assets_of('evidence', e.id),
    'draft_id', e.draft_id)
$$;

create or replace function public.get_entity_context(p_type text, p_id uuid)
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare
  r jsonb;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_type = 'project' then
    select jsonb_build_object(
      'project', to_jsonb(p) - 'user_id',
      'company', (select to_jsonb(c) - 'user_id' - 'name_norm' from companies c where c.id = p.company_id),
      'role', (select to_jsonb(ro) - 'user_id' from roles ro where ro.id = p.role_id),
      'project_skills', _skills_of('project', p.id),
      'links', _assets_of('project', p.id),
      'evidence', (select coalesce(jsonb_agg(_evidence_json(e) order by e.created_at), '[]') from evidence e where e.project_id = p.id),
      'all_skills_used', (select coalesce(jsonb_agg(distinct s.name), '[]') from skills s where s.id in (
          select skill_id from project_skills where project_id = p.id
          union select es.skill_id from evidence_skills es join evidence e on e.id = es.evidence_id where e.project_id = p.id)),
      'sibling_projects', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name)), '[]')
                           from projects x where x.role_id = p.role_id and x.id <> p.id))
      into r from projects p where p.id = p_id;
  elsif p_type = 'role' then
    select jsonb_build_object(
      'role', to_jsonb(ro) - 'user_id',
      'company', (select to_jsonb(c) - 'user_id' - 'name_norm' from companies c where c.id = ro.company_id),
      'projects', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'kind', p.kind, 'summary_en', p.summary_en,
                     'start_date', p.start_date, 'end_date', p.end_date,
                     'evidence_count', (select count(*) from evidence e where e.project_id = p.id)) order by p.start_date nulls last), '[]')
                   from projects p where p.role_id = ro.id),
      'links', _assets_of('role', ro.id),
      'role_level_evidence', (select coalesce(jsonb_agg(_evidence_json(e)), '[]') from evidence e where e.role_id = ro.id and e.project_id is null))
      into r from roles ro where ro.id = p_id;
  elsif p_type = 'company' then
    select jsonb_build_object(
      'company', to_jsonb(c) - 'user_id' - 'name_norm',
      'links', _assets_of('company', c.id),
      'roles', (select coalesce(jsonb_agg(jsonb_build_object('id', ro.id, 'title', ro.title, 'start_date', ro.start_date,
                  'end_date', ro.end_date, 'is_current', ro.is_current,
                  'projects', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name)), '[]') from projects p where p.role_id = ro.id))
                  order by ro.start_date nulls last), '[]') from roles ro where ro.company_id = c.id))
      into r from companies c where c.id = p_id;
  elsif p_type = 'evidence' then
    select jsonb_build_object(
      'evidence', _evidence_json(e),
      'project', (select jsonb_build_object('id', p.id, 'name', p.name, 'summary_en', p.summary_en) from projects p where p.id = e.project_id),
      'role', (select jsonb_build_object('id', ro.id, 'title', ro.title) from roles ro
               where ro.id = coalesce(e.role_id, (select role_id from projects where id = e.project_id))),
      'company', (select jsonb_build_object('id', c.id, 'name', c.name) from companies c where c.id = coalesce(
                    (select company_id from projects where id = e.project_id),
                    (select company_id from roles where id = coalesce(e.role_id, (select role_id from projects where id = e.project_id))))),
      'education', (select jsonb_build_object('id', ed.id, 'title', ed.title) from education ed where ed.id = e.education_id))
      into r from evidence e where e.id = p_id;
  elsif p_type = 'education' then
    select jsonb_build_object(
      'education', to_jsonb(ed) - 'user_id',
      'skills', _skills_of('education', ed.id),
      'links', _assets_of('education', ed.id),
      'evidence', (select coalesce(jsonb_agg(_evidence_json(e)), '[]') from evidence e where e.education_id = ed.id))
      into r from education ed where ed.id = p_id;
  elsif p_type = 'skill' then
    select jsonb_build_object(
      'skill', to_jsonb(s) - 'user_id' - 'name_norm' - 'aliases_norm',
      'evidence', (select coalesce(jsonb_agg(_evidence_json(e)), '[]') from evidence e join evidence_skills es on es.evidence_id = e.id where es.skill_id = s.id),
      'projects', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', p.id, 'name', p.name)), '[]') from projects p
                   where p.id in (select project_id from project_skills where skill_id = s.id
                                  union select e.project_id from evidence e join evidence_skills es on es.evidence_id = e.id where es.skill_id = s.id)))
      into r from skills s where s.id = p_id;
  elsif p_type = 'asset' then
    select jsonb_build_object(
      'asset', to_jsonb(a) - 'user_id',
      'attached_to', case
        when a.evidence_id is not null then (select jsonb_build_object('type', 'evidence', 'id', e.id, 'statement_en', e.statement_en, 'project_id', e.project_id) from evidence e where e.id = a.evidence_id)
        when a.project_id is not null then (select jsonb_build_object('type', 'project', 'id', p.id, 'name', p.name) from projects p where p.id = a.project_id)
        when a.role_id is not null then (select jsonb_build_object('type', 'role', 'id', ro.id, 'title', ro.title) from roles ro where ro.id = a.role_id)
        when a.company_id is not null then (select jsonb_build_object('type', 'company', 'id', c.id, 'name', c.name) from companies c where c.id = a.company_id)
        when a.education_id is not null then (select jsonb_build_object('type', 'education', 'id', ed.id, 'title', ed.title) from education ed where ed.id = a.education_id)
        else jsonb_build_object('type', 'profile') end)
      into r from assets a where a.id = p_id;
  else
    raise exception 'Unknown entity type %', p_type;
  end if;
  return r;
end $$;

create or replace function public.profile_overview()
returns jsonb
language sql stable
set search_path = public
as $$
  select jsonb_build_object(
    'stats', jsonb_build_object(
      'companies', (select count(*) from companies), 'roles', (select count(*) from roles),
      'projects', (select count(*) from projects), 'evidence', (select count(*) from evidence),
      'education', (select count(*) from education), 'skills', (select count(*) from skills),
      'links', (select count(*) from assets),
      'chunks_pending_embedding', (select count(*) from knowledge_chunks where embedding is null)),
    'companies', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'industry', c.industry,
        'roles', (select coalesce(jsonb_agg(jsonb_build_object(
            'id', ro.id, 'title', ro.title, 'employment_type', ro.employment_type,
            'start_date', ro.start_date, 'end_date', ro.end_date, 'is_current', ro.is_current,
            'projects', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', p.id, 'name', p.name, 'kind', p.kind, 'start_date', p.start_date, 'end_date', p.end_date,
                'evidence_count', (select count(*) from evidence e where e.project_id = p.id)) order by p.start_date nulls last), '[]')
              from projects p where p.role_id = ro.id)) order by ro.start_date desc nulls last), '[]')
          from roles ro where ro.company_id = c.id),
        'projects_without_role', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name)), '[]')
          from projects p where p.company_id = c.id and p.role_id is null))
      order by c.name), '[]') from companies c),
    'projects_outside_companies', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'kind', p.kind, 'start_date', p.start_date, 'end_date', p.end_date,
        'evidence_count', (select count(*) from evidence e where e.project_id = p.id)) order by p.start_date desc nulls last), '[]')
      from projects p where p.company_id is null and p.role_id is null),
    'education', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', ed.id, 'kind', ed.kind, 'title', ed.title, 'institution', ed.institution,
        'start_date', ed.start_date, 'end_date', ed.end_date) order by ed.end_date desc nulls first), '[]') from education ed),
    'skills', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'category', x.category, 'evidence_count', x.n)
        order by x.n desc, x.name), '[]')
      from (select s.id, s.name, s.category,
              (select count(*) from evidence_skills es where es.skill_id = s.id) n from skills s) x),
    'profile_links', _assets_of('none', null),
    'pending_drafts', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'created_at', d.created_at, 'summary', d.summary)
        order by d.created_at desc), '[]') from ingestion_drafts d where d.status = 'pending')
  )
$$;

-- Similar existing evidence (for duplicate detection in drafts)
create or replace function public.similar_chunks(query_embedding text, p_entity_type text, min_similarity float default 0.9, max_results int default 3)
returns table (entity_id uuid, title text, content text, similarity float)
language sql stable
set search_path = public, extensions
as $$
  select kc.entity_id, kc.title, kc.content, (1 - (kc.embedding <=> query_embedding::extensions.vector(384)))::float
  from knowledge_chunks kc
  where kc.user_id = auth.uid() and kc.entity_type = p_entity_type and kc.embedding is not null
    and 1 - (kc.embedding <=> query_embedding::extensions.vector(384)) >= min_similarity
  order by kc.embedding <=> query_embedding::extensions.vector(384)
  limit max_results
$$;

-- Only authenticated users may call these; never anon.
revoke execute on all functions in schema public from anon, public;
grant execute on function
  public.refresh_chunks(), public.set_chunk_embeddings(jsonb), public.invalidate_embeddings(),
  public.query_skill_ids(text, text[]),
  public.hybrid_search(text, text, int, text[], uuid[], uuid[], uuid[], text[], text[], text, text, boolean, float, float, float, int),
  public._resolve_ref(jsonb, jsonb, text), public._attach_skills(text, uuid, jsonb, boolean), public.commit_draft(uuid),
  public._skills_of(text, uuid), public._assets_of(text, uuid), public._evidence_json(public.evidence), public.get_entity_context(text, uuid),
  public.profile_overview(), public.similar_chunks(text, text, float, int)
to authenticated;
