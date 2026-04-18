import Foundation

struct AppDetail: Identifiable, Codable {
    let id: String
    let name: String
    let iconUrl: URL?
}

struct CachedAppDetail: Codable {
    let detail: AppDetail
    let timestamp: Date
}

class PlayStoreScraper {
    static let shared = PlayStoreScraper()
    
    private var cache: [String: CachedAppDetail] = [:]
    private let cacheFile: URL
    private let cacheTTL: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    
    private init() {
        // Initialize cache directory and file path
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LinkStart", isDirectory: true)
        
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        self.cacheFile = cacheDir.appendingPathComponent("AppMetadataCache.json")
        loadCache()
    }
    
    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFile) else { return }
        do {
            self.cache = try JSONDecoder().decode([String: CachedAppDetail].self, from: data)
        } catch {
            print("Failed to decode cache: \(error)")
        }
    }
    
    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheFile)
        } catch {
            print("Failed to save cache: \(error)")
        }
    }
    
    func fetchAppDetails(appId: String) async -> AppDetail? {
        // 1. Check in-memory/on-disk cache first
        if let cached = cache[appId] {
            // Check if cache is still valid
            if Date().timeIntervalSince(cached.timestamp) < cacheTTL {
                return cached.detail
            }
        }
        
        // 2. Not in cache or expired, fetch from Play Store
        guard let url = URL(string: "https://play.google.com/store/apps/details?id=\(appId)") else {
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                return nil
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            // Extract the title
            var name = appId
            if let titleMatch = try? NSRegularExpression(pattern: "<meta property=\"og:title\" content=\"([^\"]+)\"").firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let range = Range(titleMatch.range(at: 1), in: html) {
                    name = String(html[range])
                    if let index = name.range(of: " - Apps on Google Play")?.lowerBound {
                        name = String(name[..<index])
                    } else if let index = name.range(of: " - Google Play")?.lowerBound {
                        name = String(name[..<index])
                    }
                }
            }
            
            // Extract the icon URL
            var iconUrl: URL? = nil
            if let imageMatch = try? NSRegularExpression(pattern: "<meta property=\"og:image\" content=\"([^\"]+)\"").firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let range = Range(imageMatch.range(at: 1), in: html) {
                    var urlString = String(html[range])
                    if urlString.hasPrefix("//") {
                        urlString = "https:" + urlString
                    }
                    iconUrl = URL(string: urlString)
                }
            }
            
            let detail = AppDetail(id: appId, name: name, iconUrl: iconUrl)
            
            // 3. Update cache and save to disk
            cache[appId] = CachedAppDetail(detail: detail, timestamp: Date())
            saveCache()
            
            return detail
        } catch {
            return nil
        }
    }
}
