# Reynard 0.18.0 custom iOS 16 build — Codemagic free plan

This is a **manual-only** alternative to disabled GitHub Actions for
`ios16-v018-custom-fixes`, carrying official Reynard 0.18.0, Gecko 158 and
the existing iOS 16 stability / ChatGPT / download / signing customizations.

## Strict zero-spend policy

- Use a **Personal** Codemagic account and **only the free M2 machine**.
- Codemagic currently provides 500 free M2 build minutes per month for personal
  accounts; they reset monthly. Check their current pricing before starting.
- **Never enable billing, add payment methods, buy minutes, upgrade, or use M4,
  Linux or Windows billable machines.** The workflow is fixed to `mac_mini_m2`.
- No automatic webhook / push / PR triggering is configured. Builds are manual.
- This repo deliberately does not use App Store Connect or paid Apple signing;
  it uses the existing `ldid` and TrollStore packaging scripts.

## One-time Codemagic setup

1. Go to https://codemagic.io and sign in **with GitHub** on a personal/free
   account. Authorize access to `txntixnz/reynard-browser` when asked.
2. Add `txntixnz/reynard-browser` as a Codemagic application.
3. In Codemagic select **Start new build**; choose branch
   `ios16-v018-custom-fixes`, configuration **codemagic.yaml**, workflow
   **Reynard 0.18.0 + iOS 16 fixes (TrollStore)**.
4. Verify the build machine shows **mac_mini_m2** (free M2).
5. Click **Start new build** once. Do not enable automatic triggers or billing.
6. If successful, open the build's **Artifacts**, and download
   `Reynard-TrollStore.tipa` and its SHA-256 file. Install the TIPA with
   TrollStore, preferably **over** the existing custom app, not after deleting
   its data.

## What the workflow does

Checkout sets `CM_RECURSIVE_SUBMODULE_INIT: 'false'` to avoid downloading the
entire Firefox repository. The workflow initializes only `support/idevice` in
its explicit dependency step. Full history of this small app repository is
retained for the release-provenance checks.

1. Checks that the selected branch is exactly `ios16-v018-custom-fixes` and
   that the tree carries `FIREFOX_158_0_RELEASE`.
2. Runs the same stability, picker, download and background-entitlement
   regression tests as the GitHub workflow.
3. Downloads the **official upstream 0.18.0 TIPA** and rejects it if its fixed
   SHA-256 / version / build / engine-library checks fail. No Gecko recompile.
4. Builds the existing Rust idevice support and native iOS app/helper.
5. Packages the same `Reynard-TrollStore.tipa` via existing `ldid` signing.
6. Checks that the **actual packaged host and Gecko helper** both retain their
   required background entitlements.
7. Publishes the TIPA and checksum as downloadable build artifacts.

The official engine/package pin is defined in
`tools/release/prepare-prebuilt-gecko.py --release-018` and has **not** been
modified by this Codemagic integration. The original GitHub workflow and its
branch remain intact.

## Caveats and next tests

- Source configuration has been validated locally, **but an actual Codemagic
  macOS build and signed-artifact inspection have not yet run**.
- The free tier is finite. If Codemagic reports that the free minutes have
  expired, **stop** and wait for the free quota reset or use a different
  genuinely free build route. Never authorize a charge.
- On device, test ChatGPT sidebar loading, missing messages, session resume,
  background return / unexpected process restart, and saved download-folder
  behavior separately. Passing CI does not demonstrate these are resolved.
- Never share login credentials, GitHub PATs or signing keys in chat.
