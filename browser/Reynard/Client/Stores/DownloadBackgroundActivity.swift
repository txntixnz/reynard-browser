import GeckoView
import UIKit

// Keep the original Gecko response (cookies, POST and blob downloads included)
// running on entitled installs. UIKit provides a finite ordinary-install fallback.
final class DownloadBackgroundActivity {
    private let progress: () -> [UUID: Int64]
    private var observers: [NSObjectProtocol] = []
    private var generation: UUID?
    private var taskIdentifier = UIBackgroundTaskIdentifier.invalid
    private var watchdog: Timer?
    private var previousProgress: [UUID: Int64] = [:]
    private var lastProgressAt: TimeInterval = 0
    private var blockedUntilForeground = false
    static let idleTimeout: TimeInterval = 600

    init(progress: @escaping () -> [UUID: Int64]) {
        self.progress = progress
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification, Notification.Name.downloadStoreDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if notification.name == UIApplication.didBecomeActiveNotification { blockedUntilForeground = false }
                update()
            })
        }
        update()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        stop()
    }

    func update() {
        guard UIApplication.shared.applicationState == .background else { stop(); return }
        let current = progress()
        guard !current.isEmpty else { stop(); return }
        guard !blockedUntilForeground else { return }
        if current != previousProgress {
            previousProgress = current
            lastProgressAt = ProcessInfo.processInfo.systemUptime
        }
        if generation == nil { start() }
    }

    private func start() {
        let generation = UUID()
        self.generation = generation
        lastProgressAt = ProcessInfo.processInfo.systemUptime
        if getEntitlementValue("com.apple.multitasking.unlimitedassertions") {
            GeckoRuntime.beginBackgroundDownloadGrace()
        }
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish downloads") { [weak self] in
            guard let self, self.generation == generation else { return }
            releaseUIKitTask()
            if !GeckoRuntime.hasBackgroundDownloadGrace {
                blockedUntilForeground = true
                stop()
            }
        }
        guard self.generation == generation else {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
            return
        }
        taskIdentifier = identifier
        guard identifier != .invalid || GeckoRuntime.hasBackgroundDownloadGrace else {
            blockedUntilForeground = true
            stop()
            return
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.checkProgress() }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func checkProgress() {
        update()
        guard generation != nil else { return }
        if ProcessInfo.processInfo.systemUptime - lastProgressAt >= Self.idleTimeout {
            blockedUntilForeground = true
            stop()
        }
    }

    private func releaseUIKitTask() {
        guard taskIdentifier != .invalid else { return }
        let identifier = taskIdentifier
        taskIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }

    private func stop() {
        guard generation != nil else { return }
        generation = nil
        watchdog?.invalidate()
        watchdog = nil
        previousProgress = [:]
        releaseUIKitTask()
        GeckoRuntime.endBackgroundDownloadGrace()
    }
}
