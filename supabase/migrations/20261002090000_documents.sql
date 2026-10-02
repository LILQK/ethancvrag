-- Documents: owner files kept in private Storage (e.g. the CV style reference), with a text
-- representation (style guide / content) that agents can read inline through the MCP.

insert into storage.buckets (id, name, public, file_size_limit)
values ('documents', 'documents', false, 20971520)
on conflict (id) do nothing;

-- Objects live under "<auth.uid()>/..." and are only visible to that user.
create policy documents_owner_select on storage.objects for select to authenticated
  using (bucket_id = 'documents' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy documents_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy documents_owner_update on storage.objects for update to authenticated
  using (bucket_id = 'documents' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy documents_owner_delete on storage.objects for delete to authenticated
  using (bucket_id = 'documents' and (storage.foldername(name))[1] = (select auth.uid())::text);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('cv_style_reference', 'cv', 'cover_letter_reference', 'portfolio', 'other')),
  title text not null check (length(title) between 1 and 300),
  description_en text,
  storage_path text not null,            -- path inside the 'documents' bucket: <user_id>/<file>
  mime_type text not null,
  size_bytes bigint,
  style_guide_md text,                   -- how to reproduce the look & structure (no personal data needed)
  content_text text,                     -- extracted plain text of the file
  is_primary boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.documents (user_id, kind);
create trigger trg_documents_updated before update on public.documents for each row execute function public.set_updated_at();

alter table public.documents enable row level security;
alter table public.documents force row level security;
revoke all on public.documents from anon, public;
grant select, insert, update, delete on public.documents to authenticated;
create policy owner_all on public.documents for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
