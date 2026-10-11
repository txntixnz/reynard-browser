//
//  Helper.swift
//  Reynard
//
//  Created by Minh Ton on 25/2/26.
//

import GeckoView
import Foundation
import Darwin

@objc private protocol BootstrapPing {
    func ping()
}

@MainActor
private final class ProcessBootstrap {
    private static var connection: NSXPCConnection?
    private static var hostExitMonitor: DispatchSourceProcess?

    nonisolated private static func handleHostDisconnection() {
        // A Gecko runtime cannot be attached to a different host after launch.
        // Exit the orphan instead of letting NSExtension reuse a stale runtime.
        NSLog("Reynard Helper: host disconnected; exiting the child runtime")
        _exit(EXIT_SUCCESS)
    }
    
    static func start(
        context: NSExtensionContext,
        process: GeckoProcessExtension
    ) throws {
        guard connection == nil else {
            throw NSError(
                domain: "Reynard.ProcessBootstrap",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Gecko child process already started"]
            )
        }
        guard
            let input = context.inputItems.first as? NSExtensionItem,
            let userInfo = input.userInfo,
            let endpoint = userInfo["ReynardXPCListenerEndpoint"] as? NSXPCListenerEndpoint
        else {
            throw NSError(
                domain: "Reynard.ProcessBootstrap",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing NSXPC listener endpoint"]
            )
        }
        
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.invalidationHandler = { handleHostDisconnection() }
        connection.interruptionHandler = { handleHostDisconnection() }
        connection.remoteObjectInterface = NSXPCInterface(with: BootstrapPing.self)
        connection.resume()
        
        guard let xpcConnection = XPCConnectionFromNSXPC(connection) else {
            connection.invalidate()
            throw NSError(
                domain: "Reynard.ProcessBootstrap",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to bridge NSXPCConnection to libxpc"]
            )
        }
        
        self.connection = connection
        GeckoRuntime.childMain(xpcConnection: xpcConnection, process: process)
        let hostPID = XPCPeerProcessIdentifierFromNSXPC(connection)
        if hostPID > 1 {
            let monitor = DispatchSource.makeProcessSource(identifier: hostPID, eventMask: .exit, queue: .global())
            monitor.setEventHandler { handleHostDisconnection() }
            hostExitMonitor = monitor
            monitor.resume()
        }
        (connection.remoteObjectProxyWithErrorHandler({ _ in handleHostDisconnection() }) as? BootstrapPing)?.ping()
    }
}

open class BrowserHelper: NSObject, GeckoProcessExtension, NSExtensionRequestHandling {
    public required override init() {
        super.init()
    }
    
    open func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            do {
                try ProcessBootstrap.start(context: context, process: self)
            } catch {
                context.cancelRequest(withError: error)
            }
        }
    }
    
    open func lockdownSandbox(_ revision: String) {}
}

@objc(ReynardHelperMain)
final class ReynardHelperMain: BrowserHelper {}
