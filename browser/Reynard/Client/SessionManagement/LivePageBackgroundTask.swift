import GeckoView
import UIKit

// Protect an already-open ChatGPT page through long responses on entitled
// TrollStore installs. Ordinary installs still use UIKit's finite allowance.
// No periodic renewal, audio playback, automatic reload, or prompt replay.
final class LivePageBackgroundTask {
    private var generation: UUID?
    private var taskIdentifier = UIBackgroundTaskIdentifier.invalid
    private var deadline: DispatchWorkItem?
    private var onEnd: (() -> Void)?
    static let ordinaryMaximumDuration: TimeInterval = 180
    static let entitledMaximumDuration: TimeInterval = 2 * 60 * 60
    static var maximumDuration: TimeInterval {
        getEntitlementValue("com.apple.multitasking.unlimitedassertions")
            ? entitledMaximumDuration : ordinaryMaximumDuration
    }

    @discardableResult
    func start(onEnd: @escaping () -> Void) -> Bool {
        guard generation == nil else { return true }
        let generation = UUID()
        self.generation = generation
        self.onEnd = onEnd
        // The special assertion is restricted to the entitled private build.
        // UIKit supplies the fallback and protects asynchronous acquisition.
        if getEntitlementValue("com.apple.multitasking.unlimitedassertions") {
            GeckoRuntime.beginBackgroundGrace()
        }
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "Live ChatGPT response") { [weak self] in
            guard let self, self.generation == generation else { return }
            releaseUIKitTask()
            if !GeckoRuntime.hasBackgroundGrace { stop() }
        }
        guard self.generation == generation else {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
            return false
        }
        taskIdentifier = identifier
        guard taskIdentifier != .invalid || GeckoRuntime.hasBackgroundGrace else {
            stop()
            return false
        }
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            stop()
        }
        self.deadline = deadline
        let duration = Self.maximumDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: deadline)
        NSLog("Reynard: live-page background window requested (maximum %.0f seconds)", duration)
        return true
    }

    private func releaseUIKitTask() {
        guard taskIdentifier != .invalid else { return }
        let identifier = taskIdentifier
        taskIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }

    func stop() {
        guard generation != nil else { return }
        generation = nil
        deadline?.cancel()
        deadline = nil
        releaseUIKitTask()
        GeckoRuntime.endBackgroundGrace()
        let completion = onEnd
        onEnd = nil
        completion?()
        NSLog("Reynard: live-page background window ended")
    }
}
