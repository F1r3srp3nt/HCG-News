# Manual acceptance checklist (simulator and device)

For app 0.2.0 (2). Run on **an iPhone and an iPad** (simulator first, then a device), in **Light, Dark and System** appearance.

- **F** = with development fixtures: scheme environment variable `HCGNEWS_UI_TEST_FIXTURES=1`, plus optionally `HCGNEWS_UI_TEST_OFFLINE=1`, `HCGNEWS_UI_TEST_EMPTY=1` and `HCGNEWS_UI_TEST_RESET=1`.
- **L** = live: the bundled HCG platform configuration, against the real publication (see INTEGRATION-REPORT.md). Use **test content only** for anything that writes: never edit, publish or archive a real story to test.

Mark each item ☐ pass / ☐ fail / ☐ not run.

## Brand and layout
- [ ] F — Masthead: the HCG logo (silver with cyan light lines) on black, at its own proportions (never stretched or cropped), "NEWS" beside it, and today's date.
- [ ] F — The app icon on the home screen, in Settings and in Spotlight is the supplied HCG News icon (brushed-silver newspaper with "HCG NEWS" and cyan edges), on iPhone and iPad.
- [ ] F — About and Account show "A Hakmi Capital Group publication" with the Hakmi Capital Group mark.
- [ ] F — Cyan appears only on actions and status (buttons, links, the breaking marker, download state). There are no large blue panels.
- [ ] F — Appearance: System, Light and Dark switch everything, including sheets. Increase Contrast strengthens secondary text and separators.

## Configuration (Settings › Advanced)
- [ ] Settings › Advanced shows "Connected to the HCG platform · production · news.hakmicapitalgroup.com" (bundled). Check Connection gives "Connected" or a specific failure.
- [ ] A build with the bundled `HCGNewsConfiguration.json` removed: Home says "Publication not connected", with "Open Advanced Settings" and a web link. No sample articles.
- [ ] Import a valid publication file: the preview shows environment and destinations before anything changes. Apply. Status "Configured". Check Connection gives "Connected" (L) or a specific failure.
- [ ] Import a file with `client_secret`, an `http://` URL, a placeholder, or `approvedByFounder: false`: shown as unusable, and the previous configuration stays active.
- [ ] Force-quit and relaunch: the imported configuration is still active.
- [ ] Remove the imported configuration: the bundled one (or "Not configured") applies.
- [ ] Import a Connect file with a different client id while signed in (L): a warning before applying, then signed out. Local drafts lose their newsroom link but keep their text. Saved articles are unchanged.
- [ ] Diagnostics: export, then confirm it contains no tokens, client id or public key.

## Home, sections, search
- [ ] F — "Featured" appears only for editor-flagged stories. Without any, the lead is labelled "Top story".
- [ ] F — Labels: News, Analysis, Opinion, Sponsored (outlined, distinct) and HCG Announcement.
- [ ] F — Breaking: one headline at a time, with previous/next. Nothing scrolls by itself. Reduce Motion makes changes instant.
- [ ] F — The section strip and the Sections list include the orphan section (unknown parent kept).
- [ ] F — Open an article, go back: the list is at the same place. Rotate the iPad: the same article stays open.
- [ ] F with OFFLINE — "You're offline" with Try Again. EMPTY — "No articles yet". Empty section — "Nothing in … yet".
- [ ] L — Pull to refresh, then airplane mode and refresh again: the loaded articles stay, with an inline "Showing what was loaded earlier" notice.
- [ ] F — Search: the scope is stated ("This session" / "Downloaded"). Filters work. Without a connection, Downloaded search still works.

