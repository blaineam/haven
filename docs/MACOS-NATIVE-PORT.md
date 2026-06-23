# macOS: Mac Catalyst → native AppKit/SwiftUI port

**Goal:** ship the Mac app as a **native macOS SwiftUI (AppKit-backed)** app instead of Mac Catalyst,
so it gets real `NSApplication` lifecycle, dock/menu-bar/window behavior, native sheets, a
`MenuBarExtra` relay, and no Catalyst hacks (the `macSheetClose` overlay, the runtime
`setActivationPolicy` bridge in `MacAgent.swift`, etc.).

**Strategy:** build the native target **in parallel** with the working Catalyst app. Catalyst keeps
shipping until the native target reaches parity; only then do we drop Catalyst. This avoids weeks
with no usable Mac build.

The app is UIKit-deep (camera, WebRTC video views, ReplayKit, `UIImage`, `PHPicker`,
`UIApplication`), so the bulk of the work is replacing the platform layer, not flipping a setting.

---

## Phase 0 — Foundations (build can link, even if empty) ✅ DONE
- [x] Add `aarch64-apple-darwin` slice to `HavenFFI.xcframework` (`apple/build-rust-xcframework.sh`).
      (Apple Silicon only — Intel is dropped per OS 27.)
- [x] Confirm WebRTC SPM (stasel/WebRTC) resolves its **macOS** slice for `platform: macOS`.
      (Resolves `macos-x86_64_arm64`; embeds WebRTC.framework. NOTE: that slice ships the
      `RTCMTLNSVideoView` *header* but NOT its implementation — see Phase 2 video note.)
- [x] Add a native macOS target `HavenMac` in `apple/project.yml` (`platform: macOS`,
      `deploymentTarget macOS 14`), sharing the same `HavenApp` / `Shared` / `Generated` sources +
      WebRTC + SystemConfiguration. No NSE/Broadcast appex (iOS-only). Catalyst `Haven` target
      untouched. Own `HavenApp/Info.macOS.plist` + `HavenMac` scheme; sandbox entitlements reused
      (`Haven.macOS.entitlements`).
- [x] Add `apple/HavenApp/Platform.swift`: cross-platform typealiases + shims
      (`PlatformImage` = UIImage/NSImage with `jpegData`/`pngData`/`cgImage`/`downscaled`/`resized`;
      `PlatformColor`; `PlatformViewRepresentable`/`PlatformViewControllerRepresentable`;
      `PlatformPasteboard`; `PlatformIdle` (IOPMAssertion); `PlatformApp`; `PlatformScreen`;
      `PlatformHaptics`; `Image(platformImage:)`; NSColor semantic-color shims; and SwiftUI
      cross-platform shims: `havenInlineNavTitle`, `havenFullScreenCover`, `havenStatusBarHidden`,
      `havenPagedTabViewStyle`, `havenURLKeyboard`, `havenAutocap`, `ToolbarItemPlacement.haven{Leading,Trailing}`).

## Phase 1 — Compile the shared core on macOS ✅ DONE
**The native `HavenMac` target builds clean and launches to a window. iOS + Mac Catalyst builds
stay green (parallel-port intact).**
- [x] Conditionalize every `import UIKit` (→ `#if canImport(UIKit)` / `import AppKit`).
- [x] `UIImage` → `PlatformImage` across MediaStore / filters / profile / story / camera review.
- [x] `UIApplication.shared.*` (idle timer, applicationState, registerForRemoteNotifications,
      beginBackgroundTask, connectedScenes) → macOS equivalents / gated no-ops.
- [x] `UIPasteboard` → `PlatformPasteboard` (NSPasteboard); haptics → `PlatformHaptics` no-op.
- [x] Gated iOS-only features on native macOS (kept Catalyst behavior via `#if os(iOS)`):
      MediaPlayer library picker/playback (Music/AudioCoordinator — catalog via MusicKit still
      works), CallKit (CallManager keeps WebRTC + in-app flow, CallKit reporting gated),
      AVAudioSession, BGTaskScheduler, ReplayKit/broadcast, AVCaptureMultiCamSession, PushKit VoIP.
- [x] Native macOS app delegate (`NSApplicationDelegate` + `@NSApplicationDelegateAdaptor`).
- [x] Functional macOS pickers via `NSOpenPanel` (single-image + media); camera/QR/dual-cam/story
      capture views are macOS **placeholders** for now (Phase 2).
- [x] Goal met: non-UI code + plain SwiftUI views compile and the app launches to a window.

## Phase 2 — Native platform views (the heavy lift)
- [ ] Camera: `AVCaptureSession` + `NSViewRepresentable` preview (`AVCaptureVideoPreviewLayer` in an
      `NSView`); story/post capture review in AppKit.
