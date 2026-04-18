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
            HStack(spacing: 16) {
                Text("LinkStart")
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
                }
                
                Spacer()
                
                Toggle("New Display", isOn: $useNewDisplay)
                    .toggleStyle(.checkbox)
                
                if useNewDisplay {
                    HStack(spacing: 4) {
                        TextField("W", text: $displayWidth)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                        Text("x")
                            .foregroundColor(.secondary)
                        TextField("H", text: $displayHeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Button(action: {
                    viewModel.checkDependenciesAndRefresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
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
                    Text("Dependency Installation Failed")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") {
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
                    Text("No Apps Found")
                        .font(.headline)
                    Text("Ensure your Android device is connected and debugging is authorized via adb.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") {
                         viewModel.checkDependenciesAndRefresh()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.apps) { app in
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
        .alert("Execution Error", isPresented: Binding(
            get: { viewModel.alertError != nil },
            set: { if !$0 { viewModel.alertError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertError ?? "An unknown error occurred.")
        }
    }
}
