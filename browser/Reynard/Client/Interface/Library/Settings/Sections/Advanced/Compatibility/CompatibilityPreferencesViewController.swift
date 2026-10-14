//
//  CompatibilityPreferencesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit
import GeckoView

final class CompatibilityPreferencesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case userAgent
        case connections
        
        var text: SettingsSectionText {
            return SettingsSectionText()
        }
    }
    
    private enum Row {
        case useAndroidUserAgent
        case advancedOptions
        case userAgentOverrides
        case useHTTP3
        case exportDiagnostics
    }
    
    private let androidUserAgentSwitch = UISwitch()
    private let http3Switch = UISwitch()
    
    private func displayedRows(in section: Int) -> [Row] {
        guard Section.allCases.indices.contains(section) else { return [] }
        switch Section.allCases[section] {
        case .userAgent:
            return Prefs.CompatibilitySettings.useAndroidUserAgent
                ? [.useAndroidUserAgent, .advancedOptions]
                : [.useAndroidUserAgent, .userAgentOverrides]
        case .connections:
            return [.useHTTP3, .exportDiagnostics]
        }
    }
    
    private var compatibilityUserAgentName: String {
        if !Prefs.CompatibilitySettings.customUserAgent.isEmpty
            || !Prefs.CompatibilitySettings.customPlatform.isEmpty
            || !Prefs.CompatibilitySettings.customAppVersion.isEmpty
            || !Prefs.CompatibilitySettings.customOscpu.isEmpty
            || !Prefs.CompatibilitySettings.customBuildID.isEmpty {
            return NSLocalizedString("Custom", comment: "")
        }
        return Prefs.BrowsingSettings.requestDesktopWebsite ? NSLocalizedString("Desktop Firefox", comment: "") : NSLocalizedString("Firefox for Android", comment: "")
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Compatibility", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureSwitch()
        refreshDisplayedState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDisplayedState()
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        
        return displayedRows(in: section).count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              displayedRows(in: indexPath.section).indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let row = displayedRows(in: indexPath.section)[indexPath.row]
        switch row {
        case .useAndroidUserAgent:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Use Compatibility User Agent", comment: "")
            cell.selectionStyle = .none
            cell.accessoryView = androidUserAgentSwitch
            return cell
        case .advancedOptions:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("Advanced Options", comment: "")
            cell.accessoryType = .disclosureIndicator
            return cell
        case .userAgentOverrides:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("User Agent Overrides", comment: "")
            cell.accessoryType = .disclosureIndicator
            return cell
        case .useHTTP3:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "HTTP/3 Connections"
            cell.selectionStyle = .none
            cell.accessoryView = http3Switch
            return cell
        case .exportDiagnostics:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Export Connection Diagnostics"
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard Section.allCases.indices.contains(indexPath.section),
              displayedRows(in: indexPath.section).indices.contains(indexPath.row) else {
            return
        }
        switch displayedRows(in: indexPath.section)[indexPath.row] {
        case .advancedOptions:
            navigationController?.pushViewController(AdvancedOptionsPreferencesViewController(), animated: true)
        case .userAgentOverrides:
            navigationController?.pushViewController(UserAgentOverridesPreferencesViewController(), animated: true)
        case .exportDiagnostics:
            ConnectionDiagnosticsController.export(from: self, sourceView: tableView, sourceRect: tableView.rectForRow(at: indexPath))
        case .useAndroidUserAgent, .useHTTP3:
            break
        }
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        
        if Section.allCases[section] == .connections {
            return SettingsSectionText(
                headerTitle: "Connection Test",
                footerTitle: "HTTP/3 is off by default in this test build. Websites still use HTTPS over HTTP/2 or HTTP/1.1. This applies to all websites. Restart Reynard after changing this switch. Export diagnostics after reproducing a failure; chat text and account credentials are not recorded."
            )
        }
        let headerTitle = Section.allCases[section].text.headerTitle
        if Prefs.CompatibilitySettings.useAndroidUserAgent {
            let footerTitle = String(format: NSLocalizedString("Use the %@ user agent for all websites to improve compatibility.", comment: "User agent name placeholder"), compatibilityUserAgentName)
            return SettingsSectionText(headerTitle: headerTitle, footerTitle: footerTitle)
        }
        
        return SettingsSectionText(
            headerTitle: headerTitle,
            footerTitle: String(format: NSLocalizedString("Add websites with sign-in failures, human verification challenges, or other issues to use the %@ user agent.", comment: "User agent name placeholder"), compatibilityUserAgentName)
        )
    }
    
    private func refreshDisplayedState() {
        androidUserAgentSwitch.isOn = Prefs.CompatibilitySettings.useAndroidUserAgent
        http3Switch.isOn = Prefs.CompatibilitySettings.useHTTP3
    }
    
    private func configureSwitch() {
        androidUserAgentSwitch.addTarget(self, action: #selector(applyAndroidUserAgentPreference), for: .valueChanged)
        http3Switch.addTarget(self, action: #selector(http3SwitchDidChange), for: .valueChanged)
    }

    @objc private func http3SwitchDidChange() {
        Prefs.CompatibilitySettings.useHTTP3 = http3Switch.isOn
        // Apply only on the next launch, preserving current streams/downloads.
        GeckoRuntime.recordDiagnostic("HTTP3 setting requested=\(http3Switch.isOn) restart pending")
    }
    
    @objc private func applyAndroidUserAgentPreference() {
        Prefs.CompatibilitySettings.useAndroidUserAgent = androidUserAgentSwitch.isOn
        tableView.reloadData()
        
        guard let section = Section.allCases.firstIndex(of: .userAgent) else {
            return
        }
        if let footer = tableView.footerView(forSection: section) {
            footer.textLabel?.text = sectionText(for: section).footerTitle
            footer.sizeToFit()
        }
    }
}
