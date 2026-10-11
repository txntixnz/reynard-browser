import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

final class DownloadsPreferencesViewController: SettingsTableViewController, UIDocumentPickerDelegate {
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Downloads", comment: "")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }
    override func sectionText(for section: Int) -> SettingsSectionText {
        SettingsSectionText(footerTitle: NSLocalizedString("Choose On My iPhone → Downloads to use the same folder as Safari. This applies to future downloads; older files stay in their original folders.", comment: ""))
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = SettingsTableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = indexPath.row == 0 ? NSLocalizedString("Save Downloads To", comment: "") : NSLocalizedString("Use Reynard Folder", comment: "")
        if indexPath.row == 0 {
            cell.detailTextLabel?.text = DownloadStore.shared.downloadFolderName
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 1 {
            DownloadStore.shared.resetDownloadFolder()
            tableView.reloadData()
            return
        }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            try DownloadStore.shared.selectDownloadFolder(url)
            tableView.reloadData()
        } catch {
            let alert = UIAlertController(title: NSLocalizedString("Folder Unavailable", comment: ""), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            present(alert, animated: true)
        }
    }
}
