# LLP Mac

Run the commands below from `mac/` in the combined repository.

LLP is a small macOS audio loop player for listening practice. The MVP lets you open an audio file or folder, play or pause it, scrub through playback, set start and end markers, and replay the selected segment.

The progress bar shows separate start and end pointers. Drag the green start pointer or red end pointer to adjust the replay range, or use the Set Start and Set End buttons to place markers at the current playback time. Once both markers are set, use Before or Next to move the selected range by the same segment length. Click Replay Segment to jump to the start marker and play the selected range; the replayed part of the range fills blue and playback stops at the end marker until you click Replay Segment again.

Keyboard shortcuts:

- Command-O: open an audio file or folder
- Option-1: play or pause
- Option-2: set start
- Option-3: set end
- Option-4: replay segment
- Option-5: move to the next segment
- Option-6: move to the previous segment

## Run

```sh
./scripts/build.sh
swift run --skip-build LLP
```

## Test

```sh
swift test
```

The app is implemented with AppKit and AVFoundation. MP3 is supported in the first version, and the open panel also accepts common audio types supported by AVFoundation.

## Audio list

Click **Open** to choose one audio file or a folder. Audio files directly inside the folder appear on the right in natural filename order; hidden files and subfolders are excluded. Opening a selection starts its first track. The current track is highlighted and bold, including while paused. Click any item to play it from the start.

When a track finishes, the next item is loaded at the start and stays paused until you press Play. The final track stops without wrapping to the first. Segment replay still stops at its end marker without advancing the list. Empty folders and unreadable or unsupported audio show an error and preserve the current selection.

## Registration

Click **Sign up** in the player to open the registration sheet. Enter an optional username, email and password. The button shows a spinner while submitting and stops after at most five seconds. On success, check your email to verify your identity, then sign in.

The default API server is `http://localhost:8080`. For a deployed server, use HTTPS:

```sh
LLP_API_BASE_URL=https://api.example.com swift run LLP
```

The backend described by `../common/apis/llp-apis.yaml` owns MySQL persistence, password hashing and verification email delivery. The Mac app does not store passwords. If email delivery fails after the account is saved (503), request a new email through the backend's `/auth/resend-verification` endpoint instead of registering again. A timeout may also occur after the server saved the account; check your email before retrying.

Swift models and API calls are generated in the `LLPGenerated` module at build time using [Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator). The build plugin invokes the generator directly without Python. Run `./scripts/build.sh` to validate, generate and compile the client. The build plugin passes `../common/apis/llp-apis.yaml` directly to Apple's generator without application-level contract validation. Generation settings are in `Sources/LLPApis/openapi-generator-config.yaml`. Generated files live in SwiftPM's build directory and are not checked in. Registration uses the generated client with the URLSession transport.

## Sign in

Click **Sign In** in the player and enter your email and password. The app sends a stable, randomly generated device ID and the `macos` platform through the generated `/auth/login` client. The button shows a spinner and the request is cancelled after five seconds; late responses cannot change the session.

A successful login stores the access token, refresh token, device ID, email and access expiry in a single device-only Keychain item scoped to the API server. Passwords are never persisted. The player replaces Sign up and Sign In with your email and **Sign Out**, and restores the saved session on launch. Sign Out removes the saved tokens while keeping the device ID. It is a local sign-out because the contract has no token revocation endpoint.

`AuthSession.authorizationHeader` supplies the bearer access token while it is valid. Protected API calls refresh automatically on an explicit access-token-expired response. No background refresh is scheduled. The API target configuration lives in `Sources/LLPApis`; SwiftPM generates its client and types at build time, retaining the existing `LLPGenerated` module name.

## API build scripts

Requires macOS 13+, Swift 5.9+ (Xcode Command Line Tools), Git and Python 3.9+.
Run `./scripts/build.sh` from any directory; paths are relative to the mac package.
Swift build flags can be passed through, for example `./scripts/build.sh -c release`.
The Mac executable is the existing SwiftPM product `LLP` (debug output: `.build/debug/LLP`).

