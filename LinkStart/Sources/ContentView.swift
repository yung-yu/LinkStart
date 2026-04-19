import SwiftUI

struct AppItemView: View {
    let app: AppDetail
    var action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                if let url = app.iconUrl {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 64, height: 64)
                        case .success(let image):
                            image.resizable()
                                 .aspectRatio(contentMode: .fit)
                                 .frame(width: 64, height: 64)
                                 .cornerRadius(16)
                                 .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        case .failure:
                            FallbackIcon()
                        @unknown default:
                            FallbackIcon()
                        }
                    }
                } else {
                    FallbackIcon()
                }
                
                Text(app.name)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .frame(height: 36, alignment: .top)
            }
            .padding(16)
            .frame(width: 120, height: 160)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            .cornerRadius(20)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
    }
}

struct FallbackIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 64, height: 64)
            Image(systemName: "app.badge")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    
    @AppStorage("displayWidth") private var displayWidth: String = "1920"
    @AppStorage("displayHeight") private var displayHeight: String = "1080"
    @AppStorage("useNewDisplay") private var useNewDisplay: Bool = true
    
    let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 20)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                // Top Row
                HStack(spacing: 16) {
                    Text(NSLocalizedString("app_name", comment: "App Name"))
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !viewModel.devices.isEmpty {
                        Picker("", selection: $viewModel.selectedDeviceId) {
                            ForEach(viewModel.devices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 150)
                        .onChange(of: viewModel.selectedDeviceId) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "selectedDeviceId")
                            viewModel.refreshApps()
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField(NSLocalizedString("search_placeholder", comment: "Search Placeholder"), text: $viewModel.searchText)
                                .textFieldStyle(.plain)
                            if !viewModel.searchText.isEmpty {
                                Button(action: { viewModel.searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .frame(width: 180)
                    }
                    
                    Spacer()
                    
                    Toggle(NSLocalizedString("include_system_apps", comment: "Include System Apps"), isOn: $viewModel.includeSystemApps)
                        .toggleStyle(.checkbox)
                        .onChange(of: viewModel.includeSystemApps) { _ in
                            viewModel.refreshApps()
                        }
                    
                    Button(action: {
                        viewModel.checkDependenciesAndRefresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
                    
                    Button(action: {
                        viewModel.fetchAboutInfo()
                    }) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.bordered)
                }
                
                // Bottom Row
                HStack(spacing: 16) {
                    Spacer()
                    
                    Toggle(NSLocalizedString("new_display_toggle", comment: "New Display Toggle"), isOn: $useNewDisplay)
                        .toggleStyle(.checkbox)
                    
                    if useNewDisplay {
                        HStack(spacing: 4) {
                            TextField(NSLocalizedString("width_label", comment: "Width"), text: $displayWidth)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                            Text("x")
                                .foregroundColor(.secondary)
                            TextField(NSLocalizedString("height_label", comment: "Height"), text: $displayHeight)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
            
            Divider()
            
            if let errorMsg = viewModel.errorMsg {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                        .padding()
                    Text(NSLocalizedString("dep_failed_title", comment: "Dependency Error Title"))
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(NSLocalizedString("retry_button", comment: "Retry Button")) {
                         viewModel.checkDependenciesAndRefresh()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isLoading && viewModel.apps.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text(viewModel.progress)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.apps.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                        .padding()
                    Text(NSLocalizedString("no_apps_title", comment: "No Apps Title"))
                        .font(.headline)
                    Text(NSLocalizedString("no_apps_message", comment: "No Apps Message"))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(NSLocalizedString("retry_button", comment: "Retry Button")) {
                         viewModel.checkDependenciesAndRefresh()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.filteredApps) { app in
                            AppItemView(app: app) {
                                let res = "\(displayWidth)x\(displayHeight)"
                                viewModel.launchApp(appId: app.id, resolution: res, useNewDisplay: useNewDisplay)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            
            // Footer status
            if viewModel.isLoading && !viewModel.apps.isEmpty {
                Divider()
                HStack {
                    ProgressView().controlSize(.small)
                    Text(viewModel.progress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear {
            viewModel.checkDependenciesAndRefresh()
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert(NSLocalizedString("exec_error_title", comment: "Execution Error Title"), isPresented: Binding(
            get: { viewModel.alertError != nil },
            set: { if !$0 { viewModel.alertError = nil } }
        )) {
            Button(NSLocalizedString("ok_button", comment: "OK Button"), role: .cancel) { }
        } message: {
            Text(viewModel.alertError ?? NSLocalizedString("unknown_error", comment: "Unknown Error"))
        }
        .sheet(isPresented: $viewModel.showAbout) {
            VStack(spacing: 16) {
                Text(NSLocalizedString("about_title", value: "About LinkStart", comment: "About Title"))
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("作者: AndyLi")
                    HStack(spacing: 0) {
                        Text("來源: ")
                        Link("https://github.com/yung-yu/LinkStart", destination: URL(string: "https://github.com/yung-yu/LinkStart")!)
                    }
                    HStack(spacing: 0) {
                        Text("聯絡: ")
                        Link("yungyu405728@gmail.com", destination: URL(string: "mailto:yungyu405728@gmail.com")!)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Version: \(viewModel.aboutAppVersion)")
                    Text("ADB: \(viewModel.aboutAdbVersion)")
                    Text("Scrcpy: \(viewModel.aboutScrcpyVersion)")
                }
                .font(.footnote)
                
                Button(NSLocalizedString("ok_button", comment: "OK Button")) {
                    viewModel.showAbout = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
            .frame(width: 320)
        }
    }
}
