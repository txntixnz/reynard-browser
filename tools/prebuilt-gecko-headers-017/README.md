# Pinned 0.17.x release bridge headers

These headers match upstream commit cd934cafe5b004e490c720fcdd3c0ed421c9983f,
release 0.17.0, FIREFOX_157_0_1_RELEASE. They retain MPL 2.0 notices.
IOSBootstrap.h and GeckoViewRuntimeSupport.h patches are unchanged from 0.16.0.
GeckoViewSwiftSupport.h includes the release's contentTranslationY layout argument
and dismissSoftwareKeyboard selector, matching its UIKit bridge patch.
The bridge header patches are also unchanged in 0.17.1 commit
c4b79f7d142c6c19fff9dbbf2ecd25bc759f2bb1; the same ABI headers apply.

Each 0.17.x browser-only build verifies the full engine/patch source against its
release commit and the released TIPA SHA-256 before extraction. It compiles the
browser/framework/helper targets; the released native text-input engine stays
unchanged. Headers for earlier releases remain in tools/prebuilt-gecko-headers.
