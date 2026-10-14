import GeckoView
import UIKit

enum ConnectionDiagnosticsController {
    static func export(from controller: UIViewController, sourceView: UIView, sourceRect: CGRect) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let report = """
        Reynard connection test diagnostics
        App: \(version) (\(build)); Gecko: \(GeckoRuntime.version)
        iOS: \(UIDevice.current.systemVersion)
        Requested HTTP/3 setting: \(Prefs.CompatibilitySettings.useHTTP3) (applied at app launch)
        Thermal state: \(ProcessInfo.processInfo.thermalState.rawValue)
        Low power mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)

        This report records app lifecycle, OS assertion results and child-process
        exits. It does not record chat text, request URLs, headers, cookies or tokens.
        Page-load events describe navigation, not individual ChatGPT API requests.
        An assertion being valid does not prove that a process kept executing
        or that a service request completed.

        \(GeckoRuntime.diagnosticReport)
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Reynard-Connection-Diagnostics.txt")
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = sourceView
            activity.popoverPresentationController?.sourceRect = sourceRect
            controller.present(activity, animated: true)
        } catch {
            let alert = UIAlertController(title: "Diagnostics Export Failed", message: "The report could not be saved. Please try again.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            controller.present(alert, animated: true)
        }
    }
}