## Reader
- [ ] F — Headline, introduction, byline, published and updated dates. Disclosure box. Correction box. Sponsored notice (on a sponsored article).
- [ ] F — Embedded content and unsupported blocks show notices, and the rest of the article renders.
- [ ] F — Tap an image: full screen, pinch and double-tap zoom, Close button, caption and credit. VoiceOver reads the alt text.
- [ ] F — Reading settings: text size (including accessibility sizes), line spacing, reading width (iPad), typeface.
- [ ] F — Text is selectable. Share offers the canonical `https://news.hakmicapitalgroup.com/…` URL only.
- [ ] F — Read aloud is labelled "On-device voice (not a publication recording)" and stops when you leave the article.
- [ ] F — Scroll halfway, leave, reopen: "Continue where you left off" scrolls to the saved position.
- [ ] F — "Fixture headline 11" shows "Only a summary is available" with a web link, and offers no download.
- [ ] F — Restricted article: "Sign-in required", with an honest explanation.

## Saved and offline
- [ ] F — Save, force-quit, relaunch: still in Saved, marked "Not downloaded".
- [ ] F — Download, force-quit, relaunch with OFFLINE: Saved shows "Downloaded · … images unavailable offline" (fixture images aren't fetchable). Opening it shows "Stored copy from …" and the full text.
- [ ] Device — Download a live article (L), enable airplane mode, force-quit, reopen: it reads fully, images included.
- [ ] F — Force-quit during a download (tap Download, then immediately swipe the app away): next launch shows "Download interrupted" and Resume Downloads.
- [ ] F — Remove Download (Keep Saved): the bookmark remains. Remove All Downloads empties storage, and the bookmarks remain.
- [ ] F — Set the limit to 100 MB: the limit is enforced with a clear message (a small limit or a large article may be needed to trigger it).
- [ ] Upgrade from 0.1.0 (device with saved articles): all bookmarks appear, a migration notice shows once, and `bookmarks.v1-backup.json` exists in the app container.
- [ ] L — After the publication updates an article: the download shows "update available", and Update Download refreshes it.

## HCG platform: reading (L)
- [ ] Fresh install, no sign-in: Home shows the publication's published articles. No drafts, scheduled stories or "Untitled article" rows appear.
- [ ] An article matches the website: headline, excerpt, byline, section, label, date, image with caption and credit, body, sources and correction note.
- [ ] An article by the founder shows "Author disclosure: Yasin Ludvigsen Hakmi is a politician affiliated with FrP and FpU."
- [ ] Demo articles show "DEMO CONTENT" and never appear as breaking news.
- [ ] Share gives `https://news.hakmicapitalgroup.com/<section>/<slug>`, and it opens the same article on the website.
- [ ] Sections list matches the website's visible sections; a section feed shows only its articles. Pagination loads more without duplicates.
- [ ] Search finds a headline word; the section and type filters narrow results; nonsense gives "No results".
- [ ] Airplane mode: loaded content stays with a notice, downloads open, and errors say offline (not "not connected").

## HCG platform: account and access (L)
- [ ] Settings › HCG Account: HCG-branded sign-in. A wrong password says so plainly, and the password field is cleared.
- [ ] Sign in with an **ordinary** HCG account: "No newsroom role". No Newsroom in Settings or the sidebar; ⌘⇧N shows "Newsroom access required".
- [ ] Sign in with **your owner account**: the roles shown match HCG App Access (nothing is hard-coded). The Newsroom appears.
- [ ] HCG workspaces: ERP and Executive Control Center show HCG's decision. **Open** launches Safari already signed in to that page, via a one-time link. Tapping Open again works (a fresh link each time).
- [ ] Remove a newsroom role centrally (in the ERP), return to the app: within a minute the Newsroom disappears (and closes, if open). Restore the role afterwards.
- [ ] Sign out: the message says whether HCG ended the session. The Newsroom disappears. Signing in with a different account shows only that account's data.
- [ ] Revoke the session centrally (or change the password on the website), then return to the app: "session expired or was revoked", and you're signed out.
- [ ] Force-quit while signed in: still signed in after relaunch.

## HCG platform: newsroom (L, test draft only)
- [ ] New Draft creates "Untitled article" on HCG; it also appears in the website newsroom.
- [ ] Edit the headline, slug ("From Headline"), section, type, byline, body blocks (bold, italic, link, list, quote, image), cover image (library and upload, with required alt text), flags, SEO, tags, sources and correction note. Save. Reload the website newsroom: identical.
- [ ] An existing article with embeds or styled content says the body can't be edited in the app. Saving other fields leaves its body untouched on the website.
- [ ] Unsaved-edit protection: edit, force-quit, reopen the article: "Unsaved edits … stored on this device" → Restore Edits.
- [ ] Conflict: open the test draft in the app and on the website, save on the website, then save in the app: "Edited Elsewhere". Both choices behave as described, and nothing is overwritten without an explicit Save.
- [ ] Journalist or Contributor test account: only Submit for Review is offered; others' articles are read-only.
- [ ] Editor-in-Chief or Administrator: Approve, then Publish or Schedule… lists problems and needs the confirmation toggle. **Schedule the test draft for a future date**, confirm it does NOT appear on the website or in the app's public lists, then Return to Draft (cancels scheduling).
- [ ] Archive asks for confirmation. Version History lists status changes; "Copy into Editor" doesn't save until Save.
- [ ] Administration: sections can be added, renamed or hidden (Editor-in-Chief or Administrator only); the audit history appears for Administrators only.
- [ ] Delete the test draft in the website newsroom when finished.

## Account (OAuth configuration, when one is registered — L unless noted)
- [ ] F — Without Connect configuration: "Sign-in isn't set up for this app yet". Public reading works.
- [ ] Sign in with the system browser. Cancel gives "Sign-in was cancelled", with no request made.
- [ ] Identity and organisation appear only as HCG returns them. Several organisations offer a picker, and switching re-checks access.
- [ ] Capabilities are listed as issued by HCG. Nothing is inferred from an email or "Owner" title.
- [ ] Force-quit: the session is restored. Sign out: the message states exactly what happened.
- [ ] An expired or revoked session gives the correct message, and the app is signed out locally.

## Newsroom
- [ ] F — Open from Settings › Newsroom (or the iPad sidebar, or ⌘⇧N). The header says "Local drafting only", with the reason.
- [ ] F — New draft (⌘N): headline, introduction, blocks of each kind, section, type, cover image with alt text, caption and credit.
- [ ] F — Bylines can't be typed freely. Without verified authors, the explanation is shown.
- [ ] F — Save (⌘S) says "not submitted or published". Force-quit while typing, then relaunch: "Unsaved changes found", and Recover or Discard.
- [ ] F — Versions: take a snapshot (⌘⇧S), edit, then restore. Restoring snapshots the current version first.
- [ ] F — Preview (⌘⇧P) is labelled "local draft, not published", with no publication date.
- [ ] F — Export a draft file, delete the draft, import the file: it returns as a new local draft with its images.
- [ ] F — Remote actions are disabled, each with a reason. Nothing is sent, and nothing is queued.
- [ ] L — With a newsroom API: Save to newsroom, then a conflict (edit on the server first) shows the conflict sheet. A refused action shows the server's message.
- [ ] L — Unpublish and Correct open a review of the affected article and need explicit confirmation.
- [ ] F — Administration: "Troubleshooting history (this device only)" is separate from "Audit history (newsroom server)".

## iPad and accessibility
- [ ] iPad full screen: sidebar with destinations, sections, Settings & Account and Newsroom. Articles are at a comfortable width.
- [ ] Split View ⅓ / ½ / ⅔ and Slide Over: tabs when narrow, sidebar when wide, no clipping and no horizontal scrolling. The open article survives a resize.
- [ ] Keyboard: ⌘1 / ⌘2 / ⌘3 navigation, ⌘F search, ⌘, Settings, ⌘D save article, ⌘⇧T reading settings.
- [ ] VoiceOver: cards read type, headline, section, byline, date and download state. Breaking controls are labelled. Headings carry the header trait. The reading order is logical.
- [ ] The largest accessibility text size: no clipped controls, rows stack, and the masthead stacks.
- [ ] All touch targets are at least 44 pt.
