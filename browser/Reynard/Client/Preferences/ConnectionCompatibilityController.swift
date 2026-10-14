import GeckoView

enum ConnectionCompatibilityController {
    static func apply() {
        // This explicit app setting owns only the HTTP/3 preference. Clear a
        // manual override of that one key so the comparison switch is reliable.
        // Do not reset any other network, privacy or account preferences.
        GeckoRuntime.dispatchEvent(type: "GeckoView:ResetUserPrefs", message: [
            "names": ["network.http.http3.enable"]
        ])
        let enabled = Prefs.CompatibilitySettings.useHTTP3
        GeckoRuntime.setDefaultPrefs(["network.http.http3.enable": enabled])
        GeckoRuntime.recordDiagnostic("connection policy HTTP3=\(enabled)")
    }
}
