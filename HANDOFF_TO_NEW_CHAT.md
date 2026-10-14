## Device log identifies unavailable background API (2026-10-14)

User attached Reynard-Connection-Diagnostics.txt (read directly from scratch upload).
It confirms installed candidate 0.17.1 / b6d5a9f, HTTP3=false, iOS16.0,
normal thermal state, low power off. At 15:18:48 UTC page activity requested with
entitled=true, but every private acquisition reported "background assertion API
unavailable". Host and all registered child grants stayed absent/invalid. UIKit
ended the first activity at 15:19:16, about 28 seconds later; app returned 15:19:43.
The two-hour policy was never actual protection in this captured interval.
This proves an implementation defect in our API selection/fallback, not every
ChatGPT request failure. One tab process also exited, without a logged content
crash/kill; cannot establish that it was the selected ChatGPT process. HTTP3 being
off does not rule out every transport issue. Do not overstate the evidence.

New candidate prefers RunningBoard using RBSAssertion, RBSTarget and
RBSDomainAttribute (com.apple.webkit / Background), as declared and used in
WebKit webkitgtk-2.38.0 iOS source (2022, iOS16 era). Added only the corresponding
com.apple.runningboard.assertions.webkit entitlement to the private app plist;
ordinary app entitlement profiles are unchanged. BKS remains only for older OSes
where RunningBoard APIs/selectors are unavailable. An explicit modern OS denial
is logged with error domain/code/reason and does not silently try legacy.

Acquisition runs on a serial worker queue to avoid waiting for IPC on the UI
thread. UIKit protects the transition. Per-PID request tokens reject late grants
after the last owner ends or the child exits/restarts. Pending, valid and absent
grants are distinct in snapshots. Invalid cached assertions do not block a later
request. Owner separation, foreground/deadline cleanup and GPU exclusion remain.
Live-page logs identify actual grants versus the UIKit fallback, not just a
requested two-hour maximum. The successful grant and ability to execute beyond
UIKit expiry STILL need the user's next phone test; source/CI cannot prove them.

Replaced the old native fixture (which always supplied the unavailable BKS API)
with runtime-controlled RunningBoard/legacy doubles. Tests cover RBS while BKS
absent, both APIs absent, incomplete selectors, explicit denial, stale invalid
cache, late owner/child callbacks, duplicate requests and independent downloads.
CI still builds app/framework/helpers using the exact verified official 0.17.1
engine. HTTP3 remains false in this candidate; no unrelated cache, scrolling,
privacy, cookie or request-replay changes. No native engine rebuild.

Workflow/artifact: iOS 16 - 0.17.1 RunningBoard Background Fix /
Reynard-0.17.1-RunningBoard-Fix-TrollStore, contains Reynard-TrollStore.tipa.
User reports build finish. Export the same diagnostics after a background failure
or a successful test beyond one minute; look for RunningBoard acquired=1 valid=1
and continued checkpoints. Missing messages and scrolling are not confirmed fixed.

## Connection comparison and diagnostics candidate (2026-10-14)

User explicitly confirms they installed OUR workflow 38346076209, not official
0.17.1. That workflow SUCCEEDED and produced artifact 11789595382, archive SHA-256
2c0f7ea7e8addf634bf8b9e53786505676e969404b2598e2a5e2bafc835c87dd.
They report continuing timeouts and missing messages on app/background switches.
The two-hour window did NOT solve the reported problem. Do not ask which build
again, call it fixed, or simply increase the duration further.

New controlled candidate disables ONLY HTTP/3 by default. HTTPS, HTTP/2 and
HTTP/1.1 remain; user can compare the prior transport using Settings → Advanced →
Compatibility → HTTP/3 Connections, then restart Reynard. Switch changes are
applied at launch so toggling does not interrupt current responses/downloads.
The explicit app setting clears a user override of only network.http.http3.enable;
no other network/privacy/account preferences are reset. This affects ALL websites.
It is a compatibility experiment, NOT a proven diagnosis of the user's issue.
Mozilla bug 2054388 describes hanging QUIC requests after sleep/network changes on
macOS, still unconfirmed; it does not establish this iOS cause. Dictionaries and
Apple fast datapath workarounds are already off by default in the pinned engine.

