import { McpServer } from "npm:@modelcontextprotocol/sdk@1.25.3/server/mcp.js";
import { z } from "npm:zod@^4.1.13";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { embed, embedPending, looksNonEnglish, toolError, toolResult } from "./lib.ts";

// ---------------------------------------------------------------------------
// Shared vocabulary
// ---------------------------------------------------------------------------
const ENTITY_TYPES = ["company", "role", "project", "evidence", "education"] as const;
const WRITE_TYPES = ["company", "role", "project", "education", "evidence", "skill"] as const;
const TABLE: Record<string, string> = {
  company: "companies", role: "roles", project: "projects", education: "education", evidence: "evidence", skill: "skills",
};
const DATE = z.string().regex(/^\d{4}(-(0[1-9]|1[0-2])(-(0[1-9]|[12]\d|3[01]))?)?$/, "Use YYYY, YYYY-MM or YYYY-MM-DD");
const UUID = z.string().uuid();

const SERVER_INSTRUCTIONS = `Career RAG: the user's private professional memory (companies, roles, projects, evidence, education, skills).
Projects and EVIDENCE (concrete things the user did, achieved, designed, implemented or led) are the main retrieval units.

Rules for every client:
1. SEARCH BEFORE ASSUMING. Call get_profile_overview or search_career before saying something does or does not exist, and before creating companies/roles/projects that may already exist.
2. NEVER INVENT IDS. Only use ids returned by this server. To link new items created in the same draft, use {"ref": "..."} references.
3. ENGLISH SEMANTIC TEXT. All *_en fields and every query must be in English (embeddings are English-only, model gte-small). Translate/normalize yourself before calling.
4. KEEP PROVENANCE. Put the user's original words (any language, verbatim or near-verbatim excerpt) in source_text. Never drop it.
5. EXPLICIT vs INFERRED. Mark certainty="inferred" (with inference_note) for anything the user did not state explicitly. Never present inferences as facts.
6. CONFIRM WRITES. Writes are two-step: prepare_changes creates a draft -> show the preview to the user -> only after the user explicitly confirms, call commit_draft(action="commit").
7. NO FABRICATION. This server never generates experience; only store what the user told you. When matching job offers, report gaps honestly.`;

// ---------------------------------------------------------------------------
// Schemas for writes
// ---------------------------------------------------------------------------
const Link = z.object({
  id: UUID.optional().describe("Existing entity id returned by this server"),
  ref: z.string().min(1).max(64).optional().describe("Local ref of an entity created EARLIER in the same operations list"),
}).describe('Link to another entity: {"id": "<uuid from this server>"} or {"ref": "<ref created earlier in this draft>"}');

const SkillInput = z.union([
  z.string().min(1).max(120),
  z.object({
    name: z.string().min(1).max(120).describe('Canonical English name, e.g. "Kafka", "FastAPI", "Terraform", "Event-driven architecture", "Team leadership"'),
    category: z.enum(["technology", "practice", "capability", "domain", "language", "other"]).optional()
      .describe("technology = languages/frameworks/tools/platforms/cloud; practice = methods & techniques (TDD, DDD, event-driven); capability = leadership, architecture, mentoring, business, stakeholder mgmt...; domain = industry knowledge; language = spoken language"),
    certainty: z.enum(["explicit", "inferred"]).optional().describe("explicit if the user mentioned it, inferred if you deduced it"),
    aliases: z.array(z.string().max(120)).max(10).optional().describe('Alternative spellings, e.g. ["Apache Kafka"]'),
  }),
]);

