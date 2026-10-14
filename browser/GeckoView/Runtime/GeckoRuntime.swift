//
//  GeckoRuntime.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import UIKit

public protocol GeckoScreenOrientationDelegate: AnyObject {
    func lockScreenOrientation(
        to requestedOrientations: UIInterfaceOrientationMask,
        completion: @escaping (GeckoOrientationLockResult) -> Void
    )
    func unlockScreenOrientation()
}

public final class GeckoScreenOrientationController {
    public weak var delegate: GeckoScreenOrientationDelegate?
}

class GeckoRuntimeImpl: NSObject, SwiftGeckoViewRuntime {
    private var backgroundProcessMonitors: [Int32: (UUID, DispatchSourceProcess)] = [:]

    private func trackBackgroundProcess(pid: Int32, processType: String) {
        guard pid > 1 else { return }
        guard backgroundProcessMonitors[pid] == nil else { return }
        // Monitor every child exit, but only protect content and sockets.
        // GPU processes retain their normal foreground rendering lifecycle.
        let protected = processType == "tab" || processType == "socket"
        GeckoRuntimeBridge.recordDiagnostic("child started type=\(processType) pid=\(pid)")
        let generation = UUID()
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        backgroundProcessMonitors[pid] = (generation, source)
        source.setEventHandler { [weak self] in
            guard let self, backgroundProcessMonitors[pid]?.0 == generation else { return }
            GeckoRuntimeBridge.recordDiagnostic("child exited type=\(processType) pid=\(pid)")
            if protected { GeckoRuntimeBridge.removeBackgroundProcess(pid) }
            backgroundProcessMonitors.removeValue(forKey: pid)?.1.cancel()
        }
        source.resume()
        if protected { GeckoRuntimeBridge.registerBackgroundProcess(pid) }
    }
    func runtimeDispatcher() -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.runtimeInstance
    }
    
    func dispatcher(byName name: UnsafePointer<CChar>) -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.lookup(byName: String(cString: name))
    }
    
    @objc(childProcessDidStartWithPID:processType:)
    func childProcessDidStart(withPID pid: Int32, processType: String) {
        // Update jetsam limit for the child process
        updateJetsamControl(pid)
        DispatchQueue.main.async { [weak self] in
            self?.trackBackgroundProcess(pid: pid, processType: processType)
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("GeckoRuntime.ChildProcessDidStart"),
            object: nil,
            userInfo: [
                "pid": NSNumber(value: pid),
                "processType": processType
            ]
        )
    }
    
    func lockScreenOrientation(
        _ orientationMask: UInt,
        completion: @escaping (GeckoOrientationLockResult) -> Void
    ) {
        let requestedOrientations = UIInterfaceOrientationMask(rawValue: orientationMask)
        DispatchQueue.main.async {
            guard let delegate = GeckoRuntime.orientationController.delegate else {
                completion(.notSupported)
                return
            }
            delegate.lockScreenOrientation(
                to: requestedOrientations,
                completion: completion
            )
        }
    }
    
    func unlockScreenOrientation() {
        DispatchQueue.main.async {
            GeckoRuntime.orientationController.delegate?.unlockScreenOrientation()
        }
    }
}

public class GeckoRuntime {
    static let runtime = GeckoRuntimeImpl()
    public static let orientationController = GeckoScreenOrientationController()
    
    public static var version: String {
        return GeckoRuntimeBridge.version()
    }

    public static func beginBackgroundGrace() { GeckoRuntimeBridge.beginBackgroundGrace() }
    public static var hasBackgroundGrace: Bool { GeckoRuntimeBridge.hasBackgroundGrace() }
    public static func endBackgroundGrace() { GeckoRuntimeBridge.endBackgroundGrace() }
    public static func beginBackgroundDownloadGrace() { GeckoRuntimeBridge.beginBackgroundDownloadGrace() }
    public static var hasBackgroundDownloadGrace: Bool { GeckoRuntimeBridge.hasBackgroundDownloadGrace() }
    public static func endBackgroundDownloadGrace() { GeckoRuntimeBridge.endBackgroundDownloadGrace() }
    public static func recordDiagnostic(_ message: String) { GeckoRuntimeBridge.recordDiagnostic(message) }
    public static var backgroundDiagnosticSnapshot: String { GeckoRuntimeBridge.backgroundDiagnosticSnapshot() }
    public static var diagnosticReport: String { GeckoRuntimeBridge.diagnosticReport() }
    
    public static func setLocale(acceptLanguages: String) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:SetLocale",
            message: [
                "acceptLanguages": acceptLanguages
            ]
        )
    }
    
    public static func setDefaultPrefs(_ preferences: [String: Any]) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:SetDefaultPrefs",
            message: preferences
        )
    }
    
    public static func dispatchEvent(type: String, message: [String: Any?]? = nil) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: type,
            message: message
        )
    }
    
    public static func main(
        argc: Int32,
        argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>
    ) {
        MainProcessInit(argc, argv, runtime)
    }
    
    public static func childMain(
        xpcConnection: xpc_connection_t,
        process: GeckoProcessExtension
    ) {
        ChildProcessInit(xpcConnection, process, runtime)
    }
}
