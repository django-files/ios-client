# Broadcast Upload Extension — Xcode Setup

The source files are written, but a new Xcode target needs to be added by hand. Once configured, screen sharing will keep streaming when the app is backgrounded (the only iOS-supported path for system-wide screen capture).

## 1. Create the extension target

In Xcode:

1. **File → New → Target…**
2. Choose **iOS → Broadcast Upload Extension**, click **Next**.
3. Settings:
   - **Product Name:** `BroadcastUploadExtension`
   - **Bundle Identifier:** `com.djangofiles.app.BroadcastUploadExtension`
   - **Language:** Swift
   - **Include UI Extension:** unchecked
4. Click **Finish**. If Xcode asks "Activate scheme?", click **Activate**.
5. Xcode will create a folder `BroadcastUploadExtension/` and a `SampleHandler.swift` inside it. **Delete** Xcode's generated `SampleHandler.swift` and `Info.plist` — we already have ours in the existing `BroadcastUploadExtension/` folder. Move the existing files into the target if they aren't already:
   - In the Project Navigator, select `BroadcastUploadExtension/SampleHandler.swift` and `BroadcastUploadExtension/Info.plist`.
   - In the File Inspector (right sidebar) under **Target Membership**, check ✅ `BroadcastUploadExtension`.

## 2. Configure target settings

Select the `BroadcastUploadExtension` target → **Signing & Capabilities**:

1. **Team:** same team as the main `Django Files` target.
2. **Add Capability → App Groups**, check ✅ `group.djangofiles.app` (same group as the main app and UploadAndCopy).
3. Confirm **Code Signing Entitlements** points at `BroadcastUploadExtension/BroadcastUploadExtension.entitlements`. Xcode usually fills this in when you toggle App Groups; if not, set `CODE_SIGN_ENTITLEMENTS` in Build Settings manually.

Select the target → **Build Settings**:

1. **Info.plist File:** `BroadcastUploadExtension/Info.plist`
2. **iOS Deployment Target:** match the host app (currently iOS 18.6).

## 3. Link HaishinKit + RTMPHaishinKit

Select the `BroadcastUploadExtension` target → **General → Frameworks and Libraries** → **+**:

- Add `HaishinKit`
- Add `RTMPHaishinKit`

(Both products are already in the Package.resolved at the project level — you're just attaching them to the new target.)

## 4. Embed the extension in the main app

Select the `Django Files` target → **General → Frameworks, Libraries, and Embedded Content**:

- Make sure `BroadcastUploadExtension.appex` is listed with **Embed Without Signing** or **Embed & Sign**. (Adding a new extension target via the Xcode wizard usually wires this for you automatically; double-check.)

## 5. Verify Bundle IDs match

The host app reads `RTMPBroadcaster.broadcastExtensionBundleID = "com.djangofiles.app.BroadcastUploadExtension"` to preselect this extension in `RPSystemBroadcastPickerView`. If you used a different bundle ID in step 1, update that string in `Django Files/Views/Streams/StreamBroadcastView.swift`.

## 6. Add the matching provisioning profile

The existing project uses Fastlane Match. Add the new app ID + profile:

```bash
bundle exec fastlane match appstore --app_identifier "com.djangofiles.app,com.djangofiles.app.UploadAndCopy,com.djangofiles.app.BroadcastUploadExtension"
bundle exec fastlane match development --app_identifier "com.djangofiles.app,com.djangofiles.app.UploadAndCopy,com.djangofiles.app.BroadcastUploadExtension"
```

…then set `PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]` on the new target to `"match AppStore com.djangofiles.app.BroadcastUploadExtension"` (Debug builds use the development profile).

## 7. Build & test

- Build & run on a **physical device** (Broadcast extensions are unavailable on Simulator).
- Open a stream in screen-share mode.
- Tap the record button → iOS shows "Start Broadcast?" with our extension preselected → tap **Start Broadcast**.
- After the 3-second countdown, RTMP starts. Background the app — broadcast continues.
- To stop, either tap the record button again (sends a stop flag via App Group) or use the red status pill / Control Center.

## How the host app and extension communicate

App Group `group.djangofiles.app` is shared between the main app, `UploadAndCopy`, and `BroadcastUploadExtension`.

| Key                              | Direction        | Payload                                            |
| -------------------------------- | ---------------- | -------------------------------------------------- |
| `stream.broadcast.config`        | App → Extension  | `{ rtmpURL, streamKey, bitRate, longEdgePixels }`  |
| `stream.broadcast.status`        | Extension → App  | `{ state: "connecting"\|"live"\|"paused"\|"ended"\|"error", message?, timestamp }` |
| `stream.broadcast.request`       | App → Extension  | `"stop"` (cleared by extension after acting)       |

The main app writes `config` right before the user taps the picker, and polls `status` at 1 Hz to update the LIVE/Connecting badge. To stop, it writes `"stop"` to `request`; the extension reads it on its per-frame path (also rate-limited to 1 Hz) and calls `finishBroadcastWithError` to end gracefully.
