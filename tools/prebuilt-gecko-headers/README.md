# Pinned release engine bridge headers

These Objective-C bridge headers correspond to upstream Reynard 0.16.0,
build 63fb54d, using FIREFOX_157_0_RELEASE. They retain their MPL 2.0 notices;
see LICENSE.firefox.

- GeckoViewSwiftSupport.h: Firefox blob e68fca9134c058205d11d9d46d6938f6172fc9c3
  plus patches/widget/uikit/GeckoViewSwiftSupport.h.patch.
- IOSBootstrap.h: Firefox blob 2fffb86bd6d7ed2b05acab343a055757603a7a76
  plus patches/toolkit/xre/IOSBootstrap.h.patch.
- GeckoViewRuntimeSupport.h: the new header in
  patches/widget/uikit/GeckoViewRuntimeSupport.h.patch.

The browser-only workflow rebuilds the Swift bridge, browser and extensions
against the checksum-pinned released engine libraries. It refuses reuse if
engine/ or patches/ differ from build 63fb54d. A changed engine requires a
fresh engine build and updated binaries/bridge headers.
