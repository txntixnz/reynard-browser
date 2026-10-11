//
//  ExtensionBridge.mm
//  Reynard
//
//  Created by Minh Ton on 20/2/26.
//

#import "ExtensionBridge.h"
#import <dlfcn.h>

@interface NSXPCConnection (Private)
- (xpc_connection_t _Nullable)_xpcConnection;
@end

xpc_connection_t _Nullable XPCConnectionFromNSXPC(
    NSXPCConnection *_Nonnull aConnection) {
  if (![aConnection respondsToSelector:@selector(_xpcConnection)]) {
    return nil;
  }
  return [aConnection _xpcConnection];
}

int32_t XPCPeerProcessIdentifierFromNSXPC(NSXPCConnection *_Nonnull connection) {
  xpc_connection_t xpc = XPCConnectionFromNSXPC(connection);
  // This libxpc symbol is private on iOS. Resolve it only when present instead
  // of linking a declaration marked unavailable by the iOS SDK. Host-loss XPC
  // handlers still provide cleanup when peer PID lookup is unavailable.
  using PeerPIDFunction = pid_t (*)(xpc_connection_t);
  static PeerPIDFunction peerPID = reinterpret_cast<PeerPIDFunction>(
      dlsym(RTLD_DEFAULT, "xpc_connection_get_pid"));
  return xpc && peerPID ? peerPID(xpc) : 0;
}
