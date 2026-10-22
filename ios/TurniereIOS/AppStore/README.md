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

- Deploy and verify public support/privacy URLs after frontend MR approval.
- Age rating is saved (18+ globally, regional variants); finish content rights,
  privacy publication. Free pricing and availability are saved.
- German iPhone/iPad screenshots are uploaded from the automated ZIP.
  English images are also packaged for a future English store localization.
- Build 0.1 (2) is uploaded and selected; use Apple's validation for remaining fields.
- Stop before final review submission.

No advertising, analytics SDKs or tracking identifiers are included. Favorites
and snapshots are local. Ordinary network data reaches the API/hosting provider;
this must be considered separately from app-side storage when completing labels.

## Automated screenshots

Run the complete CI workflow locally on macOS:

```sh
python3 -m venv .venv-screenshots
.venv-screenshots/bin/pip install -r ios/TurniereIOS/Scripts/screenshot-requirements.txt
PATH="$PWD/.venv-screenshots/bin:$PATH" .venv-screenshots/bin/inv capture-ios-screenshots
```

Requires Xcode 27.0 (27A266a), XcodeGen, and iOS 26.2 simulator runtime
23C52. Install the runtime with
`xcodebuild -downloadPlatform iOS -buildVersion 23C52 -architectureVariant arm64`.
The GitLab `ios store screenshots` job runs this same task for pushes changing
native code, tasks, or CI. It requires a macOS shell runner tagged `xcode-27`
with Xcode at `/Applications/Xcode_27.0.app`; GitLab Docker runners cannot run
CoreSimulator. Runner registration is infrastructure setup, not provided here.

The task builds the real app and runs its UI tests on fresh isolated iPhone 17
Pro and iPad Pro 13-inch (M5) simulators. Captures use bundled synthetic demo
fixtures, with no live API access or account. German captures explicitly use
light appearance; English captures cover light and dark. Status bar uses a fixed timestamp (rendered in the simulator time zone) and
full battery. Only simulators created by the task are deleted.

Output: `e2e-artifacts/app-store/turniere-app-store-0.1.zip`, plus unpacked PNGs
in `e2e-artifacts/app-store/0.1/`. Each device directory contains `de-DE` and
`en-US` images. Native dimensions are 1206×2622 (iPhone) and 2064×2752 (iPad).
No resizing, invented screens, or manual graphics edits are required. The ZIP
includes commit/toolchain metadata, image dimensions, and SHA-256 checksums.
Upload the PNGs for the matching device and localization in App Store Connect.
GitLab retains ZIP and build logs for 30 days. CI does not upload or submit them.

Packaging checks reject missing/duplicate captures, failure attachments, and
unexpected dimensions. They run before capture through the same Invoke task.

Privacy audit: Rails production log level is WARN, which suppresses ordinary
request/IP INFO logs. Traefik access logging is not configured. No viewer
analytics or identity storage exists in the app; favorites/cache stay local.
The operator confirmed viewer PII is not retained. Review contact is saved.

Local validation (2026-10-22): the full capture workflow passed all three UI
tests on each device and generated eight validated PNGs. All five packaging
checks passed. CI execution has not been polled or verified.

Privacy URL and no-data-collected draft are saved in App Store Connect.
Publishing the declaration requires the operator's confirmation of Apple's
accuracy/compliance agreement. Content-rights declaration also awaits operator
confirmation that public organizer content may be displayed by this app.

App Store validation (2026-10-22), after accepting German iPhone/iPad images:
Apple reports only missing content-rights information and published app privacy
answers. No final submission was made. The frontend pages must additionally be
deployed and checked before submission, even though Apple's form validation
accepts their URLs now.
