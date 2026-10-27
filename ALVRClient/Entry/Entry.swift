/*
Abstract:
The Entry content for a volume: connection status, the two settings that matter and the Enter button.
*/

import SwiftUI
import UIKit

struct Entry: View {
    @ObservedObject var eventHandler = EventHandler.shared
    @EnvironmentObject var gStore: GlobalSettingsStore
    @Environment(\.scenePhase) private var scenePhase
    let saveAction: ()->Void

    private var headLookaheadMs: Binding<Double> {
        Binding(
            get: { Double(gStore.settings.headLookaheadMs) },
            set: { gStore.settings.headLookaheadMs = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack {
            VStack {
                Image(.alvrCombinedLogoHqLight)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel("AirFrameXR logo")
                .frame(maxWidth: .infinity, maxHeight: 150)
                .padding(.top)

                if eventHandler.alvrVersion != "" {
                    Text(eventHandler.alvrVersion)
                        .font(.system(size: 20, weight: .bold))
                }
                else {
                    Text("Loading settings...")
                        .font(.system(size: 20, weight: .bold))
                }

                VStack {
                    Text(eventHandler.connectionFlavorText)
                        .font(.system(size: 15))
                }
                .frame( maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .top)
            }
            .frame(minHeight: 200)

            VStack {
                Text(gStore.settings.headLookaheadMs > 0 ? "Head prediction ahead: \(gStore.settings.headLookaheadMs) ms" : "Head prediction ahead: off")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Slider(value: headLookaheadMs, in: 0...30, step: 5) {
                    Text("Head prediction ahead")
                }
                .onChange(of: gStore.settings.headLookaheadMs) {
                    saveAction()
                }
                Text("Experimental: the head pose sent to the streamer is predicted this far past the display time. Lower it if the picture swims. Takes effect at once.")
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Visible field of view")
                    Picker("Visible field of view", selection: $gStore.settings.visibleFovLimit) {
                        Text("Off").tag("off")
                        Text("Tight").tag("tight")
                        Text("Measured (+3°)").tag("measured")
                        Text("Safer (+5°)").tag("safer")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: gStore.settings.visibleFovLimit) {
                        saveAction()
                    }
                }
                .padding(.top)
                Text("Tells the streamer only the angles the panel can show (measured on one Vision Pro). If an edge of the picture is cut off, pick Safer. Reconnect after changing.")
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)

            VStack {
                if eventHandler.hostname != "" && eventHandler.IP != "" {
                    let columns = [
                        GridItem(.fixed(150), alignment: .trailing),
                        GridItem(.fixed(150), alignment: .leading)
                    ]

                    LazyVGrid(columns: columns) {
                        Text("hostname:")
                        Text(eventHandler.hostname)
                        Text("IP:")
                        Text(eventHandler.IP)
                        Text("Streamer Version:")
                        if eventHandler.hostAlvrVersion != "" {
                            Text(eventHandler.hostAlvrVersion)
                        }
                        else {
                            Text("Disconnected")
                        }
                    }
                    .frame(width: 300, alignment: .center)
                    .padding(.vertical)
                }
            }
        }
        .frame(minWidth: 650, maxWidth: 650)
        .glassBackgroundEffect()
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background, .inactive:
                saveAction()
            case .active:
                break
            @unknown default:
                break
            }
        }

        EntryControls(saveAction: saveAction)
    }
}