Added bounded persistent lifecycle/process diagnostics (last 240 events). Record
host/content/socket assertion results, process starts/exits including unprotected
GPU exits, scene transitions, memory warnings, generic content crash/kill and
ChatGPT top-level page-load start/stop. A 30-second timer samples assertion validity
while the existing page window remains active; it NEVER renews activity. End/expiry
cancels it. This does not capture individual ChatGPT API requests or prove server
completion. No chat text, request URLs, headers, cookies or tokens are recorded.

If it fails, user can export at Settings → Advanced → Compatibility → Export
Connection Diagnostics and attach Reynard-Connection-Diagnostics.txt here. Export
uses the system share sheet; no automatic upload. Cache log survives app restart
where OS cache is retained. Reports include app build, engine version and requested
transport (applied transport is in startup events). Child GPU processes remain
unprotected; downloads retain their independent ownership and proven behavior.

Candidate still uses EXACT official 0.17.1 engine/patches and verified released
TIPA. No native engine rebuild. Existing stability/download checks plus connection
scope and diagnostic grant/bounded-retention checks run in CI; actual device
connectivity, grants and reported scrolling issue remain unverified/unresolved.
Artifact: Reynard-0.17.1-ChatGPT-Connection-Test-TrollStore, contains
Reynard-TrollStore.tipa. User reports workflow finish; do not monitor whole run.

## Long ChatGPT background responses (2026-10-13)

User confirms the custom 0.17.0-based build's background downloads WORK.
Typing remains fixed. Remaining reports: ChatGPT network/timeouts after leaving
Reynard, intermittent missing messages, and "Working for" 55–100 minutes.
Conversation switches through ChatGPT's own sidebar sometimes spin until refresh;
this is same-page SPA navigation, not browser tab selection.
User's 11.5-second clip RPReplay_Final1791864998.mp4 was inspected from its
scratch attachment. The conversation repeatedly changes scroll position while
browser chrome stays fixed and live tool/status content is visible. No keyboard
or selection is shown. Root cause and applicability of the 0.17.1 caret fix are
unproven. No speculative scrolling preference or page script was added.

Found a definite app-side limitation: LivePageBackgroundTask always released the
page's assertion after 180 seconds, including on entitled TrollStore installs.
The new candidate extends ONLY entitled installs to a finite two-hour window,
using the existing host/content/socket assertion mechanism also used by the
user-confirmed background downloads. Ordinary installs keep the three-minute
maximum and UIKit's earlier expiration. Foreground return, session deactivation,
denial and deadline still clean up; repeated starts do not renew the window;
download ownership remains independent. No audio, prompt replay or auto reload.
Longer background execution may use more battery. Device grants/connectivity and
actual ChatGPT completion still require device testing. This does not establish
the cause of every missing message, foreground sidebar hang, or service-side task.

No HTTP/3 code change made. Suggested a reversible about:config test of
network.http.http3.enable=false; user has not reported its result. Do not present
that hypothesis as a confirmed diagnosis. Download folder selection has also not
been confirmed; use the existing picker rather than hardcoding Safari's container.

User then reported official 0.17.1. Inspected all ten commits since 0.17.0:
selection, caret, image paste, edit menu, desktop UA and toolbar fixes; no specific
background/connection fix found. Candidate now merges exact tag commit
c4b79f7d142c6c19fff9dbbf2ecd25bc759f2bb1. Full engine/patch source equals that
tag; bridge headers are unchanged from 0.17.0. Reuses official 0.17.1 TIPA with
SHA-256 f9cf4b70d85b02d8ef40bdf4a4a84bb2e0fff21f795757210b448ebe73d760b6,
version 0.17.1 / build c4b79f7. Preparation uses --release-0171.

