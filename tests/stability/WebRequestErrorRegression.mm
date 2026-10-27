#import <Foundation/Foundation.h>
#import "WebRequestErrorBridge.h"
#include "nsError.h"

int main() {
  @autoreleasepool {
    struct ErrorCase { nsresult code; NSString *name; };
    const ErrorCase cases[] = {
      {NS_ERROR_PHISHING_URI, @"phishing"},
      {NS_ERROR_MALWARE_URI, @"malware"},
      {NS_ERROR_UNWANTED_URI, @"unwanted"},
      {NS_ERROR_HARMFUL_URI, @"harmful"},
      {NS_ERROR_HARMFULADDON_URI, @"harmfulAddon"},
      {NS_ERROR_CONTENT_CRASHED, @"contentCrashed"},
      {NS_ERROR_INVALID_CONTENT_ENCODING, @"invalidContentEncoding"},
      {NS_ERROR_UNSAFE_CONTENT_TYPE, @"unsafeContentType"},
      {NS_ERROR_CORRUPTED_CONTENT, @"corruptedContent"},
      {NS_ERROR_NET_RESET, @"netReset"},
      {NS_ERROR_NET_INTERRUPT, @"netInterrupt"},
      {NS_ERROR_NET_TIMEOUT, @"netTimeout"},
      {NS_ERROR_CONNECTION_REFUSED, @"connectionRefused"},
      {NS_ERROR_UNKNOWN_SOCKET_TYPE, @"unknownSocketType"},
      {NS_ERROR_REDIRECT_LOOP, @"redirectLoop"},
      {NS_ERROR_HTTPS_ONLY, @"httpsOnly"},
      {NS_ERROR_BAD_HSTS_CERT, @"badHSTSCertificate"},
      {NS_ERROR_OS_LOCAL_NETWORK_ACCESS_DENIED, @"localNetworkAccessDenied"},
      {NS_ERROR_OFFLINE, @"offline"},
      {NS_ERROR_PORT_ACCESS_NOT_ALLOWED, @"portBlocked"},
      {NS_ERROR_UNKNOWN_PROTOCOL, @"unknownProtocol"},
      {NS_ERROR_UNKNOWN_HOST, @"unknownHost"},
      {NS_ERROR_MALFORMED_URI, @"malformedURI"},
      {NS_ERROR_FILE_NOT_FOUND, @"fileNotFound"},
      {NS_ERROR_FILE_ACCESS_DENIED, @"fileAccessDenied"},
      {NS_ERROR_UNKNOWN_PROXY_HOST, @"unknownProxyHost"},
      {NS_ERROR_PROXY_CONNECTION_REFUSED, @"proxyConnectionRefused"},
    };
    for (const auto &item : cases) {
      NSString *actual = [WebRequestErrorBridge loadErrorNameForCode:static_cast<uint32_t>(item.code) errorClass:0];
      NSCAssert([actual isEqualToString:item.name], @"Error mapping mismatch for %@: %@", item.name, actual);
    }
    const uint32_t security = static_cast<uint32_t>(NS_ERROR_GENERATE_FAILURE(NS_ERROR_MODULE_SECURITY, 42));
    NSCAssert([[WebRequestErrorBridge loadErrorNameForCode:security errorClass:1] isEqualToString:@"securitySSL"], @"SSL classification");
    NSCAssert([[WebRequestErrorBridge loadErrorNameForCode:security errorClass:2] isEqualToString:@"securityBadCertificate"], @"Certificate classification");
    NSCAssert([[WebRequestErrorBridge loadErrorNameForCode:security errorClass:0] isEqualToString:@"unknown"], @"Unknown security classification");
    NSCAssert([[WebRequestErrorBridge loadErrorNameForCode:0xFFFFFFFF errorClass:0] isEqualToString:@"unknown"], @"Unknown code classification");
    NSLog(@"PASS: actual 0.19 error bridge compiles with pinned headers; 27 load errors, security classes and unknown fallback map correctly");
  }
  return 0;
}