- [ ] WebRTC video: ⚠️ stasel/WebRTC's macOS slice ships the `RTCMTLNSVideoView` **header** but
      the class is **not in the binary** (linker can't find `_OBJC_CLASS_$_RTCMTLNSVideoView`).
      So `RTCVideoView` on macOS is currently a placeholder. Real options: implement a custom
      `NSView` conforming to `RTCVideoRenderer` (the protocol IS available), or switch to a WebRTC
      build whose macOS slice includes the Metal NS view.
- [ ] In-app browser: `WKWebView` via `NSViewRepresentable`.
- [ ] Media pickers: `PHPickerViewController` (has macOS support) or `NSOpenPanel` fallback.
- [ ] Screen share: already `ScreenCaptureKit` on the desktop path — drop the ReplayKit extension on
      macOS (it's iOS-only).
- [ ] Photos save: `PHPhotoLibrary` works on macOS; verify album creation.

## Phase 3 — Mac-native UX
- [ ] Real `NSApplicationDelegate` lifecycle: replace `MacAgent.swift`'s runtime
      `setActivationPolicy` bridge with the public AppKit API; `applicationShouldTerminateAfter
      LastWindowClosed = false` for the relay.
- [ ] `MenuBarExtra` for the relay (status + quit) — the proper "invisible background relay".
- [ ] Native menu bar + `Settings` scene; drop the `macSheetClose` overlay (sheets get native
      chrome).
- [ ] `SMAppService` start-at-login keeps working (it's already AppKit-friendly).

## Phase 4 — Drop Catalyst ✅ DONE (2026-06-23)
**Catalyst dropped EARLY (user chose "drop Catalyst now, backfill native views later"). The native
`HavenMac` is now the ONLY macOS build; iOS + native macOS both build green.**
- [x] Removed `macCatalyst` from `Haven` + `HavenNotificationService` `supportedDestinations`
      (now `[iOS]`); removed `SUPPORTS_MACCATALYST` / `DERIVE_MACCATALYST_*` / `MACOSX_DEPLOYMENT_TARGET`
      / `EXCLUDED_ARCHS[sdk=macosx*]` and the `[sdk=macosx*]` entitlements overrides from both.
- [x] Set `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO` on the iOS targets so the iOS app isn't ALSO
      offered on Mac (would clash with `HavenMac`'s `com.blaineam.kith` bundle id on ASC).
- [ ] NOTE: the dead `#if targetEnvironment(macCatalyst)` branches are left in place for now (they
      compile into nothing — no target builds Catalyst). Several (e.g. ScreenShare's ScreenCaptureKit
      path) are useful references for the Phase-2 native ports; clean up as each is ported.

## Phase 5 — Ship ✅ pipeline wired
- [x] `.local-ci.conf`: `PLATFORMS="ios macos"`, `MACOS_SCHEME="HavenMac"` (was `ios maccatalyst` /
      `MACCATALYST_SCHEME`). The shared `_shared/local-ci-archive.sh` already supports native `macos`
      (`platform=macOS`, `.pkg` + installer-cert export). rocket is platform-agnostic — it still
      uploads/submits under ASC platform **MAC_OS**, now from the native `.pkg`.
- [ ] Remaining to actually ship: real `rocket build Haven` archive of the native macOS `.pkg`,
      screenshots, sandbox entitlements review, and backfilling the Phase-2 native views so the
      Mac app isn't shipping placeholders for camera/in-call video/Apple Music/screen share.

## Phase 5 — Ship
- [ ] rocket/ASC native macOS upload; screenshots; sandbox entitlements review.

---

## Notes / gotchas
- **Toolbar placement on macOS:** iOS `.topBarLeading`/`.topBarTrailing` don't exist on macOS. Map
  via the `ToolbarItemPlacement.haven*` shims in `Platform.swift`. CRUCIAL distinction:
  *sheet/dialog dismiss buttons* ("Done"/"Cancel") must use `havenConfirm*`/`havenCancel*`
  (→ macOS `.confirmationAction`/`.cancellationAction`, which render as real sheet buttons that
  respond to Return/Esc). Using `.primaryAction` for them floats the button in the title-bar
  toolbar OVER the content — that's what caused the doubled "Done" and the "Done" landing on the
  CircleView gear. Persistent nav actions (call/add/gear) use `havenTrailing`/`havenLeading`
  (→ `.automatic`).
- Keep `#if os(macOS)` vs `#if targetEnvironment(macCatalyst)` straight — during the parallel phase
  BOTH the Catalyst `Haven` target and native `HavenMac` exist; Catalyst code is
  `targetEnvironment(macCatalyst)`, native is `os(macOS) && !targetEnvironment(macCatalyst)`.
- `RTCMTLNSVideoView` lives in the same WebRTC module; gate the view wrapper by platform.
- ReplayKit `HavenBroadcast` extension stays iOS-only (`platformFilter: iOS`), already the case.
- The Rust core is platform-agnostic; only the xcframework packaging needs the darwin slice.