This candidate preserves the exact official 0.17.1 engine and native typing patches,
so the existing browser-only workflow reuses the checksum-verified engine. User
reports workflow completion; do not monitor the entire run. Download the single
Reynard-0.17.1-Long-ChatGPT-Responses-TrollStore artifact containing
Reynard-TrollStore.tipa when CI succeeds.

## Official 0.17.0 is the user-confirmed typing baseline (2026-10-12)

User installed the OFFICIAL 0.17.0 release and reports typing issues are gone;
the other issues remain. This is not a failure report for our custom background
and downloads code: the official package does not include those app-side changes.
Our earlier combined 0.16.0 run 38182191273 completed and produced the installable
TIPA artifact 11719857115 (archive digest 3d15d55ccafac8ce23d7deddaa9023ea1004f0396649715338ed70563e8f0443)
and recovery artifact 11719492864. That build is preserved on ios16-autocorrect-fix.

New branch ios16-v017-background-fix merges the exact upstream 0.17.0 release
commit cd934cafe5b004e490c720fcdd3c0ed421c9983f. Engine and patches are EXACTLY
that release; none of the older custom native editor changes are applied.
Browser/helper changes retain draft/restoration/new-tab fixes, finite ChatGPT
activity, independent download activity, child exit cleanup, folder selection,
per-entry bookmarks and safe completed-file removal. Keyboard dismissal uses
the release's native API, with the existing visible-content guard and picker
presentation/focus safeguards retained.

The browser-only workflow reuses the official TrollStore package. Locally checked
its actual SHA-256 0baaa2b0e6f60f61bf2f20ef9df7e319f39a2a7da5e32eb6c83b7d0239b4611c,
version 0.17.0, build cd934ca. Source guard rejects any engine/patch difference.
Separate 0.17 bridge headers include the new contentTranslationY argument and
dismissSoftwareKeyboard selector; the bootstrap/runtime ABI headers are unchanged.
The app/framework/helpers are freshly compiled and packaged, without compiling
Gecko. Legacy 0.16 native fixture checks are skipped only in this released-engine
mode; browser/session/picker/new-tab/background/download regression checks remain.
The native 0.17 typing code is preserved byte-for-byte from the verified release.

Target device remains iPhone 13 Pro Max, iOS 16.0, TrollStore/Dopamine/full JIT.
User reports workflow completion and tests. Do not monitor the whole workflow.
Downloads folder setup: Settings → General → Downloads → Save Downloads To →
On My iPhone → Downloads. Real background grants and provider access remain
device tests. Keep the official 0.17.0 engine as the baseline.

## Retry after engine API compilation failure (2026-10-12 user local time)

Run 38154966140 / head 9055daef passed every regression and the complete iOS
app compilation gate. Gecko failed about 25 minutes into compilation because
ChildView::deleteBackward called TextInputHandler::HasMarkedText, which is private.
The test double mistakenly exposed it publicly. Replaced that call with the
existing public MarkedRange(outRange), which returns the same cached composition
state without reading document text. No engine header or ABI change is needed.
The fixture now declares HasMarkedText private and exposes MarkedRange publicly,
matching the production header. Download/background/folder changes are retained.
No completed engine artifact exists for this failed run. Compiler cache remains
available, but the total retry duration is not guaranteed. User reports workflow
completion/failure; do not monitor the entire engine build.

## Additional download requests in this retry

User screenshot identifies **On My iPhone → Downloads**, not Reynard/Downloads.
Added Settings → General → Downloads → Save Downloads To using the native folder
picker and persistent directory bookmarks. User chooses that folder once; no
hardcoded Safari container. Existing entries keep their original folder bookmark;
legacy entries remain in Reynard. Export preserves filename collisions, falls back
to Reynard with a visible warning if folder access is lost, and clearing/deleting
operates only on tracked completed files (never other Safari files or active data).
Local exports use a move to avoid copying large downloads.

