# Backend work the app is waiting for

Updated for app version 0.2.0 (2), 11 November 2026. The app side of every item below is built and tested against fixtures. Nothing here was tested against a live HCG service, because none of these contracts exist yet. Main HCG and the News website are frozen for about half a week. This list is what to pick up when they reopen.

## A. News website (publication owner) — content API

**Blocking live reading.** The site has no supported read API or feed (see [SITE-INSPECTION-2026-11-11.md](SITE-INSPECTION-2026-11-11.md)). Its internal TanStack server functions are not a contract. Implement [HCG-NEWS-CONTENT-API-PROPOSAL.md](HCG-NEWS-CONTENT-API-PROPOSAL.md), or confirm an alternative, and supply:

1. `GET meta` with `contractVersion: "1"` and `capabilities` (`search`, `searchFilters`, `fullContent`).
2. `GET home`, `GET sections` (including the `politics` hierarchy, if editors want it shown), `GET articles?section=&cursor=`, `GET articles/{id}`, and optionally `GET search?q=&section=&type=&cursor=`.
3. Stable article ids, canonical URLs, `status` and `access`. Apply the site's visibility rule (published and `published_at <= now`) on the server.
4. A body as structured blocks or HTML. Use `{"format":"summary"}` when only a summary may be shown.
5. Editorial metadata where it exists: `revision` (or `updatedAt`), `corrections`, `sponsor` (for `sponsored`), `audio` (HTTPS), `related` (editor-chosen), `breaking`, `isFeatured`.
6. **Authors with stable ids**, and their disclosures attached to the author record. The current disclosure text shown on the site is recorded in the inspection doc; the API must return it for the verified author id.
7. Renaming the two published `draft-<uuid>` slugs, with redirects.

## B. News website (publication owner) — newsroom API

**Blocking remote editorial actions.** Local drafting works without it. Implement [NEWSROOM-API-PROPOSAL.md](NEWSROOM-API-PROPOSAL.md):

1. `GET capabilities` listing **supported** and **allowed** actions for the token's subject, plus verified authors and sections.
2. Draft create/update with `baseRevision` and a `409` conflict that includes the current summary.
3. Actions: submit, approve, schedule, publish, correct, unpublish, each with server-side permission checks matching the site's role rules.
4. Media upload, editorial queue and audit history.
5. Section, author and media management endpoints, only if native administration is wanted. Otherwise provide central management links (C5).

## C. Main HCG (ERP / Executive Control Center, HCG Connect)

See [HCG-MAIN-CONFIGURATION-HANDOFF.md](HCG-MAIN-CONFIGURATION-HANDOFF.md) for the full field list. The new items found in this milestone are:

1. **Register a new public native client** for HCG News: PKCE required, no secret, redirect `com.hakmicapitalgroup.hcgnews:/oauth/callback` (PROPOSED). Do not reuse the website's or CardX's client.
2. **App Access endpoint.** In addition to the fields already proposed, it may return:
   - `displayName` and `email` (verified identity, shown in Account);
   - `organizations: [{id, name}]` and `organizationID`, honouring `?organization=<id>` for selection;
   - `entitlements: [{id, name, status, validUntil}]` for licence or subscription status.

   All of these are optional. The app shows only what is returned.
3. **Permission naming:** the newsroom permission (proposed `news.newsroom.open`). The newsroom service (B1) must apply the same central decision.
4. Logout scope (`local` / `global`), token lifetimes, refresh rotation, and how revocation surfaces.
5. `connect.managementLinks`: HTTPS HCG URLs for the sections, authors and media management pages, and the ERP pages to show in Administration.

## D. Not requested now (the app states these are unavailable)

| Feature | Needed before it can work |
|---|---|
| Push notifications | APNs registration (Push capability, APNs key held server-side), a notification service, and an editorial rule for what triggers a send. Topic preferences are already kept on the device. |
| Saved-article sync | A central per-user storage contract and account-linking rules |
| Subscriptions / payments | A product decision. The app shows HCG-reported entitlements only, and implements no purchases. |
| Published audio | `audio` in the content API (A5) |
| Offline copies of restricted articles | An agreed access and retention policy. Until then they are refused. |

## E. Packaging (separate from runtime configuration)

See [PACKAGING.md](PACKAGING.md). Nothing in A–D affects how the project builds or packages. Configuration is installed at runtime, through Settings › Advanced › Import, or as an optional bundled file.
