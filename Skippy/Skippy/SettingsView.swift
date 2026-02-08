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
                    Text("Buffer Size: \(logcatBufferSize) lines")
                        .font(.headline)
                    
                    Slider(value: Binding(
                        get: { Double(logcatBufferSize) },
                        set: { logcatBufferSize = Int($0) }
                    ), in: 1000...50000, step: 1000) {
                        Text("Buffer Size")
                    }
                    
                    Text("Number of lines to display")
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