DownloadBackgroundActivity protects host + registered content/socket processes on
entitled TrollStore installs, with a finite UIKit fallback. It keeps the original
Gecko authenticated/POST/blob response rather than re-requesting a URL. Separate
page/download assertion owners prevent either activity ending from cancelling the
other. Only running (not paused) downloads hold activity; complete/cancel/foreground
release it. Ten minutes without progress ends protection until foreground return.
Force quitting still stops live Gecko transfers. Real iOS assertion grants and
provider folder access need the user's device test; CI exercises production policy
and actual Foundation destination/bookmark/collision/removal behavior on macOS.

# Reynard iOS 16 stability test 1

## Latest failure and deletion report (2026-10-11 afternoon)

Combined run 38134691362 compiled Gecko successfully, then failed in the app
archive: ExtensionBridge.mm directly called xpc_connection_get_pid, which the
iOS SDK marks unavailable. Resume-only run 38134511268 failed on the same line.
This was a candidate implementation error. The bridge now runtime-resolves
the private symbol and returns zero if absent; XPC host-loss handlers remain.

User also reports very slow/buggy deletion of long sentences. The previous
ordinary virtual Backspace queried the entire text prefix, selected the last
grapheme range and sent a separate deletion command for each key. The updated
ordinary path invokes Gecko's existing DeleteCharBackward event handling,
which also respects content-consumed Backspace events. Active marked text,
Vietnamese buffers and Korean composition retain their explicit-range handling.
Regression fixtures cover repeated deletion of 20,000 characters without prefix
queries, selection deletion, Unicode graphemes in the editor double, consumed
events and marked-text fallback. Actual iPhone responsiveness is unverified.

The combined workflow now compiles the complete iOS app before the long Gecko
job. Compile-only engine preparation allows only changes to the editor .mm
implementation; ABI/header changes remain rejected. Packaging refuses the
compile-only engine marker. The final job builds and packages the changed
engine on a separate runner. Device-confirmed keyboard routing is preserved.

User asked for an optimization review before launching another workflow.
Additional targeted changes: hasText reads only one UTF-16 code unit instead
of copying the whole document; range conversion obtains one document-length
snapshot instead of two, clamps without overflow and rejects NSNotFound.
Selection UI refresh for ordinary edits/geometry is deferred and coalesced;
without an input delegate the existing immediate visual update is preserved.
Actual production query/update fixtures count queries and run callbacks through
Foundation's real run loop, including legacy iOS 16 notifications, Unicode,
overflow and destroyed-editor handling. This does not simulate device timing.

The full candidate build also preserves bin/include as a dereferenced engine
archive immediately after successful Gecko compilation, with engine/patch tree,
Firefox commit and variant metadata, retained seven days. A later app/package
failure therefore need not discard a completed multi-hour engine build. This
recovery archive is not the installable TIPA; future reuse must verify metadata
and artifact integrity. No complete failed-run engine was recoverable this time.

## Current device baseline and next candidate (2026-10-11)

User confirmed `ios16-text-interaction`, commit
626195e58056f946f73d6fdc88cd8809fdc954c2, fixes the attachment-menu keyboard
glitch. Full build 38072739578 succeeded. Preserve that native engine patch.
Remaining failure: leave ChatGPT working for 2–3 minutes, return to a network /
timeout error or missing messages about half the time. Reload is unreliable;
several force quits may be needed, including failure on the first fresh launch.

`ios16-resume-fix` requests a finite 180-second background window for the
selected ChatGPT page, keeps that session active within the window, ends it
on expiry, return, tab switch or close, and requests a nondestructive repaint
on resume. UIKit fallback is limited by the OS. The TrollStore private build
also requests runtime-checked BKS assertions for the host and tab/socket
processes, with explicit deadline cleanup and child-exit pruning. A denied
or unavailable assertion falls back to UIKit; device grants are unverified.
No audio mode, automatic reload, cookie clearing or draft reset is added.

Helper processes exit when the host's XPC connection is interrupted/invalidated,
the bootstrap ping fails, or the host exits. Previously the helper retained a
static engine connection without host-loss cleanup. Orphan reuse is a hypothesis
for repeated force-quit failures, not a confirmed root cause.

