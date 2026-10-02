---
name: career-rag
description: Use the career-rag MCP server (the user's private professional memory). Use whenever the user talks about their own work experience, projects, achievements, skills, studies or CV; wants to add, correct or delete career information; asks "what experience do I have with X"; wants a CV, cover letter, LinkedIn text or interview answers based on their real experience; or pastes a job offer to compare against their profile. Explains the data model, the English-only semantic layer, the two-step draft→commit write flow and the job-matching workflow.
---

# Career RAG

The `career-rag` MCP server stores the user's whole professional history in Supabase (Postgres + pgvector).
The backend has **no LLM**: you (the agent) do all understanding, structuring and translation; the server
validates, stores, indexes and retrieves. It never invents experience — and neither may you.

The user usually speaks **Spanish**. Talk to them in their language. Only the semantic layer is English.

## Data model

```
Company ──< Role ──< Project ──< Evidence >── Skill
                 └──< Evidence (role-level, e.g. mentoring)
Project (kind=personal|open_source, no company/role)
Education (degree|certification|course|bootcamp) ──< Evidence
Asset (link) ── attached to ONE of company / role / project / evidence / education, or none (profile-level)
```

| Entity | What it is | Key fields |
|---|---|---|
| company | Employer/client | name, industry, location, description_en |
| role | A job/position at a company | title, employment_type, seniority, start_date, end_date, is_current, summary_en |
| project | Unit of work inside a role, or a personal project | name, kind, summary_en (required), description_en, my_role_en, team_size, dates |
| **evidence** | ONE concrete thing the user did/achieved/designed/implemented/led | statement_en (required), kind, impact_en, metrics, certainty, inference_note, source_text |
| education | Degree / certification / course | title, kind, institution, field, dates |
| skill | Technology, practice, capability, domain or spoken language | name, category, aliases |
| asset | A link: repo, demo, talk, article, video, certificate… | url, title (required), kind, description_en, published_on, source_text |

- **Projects and evidence are the retrieval units**, not jobs. The user's experience is multidisciplinary:
  capture architecture, leadership, business, mentoring, etc. as evidence too.
- evidence.kind: `achievement | responsibility | implementation | design | leadership | mentoring | business | research | communication | other`
- skill.category: `technology` (languages, frameworks, tools, cloud) · `practice` (TDD, DDD, event-driven, IaC) ·
  `capability` (leadership, architecture, mentoring, stakeholder management) · `domain` (fintech, logistics) · `language`
- Dates: `YYYY`, `YYYY-MM` or `YYYY-MM-DD`. Ongoing → omit end_date, `is_current: true`.
- Companies and skills are de-duplicated by normalized name ("Fast API" = "FastAPI").
- `knowledge_chunks` is a derived index (rebuilt from the tables); never reason about it directly.

## Language rules (why English)

Embeddings use Supabase's built-in `gte-small`, which is **English-only**. Therefore:

- Every `*_en` field (`statement_en`, `summary_en`, `description_en`, `my_role_en`, `impact_en`) and every
  search `query_en` / `requirement_en` **must be English**. Translate and normalize yourself.
- `source_text` keeps the user's **original words, untranslated** (provenance). Always fill it for
  evidence, using the relevant excerpt of what they said. `prepare_changes.source_text` = their full message.
- Skill names: canonical English/industry names ("Kafka", "Team leadership", not "liderazgo de equipos").
- Write `statement_en` as a self-contained, search-friendly sentence: action verb + what + how/tech + context
  (+ result). Good: "Designed an asynchronous order-processing backend with Kafka consumers and FastAPI services."
  Bad: "Did the backend." Split long stories into several evidence items (one achievement each).

## Explicit vs inferred

- `certainty: "explicit"` only if the user actually said it.
- Anything you deduce (a skill implied by a technology, team coordination implied by a lead role…) →
  `certainty: "inferred"` + `inference_note` explaining why. Skills can be inferred individually:
  `{"name": "Python", "certainty": "inferred"}`.
- Never upgrade inferred to explicit without the user confirming. When presenting results, flag inferred items.

## Tools

| Tool | Use |
|---|---|
| `get_profile_overview` | Skeleton with ids: companies → roles → projects, personal projects, education, skills, pending drafts. Call first. |
| `search_career` | Hybrid search (vector + full text + exact skill match + filters). English query. |
| `get_entity` | Full context of a project (company, role, all evidence with source_text, skills) or role/company/evidence/education/skill. |
| `match_job_requirements` | Per-requirement evidence + `coverage_signal` (strong/partial/weak/none). |
| `prepare_changes` | Step 1 of writes: validates and stores a PENDING draft, returns preview + warnings. |
| `commit_draft` | Step 2: `commit` (after explicit user OK) / `discard` / `show`. |
| `reindex` | Only if a response reports pending embeddings: call until `remaining` is 0. |

## Workflow: adding experience

1. `get_profile_overview` (and `search_career` if needed) → reuse existing company/role/project **ids**.
   Never invent ids; never re-create something that exists.
2. If key facts are missing (dates, which company, what *they* did vs the team), ask briefly. Don't fabricate.
3. Build operations in order with refs: company (`ref:"c1"`) → role (`company:{ref:"c1"}`) → project
   (`role:{ref:"r1"}`) → evidence (`project:{ref:"p1"}`, with skills). Existing entities: `{"id":"<uuid>"}`.
4. `prepare_changes` → show the user, **in their language**, a readable summary of the preview and all
   warnings (duplicates, non-English text, missing provenance, inferred items).
5. Only after an explicit "sí/ok/confirm": `commit_draft(action:"commit")`. If they want changes, prepare a new
   draft and `discard` the old one.
6. If the commit result says embeddings remain, call `reindex` until `remaining: 0`.

Large histories: one company or a few projects per draft.

Minimal example:

```json
{"source_text": "En Acme fui consultor (2019-2021) y diseñé un backend asíncrono con Kafka",
 "source_language": "es",
 "operations": [
  {"op":"create","type":"company","ref":"c1","data":{"name":"Acme"}},
  {"op":"create","type":"role","ref":"r1","data":{"company":{"ref":"c1"},"title":"Consultant","employment_type":"consulting","start_date":"2019","end_date":"2021"}},
  {"op":"create","type":"project","ref":"p1","data":{"role":{"ref":"r1"},"name":"Asynchronous backend","summary_en":"Asynchronous event-driven backend platform."}},
  {"op":"create","type":"evidence","data":{"project":{"ref":"p1"},"kind":"design",
    "statement_en":"Designed an asynchronous event-driven backend based on Kafka.",
    "source_text":"diseñé un backend asíncrono con Kafka",
    "skills":[{"name":"Kafka","category":"technology"},{"name":"Event-driven architecture","category":"practice","certainty":"inferred"}]}}
 ]}
```

## Workflow: links (assets)

- `{"op":"create","type":"asset","data":{"project":{"id":"<uuid>"},"kind":"talk","title":"…","url":"https://…",
  "description_en":"…","published_on":"2023-05","source_text":"…"}}`
- kind: `repo | demo | website | article | talk | video | image | document | certificate | publication | link | other`.
- Attach to the most specific item it supports: evidence > project > role/education > company. No parent =
  profile-level link (GitHub profile, portfolio, LinkedIn).
- **description_en is what makes a link findable** (embeddings are text-only): say in English what it shows
  and why it matters. For a video or image the user shares, describe its content; for a repo, what it does and
  its stack. Keep the link's own skills on the evidence/project it is attached to.
- Only store URLs the user actually gave you; never guess or "fix" URLs. Links are returned in every
  `get_entity` result under `links`, and assets also appear in `search_career` (entity_type `asset`).
- When writing CVs / answers, cite the relevant links as supporting material.

## Workflow: corrections and deletions

- Find the target with `search_career` / `get_entity` to get its id.
- `{"op":"update","type":"evidence","id":"<uuid>","data":{...only changed fields...}}`.
  On update, `skills` **replaces** the set unless `"replace_skills": false`.
- `{"op":"unlink_skill","type":"evidence","id":"<uuid>","data":{"skill":"Kafka"}}`.
- `{"op":"delete","type":"project","id":"<uuid>"}`: deleting a project deletes its evidence and links; deleting a
  role deletes its role-level evidence. Always explain this in the preview.
- Same draft → confirm → commit flow.

## Workflow: questions about the user's experience

- Translate the question into an English `query_en`. For a technology, search its name ("Terraform").
  For a concept, use descriptive English ("experience designing asynchronous backend systems").
- Use filters when useful: `entity_types`, `required_skills`, `company_ids`, `date_from/date_to`, `project_kinds`.
- **Technology questions ("what experience do I have with X"): always run a second search with
  `required_skills`** set to every stored skill name for that technology (check `get_profile_overview`
  for variants, e.g. "netcode" → `["Unity Netcode", "Netcode for GameObjects"]`). A plain text query is
  not enough: exact skill matching only fires when the query equals the skill name, and a project whose
  text is about something else (where the tech is only in its skill list) ranks low and falls below
  `limit`, behind unrelated semantic hits. Lesson learned: "netcode" without the filter missed
  TV3 — ISE, which was tagged Unity Netcode.
- Before saying "there's no evidence of X", confirm with the `required_skills` filter.
- Skill `aliases` make a plain query hit the exact skill match (e.g. "Netcode"/"NGO" on both Unity
  Netcode skills). When a short or common name misses a skill, propose adding it as an alias
  (`op:"update", type:"skill"`, same draft → confirm → commit flow).
- Open the best hits with `get_entity` before writing CVs or answers that need detail.
- Empty or weak results mean there's no stored evidence: say so; don't fill gaps with invention.

## Workflow: job offers

1. Extract requirements from the offer yourself and rewrite each as a short English `requirement_en`
   (one per item), with `importance` (must/nice) and the explicit `skills` it names.
2. `match_job_requirements`.
3. Report per requirement: what evidence covers it (quote statement_en, project, company, dates), whether
   it's explicit or inferred, and honest gaps for `none`/`weak`. Verify `partial` by reading the evidence.
   Check "N years of X" against role/project dates yourself.
4. If the user then remembers relevant experience that wasn't stored, offer to add it (draft → confirm).

## Workflow: writing a CV (or cover letter / one-pager)

1. `get_document(kind:"cv_style_reference")` FIRST. Follow `style_guide_md` exactly (one A4 page, two columns,
   typography, colors, section order, bullet style). `content_text` is only there to show tone and structure:
   **never copy facts from it**. To see the original, download `download_url` (signed, about 10 minutes), for
   example with `curl -L -o reference.pdf '<url>'`. It contains personal data: don't publish it.
2. Content comes only from the RAG: run `match_job_requirements` against the offer, then `search_career` and
   `get_entity` for the chosen projects. Use explicit evidence; flag inferred items to the user before using them.
3. Tailor everything to the offer (headline, profile, role framing, skills heading). Write in the offer's language.
4. Produce HTML/CSS (or DOCX) and print to PDF on one A4 page. Check that it does not overflow. Name the file
   `Firstname_Lastname_COMPANY_Role_CV.pdf`.

## Never

- Invent ids, experience, metrics or dates.
- Write non-English text into `*_en` fields, or drop `source_text`.
- Commit without explicit user confirmation.
- Present inferred evidence as fact.
