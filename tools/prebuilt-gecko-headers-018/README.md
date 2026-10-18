# Pinned 0.18.0 release bridge headers

These headers are derived from Firefox commit
3c71aeacdb296402e41fb2084b13e797d1770642 by applying the unmodified header patches
from Reynard 0.18.0 commit 860bb6f4d0ff2b5d45f7dbe48eca8f39ee88a4fa.
They retain the MPL 2.0 notices. The Swift bridge includes Gecko 158's
MOZ_CAN_RUN_SCRIPT_BOUNDARY annotation and the release's key-command delegate.

The browser-only workflow verifies the complete engine/patch source against the
release commit, plus the official TrollStore package's SHA-256, version and build.
It reuses the official Gecko 158.0 binaries and runtime resources; it never pairs
0.18.0 app code with the older 157 engine. Existing 0.16/0.17 headers remain for
their respective pinned workflow modes.