The fast resume workflow reuses the exact successful keyboard engine artifact
11683403964, checks its run/commit, archive digest, app version and engine-source
match, then rebuilds browser/framework/helper targets. This avoids another
full Gecko compile while retaining the device-confirmed keyboard fix.

New fixtures exercise production lifecycle and native assertion methods with
controlled API results, plus helper host-disconnection paths. They do not
reproduce ChatGPT or prove iOS will grant background activity. Device tests:
repeat 2–3-minute background responses, check drafts/messages, and reopen after
one force quit. User will report completion; do not monitor entire workflows.

Additional user report: autocorrect/word suggestions (not voice dictation)
can misbehave after deleting/retyping a word and take too long to select the
correct word. Investigate native text-input synchronization separately from
the fast resume build so its engine pin remains valid.

`ios16-autocorrect-fix` builds on the resume candidate and removes synchronous
inputDelegate change notifications from UIKit-initiated selection, insertion,
replacement, deletion and composition requests. Apple's lower-level text-input
guide reserves those notifications for external edits. Backspace and range
replacement now schedule the same deferred selection reconciliation as insert.
Touch selection and external cut/paste notifications remain intact, as do the
Vietnamese/Korean edit paths and the confirmed attachment-menu tap routing.
The native fixture executes these production methods and checks delete/retype,
autocorrect replacement, composition, delegate feedback and external cut/paste.
This requires a full Gecko compile and includes the resume changes; the fast
resume candidate remains available independently. Prediction quality and
latency still need a device comparison; do not promise Safari equivalence.

User fork: https://github.com/txntixnz/reynard-browser
Base commit: 5fd27d85581814094e1c901d53c8b3095aa11f3b (upstream 0.16.0)
Target: iPhone 13 Pro Max, iOS 16.0, TrollStore, Dopamine.

## Reported symptoms

- Reopening Reynard with ChatGPT as the last tab can leave it unloaded until
  repeated force quits.
- ChatGPT messages sometimes do not render completely.
- The user additionally reported an @GitHub mention stuck in the composer.

## Changes in this test

- Reassert selected tab activity/focus on foreground activation, including an
  open native window whose content became inactive.
- Activate replacement sessions within recovery itself, so direct browsing
  recovery cannot bypass activation, mute state, or media selection. Dispose
  the previous session.
- Use serialized session/form state only when its current history URL matches
  the saved tab URL. Fall back to the saved URL for stale/invalid history.
- Ignore initial about:blank state updates for tabs with a saved page, so they
  cannot replace the last useful page/form snapshot. Also reject blank/stale
  engine snapshots during process termination before saving recovery state.
- Wait for slow content scripts instead of automatically terminating them.
  This can help heavy web apps survive temporary stalls. Truly stuck scripts
  now require the user to reload or close the tab.
- Persist the last known snapshot before requesting an asynchronous engine
  flush; flush pending writes also if that request throws.
- Remove the upstream owner-only build guard so the fork can build.
- Add a push/manual test workflow that checks Swift and builds only the
  TrollStore TIPA, using the existing upstream build/packaging scripts.

No engine patches, cookie clearing, login reset, or periodic page reloads are
added. Gecko and deployment targets remain those of the base repository
(iOS 13+, including iOS 16). The package retains the original app identifiers
so it updates the existing installation. Back up anything important before
installing; do not uninstall the existing browser as part of this test.

## Validation and limits

On 2026-10-10 the user reported that opening website-created tabs now works
with popup-test commit 9d7ca40bd9a1b6e941f95c6d25818ee67c625fb5, but continues
testing. New clip RPReplay_Final1791651968.mp4 shows repeated keyboard/page
jumps while using ChatGPT's attachment plus button, often before a native
picker appears.

The separate ios16-picker-fix candidate leaves an existing engine first
responder alone during content focus restoration: the hardware-focus bridge
explicitly suppresses the software keyboard. It dismisses content editing at
native file-picker entry, replaces private inline menu presentation with a
public action sheet, waits for that sheet to dismiss before launching Photos
or Files, and protects the followup controller from a delayed dismissal
callback. Regression checks cover focus ownership and picker handoff using
the actual production methods; UIKit and ChatGPT still require device retests.
On 2026-10-10 the user reported that picker build 40e4121 still glitches.
The new clip 01-RPReplay_Final1791653597.mp4 shows the web attachment menu
followed by keyboard/page jumps, without a native file picker appearing.