const EntityData = z.object({
  // identity / text
  name: z.string().min(1).max(300).optional().describe("company | project | skill: name"),
  title: z.string().min(1).max(300).optional().describe("role: job title (e.g. 'Senior Backend Consultant'); education: degree/certification title"),
  kind: z.string().optional().describe(
    "project: work|personal|open_source|freelance|academic|other. education: degree|certification|course|bootcamp|other. " +
    "evidence: achievement|responsibility|implementation|design|leadership|mentoring|business|research|communication|other"),
  category: z.enum(["technology", "practice", "capability", "domain", "language", "other"]).optional().describe("skill only"),
  aliases: z.array(z.string().max(120)).max(10).optional().describe("skill only"),
  // English semantic fields
  summary_en: z.string().max(4000).optional().describe("ENGLISH. role: short summary; project (required on create): what the project was, its goal and context"),
  description_en: z.string().max(8000).optional().describe("ENGLISH. company/project/education/skill: longer description"),
  my_role_en: z.string().max(2000).optional().describe("ENGLISH. project: what the user personally did/was responsible for"),
  statement_en: z.string().min(3).max(4000).optional().describe(
    "ENGLISH. evidence (required): ONE concrete, self-contained statement of what the user did, written for semantic search, " +
    "e.g. 'Designed an asynchronous order-processing backend using Kafka consumers and FastAPI services, handling 2M events/day.'"),
  impact_en: z.string().max(2000).optional().describe("ENGLISH. evidence: outcome / business impact"),
  metrics: z.array(z.object({ name: z.string().max(200), value: z.string().max(200) })).max(20).optional()
    .describe('evidence: quantified results, e.g. [{"name":"p95 latency","value":"-40%"}]'),
  certainty: z.enum(["explicit", "inferred"]).optional().describe("evidence: explicit (user said it) or inferred (you deduced it). Default explicit"),
  inference_note: z.string().max(1000).optional().describe("evidence: REQUIRED when certainty=inferred: why you inferred it"),
  source_text: z.string().max(8000).optional().describe("Provenance: the user's ORIGINAL words for this item, in their language. Do not translate."),
  // facts
  industry: z.string().max(200).optional().describe("company"),
  location: z.string().max(200).optional().describe("company | role"),
  website: z.string().max(500).optional().describe("company"),
  employment_type: z.enum(["full_time", "part_time", "contract", "freelance", "consulting", "internship", "founder", "volunteer", "other"]).optional().describe("role"),
  seniority: z.string().max(100).optional().describe("role: e.g. junior, mid, senior, lead, principal, manager, director"),
  institution: z.string().max(300).optional().describe("education"),
  field: z.string().max(300).optional().describe("education: field of study"),
  credential_url: z.string().max(500).optional().describe("education"),
  url: z.string().max(500).optional().describe("project"),
  team_size: z.number().int().min(1).max(100000).optional().describe("project"),
  start_date: DATE.nullable().optional().describe("YYYY | YYYY-MM | YYYY-MM-DD"),
  end_date: DATE.nullable().optional().describe("YYYY | YYYY-MM | YYYY-MM-DD; omit/null if ongoing"),
  is_current: z.boolean().optional().describe("role | project: still ongoing"),
  // relationships
  company: Link.nullable().optional().describe("role | project: company"),
  role: Link.nullable().optional().describe("project | evidence: role (job) it belongs to"),
  project: Link.nullable().optional().describe("evidence: project it belongs to (preferred anchor for evidence)"),
  education: Link.nullable().optional().describe("evidence: education item it belongs to (e.g. thesis work)"),
  skills: z.array(SkillInput).max(40).optional().describe(
    "evidence | project | education: skills/technologies/capabilities demonstrated. On update, the list REPLACES existing links unless replace_skills=false"),
  skill: z.string().max(120).optional().describe("unlink_skill only: skill name to unlink"),
}).strict();

const Operation = z.object({
  op: z.enum(["create", "update", "delete", "unlink_skill"]),
  type: z.enum(WRITE_TYPES),
  ref: z.string().min(1).max(64).optional().describe("create only: local name (e.g. 'p1') so later operations can link to it with {\"ref\":\"p1\"}"),
  id: UUID.optional().describe("update | delete | unlink_skill: id of the existing entity (from this server)"),
  data: EntityData.optional(),
  replace_skills: z.boolean().optional().describe("update only: false = add skills instead of replacing the set"),
});

const REQUIRED_ON_CREATE: Record<string, string[]> = {
  company: ["name"], role: ["title"], project: ["name", "summary_en"], education: ["title"], evidence: ["statement_en"], skill: ["name"],
};
const ALLOWED_FIELDS: Record<string, string[]> = {
  company: ["name", "industry", "location", "website", "description_en", "source_text"],
  role: ["title", "employment_type", "seniority", "location", "start_date", "end_date", "is_current", "summary_en", "source_text", "company"],
  project: ["name", "kind", "summary_en", "description_en", "my_role_en", "team_size", "start_date", "end_date", "is_current", "url", "source_text", "role", "company", "skills"],
  education: ["kind", "title", "institution", "field", "start_date", "end_date", "credential_url", "description_en", "source_text", "skills"],
  evidence: ["kind", "statement_en", "impact_en", "metrics", "certainty", "inference_note", "source_text", "start_date", "end_date", "project", "role", "education", "skills"],
  skill: ["name", "category", "aliases", "description_en"],
};
const KINDS: Record<string, string[]> = {
  project: ["work", "personal", "open_source", "freelance", "academic", "other"],
  education: ["degree", "certification", "course", "bootcamp", "other"],
  evidence: ["achievement", "responsibility", "implementation", "design", "leadership", "mentoring", "business", "research", "communication", "other"],
};
const LINK_TYPES: Record<string, string> = { company: "company", role: "role", project: "project", education: "education" };
const EN_FIELDS = ["summary_en", "description_en", "my_role_en", "statement_en", "impact_en"];

