# HCG News Newsroom API v1 — PROPOSAL

Status: **PROPOSED. No such API exists.** The publication's own editor uses internal TanStack server functions (see [SITE-INSPECTION-2026-11-11.md](SITE-INSPECTION-2026-11-11.md)), which are not a supported interface. The app's client (`HCGNewsKit/Sources/Newsroom/NewsroomService.swift`) implements exactly this shape. It is used only when a publication configuration names `content.newsroomAPIBaseURL`. Until then, the newsroom workspace is local-drafting only, and every remote action states why it is unavailable.

## Principles

- **Authorisation is server-side.** Every request carries the reader's HCG Connect access token (`Authorization: Bearer …`). The service verifies it with HCG and applies its own editorial permissions to every call. The app never decides who may publish.
- **What is supported and what is allowed are separate.** `capabilities` lists what the service *implements* (`supportedActions`) and what it *authorises for this account right now* (`allowedActions`). The app offers an action only when both include it, and only when HCG App Access is granted (and names `connect.newsroomPermission`, if configured).
- **Nothing is automatic.** The app never queues, retries or submits in the background. Each request follows an explicit user action.
- **Optimistic concurrency.** Every update carries `baseRevision`. If the server holds a newer revision, it answers `409` with its current summary and changes nothing. The app then offers "keep mine as a separate local draft" or "load the newsroom version". It never overwrites.

## Endpoints (relative to `content.newsroomAPIBaseURL`)

| Method & path | Purpose | Success response |
|---|---|---|
| `GET capabilities` | Contract version, supported/allowed actions, verified authors, sections | `{"contractVersion":"1","supportedActions":[…],"allowedActions":[…],"authors":[{"id","name","title"}],"sections":[Section]}` |
| `GET queue` | Editorial queue visible to this account | `{"items":[ServerDraftSummary]}` |
| `GET drafts/{id}` | One server draft, for conflict resolution | `{"summary":ServerDraftSummary,"draft":Draft}` |
| `POST drafts` | Create a server draft from a local draft (status `draft`) | `ServerDraftSummary` |
| `PUT drafts/{id}` | Update a server draft; body includes `baseRevision` | `ServerDraftSummary` |
| `POST drafts/{id}/actions/{action}` | `submit`, `approve`, `schedule` (`scheduleAt`), `publish`, `correct` (`note` = correction text), `unpublish` (`note` = reason); body includes `baseRevision` | `ServerDraftSummary` |
| `POST media?filename=…` | Upload one image (raw body, `Content-Type` = image MIME type) | `{"id":"<remote media id>"}` |
| `GET audit[?draft=id]` | Audit history recorded by the service | `{"items":[{"id","at","actor","action","articleID","detail"}]}` |

Action names: `save_draft`, `submit`, `approve`, `schedule`, `publish`, `correct`, `unpublish`, `upload_media`, `view_queue`, `view_audit`, `manage_sections`, `manage_authors`, `manage_media`.

`ServerDraftSummary`: `{"id","headline","status","revision","updatedAt","updatedBy","scheduledFor"}`. `status` uses the publication's own vocabulary (`draft`, `in_review`, `approved`, `published`, `archived`, plus `scheduled` if the service has it).

`Draft` uses the same shape as the export format in [NEWSROOM-DRAFT-FORMAT.md](NEWSROOM-DRAFT-FORMAT.md) (`draft` object). The service may map it to its own storage. `media` in a save body maps local attachment UUIDs to uploaded media ids.

## Errors

| Status | Meaning | App behaviour |
|---|---|---|
| `401` | Token missing or expired | "Sign in with HCG Connect first" |
| `403` `{"message":…}` | Not authorised for this action | The server's message is shown; nothing changes locally |
| `404` / `501` | Endpoint or action not implemented | Treated as unavailable |
| `409` `{"current":ServerDraftSummary}` | Newer server revision | Conflict sheet; nothing overwritten |
| `422` `{"problems":[…]}` | Validation failed | The problems are listed |
| other | Server error | Generic failure; local work kept |

## Required server behaviour (for review)

1. Verify the HCG Connect token, and resolve the subject's newsroom role from the publication's own role store (`owner`, `editor_in_chief`, `editor`, `journalist`, `contributor` were observed), mapped through central App Access.
2. Enforce the publication's existing rules. The site's code shows that only owner and editor-in-chief may set `published` or `archived`, editors may approve, and others may submit.
3. Never accept a byline for an author id that isn't a verified author record.
4. Record every write in the audit log.
5. Keep `unpublish` and `correct` reversible and auditable. Corrections must appear in the public article's `corrections` (see the content API proposal).
