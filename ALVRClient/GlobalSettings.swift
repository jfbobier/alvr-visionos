//
//  GlobalSettings.swift
//
// Client-side settings and defaults
//

import Foundation
import SwiftUI
import simd

struct GlobalSettings: Codable {
    var keepSteamVRCenter: Bool = false
    var showHandsOverlaid: Bool = false
    var disablePersistentSystemOverlays: Bool = true
    var enableDoubleTapForHands: Bool = false
    var streamFPS: String = "Default"
    var chromaKeyEnabled: Bool = false
    var chromaKeyFromStreamer: Bool = true
    var chromaKeyDistRangeMin: Float = 0.35
    var chromaKeyDistRangeMax: Float = 0.7
    var chromaKeyColorR: Float = 16.0 / 255.0
    var chromaKeyColorG: Float = 124.0 / 255.0
    var chromaKeyColorB: Float = 16.0 / 255.0
    var dismissWindowOnEnter: Bool = true
    var emulatedPinchInteractions: Bool = false
    var fovRenderScale: Float = 1.0
    /// Per-edge limit of the field of view declared to the streamer, from the visible window measured on a Vision Pro
    /// (docs/AVP_FOV.md in the AirFrameXR repo): "off", "tight", "measured" (visible + 3 deg), "safer" (visible + 5 deg).
    var visibleFovLimit: String = "measured"
    var targetHandsAtRoundtripLatency = false
    var showFaceTrackingDebug = false
    var lastUsedAppVersion = "never launched"
    var chaperoneDistanceCm: Int = 0
    var showPerformanceHud: Bool = false
    var claimControllerHomeButton: Bool = true
    /// Milliseconds the head pose sent to the streamer is predicted past the display time of the current frame (10, 20 or 30; 0 = off). Starts at the maximum, to be ratcheted down.
    var headLookaheadMs: Int = 30
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.keepSteamVRCenter = try container.decodeIfPresent(Bool.self, forKey: .keepSteamVRCenter) ?? self.keepSteamVRCenter
        self.showHandsOverlaid = try container.decodeIfPresent(Bool.self, forKey: .showHandsOverlaid) ?? self.showHandsOverlaid
        self.disablePersistentSystemOverlays = try container.decodeIfPresent(Bool.self, forKey: .disablePersistentSystemOverlays) ?? self.disablePersistentSystemOverlays
        self.enableDoubleTapForHands = try container.decodeIfPresent(Bool.self, forKey: .enableDoubleTapForHands) ?? self.enableDoubleTapForHands
        self.streamFPS = try container.decodeIfPresent(String.self, forKey: .streamFPS) ?? self.streamFPS
        self.chromaKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .chromaKeyEnabled) ?? self.chromaKeyEnabled
        self.chromaKeyFromStreamer = try container.decodeIfPresent(Bool.self, forKey: .chromaKeyFromStreamer) ?? self.chromaKeyFromStreamer
        self.chromaKeyDistRangeMin = try container.decodeIfPresent(Float.self, forKey: .chromaKeyDistRangeMin) ?? self.chromaKeyDistRangeMin
        self.chromaKeyDistRangeMax = try container.decodeIfPresent(Float.self, forKey: .chromaKeyDistRangeMax) ?? self.chromaKeyDistRangeMax
        self.chromaKeyColorR = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorR) ?? self.chromaKeyColorR
        self.chromaKeyColorG = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorG) ?? self.chromaKeyColorG
        self.chromaKeyColorB = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorB) ?? self.chromaKeyColorB
        self.dismissWindowOnEnter = try container.decodeIfPresent(Bool.self, forKey: .dismissWindowOnEnter) ?? self.dismissWindowOnEnter
        self.emulatedPinchInteractions = try container.decodeIfPresent(Bool.self, forKey: .emulatedPinchInteractions) ?? self.emulatedPinchInteractions
        self.fovRenderScale = try container.decodeIfPresent(Float.self, forKey: .fovRenderScale) ?? self.fovRenderScale
        self.visibleFovLimit = try container.decodeIfPresent(String.self, forKey: .visibleFovLimit) ?? self.visibleFovLimit
        self.targetHandsAtRoundtripLatency = try container.decodeIfPresent(Bool.self, forKey: .targetHandsAtRoundtripLatency) ?? self.targetHandsAtRoundtripLatency
        self.showFaceTrackingDebug = try container.decodeIfPresent(Bool.self, forKey: .showFaceTrackingDebug) ?? self.showFaceTrackingDebug
        self.lastUsedAppVersion = try container.decodeIfPresent(String.self, forKey: .lastUsedAppVersion) ?? self.lastUsedAppVersion
        self.chaperoneDistanceCm = try container.decodeIfPresent(Int.self, forKey: .chaperoneDistanceCm) ?? self.chaperoneDistanceCm
        self.showPerformanceHud = try container.decodeIfPresent(Bool.self, forKey: .showPerformanceHud) ?? self.showPerformanceHud
        self.claimControllerHomeButton = try container.decodeIfPresent(Bool.self, forKey: .claimControllerHomeButton) ?? self.claimControllerHomeButton
        self.headLookaheadMs = try container.decodeIfPresent(Int.self, forKey: .headLookaheadMs) ?? self.headLookaheadMs
    }
}

extension GlobalSettings {
    /// Tangent limits (left, right, up, down) for one eye, or nil when the limit is off. Measured on the left eye as
    /// outer / inner / up / down; the right eye is assumed to mirror it, so outer and inner swap.
    func visibleFovTangents(isLeftEye: Bool) -> simd_float4? {
        let outerInnerUpDown: simd_float4
        switch visibleFovLimit {
        case "tight": outerInnerUpDown = simd_float4(0.85, 0.84, 0.81, 0.68)
        case "measured": outerInnerUpDown = simd_float4(0.94, 0.93, 0.90, 0.76)
        case "safer": outerInnerUpDown = simd_float4(1.01, 1.00, 0.97, 0.82)
        default: return nil
        }
        return isLeftEye ? outerInnerUpDown : simd_float4(outerInnerUpDown.y, outerInnerUpDown.x, outerInnerUpDown.z, outerInnerUpDown.w)
    }
}

extension GlobalSettingsStore {
    static let sampleData: GlobalSettingsStore =
    GlobalSettingsStore()
}

class GlobalSettingsStore: ObservableObject {
    @Published var settings: GlobalSettings = GlobalSettings()
    
    init() {
        try? load()
    }

    private static func fileURL() throws -> URL {
        try FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        .appendingPathComponent("globalsettings.data")
    }
    
    func load() throws {
        let fileURL = try Self.fileURL()
        guard let data = try? Data(contentsOf: fileURL) else {
            return self.settings = GlobalSettings()
        }
        let globalSettings = try JSONDecoder().decode(GlobalSettings.self, from: data)
        self.settings = globalSettings
    }
    
    func save(settings: GlobalSettings) throws {
        let data = try JSONEncoder().encode(settings)
        let outfile = try Self.fileURL()
        try data.write(to: outfile)
    }
}
