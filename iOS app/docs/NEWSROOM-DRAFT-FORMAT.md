# HCG News draft file format (`hcg-news-draft`, version 1)

Local drafts can be exported and imported as a single JSON file (`*.hcgnews-draft.json`). Use it to hand work to the newsroom while no newsroom API exists, to move drafts between devices, or as a backup.

- **An export is never a submission.** It contains no server link, server revision or upload state.
- **An import always creates a new local draft** with a new id, and new ids for every media file. It never replaces an existing draft.
- Readers of this format must refuse a `version` higher than they understand. The app does this, and explains it.

## Top level

```json
{
  "format": "hcg-news-draft",
  "version": 1,
  "exportedAt": "2026-11-11T09:30:00.000Z",
  "generator": "HCG News iOS 0.2.0 (2)",
  "draft": { … },
  "media": [ { "id": "UUID", "filename": "cover.jpg", "mimeType": "image/jpeg", "data": "<base64>" } ]
}
```

## `draft`

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Replaced on import |
| `createdAt`, `updatedAt` | ISO 8601 | |
| `headline`, `standfirst` | string | `standfirst` is the introduction |
| `blocks` | array of Block | Body, in order |
| `sectionSlug`, `sectionName` | string? | From the publication's sections |
| `editorialTypeWire` | string? | `news`, `analysis`, `opinion`, `sponsored`, `announcement` |
| `authors` | array of `{id, name, title?}` | Verified authors only; never free text |
| `cover` | ImageMeta? | Cover image |
| `attachments` | array of `{id, filename, mimeType, byteCount, addedAt, uploadState}` | `uploadState` is always `{"localOnly":{}}` in exports |
| `localRevision` | int | Local save counter |
| `serverLink`, `detachedNote` | — | Always absent in exports |

**Block:** `{"id": UUID, "kind": "paragraph" | "heading" | "bulletList" | "numberedList" | "quote" | "image", "text": string, "attribution": string, "image": ImageMeta?}`.

- List items are separate lines of `text`.
- Inline markup inside `text`: `**bold**`, `*italic*`, and `[label](https://…)`. Only `https`, `http` and `mailto` links survive.

**ImageMeta:** `{"attachmentID": UUID?, "caption": string, "credit": string, "altText": string}`. `attachmentID` refers to an entry in `media` / `attachments`.

## Media

Images only: JPEG, PNG, HEIC, WebP or GIF, at most 25 MB each, base64-encoded. Other types are skipped on import.