type Op = z.infer<typeof Operation>;

function normSkill(s: z.infer<typeof SkillInput>) {
  return typeof s === "string" ? { name: s } : s;
}
const normKey = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}+#]+/gu, "");

// ---------------------------------------------------------------------------
// Tool registration
// ---------------------------------------------------------------------------
export function buildServer(db: SupabaseClient) {
  const server = new McpServer(
    { name: "career-rag", version: "1.0.0" },
    { instructions: SERVER_INSTRUCTIONS },
  );

  const wrap = <A>(fn: (args: A) => Promise<unknown>) => async (args: A) => {
    try {
      return toolResult(await fn(args));
    } catch (e) {
      return toolError(e instanceof Error ? e.message : String(e));
    }
  };

  // -------------------------------------------------------------------------
  server.registerTool("get_profile_overview", {
    title: "Get career profile overview",
    description:
      "Returns the full skeleton of the user's career with ids: companies -> roles -> projects (with evidence counts), " +
      "projects outside companies (personal/open source), education, all skills with evidence counts, pending drafts and index stats. " +
      "Call this FIRST in a session, before adding experience (to reuse existing companies/roles/projects ids instead of duplicating them) " +
      "and whenever you need ids. It does not include evidence text: use search_career or get_entity for details.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, wrap(async () => {
    const { data, error } = await db.rpc("profile_overview");
    if (error) throw new Error(error.message);
    return data;
  }));

  // -------------------------------------------------------------------------
  server.registerTool("search_career", {
    title: "Search career memory (hybrid)",
    description:
      "Hybrid search over the user's career: semantic vector search (gte-small) + full-text search + exact skill/technology matching, " +
      "fused with reciprocal rank fusion, plus structured filters. Works for concepts ('experience designing asynchronous backend systems') " +
      "and exact technologies ('Kafka', 'Terraform', 'FastAPI'). The query MUST be in English (translate the user's question first). " +
      "Results are evidence/projects/roles/companies/education chunks with entity ids, scores and signals " +
      "(semantic_similarity, fts_rank, matched_skills) and certainty (explicit/inferred: never present inferred items as facts). " +
      "Use get_entity with a returned id for full context. An empty result means nothing stored matches: say so, do not invent.",
    inputSchema: {
      query_en: z.string().min(1).max(1000).describe("Search query in ENGLISH"),
      entity_types: z.array(z.enum(ENTITY_TYPES)).optional().describe("Restrict to these entity types, e.g. ['evidence','project']. Default: all"),
      limit: z.number().int().min(1).max(50).optional().describe("Max results (default 10)"),
      company_ids: z.array(UUID).optional().describe("Filter: only these companies (ids from this server)"),
      role_ids: z.array(UUID).optional(),
      project_ids: z.array(UUID).optional(),
      project_kinds: z.array(z.enum(["work", "personal", "open_source", "freelance", "academic", "other"])).optional(),
      required_skills: z.array(z.string()).optional().describe("Filter: only items linked to at least one of these skills/technologies (matched by normalized name or alias)"),
      date_from: DATE.optional().describe("Filter: items overlapping this period start (YYYY[-MM[-DD]])"),
      date_to: DATE.optional(),
      include_inferred: z.boolean().optional().describe("Include evidence marked as inferred (default true)"),
    },
    annotations: { readOnlyHint: true },
  }, wrap(async (a: {
    query_en: string; entity_types?: string[]; limit?: number; company_ids?: string[]; role_ids?: string[]; project_ids?: string[];
    project_kinds?: string[]; required_skills?: string[]; date_from?: string; date_to?: string; include_inferred?: boolean;
  }) => {
    const pending = await embedPending(db, 4, 6000);
    const rows = await hybrid(db, a.query_en, {
      match_count: a.limit ?? 10, entity_types: a.entity_types, company_ids: a.company_ids, role_ids: a.role_ids,
      project_ids: a.project_ids, project_kinds: a.project_kinds, required_skills: a.required_skills,
      date_from: a.date_from, date_to: a.date_to, include_inferred: a.include_inferred ?? true,
    });
    return {
      query_en: a.query_en,
      ...(looksNonEnglish(a.query_en) ? { warning: "Query does not look like English; semantic search works best in English." } : {}),
      ...(pending.remaining > 0 ? { note: `${pending.remaining} chunks still awaiting embeddings; call reindex to finish.` } : {}),
      results: rows.map(shapeHit),
    };
  }));

  // -------------------------------------------------------------------------
  server.registerTool("get_entity", {
    title: "Get an entity with full context",
    description:
      "Returns one entity with its full context. For a PROJECT: the project, its company, its role, all its evidence (with skills, " +
      "certainty, source_text provenance), project skills, all skills used and sibling projects. Also supports role, company, evidence, " +
      "education and skill (skill returns all evidence/projects using it). Use only ids returned by this server.",
    inputSchema: {
      entity_type: z.enum(["project", "role", "company", "evidence", "education", "skill"]),
      id: UUID,
    },
    annotations: { readOnlyHint: true },
  }, wrap(async (a: { entity_type: string; id: string }) => {
    const { data, error } = await db.rpc("get_entity_context", { p_type: a.entity_type, p_id: a.id });
    if (error) throw new Error(error.message);
    if (!data) throw new Error(`${a.entity_type} ${a.id} not found. Do not guess ids: use search_career or get_profile_overview.`);
    return data;
  }));

  // -------------------------------------------------------------------------
  server.registerTool("match_job_requirements", {
    title: "Match job requirements to evidence",
    description:
      "For a job offer: YOU (the client) first extract the requirements from the offer and rewrite each as a short ENGLISH requirement " +
      "(one per item, e.g. 'Production experience with Kafka', '5+ years building Python backends', 'Mentoring junior engineers'), " +
      "optionally with the key skills/technologies it names. This tool returns, per requirement, the best matching evidence/projects " +
      "from the user's memory with scores and a heuristic coverage_signal (strong | partial | weak | none) based on semantic similarity and " +
      "exact skill matches. It never invents experience: treat 'none'/'weak' as gaps, and verify 'partial' by reading the evidence. " +
      "Years-of-experience requirements must be checked against dates yourself.",
    inputSchema: {
      job_title: z.string().max(300).optional(),
      requirements: z.array(z.object({
        id: z.string().max(50).optional().describe("Your own label, e.g. 'R1'"),
        requirement_en: z.string().min(3).max(1000).describe("Requirement in ENGLISH"),
        importance: z.enum(["must", "nice", "unknown"]).optional(),
        skills: z.array(z.string().max(120)).max(15).optional().describe("Technologies/skills explicitly named in the requirement"),
      })).min(1).max(40),
      per_requirement: z.number().int().min(1).max(10).optional().describe("Evidence items per requirement (default 3)"),
      include_inferred: z.boolean().optional().describe("Default true; inferred evidence is flagged"),
    },
    annotations: { readOnlyHint: true },
  }, wrap(async (a: {
    job_title?: string; requirements: { id?: string; requirement_en: string; importance?: string; skills?: string[] }[];
    per_requirement?: number; include_inferred?: boolean;
  }) => {
    await embedPending(db, 4, 6000);
    const k = a.per_requirement ?? 3;
    const out = [];
    for (const [i, r] of a.requirements.entries()) {
      const q = r.skills?.length ? `${r.requirement_en} (${r.skills.join(", ")})` : r.requirement_en;
      const rows = await hybrid(db, q, {
        match_count: k, entity_types: ["evidence", "project", "education"], include_inferred: a.include_inferred ?? true,
      });
      const best = rows[0];
      const bestSim = Math.max(0, ...rows.map((x) => x.semantic_similarity ?? 0));
      const skillHit = rows.some((x) => (x.matched_skills ?? []).length > 0);
      const explicitHit = rows.some((x) => x.certainty === "explicit" && ((x.semantic_similarity ?? 0) >= SIM_STRONG || (x.matched_skills ?? []).length));
      let signal: "strong" | "partial" | "weak" | "none" = "none";
      if (best) {
        if ((skillHit && bestSim >= SIM_PARTIAL) || bestSim >= SIM_STRONG) signal = explicitHit ? "strong" : "partial";
        else if (skillHit || bestSim >= SIM_PARTIAL) signal = "partial";
        else if (bestSim >= SIM_WEAK) signal = "weak";
      }
      out.push({
        requirement_id: r.id ?? `R${i + 1}`, requirement_en: r.requirement_en, importance: r.importance ?? "unknown",
        coverage_signal: signal, best_semantic_similarity: round(bestSim),
        matched_skills: [...new Set(rows.flatMap((x) => x.matched_skills ?? []))],
        evidence: signal === "none" ? [] : rows.map(shapeHit),
      });
    }
    const counts = out.reduce((acc, r) => ({ ...acc, [r.coverage_signal]: (acc[r.coverage_signal] ?? 0) + 1 }), {} as Record<string, number>);
    return {
      job_title: a.job_title, summary: counts, requirements: out,
      guidance: "coverage_signal is a retrieval heuristic, not a judgment. Read the evidence before claiming a match; report gaps honestly.",
    };
  }));

  // -------------------------------------------------------------------------
  server.registerTool("prepare_changes", {
    title: "Prepare a draft of career changes (step 1 of 2)",
    description:
      "STEP 1 of the write flow. Turn what the user told you into structured operations and store them as a PENDING DRAFT. Nothing is " +
      "saved to the career memory until commit_draft(action='commit') is called after the user explicitly confirms the preview.\n" +
      "Before calling: use get_profile_overview/search_career to find existing companies/roles/projects and link to their ids instead of " +
      "re-creating them. Never invent ids.\n" +
      "Operations are applied in order. create ops may set a 'ref' that later ops link to with {\"ref\":\"...\"}; existing entities are linked " +
      "with {\"id\":\"<uuid>\"}. Typical hierarchy: company -> role (data.company) -> project (data.role) -> evidence (data.project) with skills.\n" +
      "Model the user's experience as PROJECTS and EVIDENCE: one evidence = one concrete thing they did/achieved/designed/implemented/led. " +
      "Split long stories into several evidence items. Personal projects: project with kind='personal' and no role/company.\n" +
      "Language: all *_en fields in ENGLISH (normalized for semantic search); source_text keeps the user's ORIGINAL words (provenance). " +
      "Mark anything the user did not state as certainty='inferred' with an inference_note (also for inferred skills).\n" +
      "Corrections: use op='update' with the entity id and only the fields to change (for evidence, 'skills' replaces the skill set unless " +
      "replace_skills=false), op='delete' to remove (deleting a project deletes its evidence; deleting a role deletes its role-level evidence), " +
      "op='unlink_skill' with data.skill to drop one skill. Companies and skills are de-duplicated by normalized name automatically.\n" +
      "Returns draft_id, a human-readable preview, and warnings (possible duplicates, non-English text, missing provenance). Show the preview " +
      "and warnings to the user and ask for confirmation; fix issues by preparing a new draft (and discarding the old one).\n" +
      'Example: {"source_text":"En Acme fui consultor y diseñé un backend asíncrono con Kafka","source_language":"es","operations":[' +
      '{"op":"create","type":"company","ref":"c1","data":{"name":"Acme"}},' +
      '{"op":"create","type":"role","ref":"r1","data":{"company":{"ref":"c1"},"title":"Consultant","employment_type":"consulting"}},' +
      '{"op":"create","type":"project","ref":"p1","data":{"role":{"ref":"r1"},"name":"Order processing backend","summary_en":"Asynchronous backend for order processing"}},' +
      '{"op":"create","type":"evidence","data":{"project":{"ref":"p1"},"kind":"design","statement_en":"Designed an asynchronous backend based on Kafka","source_text":"diseñé un backend asíncrono con Kafka","skills":[{"name":"Kafka","category":"technology"},{"name":"Event-driven architecture","category":"practice","certainty":"inferred"}]}}]}',
    inputSchema: {
      source_text: z.string().min(1).max(20000).describe("The user's original message(s) this draft is based on, verbatim, in their language"),
      source_language: z.string().max(20).optional().describe("ISO code of source_text, e.g. 'es'"),
      operations: z.array(Operation).min(1).max(200),
    },
  }, wrap(async (a: { source_text: string; source_language?: string; operations: Op[] }) => {
    return await prepareDraft(db, a);
  }));

  // -------------------------------------------------------------------------
  server.registerTool("commit_draft", {
    title: "Commit, discard or show a draft (step 2 of 2)",
    description:
      "STEP 2 of the write flow. action='commit' applies a pending draft atomically (all or nothing) and re-indexes search. " +
      "ONLY call commit after the user has explicitly confirmed the preview in this conversation. action='discard' abandons it. " +
      "action='show' returns the stored operations and warnings. Returns created ids (with their refs).",
    inputSchema: {
      draft_id: UUID,
      action: z.enum(["commit", "discard", "show"]),
    },
    annotations: { destructiveHint: true },
  }, wrap(async (a: { draft_id: string; action: "commit" | "discard" | "show" }) => {
    if (a.action === "show") {
      const { data, error } = await db.from("ingestion_drafts").select("*").eq("id", a.draft_id).maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) throw new Error("Draft not found");
      return data;
    }
    if (a.action === "discard") {
      const { data, error } = await db.from("ingestion_drafts").update({ status: "discarded" })
        .eq("id", a.draft_id).eq("status", "pending").select("id, status").maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) throw new Error("Draft not found or not pending");
      return data;
    }
    const { data, error } = await db.rpc("commit_draft", { p_draft_id: a.draft_id });
    if (error) throw new Error(`Commit failed, nothing was saved: ${error.message}`);
    let index = { embedded: 0, remaining: 0 };
    try {
      index = await embedPending(db, 8, 15000);
    } catch (e) {
      index = { embedded: 0, remaining: -1, ...{ error: String(e) } } as typeof index;
    }
    return { status: "committed", ...data, embeddings: index,
      ...(index.remaining > 0 ? { note: "Some chunks still need embeddings: call reindex until remaining is 0." } : {}) };
  }));

  // -------------------------------------------------------------------------
  server.registerTool("reindex", {
    title: "Rebuild the derived search index",
    description:
      "Maintenance. Rebuilds knowledge chunks from the structured data (source of truth) and computes missing embeddings in batches. " +
      "Call repeatedly while 'remaining' > 0. force=true re-embeds everything (e.g. after a model change). Not needed after normal commits.",
    inputSchema: {
      force: z.boolean().optional(),
      batch_size: z.number().int().min(1).max(50).optional().describe("Chunks to embed in this call (default 8; edge CPU limits allow ~10 per call)"),
    },
    annotations: { idempotentHint: true },
  }, wrap(async (a: { force?: boolean; batch_size?: number }) => {
    const { data: refresh, error } = await db.rpc("refresh_chunks");
    if (error) throw new Error(error.message);
    if (a.force) {
      const { error: e2 } = await db.rpc("invalidate_embeddings");
      if (e2) throw new Error(e2.message);
    }
    const res = await embedPending(db, a.batch_size ?? 8, 20000);
    return { refresh, ...res };
  }));

  return server;
}

