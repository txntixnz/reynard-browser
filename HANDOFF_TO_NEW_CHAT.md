# Reynard iOS 16 stability test 1

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
