import Combine
import GameController

extension GCController {
    class func spatialControllers() -> [GCController] {
        if #available(visionOS 26.0, *) {
#if XCODE_BETA_26
            //print(GCController.controllers().map({ $0.productCategory}))
            return GCController.controllers().filter { $0.productCategory == GCProductCategorySpatialController }
#else
            return []
#endif
        }
        else {
            return []
        }
    }
}

extension GCController {
    /// Buttons the system may act on while an app is in front: Home (PS), and the menu-like ones (Menu, Options/Create, Share).
    /// Only Home is claimed (Apple documents that one); the others are reported as the profile sees them.
    static let systemClaimedButtons = [GCInputButtonHome]
    static let reportedButtons = [GCInputButtonHome, GCInputButtonMenu, GCInputButtonOptions, GCInputButtonShare]

    /// Asks visionOS not to act on the controller's Home button, so the press reaches the app.
    ///
    /// This is only a request: the system honors it when the user listed the app under Home Button Overrides
    /// (Settings > General > Game Controller, visionOS 27). See `ControllerHomeButtonStatus`. Returns a one-line
    /// report (which buttons exist, what they were set to, whether the system binds them) for the host log.
    /// Field result 2026-10-28: the Sense controllers expose no Home element at all ("Button Home=absent").
    @discardableResult
    func claimHomeButtonFromSystem() -> String {
        var report = [String]()
        for name in GCController.reportedButtons {
            guard let button = physicalInputProfile.buttons[name] else {
                report.append("\(name)=absent")
                continue
            }
            var state = "present"
            if GCController.systemClaimedButtons.contains(name) {
                if button.preferredSystemGestureState != .disabled {
                    button.preferredSystemGestureState = .disabled
                }
                state = button.preferredSystemGestureState == .disabled ? "claimed" : "refused"
            }
            report.append("\(name)=\(state)\(button.isBoundToSystemGesture ? "/bound" : "")")
        }
        return report.joined(separator: " ")
    }

    /// The Home (PS) button as the physical input profile sees it. The live-input snapshot (`input.nextInputState()`)
    /// and the profile are two collections, and Apple has acknowledged they differ for the Sense controllers,
    /// so the press is read from both.
    var homeButtonPressedInProfile: Bool {
        physicalInputProfile.buttons[GCInputButtonHome]?.isPressed ?? false
    }
}

/// Whether the controller Home (PS) button can reach the app, and a way to ask the user to enable it.
///
/// visionOS 27 lets the user choose what the Home button does while an app is in front: keep the system
/// behavior, or defer to the app. The app can read that choice and open the Settings page, but not change it.
final class ControllerHomeButtonStatus: ObservableObject {
    static let shared = ControllerHomeButtonStatus()

    enum State {
        /// visionOS older than 27, or the setting can't be read (no controller connected, no permission).
        case unknown
        /// The system keeps handling the Home button; the user has to switch it to "Defer to app".
        case systemHandles
        /// The app receives the Home button while it is in front.
        case deliveredToApp
    }

    @Published private(set) var state: State = .unknown

    /// True only when we know the Home button press reaches the app.
    var reachesApp: Bool { state == .deliveredToApp }

#if XCODE_BETA_27
    private var manager: AnyObject? = nil
    private var updatesTask: Task<Void, Never>? = nil
#endif

    /// Call once a controller is connected (the manager refuses to work without one). Cheap to call again.
    @MainActor func start() {
#if XCODE_BETA_27
        if #available(visionOS 27.0, *) {
            guard manager == nil else { return }
            let m = GCControllerHomeButtonSettingsManager()
            manager = m
            refresh(m)
            updatesTask = Task { @MainActor [weak self] in
                for await _ in m.settingsUpdates {
                    self?.refresh(m)
                }
            }
        }
#endif
    }

    /// Opens the Settings page where the user picks "Defer to app" for the in-app action.
    @MainActor func openSettings() {
#if XCODE_BETA_27
        if #available(visionOS 27.0, *), let m = manager as? GCControllerHomeButtonSettingsManager {
            do {
                try m.openControllerHomeButtonSettings(for: .customizeInAppAction)
            }
            catch {
                print("Could not open controller Home button settings: \(error)")
            }
        }
#endif
    }

#if XCODE_BETA_27
    @available(visionOS 27.0, *)
    @MainActor private func refresh(_ m: GCControllerHomeButtonSettingsManager) {
        do {
            let (action, _) = try m.controllerHomeButtonInAppAction
            state = (action == .defer) ? .deliveredToApp : .systemHandles
        }
        catch {
            // Reading needs a connected controller; try again on the next start() call.
            manager = nil
            updatesTask?.cancel()
            updatesTask = nil
            state = .unknown
        }
    }
#endif
}