// ---------------------------------------------------------------------------
// Retrieval helpers
// ---------------------------------------------------------------------------
// Similarity thresholds for gte-small (normalized cosine). Calibrated empirically:
// unrelated career texts typically score ~0.70-0.78, related ones 0.80+.
const SIM_STRONG = 0.86;
const SIM_PARTIAL = 0.845;
const SIM_WEAK = 0.825;
// Hits supported ONLY by semantic similarity below this floor are noise for gte-small.
const SIM_FLOOR = 0.815;
const round = (n: number | null | undefined) => (n == null ? null : Math.round(n * 1000) / 1000);

type Hit = {
  entity_type: string; entity_id: string; title: string; content: string; score: number; semantic_similarity: number | null;
  fts_rank: number | null; matched_skills: string[]; company_id: string | null; role_id: string | null; project_id: string | null;
  project_kind: string | null; certainty: string; start_date: string | null; end_date: string | null; is_current: boolean; skill_names: string[];
};

async function hybrid(db: SupabaseClient, query: string, f: Record<string, unknown>): Promise<Hit[]> {
  const { data, error } = await db.rpc("hybrid_search", {
    query_text: query, query_embedding: await embed(query), ...Object.fromEntries(Object.entries(f).filter(([, v]) => v !== undefined)),
  });
  if (error) throw new Error(`search failed: ${error.message}`);
  return ((data ?? []) as Hit[]).filter((h) =>
    h.fts_rank != null || (h.matched_skills ?? []).length > 0 || (h.semantic_similarity ?? 0) >= SIM_FLOOR);
}

