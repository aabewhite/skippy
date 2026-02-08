//
//  SettingsView.swift
//  Skippy
//
//  Created by Abe White on 2/7/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("logcatBufferSize") private var logcatBufferSize: Int = 4000
    
    var body: some View {
        Form {
            Section("Logcat") {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(logcatBufferSize) },
                        set: { logcatBufferSize = Int($0) }
                    ), in: 1000...10000, step: 1000) {
                        Text("Buffer Size")
                    }

                    Text("\(logcatBufferSize) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
    }
}

#Preview {
    SettingsView()
}
