# App Store release 0.1

- App: turnie.re; bundle ID and SKU: `re.turnie`
- Apple ID: `6825204672`; team: `VWKG94374J`
- Contact: Daniel Schaedler, `turniere@schaedler.rocks`
- Category: Sports; German primary listing
- Support: https://turnie.re/support
- Marketing: https://turnie.re/app
- Privacy: https://turnie.re/app-privacy
- Release mode: manual; no account/sign-in required

Frontend pages are in https://gitlab.com/turniere/turniere-frontend/-/merge_requests/148.
Keep that MR for user review; do not deploy before approval. The new URLs are not
live until deployment. Website legal pages predate the app; the app-specific
privacy page identifies its developer separately.

## Review walkthrough

Open a public tournament from Discover, choose a favorite team, and view its
matches and group standings. No credentials or payment required. The public
numeric link `https://turnie.re/t/11` is another entry point. Production access
is read-only. Organizer names/content are shown as supplied by the API.

## Remaining submission checks

- Restore App Store Connect browser session (Xcode upload credentials are separate).
- Supply review contact phone number.
- Confirm API/infrastructure logging and retention before publishing privacy labels.
- Deploy and verify public support/privacy URLs after frontend MR approval.
- Finish age rating, content rights, free pricing/availability and privacy metadata.
- Upload German/English iPhone and iPad screenshots from UI-test attachments.
- Select the latest processed build; use Apple's validation to identify remaining fields.
- Stop before final review submission.

No advertising, analytics SDKs or tracking identifiers are included. Favorites
and snapshots are local. Ordinary network data reaches the API/hosting provider;
this must be considered separately from app-side storage when completing labels.