function shapeHit(h: Hit) {
  return {
    entity_type: h.entity_type, id: h.entity_id, title: h.title,
    text: h.content.length > 900 ? h.content.slice(0, 900) + "…" : h.content,
    certainty: h.certainty, period: [h.start_date, h.is_current ? "present" : h.end_date],
    score: round(h.score), signals: { semantic_similarity: round(h.semantic_similarity), fts_rank: round(h.fts_rank), matched_skills: h.matched_skills },
    skills: h.skill_names, project_id: h.project_id, role_id: h.role_id, company_id: h.company_id,
  };
}

// ---------------------------------------------------------------------------
// Draft preparation: validation + duplicate detection (no writes to career data)
// ---------------------------------------------------------------------------
async function prepareDraft(db: SupabaseClient, a: { source_text: string; source_language?: string; operations: Op[] }) {
  const errors: string[] = [];
  const warnings: string[] = [];
  const preview: string[] = [];
  const refs = new Map<string, string>(); // ref -> type
  const idsToCheck: Record<string, Set<string>> = {};
  const need = (type: string, id: string) => (idsToCheck[type] ??= new Set()).add(id);

  const ops = a.operations.map((o) => ({ ...o, data: o.data ? { ...o.data } : undefined }));

  ops.forEach((o, i) => {
    const at = `operations[${i}] (${o.op} ${o.type})`;
    const d = (o.data ?? {}) as Record<string, unknown>;
    for (const k of Object.keys(d)) {
      if (o.op === "unlink_skill" ? k !== "skill" : !ALLOWED_FIELDS[o.type].includes(k)) {
        errors.push(`${at}: field '${k}' is not allowed for ${o.type}. Allowed: ${ALLOWED_FIELDS[o.type].join(", ")}`);
      }
    }
    if (o.op === "create") {
      for (const f of REQUIRED_ON_CREATE[o.type]) if (d[f] == null || d[f] === "") errors.push(`${at}: '${f}' is required`);
      if (o.id) errors.push(`${at}: create must not have an id (ids are generated by the server)`);
      if (o.ref) {
        if (refs.has(o.ref)) errors.push(`${at}: duplicate ref '${o.ref}'`);
        refs.set(o.ref, o.type);
      }
    } else {
      if (!o.id) errors.push(`${at}: 'id' of an existing ${o.type} is required`);
      else need(o.type, o.id);
      if (o.ref) errors.push(`${at}: ref is only valid on create`);
      if (o.op === "unlink_skill" && (!["evidence", "project", "education"].includes(o.type) || !d.skill)) {
        errors.push(`${at}: unlink_skill needs type evidence|project|education and data.skill`);
      }
      if (o.op === "update" && Object.keys(d).length === 0) errors.push(`${at}: nothing to update`);
    }
    if (d.kind != null && KINDS[o.type] && !KINDS[o.type].includes(String(d.kind))) {
      errors.push(`${at}: kind must be one of ${KINDS[o.type].join("|")}`);
    }
    if (d.kind != null && !KINDS[o.type]) errors.push(`${at}: 'kind' is not valid for ${o.type}`);
    for (const lk of ["company", "role", "project", "education"]) {
      const link = d[lk] as { id?: string; ref?: string } | null | undefined;
      if (!link) continue;
      if (!!link.id === !!link.ref) { errors.push(`${at}: ${lk} link needs exactly one of id or ref`); continue; }
      if (link.ref) {
        if (!refs.has(link.ref)) errors.push(`${at}: ${lk}.ref '${link.ref}' is not created earlier in this draft`);
        else if (refs.get(link.ref) !== LINK_TYPES[lk]) errors.push(`${at}: ${lk}.ref '${link.ref}' is a ${refs.get(link.ref)}`);
      } else if (link.id) need(LINK_TYPES[lk], link.id);
    }
    if (o.type === "evidence" && o.op === "create") {
      if (!d.project && !d.role && !d.education) warnings.push(`${at}: evidence is not linked to any project, role or education`);
      if (!d.source_text) warnings.push(`${at}: no source_text (provenance) for this evidence`);
      if (d.certainty === "inferred" && !d.inference_note) warnings.push(`${at}: inferred evidence without inference_note`);
    }
    for (const f of EN_FIELDS) {
      if (typeof d[f] === "string" && looksNonEnglish(d[f] as string)) warnings.push(`${at}: ${f} does not look like English; *_en fields must be English`);
    }
    if (Array.isArray(d.skills)) d.skills = (d.skills as z.infer<typeof SkillInput>[]).map(normSkill);
    if (d.start_date && d.end_date && String(d.start_date) > String(d.end_date)) warnings.push(`${at}: start_date is after end_date`);
  });

  // Existence of referenced ids (RLS: only the owner's rows are visible)
  for (const [type, set] of Object.entries(idsToCheck)) {
    const ids = [...set];
    const { data, error } = await db.from(TABLE[type]).select("id").in("id", ids);
    if (error) throw new Error(error.message);
    const found = new Set((data ?? []).map((r: { id: string }) => r.id));
    for (const id of ids) if (!found.has(id)) errors.push(`${type} id ${id} does not exist. Use ids returned by search_career/get_profile_overview; never invent ids.`);
  }

  if (errors.length) return { status: "invalid", errors, warnings, hint: "Fix the errors and call prepare_changes again. Nothing was stored." };

  // Duplicate hints
  const createdNames = (type: string, field: string) =>
    ops.filter((o) => o.op === "create" && o.type === type).map((o) => String((o.data as Record<string, unknown>)[field]));
  const companyNames = createdNames("company", "name");
  if (companyNames.length) {
    const { data } = await db.from("companies").select("id, name, name_norm");
    for (const n of companyNames) {
      const hit = (data ?? []).find((c: { name_norm: string }) => c.name_norm === normKey(n));
      if (hit) warnings.push(`company "${n}" already exists (id ${hit.id}); it will be reused, not duplicated. Prefer linking with {"id":"${hit.id}"}.`);
    }
  }
  const projectNames = createdNames("project", "name");
  if (projectNames.length) {
    const { data } = await db.from("projects").select("id, name");
    for (const n of projectNames) {
      const hit = (data ?? []).find((p: { name: string }) => normKey(p.name) === normKey(n));
      if (hit) warnings.push(`a project named "${hit.name}" already exists (id ${hit.id}). Is this the same project? If so link to it instead of creating a new one.`);
    }
  }
  const roleCreates = ops.filter((o) => o.op === "create" && o.type === "role");
  if (roleCreates.length) {
    const { data } = await db.from("roles").select("id, title, company_id");
    for (const o of roleCreates) {
      const d = o.data as Record<string, { id?: string } | string>;
      const cid = (d.company as { id?: string } | undefined)?.id;
      const hit = (data ?? []).find((r: { title: string; company_id: string }) => normKey(r.title) === normKey(String(d.title)) && (!cid || r.company_id === cid));
      if (hit && cid) warnings.push(`role "${d.title}" already exists at that company (id ${hit.id}). Link to it if it is the same job.`);
    }
  }
  const evid = ops.filter((o) => o.op === "create" && o.type === "evidence").slice(0, 15);
  for (const o of evid) {
    const st = String((o.data as Record<string, unknown>).statement_en);
    const { data } = await db.rpc("similar_chunks", { query_embedding: await embed(st), p_entity_type: "evidence", min_similarity: 0.92, max_results: 2 });
    for (const h of (data ?? []) as { entity_id: string; content: string; similarity: number }[]) {
      warnings.push(`evidence "${st.slice(0, 80)}" is very similar (${round(h.similarity)}) to existing evidence ${h.entity_id}: "${h.content.slice(0, 120)}…". Consider updating it instead.`);
    }
  }

  // Human-readable preview
  for (const o of ops) {
    const d = (o.data ?? {}) as Record<string, unknown>;
    const label = d.name ?? d.title ?? d.statement_en ?? "";
    const skills = Array.isArray(d.skills) ? ` [skills: ${(d.skills as { name: string; certainty?: string }[]).map((s) => s.name + (s.certainty === "inferred" ? " (inferred)" : "")).join(", ")}]` : "";
    const cert = d.certainty === "inferred" ? " (INFERRED)" : "";
    const target = o.id ? ` ${o.id}` : o.ref ? ` as ${o.ref}` : "";
    const fields = o.op === "update"
      ? ` set: ${Object.entries(d).filter(([k]) => k !== "skills").map(([k, v]) => `${k}=${JSON.stringify(v).slice(0, 160)}`).join("; ")}`
      : "";
    preview.push(`${o.op.toUpperCase()} ${o.type}${target}: ${String(label).slice(0, 200)}${cert}${skills}${fields}`.trim());
  }
  const counts: Record<string, number> = {};
  for (const o of ops) counts[`${o.op}_${o.type}`] = (counts[`${o.op}_${o.type}`] ?? 0) + 1;

  const { data: draft, error } = await db.from("ingestion_drafts").insert({
    source_text: a.source_text, source_language: a.source_language ?? null, operations: ops,
    summary: { counts, preview }, warnings,
  }).select("id, status, created_at").single();
  if (error) throw new Error(error.message);

  return {
    draft_id: draft.id, status: "pending", counts, preview, warnings,
    next_step: "Show this preview (and warnings) to the user. Only after explicit confirmation call commit_draft with action='commit'. " +
      "To change something, prepare a new draft and discard this one.",
  };
}
