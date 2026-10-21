# turnie.re for iPhone and iPad

Native, read-only tournament companion in the Rails repository. Browse public tournaments,
open a tournament code or `https://turnie.re/t/<id>` link, view results and group standings,
and select one favorite team per tournament. German UI, iOS 17+, Swift 6, no third-party SDKs.

## Build and verification

Install Xcode and XcodeGen. From the backend repository root, using the existing Invoke environment:

```sh
.venv/bin/inv generate-ios-project
.venv/bin/inv check-ios-package
.venv/bin/inv build-ios-simulator
.venv/bin/inv check-ios-ui --destination='platform=iOS Simulator,name=iPhone 17 Pro'
# Optional: GET requests only to the public production API; no authentication or mutations.
.venv/bin/inv check-ios-package --live
```

Open `ios/TurniereIOS/TurniereApp.xcodeproj`, select **Turniere**, and run on a simulator or
signed device. Generated projects, Info.plist, build products, and result bundles are ignored.
`project.yml` is authoritative. The core Swift package runs on macOS without a simulator.
UI tests use `--demo` in DEBUG builds with deterministic synthetic fixtures and a separate local
library, never a production account. `--reset-demo` clears only that fixture library;
`--demo-offline` simulates an unavailable server to verify cached results after process restart.
The app does not expose fixture switches in Release builds.

## Behavior and API contract

- Default API: `https://api.turnie.re`. `APIClient` contains only GET operations.
- The Rails detail route resolves **IDs**, not tournament codes. Public codes are resolved through
  `GET /tournaments`, then loaded through `GET /tournaments/:id`. Both ID and code are verified.
  This is essential: Rails can interpret a hexadecimal code's numeric prefix as another record's ID.
- Numeric tournament links are also supported. Private codes cannot be resolved through the public
  index; use the tournament's numeric link. Share links use numeric IDs, matching the web frontend.
- Standings use backend positions and stable server order for ties. No client-side ranking rules.
  Decider matches display `hidden_points`; ordinary matches display `points`. Unplayed matches
  show dashes instead of implying a 0–0 result. Byes and unresolved opponents have explicit labels.
- Detail refresh runs every 20 seconds while active, when returning to foreground, and on pull-to-refresh.
  Requests do not overlap for the same reference. No background refresh or push notifications.
- Opened tournament snapshots, their fetch times, and favorite team IDs are saved atomically in
  Application Support. Cached content remains visible after network failure, with an explicit notice.
  Favorite selection is per tournament and survives refresh/relaunch. Swipe a saved tournament to remove it.
  A corrupt cache is preserved and reported; failed writes are reported as session-only changes.
- System/light/dark appearance, standard SwiftUI navigation, Dynamic Type, semantic colors,
  and labeled controls follow the existing app conventions. iOS 26+ uses native Liquid Glass chrome.
- Authentication and result submission are deliberately deferred until player APIs are ready.

The default privacy manifest declares local UserDefaults use for appearance and no tracking SDKs.
Before distribution, complete App Store privacy answers for the actual deployed service's practices.

## Patterns reused

Planini (`Malaber/listerine/ios/PlaniniIOS`), HiInterval, Onionary
(`tobhuber/what-should-we-eat/ios/Onionary`), and Tracy supplied the conventions:
XcodeGen, a separately tested core package, a SwiftUI app shell, iPhone/iPad support,
semantic appearance settings, deterministic UI fixtures, and Invoke build/test tasks.
No account or write-path code from those apps is needed by this viewer.

## Apple identity

- App Store name: **turnie.re**
- Bundle ID and SKU: **re.turnie**
- Apple ID: **6825204672**
- Team: **VWKG94374J**
- Primary language: German
- Source version: **0.1 (1)**
- [App Store Connect](https://appstoreconnect.apple.com/apps/6825204672/distribution/info)

The bundle and app record were created on 2026-10-21. TestFlight delivery uses the signed-in Xcode account:

```sh
.venv/bin/inv upload-ios-testflight --version=0.1 --build-number=1
```

Use a new build number for every subsequent upload. Archive paths are printed by the task.
Apple's initial store version is 1.0; set it to the intended marketing version before submitting.
Signed physical-device validation, release metadata, privacy disclosures, and store screenshots
remain distribution work; simulator verification does not establish physical-device signing.

## Artwork

`Design/logo-original.png` preserves the supplied artwork in its own first commit.
`Design/logo-buckle-fixed.png` threads the ribbon through the buckle in a separate commit.
The 1024px app icon is derived from that corrected image. See `Design/README.md` for the edit prompt.
