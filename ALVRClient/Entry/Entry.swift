/*
Abstract:
The Entry content for a volume: connection status, a few switches and the Enter button, in one column so nothing sits outside the window.
*/

import SwiftUI
import UIKit

struct Entry: View {
    @ObservedObject var eventHandler = EventHandler.shared
    @EnvironmentObject var gStore: GlobalSettingsStore
    @ObservedObject var floorReadout = FloorReadout.shared
    @Environment(\.scenePhase) private var scenePhase
    let saveAction: ()->Void

    private var heightOffsetCm: Binding<Double> {
        Binding(
            get: { Double(gStore.settings.heightOffsetCm) },
            set: { gStore.settings.heightOffsetCm = Int($0.rounded()) }
        )
    }

    private var floorReading: [String] {
        guard let head = floorReadout.headY else {
            return ["Height readings appear here after your first session."]
        }
        var lines = [String(format: "Last session, the headset read your head at %.2f m.", head)]
        if let floor = floorReadout.floorY {
            lines.append(String(format: "The room scan put your head %.2f m above the floor it saw.", head - floor))
        } else {
            lines.append("The room scan saw no floor.")
        }
        return lines
    }

    var body: some View {
        VStack(spacing: 20) {
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
                ForEach(floorReading, id: \.self) { line in
                    Text(line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(String(format: "Floor height offset correction: %+d cm", gStore.settings.heightOffsetCm))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top)
                Slider(value: heightOffsetCm, in: -50...50, step: 1) {
                    Text("Floor height offset correction")
                }
                .onChange(of: gStore.settings.heightOffsetCm) {
                    saveAction()
                }
                Text("Added to whatever height the headset reads (positive raises you in the game). Standing, the reading is usually right; seated it can be off and games then misplace you. Compare the readings with your real eye height and correct here. Takes effect at once.")
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.top)

            VStack {
                Toggle(isOn: Binding(
                    get: { gStore.settings.chaperoneDistanceCm > 0 },
                    set: { gStore.settings.chaperoneDistanceCm = $0 ? 30 : 0; saveAction() }
                )) {
                    Text("Proximity chaperone")
                }
                .toggleStyle(.switch)
                Toggle(isOn: $gStore.settings.showPerformanceHud) {
                    Text("Performance HUD (left forearm)")
                }
                .toggleStyle(.switch)
                .onChange(of: gStore.settings.showPerformanceHud) {
                    saveAction()
                }
                Toggle(isOn: $gStore.settings.autoConnect) {
                    Text("Auto-connect")
                }
                .toggleStyle(.switch)
                .onChange(of: gStore.settings.autoConnect) {
                    saveAction()
                }
                Text("Auto-connect enters the stream as soon as the streamer connects. Leave it off if the streamer starts before you put the headset on.")
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.top)

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
        .padding(.bottom)
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
}