`api-version` contains `API 1.0.0`, matching the current client contract. Update it
when adopting a new backend API version. Validation reads `../common/apis/llp-apis.yaml`
directly and rejects it if `info.version` differs from `api-version`.
Version numbers are compared exactly, including prerelease/build suffixes.
The shared contract is the source for both validation and Swift generation;
no contract fetch or local copy is needed.

The build creates `.build/api-tools` and installs the pinned validator packages
from `scripts/requirements-api.txt`. Network access is needed for Python packages, initial Swift package resolution. To use a prepared Python
environment, set `LLP_API_PYTHON` to its absolute Python executable path.
The same interpreter can be used for standalone validation:

```sh
./scripts/validate-api.sh
```

Validation checks the exact version and the OpenAPI schema, including local
references. The shared contract must be self-contained: external references
are rejected. Validation failures stop generation and compilation. Each stage
reports an error and exits nonzero. Direct `swift build` uses the shared
contract and bypasses the script's version/schema gate.

`Tests/LLPTests/APIScriptTests.swift` covers passing the shared contract to the
validator and rejecting missing or empty contracts without backend access.

### Authenticated HTTP suite

`LLPCore.APIClient` centralizes Keychain credentials, refresh, and one request replay:

```swift
let apiClient = APIClient(baseURL: baseURL)
let (response, body) = try await apiClient.send(
    HTTPRequest(method: .get, path: "/resource"))
```

Import `HTTPTypes` for `HTTPRequest`. Request paths are relative to the configured
server URL. Login, registration, verification, and resend-verification omit
Authorization, including requests with query parameters. Protected requests read
the saved session and send `Authorization: Bearer <access token>`.

The current contract has no protected-resource expiration schema. By default,
only HTTP 401 with JSON `{"code":"access_token_expired"}` triggers refresh;
`isExpired` can be supplied when integrating another explicit backend signal.
Other HTTP errors throw `APIClientError.http` immediately. Refresh posts JSON
`{"refresh_token":"..."}` to `/auth/refresh` without an access token, saves the
new access token atomically, and replays the original request once. Concurrent
requests on the same client share refresh work. A rejected refresh clears the
saved session and throws `APIClientError.loginRequired`; callers should show
sign-in. Storage and network failures propagate without replay. Bodies are
buffered in memory for replay, so this suite is intended for bounded API payloads.

All existing generated API calls use this suite through `AuthenticatedTransport`,
which preserves endpoint-specific error decoding and UI messages. Automatic
refresh occurs on protected calls.
`APIClientTests` covers token injection, whitelist handling, refresh persistence,
request replay, bounded retries, rejected refresh, and failure paths. Existing
client integration tests exercise generated APIs through the shared transport.
Tests must be executed by TestingAgent with `swift test` after resolving Swift packages.

### Favorite text colors

The listening editor has three color circles, initially red, black, and green.
Black starts selected. Click a circle to apply its color to selected text, or to
text you type next. A check mark identifies the one active circle. Double-click
any circle to replace its color from a fixed palette of 12 colors. Click outside
the palette or press Escape to dismiss it. Keyboard users can focus a circle,
press Space to select it, and Option-Space to open its replacement palette.

### Listening editor undo/redo validation

`ListeningTextUndoTests` checks menu configuration and invokes the actual editor's
undo/redo actions directly, with explicit undo groups. A synthetic menu key event
in a SwiftPM unit-test process does not establish the active application's key
window or responder routing; a handled key equivalent alone does not prove the
editor received the action. Keyboard and menu routing require the following
manual validation in a macOS desktop session (pending):

1. Launch the built app with `swift run --skip-build LLP`, activate its window,
   open the listening text editor, and click inside it.
2. Type `hello world`, select `world`, and type `reader`. Press Command-Z:
   expect `hello world`. Press Shift-Command-Z: expect `hello reader`.
