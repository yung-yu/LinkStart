import Foundation

struct AppDetail: Identifiable {
    let id: String
    let name: String
    let iconUrl: URL?
}

class PlayStoreScraper {
    static let shared = PlayStoreScraper()
    
    func fetchAppDetails(appId: String) async -> AppDetail? {
        guard let url = URL(string: "https://play.google.com/store/apps/details?id=\(appId)") else {
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            // Disguise as a standard browser to avoid basic blocks
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // If the app is not found, Play Store usually returns a 404
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
                    // Clean up " - Apps on Google Play"
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
                    // Sometimes URLs can be missing the "https:" prefix
                    if urlString.hasPrefix("//") {
                        urlString = "https:" + urlString
                    }
                    iconUrl = URL(string: urlString)
                }
            }
            
            return AppDetail(id: appId, name: name, iconUrl: iconUrl)
        } catch {
            return nil
        }
    }
}
