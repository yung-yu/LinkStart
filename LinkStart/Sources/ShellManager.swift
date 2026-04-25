import Foundation

enum ShellError: Error, LocalizedError {
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let msg):
            return msg
        }
    }
}

struct AdbDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ShellManager {
    static let shared = ShellManager()
    
    /// Executes a shell command using zsh and inheriting the system PATH
    @discardableResult
    func run(_ command: String) throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        
        // We ensure homebrew binaries and standard locales are respected
        // We use login shell (-l) so ~/.zshrc or path configs are loaded
        task.arguments = ["-l", "-c", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; \(command)"]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.environment = ProcessInfo.processInfo.environment
        
        try task.run()
        
        // Read all output (stdout and stderr are combined in the pipe)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let errorMsg = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShellError.executionFailed(errorMsg.isEmpty ? "Command failed with exit code \(task.terminationStatus)" : errorMsg)
        }
        
        return output
    }
    
    func isToolInstalled(_ tool: String) -> Bool {
        do {
            try run("which \(tool)")
            return true
        } catch {
            return false
        }
    }
    
    func getDevices() -> [AdbDevice] {
        do {
            let output = try run("adb devices -l")
            let lines = output.components(separatedBy: .newlines)
            var devices: [AdbDevice] = []
            
            for line in lines {
                if line.contains("List of devices") || line.isEmpty { continue }
                
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 2 {
                    let id = components[0]
                    var name = id
                    
                    if let modelMatch = try? NSRegularExpression(pattern: "model:([^\\s]+)").firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                        if let range = Range(modelMatch.range(at: 1), in: line) {
                            name = String(line[range]).replacingOccurrences(of: "_", with: " ")
                        }
                    }
                    devices.append(AdbDevice(id: id, name: name))
                }
            }
            return devices
        } catch {
            return []
        }
    }
    
    func getInstalledPackages(deviceId: String?, includeSystem: Bool) -> [String] {
        do {
            // -3 filters for third-party user apps to avoid 300+ unresolvable system configs.
            // If includeSystem is true, we remove the -3 flag to show all apps.
            let filterFlag = includeSystem ? "" : " -3"
            let adbCommand = deviceId != nil ? "adb -s \(deviceId!) shell pm list packages\(filterFlag)" : "adb shell pm list packages\(filterFlag)"
            let output = try run(adbCommand)
            // Output is like: package:com.example.app\npackage:com.another.app
            let lines = output.components(separatedBy: .newlines)
            var packages: [String] = []
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("package:") {
                    let id = trimmed.replacingOccurrences(of: "package:", with: "")
                    if !id.isEmpty {
                        packages.append(id)
                    }
                }
            }
            return packages
        } catch {
            print("Failed to run adb to fetch packages")
            return []
        }
    }
    
    func isScrcpyRunning(deviceId: String?, isVirtual: Bool, packageId: String? = nil) -> Bool {
        do {
            // Check process list for scrcpy
            let output = try run("ps -A -o args")
            let lines = output.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                // Ensure we match 'scrcpy' binary but NOT 'LinkStart' (this app)
                let isActualScrcpy = (trimmedLine.hasPrefix("scrcpy") || trimmedLine.contains("/scrcpy")) && !trimmedLine.contains("LinkStart.app")
                
                if isActualScrcpy {
                    // Check for device ID if specified
                    let hasDeviceId = deviceId == nil || trimmedLine.contains("-s \(deviceId!)")
                    let hasNewDisplay = trimmedLine.contains("--new-display")
                    let hasPackage = packageId == nil || trimmedLine.contains("--start-app=\(packageId!)")
                    
                    if hasDeviceId && hasPackage {
                        if isVirtual && hasNewDisplay { return true }
                        if !isVirtual && !hasNewDisplay { return true }
                    }
                }
            }
        } catch {
            return false
        }
        return false
    }

    func focusWindow(title: String) {
        let script = """
        tell application "System Events"
            if exists process "scrcpy" then
                set frontmost of process "scrcpy" to true
                try
                    -- Try to find the specific window by title.
                    -- Note: title matching is 'contains' for robustness.
                    set theWindow to (first window of process "scrcpy" whose title contains "\(title)")
                    perform action "AXRaise" of theWindow
                on error
                    -- Fallback if window not found or title mismatch
                end try
            end if
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }
    
    func startScrcpy(for packageId: String, deviceId: String?, resolution: String, videoBitRate: String, maxFps: String, videoCodec: String, useNewDisplay: Bool, iconPath: String? = nil, title: String? = nil) async throws {
        // Handle window reuse logic
        if useNewDisplay {
            // Check if this specific app is already running in a virtual display
            if isScrcpyRunning(deviceId: deviceId, isVirtual: true, packageId: packageId) {
                focusWindow(title: title ?? packageId)
                return
            }
        } else {
            // Check if a main mirror is already running for this device
            if isScrcpyRunning(deviceId: deviceId, isVirtual: false) {
                // Just start the app on the device
                let adbPrefix = deviceId != nil ? "adb -s \(deviceId!) shell" : "adb shell"
                let launchCmd = "\(adbPrefix) monkey -p \(packageId) -c android.intent.category.LAUNCHER 1"
                try _ = run(launchCmd)
                
                // Bring to front
                focusWindow(title: title ?? "scrcpy")
                return
            }
        }

        // Starts scrcpy.
        var command = deviceId != nil ? "scrcpy -s \(deviceId!) --start-app=\(packageId)" : "scrcpy --start-app=\(packageId)"
        
        if let mbps = Int(videoBitRate) {
            let bitRateValue = mbps * 1000000
            command += " --video-bit-rate=\(bitRateValue)"
        }
        
        if let fps = Int(maxFps) {
            command += " --max-fps=\(fps)"
        }
        
        if !videoCodec.isEmpty {
            command += " --video-codec=\(videoCodec)"
        }
        
        if let windowTitle = title {
            command += " --window-title=\"\(windowTitle)\""
        }
        
        if useNewDisplay {
            command += " --new-display=\(resolution)"
        }
             
        // Use a persistent task for scrcpy
        let task = Process()
        let errorPipe = Pipe()
        task.standardError = errorPipe
        task.arguments = ["-l", "-c", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; \(command)"]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var env = ProcessInfo.processInfo.environment
        if let path = iconPath {
            env["SCRCPY_ICON_PATH"] = path
        }
        task.environment = env
        
        try task.run()
        
        // We wait a short moment to see if it crashes immediately
        // This is a simple heuristic to catch most "device not found" or "invalid argument" errors
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        if !task.isRunning && task.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ShellError.executionFailed(errorMsg.isEmpty ? "scrcpy failed to start (exit code \(task.terminationStatus))" : errorMsg)
        }
    }
}
