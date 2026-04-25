import Foundation
import Combine

@MainActor
class AppViewModel: ObservableObject {
    @Published var apps: [AppDetail] = []
    @Published var devices: [AdbDevice] = []
    
    @Published var selectedDeviceId: String = UserDefaults.standard.string(forKey: "selectedDeviceId") ?? "" {
        didSet {
            if selectedDeviceId != oldValue {
                UserDefaults.standard.set(selectedDeviceId, forKey: "selectedDeviceId")
                loadSettings(for: selectedDeviceId)
            }
        }
    }
    @Published var isLoading: Bool = false
    @Published var progress: String = ""
    @Published var searchText: String = ""
    
    @Published var includeSystemApps: Bool = false {
        didSet { saveSetting(key: "includeSystemApps", value: includeSystemApps) }
    }
    @Published var displayWidth: String = "1920" {
        didSet { saveSetting(key: "displayWidth", value: displayWidth) }
    }
    @Published var displayHeight: String = "1080" {
        didSet { saveSetting(key: "displayHeight", value: displayHeight) }
    }
    @Published var videoBitRate: String = "8" {
        didSet { saveSetting(key: "videoBitRate", value: videoBitRate) }
    }
    @Published var maxFps: String = "60" {
        didSet { saveSetting(key: "maxFps", value: maxFps) }
    }
    @Published var videoCodec: String = "h264" {
        didSet { saveSetting(key: "videoCodec", value: videoCodec) }
    }
    @Published var useNewDisplay: Bool = true {
        didSet { saveSetting(key: "useNewDisplay", value: useNewDisplay) }
    }
    
    init() {
        if !selectedDeviceId.isEmpty {
            loadSettings(for: selectedDeviceId)
        }
    }
    
    private func saveSetting(key: String, value: Any) {
        guard !selectedDeviceId.isEmpty else { return }
        UserDefaults.standard.set(value, forKey: "\(selectedDeviceId)_\(key)")
    }
    
    private func loadSettings(for deviceId: String) {
        guard !deviceId.isEmpty else { return }
        let defaults = UserDefaults.standard
        
        displayWidth = defaults.string(forKey: "\(deviceId)_displayWidth") ?? "1920"
        displayHeight = defaults.string(forKey: "\(deviceId)_displayHeight") ?? "1080"
        videoBitRate = defaults.string(forKey: "\(deviceId)_videoBitRate") ?? "8"
        maxFps = defaults.string(forKey: "\(deviceId)_maxFps") ?? "60"
        videoCodec = defaults.string(forKey: "\(deviceId)_videoCodec") ?? "h264"
        
        if defaults.object(forKey: "\(deviceId)_useNewDisplay") != nil {
            useNewDisplay = defaults.bool(forKey: "\(deviceId)_useNewDisplay")
        } else {
            useNewDisplay = true
        }
        
        if defaults.object(forKey: "\(deviceId)_includeSystemApps") != nil {
            includeSystemApps = defaults.bool(forKey: "\(deviceId)_includeSystemApps")
        } else {
            includeSystemApps = false
        }
    }
    @Published var alertError: String? = nil
    @Published var errorMsg: String? = nil
    
    @Published var showAbout: Bool = false
    @Published var aboutAdbVersion: String = ""
    @Published var aboutScrcpyVersion: String = ""
    @Published var aboutAppVersion: String = ""
    
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
        progress = NSLocalizedString("prog_checking_dep", comment: "Checking Dependencies")
        errorMsg = nil
        
        Task.detached {
            if !ShellManager.shared.isToolInstalled("adb") {
                await MainActor.run { self.progress = NSLocalizedString("prog_install_adb", comment: "Installing ADB") }
                do {
                    try ShellManager.shared.run("brew install --cask android-platform-tools")
                } catch {
                    await MainActor.run {
                        self.errorMsg = NSLocalizedString("err_adb_install", comment: "ADB Install Error")
                        self.isLoading = false
                    }
                    return
                }
            }
            
            if !ShellManager.shared.isToolInstalled("scrcpy") {
                await MainActor.run { self.progress = NSLocalizedString("prog_install_scrcpy", comment: "Installing Scrcpy") }
                do {
                    try ShellManager.shared.run("brew install scrcpy")
                } catch {
                    await MainActor.run {
                        self.errorMsg = NSLocalizedString("err_scrcpy_install", comment: "Scrcpy Install Error")
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
            self.progress = NSLocalizedString("err_no_devices", comment: "No Devices Error")
            self.isLoading = false
            return
        }
        
        progress = String(format: NSLocalizedString("prog_listing_packages", comment: "Listing Packages"), selectedDeviceId)
        
        Task {
            // Retrieve installed packages using the shell
            let packageIds = ShellManager.shared.getInstalledPackages(
                deviceId: selectedDeviceId.isEmpty ? nil : selectedDeviceId,
                includeSystem: includeSystemApps
            )
            
            if packageIds.isEmpty {
                self.progress = NSLocalizedString("err_no_packages", comment: "No Packages Error")
                self.isLoading = false
                return
            }
            
            self.progress = String(format: NSLocalizedString("prog_fetching_details", comment: "Fetching Details"), packageIds.count)
            
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
            
            self.progress = String(format: NSLocalizedString("prog_loaded_count", comment: "Loaded Count"), fetchedApps.count)
            self.isLoading = false
        }
    }
    
    func launchApp(appId: String, resolution: String, videoBitRate: String, maxFps: String, videoCodec: String, useNewDisplay: Bool) {
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
                let deviceName = await MainActor.run { self.devices.first(where: { $0.id == (deviceId ?? "") })?.name ?? NSLocalizedString("fallback_device_name", comment: "Fallback Device Name") }
                
                // Only use the app name in the title if we are opening a new virtual display.
                // For the main mirror, keep the title stable as the device name for better window reuse.
                let windowTitle = useNewDisplay ? "\(app.name) — \(deviceName)" : deviceName
                
                try await ShellManager.shared.startScrcpy(for: appId, deviceId: deviceId, resolution: resolution, videoBitRate: videoBitRate, maxFps: maxFps, videoCodec: videoCodec, useNewDisplay: useNewDisplay, iconPath: iconPath, title: windowTitle)
            } catch {
                await MainActor.run {
                    self.alertError = error.localizedDescription
                }
            }
        }
    }
    
    func fetchAboutInfo() {
        Task {
            var adbVersion = "Unknown"
            var scrcpyVersion = "Unknown"
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
            
            do {
                let adbOut = try ShellManager.shared.run("adb --version")
                if let line = adbOut.components(separatedBy: .newlines).first(where: { $0.contains("Version") || $0.contains("version") }) {
                    adbVersion = line.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    adbVersion = adbOut.components(separatedBy: .newlines).first ?? "Installed"
                }
            } catch {
                adbVersion = "Not Installed or Error"
            }
            
            do {
                let scrcpyOut = try ShellManager.shared.run("scrcpy --version")
                if let line = scrcpyOut.components(separatedBy: .newlines).first(where: { $0.contains("scrcpy") }) {
                    scrcpyVersion = line.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    scrcpyVersion = scrcpyOut.components(separatedBy: .newlines).first ?? "Installed"
                }
            } catch {
                scrcpyVersion = "Not Installed or Error"
            }
            
            await MainActor.run {
                self.aboutAdbVersion = adbVersion
                self.aboutScrcpyVersion = scrcpyVersion
                self.aboutAppVersion = "\(appVersion) (Build \(buildVersion))"
                self.showAbout = true
            }
        }
    }
}
