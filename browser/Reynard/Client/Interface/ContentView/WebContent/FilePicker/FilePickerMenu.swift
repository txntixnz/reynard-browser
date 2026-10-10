//
//  FilePickerMenu.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import MobileCoreServices
import UIKit

extension FilePicker {
    func showMenu() {
        guard let geckoView else {
            finish(with: nil)
            return
        }
        
        // Use a native presentation that owns focus and participates in the
        // normal controller lifecycle, without the private menu selector.
        showActionSheet(in: geckoView)
    }
    
    func showActionSheet(in geckoView: UIView) {
        guard let presenter = UIApplication.shared.topViewController() else {
            finish(with: nil)
            return
        }
        
        let alert = PromptAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.onDismissed = { [weak self, weak alert] in
            guard let self else { return }
            if let alert {
                self.handleActionSheetDismissed(alert)
            } else {
                self.handleMenuDismissed()
            }
        }
        for action in availableActions {
            alert.addAction(UIAlertAction(title: title(for: action), style: .default) { [weak self] _ in
                self?.launchFollowupPicker {
                    self?.performAction(action)
                }
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = geckoView
            popover.sourceRect = CGRect(x: geckoView.bounds.midX, y: geckoView.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        presenter.present(alert, animated: true)
        presentedController = alert
    }
    
    var preferredInitialAction: PickerAction? {
        guard capture != .none,
              acceptedTypes.captureMediaKind != nil,
              canUseCamera else {
            return nil
        }
        return .camera
    }
    
    var availableActions: [PickerAction] {
        var actions: [PickerAction] = []
        if canUsePhotoLibrary {
            actions.append(.photoLibrary)
        }
        if canUseCamera {
            actions.append(.camera)
        }
        actions.append(.chooseFile)
        return actions
    }
    
    private func title(for action: PickerAction) -> String {
        switch action {
        case .photoLibrary:
            return NSLocalizedString("Photo Library", comment: "")
        case .camera:
            return cameraActionTitle
        case .chooseFile:
            return mode == .folder ? NSLocalizedString("Choose Folder", comment: "") : NSLocalizedString("Choose File", comment: "")
        }
    }
    
    private var cameraActionTitle: String {
        let mediaTypes = Set(acceptedTypes.mediaTypes)
        let supportsImages = mediaTypes.contains(kUTTypeImage as String)
        let supportsVideos = mediaTypes.contains(kUTTypeMovie as String)
        
        switch (supportsImages, supportsVideos) {
        case (true, true):
            return NSLocalizedString("Take Photo or Video", comment: "")
        case (true, false):
            return NSLocalizedString("Take Photo", comment: "")
        case (false, true):
            return NSLocalizedString("Take Video", comment: "")
        case (false, false):
            return NSLocalizedString("Take Photo", comment: "")
        }
    }
    
    func launchFollowupPicker(_ action: @escaping @MainActor () -> Void) {
        launchedFollowupPicker = true
        guard let controller = presentedController else {
            DispatchQueue.main.async(execute: action)
            return
        }
        controller.dismiss(animated: true) { [weak self] in
            guard let self, self.continuation != nil else { return }
            self.presentedController = nil
            action()
        }
    }

    func handleActionSheetDismissed(_ controller: UIViewController) {
        // PromptAlertController reports dismissal on the next run loop. By
        // then Photos/Files may already be installed as presentedController.
        if presentedController === controller {
            presentedController = nil
        }
        handleMenuDismissed()
    }
    
    func handleMenuDismissed() {
        anchorButton?.removeFromSuperview()
        anchorButton = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.launchedFollowupPicker else { return }
            self.finish(with: nil)
        }
    }
}
