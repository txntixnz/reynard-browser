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
  cannot replace the last useful page/form snapshot.
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
