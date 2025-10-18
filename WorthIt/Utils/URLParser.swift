//
//  URLParser.swift
//  WorthIt
//

import Foundation

// Ensure Logger.swift and Models.swift (for AppConstants) are correctly targeted for this file.

enum URLParserError: Error, LocalizedError {
    case invalidURL(String)
    case unsupportedDomain(String)
    case missingVideoID(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "The provided URL is invalid: \(url)"
        case .unsupportedDomain(let domain): return "The domain '\(domain)' is not supported."
        case .missingVideoID(let url): return "Could not find a valid video ID in the URL: \(url)"
        }
    }
}

class URLParser {
    private static let validVideoIDChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    static func extractVideoID(from url: URL) throws -> String {
        let urlString = url.absoluteString
        Logger.shared.debug("Attempting to parse video link: \(urlString)", category: .parsing)

        guard let host = url.host?.lowercased() else {
            Logger.shared.error("Invalid URL: missing host for \(urlString)", category: .parsing)
            throw URLParserError.invalidURL(urlString)
        }

        let isSupportedPlatform = host.contains("youtu")

        guard isSupportedPlatform else {
            Logger.shared.error("Unsupported video domain: \(host) from URL: \(urlString)", category: .parsing)
            throw URLParserError.unsupportedDomain(host)
        }

        if host == "youtu.be" {
            let videoID = String(url.path.dropFirst())
            if isValidVideoIDFormat(videoID) {
                Logger.shared.info("Extracted video ID '\(videoID)' from short URL: \(urlString)", category: .parsing)
                return videoID
            } else {
                 Logger.shared.warning("Invalid ID '\(videoID)' from short URL path: \(urlString)", category: .parsing)
            }
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            if let videoID = queryItems.first(where: { $0.name == "v" })?.value, isValidVideoIDFormat(videoID) {
                Logger.shared.info("Extracted video ID '\(videoID)' from 'v' query parameter: \(urlString)", category: .parsing)
                return videoID
            }
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        let pathBasedKeywords = ["embed", "shorts", "live"]
        for keyword in pathBasedKeywords {
            if let keywordIndex = pathComponents.firstIndex(of: keyword), keywordIndex + 1 < pathComponents.count {
                let potentialID = pathComponents[keywordIndex + 1]
                if isValidVideoIDFormat(potentialID) {
                    Logger.shared.info("Extracted video ID '\(potentialID)' from '/\(keyword)/' path: \(urlString)", category: .parsing)
                    return potentialID
                } else {
                    Logger.shared.warning("Invalid ID '\(potentialID)' found after '/\(keyword)/' in URL: \(urlString)", category: .parsing)
                }
            }
        }

        if pathComponents.first == "v", pathComponents.count > 1 {
            let potentialID = pathComponents[1]
            if isValidVideoIDFormat(potentialID) {
                Logger.shared.info("Extracted video ID '\(potentialID)' from '/v/' path: \(urlString)", category: .parsing)
                return potentialID
            } else {
                Logger.shared.warning("Invalid ID '\(potentialID)' found after '/v/' in URL: \(urlString)", category: .parsing)
            }
        }

        Logger.shared.error("Failed to extract a valid video ID from URL: \(urlString) after all checks.", category: .parsing)
        throw URLParserError.missingVideoID(urlString)
    }

    static func firstSupportedVideoURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            Logger.shared.error("Failed to create NSDataDetector for link detection.", category: .parsing)
            return nil
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let matches = detector.matches(in: text, options: [], range: fullRange)

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let urlString = String(text[range])

            if let url = URL(string: urlString) {
                if let host = url.host?.lowercased(), host.contains("youtu") {
                    if (try? extractVideoID(from: url)) != nil {
                        Logger.shared.info("Found supported video URL in text: \(url.absoluteString)", category: .parsing)
                        return url
                    }
                }
            }
        }
        Logger.shared.debug("No supported video URL found in provided text.", category: .parsing)
        return nil
    }

    private static func isValidVideoIDFormat(_ id: String) -> Bool {
        return id.count == 11 && id.rangeOfCharacter(from: validVideoIDChars.inverted) == nil
    }
}
