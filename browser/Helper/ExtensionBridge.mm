//
//  ExtensionBridge.mm
//  Reynard
//
//  Created by Minh Ton on 20/2/26.
//

#import "ExtensionBridge.h"

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
  return xpc ? xpc_connection_get_pid(xpc) : 0;
}
