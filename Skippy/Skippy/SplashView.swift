//
//  SplashView.swift
//  Skippy
//
//  Created by Abe White on 2/16/26.
//

import SwiftUI
import AppKit

struct SplashView: View {
    @State private var selectedProject: RecentProject.ID?

    // Stubbed recent projects list (empty for now)
    private let recentProjects: [RecentProject] = []

    var body: some View {
        HStack(spacing: 0) {
            // Left pane: branding + actions
            VStack(spacing: 16) {
                Spacer()

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)

                Text("Skippy")
                    .font(.system(size: 28, weight: .bold))

                Text(versionString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(spacing: 8) {
                    Button {
                        // TODO: New Skip Project action
                    } label: {
                        Text("New Skip Project")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button {
                        // TODO: Open Skip Project action
                    } label: {
                        Text("Open Skip Project")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal, 20)

                Spacer()
                    .frame(height: 24)
            }
            .frame(width: 240)
            .frame(maxHeight: .infinity)

            Divider()

            // Right pane: recent projects
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent Projects")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                if recentProjects.isEmpty {
                    Spacer()
                    Text("No Recent Projects")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List(recentProjects, selection: $selectedProject) { project in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .fontWeight(.semibold)
                            Text(project.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                        .onTapGesture(count: 2) {
                            openProject(project)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 300)
            .frame(maxHeight: .infinity)
        }
        .frame(width: 600, height: 400)
        .background(
            WindowAccessor { window in
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        )
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }

    private func openProject(_ project: RecentProject) {
        // TODO: Open project action
    }
}

struct RecentProject: Identifiable {
    let id = UUID()
    let name: String
    let path: String
}

/// NSViewRepresentable helper that provides access to the hosting NSWindow
/// so we can hide miniaturize and zoom buttons.
private struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    SplashView()
}
