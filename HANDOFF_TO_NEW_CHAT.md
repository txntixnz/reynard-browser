# Reynard iOS 16 stability test 1

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