3. Press Command-Z again, move to the end, and type `!`: expect `hello world!`.
   Redo should be disabled; Command-Z should remove `!`, leaving `hello world`.
4. Repeat the replacement using Edit > Undo and Edit > Redo instead of shortcuts;
   expect the same text restoration and menu availability.

TestingAgent must rerun `swift test`; these manual checks additionally verify the
real application's keyboard dispatch and responder chain.

## Saved dictations

Signed-in users load their saved plain listening text and playback position when
starting a media item. Opening local media or **Open URL** starts playback; an
automatically advanced playlist item waits for Play before loading dictation data.
Local audio and video use SHA-256 of file contents, so renaming a file preserves
its identity. Remote HTTP(S) media use SHA-256 of the exact URL; changing the URL
(including its query) creates a separate identity. Video appears above the progress
bar. Supported formats depend on AVFoundation and the remote server.

Every five seconds, changed text (including deletion to empty) is saved with the
current pointer in milliseconds, even while paused. Unchanged text causes no save.
Failed saves retry at the next interval; failed loads require restarting playback
and cannot overwrite unknown server content. Unsaved edits within the last five
seconds can be lost on closing or switching media/accounts. Account switches clear
the editor and undo history. Guests do not load or save backend dictations.

GET/PUT `/dictations` use the shared authenticated API client. The backend contract
receives source type, media key and media_type (audio or video) on loads and saves.
Media type follows the URL extension, using the same movie classification as file
discovery and defaulting to audio for unrecognized extensions. The checked-in API
schema predates the review-requested media_type field; backend compatibility needs
validation. Title is omitted. Rich formatting remains available in the existing JSON text
export/import; server persistence stores plain text.

Validation is pending TestingAgent: run `swift test` on macOS with the shared
API contract and resolved Swift packages. `DictationTests` covers content hashes,
authentication gating, delayed load, snapshots, retries, empty text, wire payloads
and rejection of requests bound to a different account.

Manual validation (pending; requires macOS desktop and a running backend with two
verified users):

1. As a guest, open local audio/video and an HTTP(S) media URL, type text and wait
   more than five seconds. Confirm no dictation requests in backend logs.
2. Sign in as A, start playback, type text, pause at a known position and wait
   five seconds. Reopen the same media: expect restored text and pointer. Verify
   the picture for video and audio playback; repeat for the remote URL.
3. Sign out, sign in as B and play the same media. Expect B's own text/position
   (empty/zero initially); save different values, then return to A and verify A's
   values remain intact. Confirm undo cannot reveal the previous user's text.
4. Delay a GET response, switch media or accounts, then release it. Expect no
   stale text or seek. Interrupt the network during a PUT, edit again and restore
   connectivity: the next interval saves the latest text. Confirm unchanged text
   produces no further PUT and deleting all text persists an empty string.
5. Exercise local playlist advance, pause, seek and segment replay with audio and
   video. The next paused item must not GET until playback starts. Inspect error
   logs for failed load, save and invalid media without token/content disclosure.

### Transcript editor

Open the listening area and select **Transcript** to show an editable transcript
on the right. **Save Transcript** updates the signed-in user's transcript for the
selected media. Uncheck **Transcript** to regain the listening editor's width;
both drafts are retained while toggling. Changing media or account clears the
transcript draft. Empty text clears the saved transcript. The API accepts at most
65535 UTF-8 bytes. Saving a transcript creates the selected media's dictation if
needed; playback and listening-text autosave are not prerequisites. Existing
listening content and position are preserved. Failed saves retain the draft for retry.
Deploy the backend with support for transcript media metadata before the updated app.