The ios16-text-interaction candidate changes the native editable
UITextInteraction delegate: it now checks Gecko's editor rectangle, converted
from device pixels and clipped to visible view bounds, before starting a text
gesture. Selection handles outside that rectangle remain allowed for nonempty
selections; noneditable page selection is unchanged. Previously every point
in the whole Gecko view was accepted, and interactionWillBegin takes first
responder ownership. This is a plausible interference path for web buttons;
only a device retest can establish whether it causes the reported glitch.
Done now explicitly suppresses the software keyboard through the existing
hardware-focus bridge, instead of only resigning with the editor still focused.
Regression fixtures execute the production native delegate and Done method.
This candidate requires a full Gecko rebuild. The browser-only workflow must
not be used because its released-engine source guard rejects this patch.
The previous working branches remain available.

Working device baseline: commit 64632ac25f69a08043c2f5a3e73d88ce177e33cf,
branch ios16-browser-only, successful run 38057152439. On 2026-10-10 the user
reported normal ChatGPT loading, complete messages and no issues in initial use.
Later they reported that website-created tabs (including Branch in new chat)
stay on ChatGPT's loading spinner; video RPReplay_Final1791647029.mp4 shows this.

The separate ios16-popup-fix test opens each website-created session with Gecko's
requested window ID before publishing the tab to UI observers/animations.
This prevents early selection from treating the unopened popup as a crashed
session and replacing its opener-connected window. The source session stays
active until selection occurs, and delayed animation completion resolves the
new tab by ID rather than a potentially stale index. It does not issue a second
URL load, preserving window.open and opener semantics. New regression checks
exercise actual onNewSession/createSession methods with immediate/delayed UI,
reordering, closed tabs, background targets and private mode. This addresses a
source-level race; device testing must establish whether it resolves the spinner.
The working baseline branch remains unchanged.

The `ios16-browser-only` branch adds a separate browser-only workflow after the
full Gecko build stopped producing visible progress. It reuses the engine from
the official upstream 0.16.0 TrollStore package (build 63fb54d), verifies its
SHA-256 and matching engine source/patches, and rebuilds GeckoView, browser,
extensions and idevice support. Bridge headers retain Firefox MPL notices and
their provenance is documented in tools/prebuilt-gecko-headers/README.md.
This workflow produces the same candidate browser fixes without compiling Gecko.
Its concurrency group is separate from the original full build.

`tests/stability/run.py` compiles actual extracted production restoration and
activation methods plus GeckoSessionState/PayloadValue with engine doubles.
It checks matching/stale/blank history, form data retention, private URL-only
restoration, direct recovery activation, mute/media selection, warm resume
without reload, and slow-script continuation. It does not execute Gecko or
ChatGPT. The workflow separately compiles the complete app.

No device reproduction has been performed here. These are candidate fixes
based on source review, not proof that every reported symptom is resolved.
The stuck mention may involve Gecko's contenteditable/keyboard integration;
that needs a device retest after this build. Do not claim it is fixed yet.

## Device test

1. Install the workflow's Reynard-TrollStore.tipa over the existing app.
2. Open ChatGPT and an existing conversation; send a message and check the
   complete response.
3. Type an unsent draft, switch to another app for 10 seconds, and return.
   Repeat after about 2 minutes and after locking/unlocking the phone.
4. Confirm conversation and draft stay visible on warm resume.
5. Leave ChatGPT selected, force quit once, reopen once, and check restoration.
6. Open a second site, switch tabs, test back/forward, and test private tabs.
7. Retry deleting the stuck mention and ordinary typed text. If still broken,
   collect exact steps, Reynard version/build SHA, and any available browser
   diagnostics/crash logs. Avoid including private conversation content.
