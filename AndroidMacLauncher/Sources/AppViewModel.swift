import Foundation
import Combine

@MainActor
class AppViewModel: ObservableObject {
    @Published var apps: [AppDetail] = []
    @Published var devices: [AdbDevice] = []
    
    @Published var selectedDeviceId: String = UserDefaults.standard.string(forKey: "selectedDeviceId") ?? ""
    @Published var isLoading: Bool = false
    @Published var progress: String = ""
    @Published var searchText: String = ""
    @Published var alertError: String? = nil
    @Published var errorMsg: String? = nil
    
    var filteredApps: [AppDetail] {
        if searchText.isEmpty {
            return apps
        } else {
            return apps.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) || 
                $0.id.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    func checkDependenciesAndRefresh() {
        isLoading = true
        progress = "Checking dependencies..."
        errorMsg = nil
        
        Task.detached {
            if !ShellManager.shared.isToolInstalled("adb") {
                await MainActor.run { self.progress = "Installing adb (android-platform-tools)..." }
                do {
                    try ShellManager.shared.run("brew install --cask android-platform-tools")
                } catch {
                    await MainActor.run {
                        self.errorMsg = "Failed to install adb. Please install homebrew or run: brew install --cask android-platform-tools manually."
                        self.isLoading = false
                    }
                    return
                }
            }
            
            if !ShellManager.shared.isToolInstalled("scrcpy") {
                await MainActor.run { self.progress = "Installing scrcpy... This may take a few minutes." }
                do {
                    try ShellManager.shared.run("brew install scrcpy")
                } catch {
                    await MainActor.run {
                        self.errorMsg = "Failed to install scrcpy. Please install homebrew or run: brew install scrcpy manually."
                        self.isLoading = false
                    }
                    return
                }
            }
            
            await MainActor.run { self.refreshApps() }
        }
    }
    
    func refreshApps() {
        isLoading = true
        apps = []
        
        let currentDevices = ShellManager.shared.getDevices()
        self.devices = currentDevices
        if !currentDevices.contains(where: { $0.id == selectedDeviceId }) {
            selectedDeviceId = currentDevices.first?.id ?? ""
        }
        
        if currentDevices.isEmpty {
            self.progress = "No adb devices found."
            self.isLoading = false
            return
        }
        
        progress = "Listing packages for \(selectedDeviceId)..."
        
        Task {
            // Retrieve installed packages using the shell
            let packageIds = ShellManager.shared.getInstalledPackages(deviceId: selectedDeviceId.isEmpty ? nil : selectedDeviceId)
            
            if packageIds.isEmpty {
                self.progress = "No packages found, or adb device is offline."
                self.isLoading = false
                return
            }
            
            self.progress = "Fetching details for \(packageIds.count) apps..."
            
            var fetchedApps: [AppDetail] = []
            
            // To prevent blocking or being rate-limited by Play Store,
            // we will process them concurrently but smoothly. 
            // In a real robust system, use a TaskGroup with limits.
            await withTaskGroup(of: AppDetail?.self) { group in
                for id in packageIds {
                    group.addTask {
                        // Some apps won't have store listings, return a generic one if 404
                        if let detail = await PlayStoreScraper.shared.fetchAppDetails(appId: id) {
                            return detail
                        }
                        return AppDetail(id: id, name: id, iconUrl: nil)
                    }
                }
                
                for await result in group {
                    if let detail = result {
                        // Avoid adding duplicates (sometimes adb returns same app for different users)
                        if !fetchedApps.contains(where: { $0.id == detail.id }) {
                            fetchedApps.append(detail)
                            // We can update the UI dynamically so it doesn't look stuck
                            let sortedApps = fetchedApps.sorted { $0.name.lowercased() < $1.name.lowercased() }
                            self.apps = sortedApps
                        }
                    }
                }
            }
            
            self.progress = "Loaded \(fetchedApps.count) apps."
            self.isLoading = false
        }
    }
    
    func launchApp(appId: String, resolution: String, useNewDisplay: Bool) {
        guard let app = apps.first(where: { $0.id == appId }) else { return }
        
        Task.detached {
            var iconPath: String? = nil
            
            // Optimization: If we are reusing an existing window, we don't need to change/download the icon
            let deviceId = await MainActor.run { self.selectedDeviceId.isEmpty ? nil : self.selectedDeviceId }
            let willReuseWindow = !useNewDisplay && ShellManager.shared.isScrcpyRunning(deviceId: deviceId, isVirtual: false)
            
            if !willReuseWindow, let url = app.iconUrl {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileUrl = tempDir.appendingPathComponent("\(appId)_icon.png")
                    try data.write(to: fileUrl)
                    iconPath = fileUrl.path
                } catch {
                    print("Failed to download icon for scrcpy: \(error)")
                }
            }
            
            do {
                let deviceId = await MainActor.run { self.selectedDeviceId.isEmpty ? nil : self.selectedDeviceId }
                let deviceName = await MainActor.run { self.devices.first(where: { $0.id == (deviceId ?? "") })?.name ?? "Android Device" }
                
                // Only use the app name in the title if we are opening a new virtual display.
                // For the main mirror, keep the title stable as the device name for better window reuse.
                let windowTitle = useNewDisplay ? "\(app.name) — \(deviceName)" : deviceName
                
                try await ShellManager.shared.startScrcpy(for: appId, deviceId: deviceId, resolution: resolution, useNewDisplay: useNewDisplay, iconPath: iconPath, title: windowTitle)
            } catch {
                await MainActor.run {
                    self.alertError = error.localizedDescription
                }
            }
        }
    }
}
