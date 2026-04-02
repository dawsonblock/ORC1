// RootView+Settings.swift — Settings workspace and inspector views.

import AppKit
import Foundation
import SwiftUI
import OracleControllerShared

struct SettingsInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            PanelCard("Controller Session", subtitle: "Host process and active monitor details") {
                if let session = store.session {
                    KVRow(key: "Session ID", value: session.id, monospaced: true)
                    KVRow(key: "Host PID", value: "\(session.hostProcessID)", monospaced: true)
                    KVRow(key: "Active App", value: session.activeAppName ?? "Unknown")
                    KVRow(key: "Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                } else {
                    EmptyStateView(
                        systemImage: "switch.2",
                        title: "No Session Yet",
                        message: "The host session will appear here after the controller bootstraps."
                    )
                    .frame(height: 240)
                }
            }
            .padding(20)
        }
    }
}
