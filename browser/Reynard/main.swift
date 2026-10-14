//
//  main.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import GeckoView
import UIKit
import Darwin

@available(iOS, introduced: 13.0, obsoleted: 14.0)
private func configureUnsandboxedAppDataDirectories() {
    guard let cachesDirectory = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first else {
        return
    }
    
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
        return
    }
    
    let appDataDirectory = cachesDirectory
        .appendingPathComponent(bundleIdentifier, isDirectory: true)
        .appendingPathComponent(".mozilla", isDirectory: true)
        .appendingPathComponent("firefox", isDirectory: true)
    
    do {
        try FileManager.default.createDirectory(
            at: appDataDirectory,
            withIntermediateDirectories: true
        )
    } catch {
        return
    }
    
    setenv("MOZ_APP_DATA", appDataDirectory.path, 1)
    setenv("MOZ_LOCAL_APP_DATA", appDataDirectory.path, 1)
}

private func configureSandboxExtension() {
    guard let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        return
    }
    
    typealias IssueFileExtension = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UInt32) -> UnsafeMutablePointer<CChar>?
    
    // I can't seem to find any public documentation for these stuff on iOS?
    // Also I'm surprised that this works on iOS
    // https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/spi/darwin/SandboxSPI.h
    // https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/Cocoa/SandboxExtensionCocoa.mm
    guard let sandboxHandle = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_LAZY),
          let symbol = dlsym(sandboxHandle, "sandbox_extension_issue_file") else {
        return
    }
    
    let issueFileExtension = unsafeBitCast(symbol, to: IssueFileExtension.self)
    let extensionClass = "com.apple.app-sandbox.read"
    
    guard let token = extensionClass.withCString({ extensionClassPointer in
        documentsDirectoryURL.path.withCString { pathPointer in
            issueFileExtension(extensionClassPointer, pathPointer, 0)
        }
    }) else {
        return
    }
    
    let tokenString = String(cString: token)
    free(UnsafeMutableRawPointer(token))
    setenv("MOZ_DOCUMENTS_SANDBOX_EXTENSION", tokenString, 1)
}

LocalizationBundle.activate()
JITController.shared.start()

// Gecko's AppShellDelegate owns UIApplicationMain, so startup diagnostics and
// setup belong here rather than the unused Swift AppDelegate.
let diagnosticBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
GeckoRuntime.recordDiagnostic("host startup pid=\(ProcessInfo.processInfo.processIdentifier) build=\(diagnosticBuild)")
if getEntitlementValue("com.apple.multitasking.unlimitedassertions"),
   getEntitlementValue("com.apple.runningboard.assertions.webkit"),
   let helperURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Reynard Helper.appex"),
   let helperIdentifier = Bundle(url: helperURL)?.bundleIdentifier {
    GeckoRuntime.configureHeadlessExtensionLifecycle(helperIdentifier: helperIdentifier)
}
_ = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
    GeckoRuntime.recordDiagnostic("UIKit memory warning")
}

if #unavailable(iOS 14.0),
   getEntitlementValue("com.apple.private.security.no-sandbox") {
    configureUnsandboxedAppDataDirectories()
}

configureSandboxExtension()

_ = NotificationCenter.default.addObserver(forName: Notification.Name("GeckoView.BuildMenu"), object: nil, queue: .main) { notification in
    guard let builder = notification.object as? UIMenuBuilder else { return }
    ApplicationMenuBuilder.build(with: builder)
}

GeckoRuntime.main(argc: CommandLine.argc, argv: CommandLine.unsafeArgv)
