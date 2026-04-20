import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "UpdateChecker")

/// Checks GitHub Releases for newer versions of Scribe
public actor UpdateChecker {
    public static let shared = UpdateChecker()

    private let repo = "iamabhishekmathur/scribe"
    private let currentVersion: String

    /// Set after a successful check — latest release info
    public struct Release: Sendable {
        public let version: String
        public let downloadURL: URL
        public let htmlURL: URL
        public let releaseNotes: String
    }

    private init() {
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check GitHub for a newer release. Returns the release if one is available, nil otherwise.
    public func checkForUpdate() async -> Release? {
        let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.info("GitHub API returned non-200 status")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString) else {
                return nil
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let releaseNotes = json["body"] as? String ?? ""

            guard isNewer(remote: remoteVersion, current: currentVersion) else {
                logger.info("Up to date (current: \(self.currentVersion), latest: \(remoteVersion))")
                return nil
            }

            // Find .dmg asset download URL
            var dmgURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.hasSuffix(".dmg"),
                       let downloadStr = asset["browser_download_url"] as? String,
                       let downloadUrl = URL(string: downloadStr) {
                        dmgURL = downloadUrl
                        break
                    }
                }
            }

            let downloadURL = dmgURL ?? htmlURL

            logger.info("Update available: \(self.currentVersion) → \(remoteVersion)")
            return Release(
                version: remoteVersion,
                downloadURL: downloadURL,
                htmlURL: htmlURL,
                releaseNotes: releaseNotes
            )
        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Simple semver comparison: returns true if remote > current
    private func isNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