Manual validation (pending): on macOS 13+ with a configured running backend,
log in, select media, play it, type listening text, and wait for autosave. Show the
listening area, check Transcript, and verify editable listening text on the left
and editable transcript text on the right. Type distinct multiline text in both;
uncheck and recheck Transcript, checking that the listening editor expands and
both drafts survive. Save the transcript and confirm the backend dictation's
transcript changes while its listening content and playback position remain
intact. Save empty text and confirm the transcript clears. Disconnect the server,
save, verify an error and retained draft, reconnect and retry. Switch media or
log out during a save and verify its completion does not change the new editor.
These AppKit layout and real backend checks require a running app; ordinary unit
tests do not reliably validate them.

Automated validation (pending, TestingAgent): run `swift test` from `mac` on
macOS with Swift and package dependencies available. `TranscriptTests` covers
request encoding, empty/Unicode text, UTF-8 limits, authentication, HTTP failures,
retry, duplicate saves, and stale completion. Run the full suite for regressions.

Transcript **Upload** opens a local image picker (JPEG, PNG, GIF, BMP, TIFF,
WebP, HEIC, HEIF; smaller than 5 MB). HEIC/HEIF is converted locally to JPEG;
the converted image must also be smaller than 5,000,000 bytes. Recognition displays a spinner and has a 35-second deadline.
Review the returned draft before **Save Transcript**. Configure Google Vision
only on the backend; see the root README for setup and pending manual checks.


LLP-60 manual regression (pending; requires macOS 13+, the updated backend,
and MySQL with the dictations schema). AppKit interaction and real MySQL upsert
semantics are not exercised by the unit/SQL-mock tests:

1. Log in and select a new local media file. Open Transcript, type multiline
   Unicode text, and click Save Transcript without playing or editing listening
   text. Expect “Transcript saved.” Repeat with a new remote media URL.
2. Switch away and reopen each media item, then start playback to load saved data.
   Expect the saved transcript, empty listening text, and zero initial position.
3. Create listening text and a playback position, wait for autosave, then edit and
   save only the transcript. Reload and verify listening text and position are
   preserved. Save the same transcript again, then clear and save it; both succeed.
4. Disconnect the backend and save a new draft. Expect a failure with the draft
   retained. Reconnect and retry; expect success. Log in as another user and load
   the same media; the first user's transcript must not appear.

### Playback speed

Use **Speed** to select **0.5X** (half speed), **1X** (original), or **2X**
(double speed). Changes apply immediately during playback without seeking.
Every Play or Replay Segment action starts at **1X**, including resume after
pause. Opening or selecting a track also resets to **1X**. Selecting a speed
while paused does not start playback; the next Play resets it to **1X**.
Unavailable media or unsupported slow playback leaves the previous selection
intact, shows an error, and logs through `DiagnosticLog`.

Validation is pending. TestingAgent should run `swift test` from `mac/` on macOS
13+ with Swift dependencies resolved, including `PlaybackSpeedTests` and the
full regression suite. Real audio timing, streaming and AppKit interaction need
manual validation in a macOS desktop session; unit tests cannot reliably verify
AVFoundation decoding, buffering or audible output:

1. Open a local audio file of at least 30 seconds. Expect **1X**. Select **0.5X**,
   **1X**, then **2X** while playing. Over four wall-clock seconds, the media
   pointer should advance approximately two, four, and eight seconds respectively;
   confirm audible speed matches and selection does not move the pointer.
2. At **2X**, pause and resume, then replay a marked segment: each start shows
   **1X** and plays at original speed. Change speed during segment replay and
   confirm it still stops at the end marker. Seek while playing at **0.5X** and
   confirm the selected speed remains active.
3. Select another track, reselect it, and let a playlist advance: each new track
   shows **1X**; the automatically advanced track remains paused until Play.
4. Repeat with local video and a working HTTP(S) media URL. During buffering,
   confirm the selected rate resumes when data is available. Try slow playback
   on media without slow-rate support: expect an error and unchanged selection.
   Try unavailable remote media: expect a playback error. Inspect Console's LLP
   diagnostics for failure events. Confirm the Speed control is disabled before
   media loads and remains visible at the minimum window size.
