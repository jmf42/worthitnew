
// APIManager.swift

import Foundation

// MARK: - Data Models


enum NetworkError: LocalizedError {
    case serverUnavailable
    case rateLimited
    case decodingFailed
    case network(Error)
    case unknownStatus(Int)

    var errorDescription: String? {
        switch self {
        case .serverUnavailable:
            return "Our servers are temporarily unavailable. Please try again later."
        case .rateLimited:
            return "Too many requests — please wait a moment and retry."
        case .decodingFailed:
            return "We couldn't read the server response."
        case .network(let err):
            return err.localizedDescription
        case .unknownStatus(let code):
            return "Unexpected server response (code \(code))."
        }
    }
}

private actor TranscriptTaskRegistry {
    private var tasks: [String: Task<String, Error>] = [:]

    func task(for videoId: String) -> Task<String, Error>? {
        tasks[videoId]
    }

    func insert(_ task: Task<String, Error>, for videoId: String) {
        tasks[videoId] = task
    }

    func remove(for videoId: String) {
        tasks[videoId] = nil
    }
}

protocol GPTServiceProtocol {
    func fetchContentAnalysis(transcript: String, videoTitle: String, comments: [String]) async throws -> ContentAnalysis
    func fetchCommentInsights(comments: [String], transcriptContext: String) async throws -> CommentInsights
    func answerQuestion(transcript: String, question: String, history: [ChatMessage]) async throws -> QAResponse
}

class APIManager: GPTServiceProtocol {
    private let session: URLSession
    private let baseURL: URL
    private var openAIModelName: String
    var lastResponseId: String?
    private var cachedCommentInsights: CommentInsights?
    private let transcriptTaskRegistry = TranscriptTaskRegistry()

    init(session: URLSession = URLSession.shared) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15        // seconds
        configuration.timeoutIntervalForResource = 30       // seconds
        self.session = URLSession(configuration: configuration)
        guard let baseURLString = Bundle.main.infoDictionary?[AppConstants.apiBaseURLKey] as? String,
              let url = URL(string: baseURLString) else {
            Logger.shared.critical("APIManager Fatal Error: \(AppConstants.apiBaseURLKey) not set or invalid in Info.plist", category: .networking)
            fatalError("\(AppConstants.apiBaseURLKey) not set or invalid in Info.plist")
        }
        self.baseURL = url
        // Default to GPT‑5 Nano (low thinking) model
        self.openAIModelName = "gpt-5-nano-2025-08-07"
        Logger.shared.info("APIManager initialized with base URL: \(self.baseURL.absoluteString)", category: .services)
    }

    // Generic request performer - T must be Decodable
    private func performRequest<T: Decodable>(endpoint: String, method: String = "GET", queryParams: [String: String]? = nil, body: Data? = nil, timeout: TimeInterval = 35, extraHeaders: [String: String]? = nil) async throws -> T {
        // Build an absolute or relative URL without duplicating the baseURL
        let targetURL: URL
        if endpoint.hasPrefix("http") {
            guard let abs = URL(string: endpoint) else {
                throw NetworkError.unknownStatus(-1)
            }
            targetURL = abs
        } else {
            targetURL = baseURL.appendingPathComponent(endpoint)
        }
        var components = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)!
        if let queryParams = queryParams {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        let url = components.url ?? targetURL

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        var logExtra: [String: Any] = [:]
        if let bodyData = body {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            logExtra["body_size"] = bodyData.count
        }

        if let headers = extraHeaders {
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        }

        Logger.shared.debug("Requesting \(method) \(url.absoluteString)", category: .networking, extra: logExtra)

        var attempt = 0
        let maxRetries = 1
        while true {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.serverUnavailable
                }

                Logger.shared.debug("Response status: \(httpResponse.statusCode) for \(url.absoluteString) (endpoint: \(endpoint))", category: .networking)

                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorPayload = String(data: data, encoding: .utf8) ?? "No error details"
                    Logger.shared.error("API Error: \(httpResponse.statusCode) for \(url.absoluteString) (endpoint: \(endpoint))", category: .networking, extra: ["details": errorPayload.prefix(1000)])
                    AnalyticsService.shared.logNetworkError(endpoint: endpoint, error: "HTTP \(httpResponse.statusCode)")
                    if httpResponse.statusCode == 429 { throw NetworkError.rateLimited }
                    if (try? JSONDecoder().decode(BackendErrorResponse.self, from: data)) != nil {
                        throw NetworkError.unknownStatus(httpResponse.statusCode)
                    }
                    throw NetworkError.unknownStatus(httpResponse.statusCode)
                }

                if T.self == Data.self {
                    return data as! T
                }

                do {
                    let decoder = JSONDecoder()
                    let decodedObject = try decoder.decode(T.self, from: data)
                    return decodedObject
                } catch let decodingError {
                    let dataPreview = String(data: data, encoding: .utf8)?.prefix(1000) ?? "Invalid UTF-8 data"
                    var errorDetails = "Raw data preview: \(dataPreview)"
                    // Use the general Error.userFriendlyMessage extension for consistent messaging
                    errorDetails += "\nDecoding Error Context: \(decodingError.userFriendlyMessage)"
                    Logger.shared.error("Decoding error for \(T.self) from \(endpoint) URL: \(url.absoluteString). \(errorDetails)", category: .parsing, error: decodingError)
                    throw NetworkError.decodingFailed
                }
            }
            catch {
                if (error as? URLError)?.code == .timedOut, attempt < maxRetries {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))
                    continue
                }
                AnalyticsService.shared.logNetworkError(endpoint: endpoint, error: error.localizedDescription)
                throw NetworkError.network(error)
            }
        }
    }

    private struct BackendErrorResponse: Decodable {
        let error: String
    }

    func fetchTranscript(videoId: String) async throws -> String {
        if let existing = await transcriptTaskRegistry.task(for: videoId) {
            Logger.shared.info("Joining in-flight transcript fetch for \(videoId)", category: .networking)
            return try await existing.value
        }

        let task = Task<String, Error> {
            try await self.performTranscriptFetch(videoId: videoId)
        }

        await transcriptTaskRegistry.insert(task, for: videoId)

        do {
            let transcript = try await task.value
            await transcriptTaskRegistry.remove(for: videoId)
            return transcript
        } catch {
            await transcriptTaskRegistry.remove(for: videoId)
            throw error
        }
    }

    private func performTranscriptFetch(videoId: String) async throws -> String {
        struct BackendTranscriptResponse: Decodable { let text: String? }

        let deviceLang: String = {
            guard let id = Locale.preferredLanguages.first, !id.isEmpty else { return "en" }
            if #available(iOS 16.0, *) {
                let lang = Locale.Language(identifier: id)
                if let code = lang.languageCode?.identifier { return code }
            } else if let primary = id.split(separator: "-").first, !primary.isEmpty {
                return String(primary)
            }
            let simple = id.prefix(2)
            return simple.isEmpty ? "en" : String(simple)
        }()

        let base = ["en", "es", "pt", "hi", "ar"]
        var ordered: [String] = []
        func appendUnique(_ code: String) { if !ordered.contains(code) { ordered.append(code) } }
        appendUnique(deviceLang)
        for code in base { appendUnique(code) }
        ordered = Array(ordered.prefix(5))

        let primaryLanguage = ordered.first ?? "en"
        let fallbackLanguages = ordered.joined(separator: ",")
        let fallbackAccept = ordered.enumerated().map { idx, code in
            let q = String(format: "%.1f", 1.0 - (Double(idx) * 0.1))
            return "\(code);q=\(q)"
        }.joined(separator: ", ")

        Logger.shared.info("Transcript request starting for \(videoId) with primary language=\(primaryLanguage)", category: .networking)
        let transcriptRequestTimeout: TimeInterval = 25
        do {
            let response: BackendTranscriptResponse = try await performRequest(
                endpoint: "transcript",
                queryParams: ["videoId": videoId, "languages": primaryLanguage],
                timeout: transcriptRequestTimeout,
                extraHeaders: [
                    "Accept-Language": "\(primaryLanguage);q=1.0",
                    "X-Device-Languages": primaryLanguage
                ]
            )
            if let text = response.text, !text.isEmpty { return text }
            throw NetworkError.decodingFailed
        } catch let NetworkError.unknownStatus(code) where code == 404 {
            Logger.shared.notice("Transcript 404 for \(videoId) with primary language. Retrying with fallbacks...", category: .networking)
            if let text = try? await performRequest(
                endpoint: "transcript",
                queryParams: ["videoId": videoId],
                timeout: transcriptRequestTimeout
            ) as BackendTranscriptResponse, let t = text.text, !t.isEmpty {
                Logger.shared.info("Transcript fallback succeeded without languages for \(videoId)", category: .networking)
                return t
            }
            if let text = try? await performRequest(
                endpoint: "transcript",
                queryParams: ["videoId": videoId, "languages": "en"],
                timeout: transcriptRequestTimeout
            ) as BackendTranscriptResponse, let t = text.text, !t.isEmpty {
                Logger.shared.info("Transcript fallback succeeded with languages=en for \(videoId)", category: .networking)
                return t
            }
            if fallbackLanguages != primaryLanguage,
               !fallbackLanguages.isEmpty,
               let text = try? await performRequest(
                    endpoint: "transcript",
                    queryParams: ["videoId": videoId, "languages": fallbackLanguages],
                    timeout: transcriptRequestTimeout,
                    extraHeaders: [
                        "Accept-Language": fallbackAccept,
                        "X-Device-Languages": fallbackLanguages
                    ]
               ) as BackendTranscriptResponse, let t = text.text, !t.isEmpty {
                Logger.shared.info("Transcript fallback succeeded with expanded languages for \(videoId)", category: .networking)
                return t
            }
            Logger.shared.warning("Transcript not available after fallbacks for \(videoId)", category: .networking)
            throw NetworkError.unknownStatus(404)
        } catch let NetworkError.network(inner) {
            if let ne = inner as? NetworkError, case .unknownStatus(let code) = ne, code == 404 {
                Logger.shared.notice("Transcript 404 (wrapped) for \(videoId). Retrying fallbacks...", category: .networking)
                if let text = try? await performRequest(
                    endpoint: "transcript",
                    queryParams: ["videoId": videoId],
                    timeout: transcriptRequestTimeout
                ) as BackendTranscriptResponse, let t = text.text, !t.isEmpty {
                    Logger.shared.info("Transcript fallback succeeded without languages for \(videoId)", category: .networking)
                    return t
                }
                if let text = try? await performRequest(
                    endpoint: "transcript",
                    queryParams: ["videoId": videoId, "languages": "en"],
                    timeout: transcriptRequestTimeout
                ) as BackendTranscriptResponse, let t = text.text, !t.isEmpty {
                    Logger.shared.info("Transcript fallback succeeded with languages=en for \(videoId)", category: .networking)
                    return t
                }
                if fallbackLanguages != primaryLanguage,
                   !fallbackLanguages.isEmpty,
                   let text = try? await performRequest(
                        endpoint: "transcript",
                        queryParams: ["videoId": videoId, "languages": fallbackLanguages],
                        timeout: transcriptRequestTimeout
                   ) as BackendTranscriptResponse, let t = text.text, !t.isEmpty {
                    Logger.shared.info("Transcript fallback succeeded with expanded languages for \(videoId)", category: .networking)
                    return t
                }
                Logger.shared.warning("Transcript not available after fallbacks for \(videoId)", category: .networking)
                throw NetworkError.unknownStatus(404)
            }
            throw NetworkError.network(inner)
        }
    }

    func fetchComments(videoId: String) async throws -> [String] {
        struct CommentsResponse: Decodable { let comments: [String]? }

        do {
            let response: CommentsResponse = try await performRequest(
                endpoint: "comments",
                queryParams: ["videoId": videoId, "limit": "50"],
                timeout: 15
            )
            return response.comments ?? []
        } catch {
            Logger.shared.warning("Comments unavailable for \(videoId): \(error)")
            AnalyticsService.shared.logCommentsNotFound(videoId: videoId)
            return [] // graceful fallback
        }
    }

    private func performOpenAIRequest<Payload: Encodable, ResponseType: Decodable>(
        payload: Payload, // This is OpenAIProxyRequest<String>
        captureResponseId: Bool = false
    ) async throws -> ResponseType {
        // Encode the payload (do not implicitly chain here; call sites decide)
        let initialBody = try JSONEncoder().encode(payload)
        var bodyDict = try JSONSerialization.jsonObject(with: initialBody) as! [String: Any]
        // Force JSON object responses via Responses API text.format only (proxy rejects top-level response_format)
        var textObj = (bodyDict["text"] as? [String: Any]) ?? [:]
        var formatObj = (textObj["format"] as? [String: Any]) ?? [:]
        formatObj["type"] = "json_object"
        textObj["format"] = formatObj
        // Reduce verbosity to minimize output tokens
        textObj["verbosity"] = "low"
        bodyDict["text"] = textObj
        // Reduce reasoning effort to lower latency and token use
        var reasoningObj = (bodyDict["reasoning"] as? [String: Any]) ?? [:]
        reasoningObj["effort"] = "minimal"
        bodyDict["reasoning"] = reasoningObj
        // Ensure responses are stored for observability and debugging
        bodyDict["store"] = true
        // Retain central temperature stripping for GPT‑5 nano to avoid API complaints
        if let modelInBody = bodyDict["model"] as? String, modelInBody.hasPrefix("gpt-5-nano") {
            bodyDict.removeValue(forKey: "temperature")
        }
        let requestBody = try JSONSerialization.data(withJSONObject: bodyDict)

        // 1. Get raw Data from the proxy endpoint.
        let rawProxyResponseData: Data = try await performRequest(
            endpoint: "openai/responses",
            method: "POST",
            body: requestBody,
            timeout: 120
        )

        let proxyResponsePreviewProvider: () -> String = {
            String(data: rawProxyResponseData, encoding: .utf8) ?? "Could not convert proxy response data to UTF8 string"
        }
        let rawProxyResponseStringForLog: String?
        if Logger.isVerboseLoggingEnabled {
            let preview = proxyResponsePreviewProvider()
            rawProxyResponseStringForLog = preview
            Logger.shared.debug(
                "Raw data from OpenAI proxy (size: \(rawProxyResponseData.count)) before DTO decoding: \(preview.prefix(1500))",
                category: .networking
            )
        } else {
            rawProxyResponseStringForLog = nil
        }

        // 2. Decode the raw data into OpenAIProxyResponseDTO (best-effort). If it fails, fall back to raw-walk parsing later.
        let proxyDTO: OpenAIProxyResponseDTO?
        do {
            proxyDTO = try JSONDecoder().decode(OpenAIProxyResponseDTO.self, from: rawProxyResponseData)
        } catch let dtoDecodingError {
            let preview = rawProxyResponseStringForLog ?? proxyResponsePreviewProvider()
            Logger.shared.error(
                "Failed to decode OpenAIProxyResponseDTO from proxy response.",
                category: .parsing,
                error: dtoDecodingError,
                extra: ["rawDataPreview": preview.prefix(500)]
            )
            // Proceed with fallback path using raw JSON below
            proxyDTO = nil
        }

        // Save the response id only when explicitly requested (Q&A chaining)
        if captureResponseId, let newId = proxyDTO?.id, !newId.isEmpty {
            lastResponseId = newId
            Logger.shared.info("Updated lastResponseId to \(newId)", category: .services)
        }

        // 3. Extract the primary JSON text content from the DTO (with GPT-5 fallback)
        var extractedText = proxyDTO?.getPrimaryTextContent()
        if extractedText == nil {
            // Fallback for GPT‑5 Responses: try root `output_text` or walk `output[].content[]`
            if let root = try? JSONSerialization.jsonObject(with: rawProxyResponseData, options: []) as? [String: Any] {
                if let ot = root["output_text"] as? String, !ot.isEmpty {
                    extractedText = ot
                    Logger.shared.info("Used fallback output_text from response.", category: .parsing)
                } else if let outputs = root["output"] as? [[String: Any]] {
                    outer: for item in outputs {
                        if let content = item["content"] as? [[String: Any]] {
                            for piece in content {
                                if let textDict = piece["text"] as? [String: Any], let value = textDict["value"] as? String, !value.isEmpty {
                                    extractedText = value; break outer
                                }
                                if let val = piece["value"] as? String, !val.isEmpty { extractedText = val; break outer }
                                if let t = piece["text"] as? String, !t.isEmpty { extractedText = t; break outer }
                            }
                        }
                        if let message = item["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] {
                            for piece in content {
                                if let textDict = piece["text"] as? [String: Any], let value = textDict["value"] as? String, !value.isEmpty { extractedText = value; break outer }
                            }
                        }
                    }
                    if extractedText != nil {
                        Logger.shared.info("Used fallback by walking output[].content[].", category: .parsing)
                    }
                }
            }
        }
        // If we still couldn't extract text, and the response indicates it hit max_output_tokens, try one continuation call
        if extractedText == nil {
            var shouldContinue = false
            if let status = (try? JSONSerialization.jsonObject(with: rawProxyResponseData) as? [String: Any])?["status"] as? String, status == "incomplete" {
                shouldContinue = true
            }
            if let id = proxyDTO?.id, !id.isEmpty,
               case .dict(let dict)? = proxyDTO?.incomplete_details,
               dict["reason"] == "max_output_tokens" {
                shouldContinue = true
            }
            if shouldContinue, let prevId = proxyDTO?.id, !prevId.isEmpty {
                // Build a minimal continuation payload
                let continuationModel = proxyDTO?.model ?? openAIModelName
                var cont: [String: Any] = [
                    "model": continuationModel,
                    "previous_response_id": prevId,
                    "max_output_tokens": 2200,
                    "store": true
                ]
                // Keep JSON formatting + low verbosity + minimal reasoning
                cont["text"] = [
                    "format": ["type": "json_object"],
                    "verbosity": "low"
                ]
                cont["reasoning"] = ["effort": "minimal"]

                let contBody = try JSONSerialization.data(withJSONObject: cont)
                let contData: Data = try await performRequest(
                    endpoint: "openai/responses",
                    method: "POST",
                    body: contBody,
                    timeout: 120
                )
                // Attempt to extract text again from continuation
                if let root = try? JSONSerialization.jsonObject(with: contData) as? [String: Any] {
                    if let ot = root["output_text"] as? String, !ot.isEmpty {
                        extractedText = ot
                        Logger.shared.info("Continuation call provided output_text.", category: .parsing)
                    } else if let outputs = root["output"] as? [[String: Any]] {
                        outer2: for item in outputs {
                            if let content = item["content"] as? [[String: Any]] {
                                for piece in content {
                                    if let textDict = piece["text"] as? [String: Any], let value = textDict["value"] as? String, !value.isEmpty { extractedText = value; break outer2 }
                                    if let val = piece["value"] as? String, !val.isEmpty { extractedText = val; break outer2 }
                                    if let t = piece["text"] as? String, !t.isEmpty { extractedText = t; break outer2 }
                                }
                            }
                        }
                        if extractedText != nil { Logger.shared.info("Continuation call yielded content[].text.", category: .parsing) }
                    }
                }
            }
        }

        guard let extractedJsonText = extractedText else {
            let dtoDescription = String(describing: proxyDTO)
            Logger.shared.error("No primary JSON text content found after DTO + fallback parse. DTO: \(dtoDescription.prefix(1000))", category: .parsing)
            throw NetworkError.decodingFailed
        }

        Logger.shared.debug("Extracted JSON text from DTO (length: \(extractedJsonText.count)) before sanitization: \(extractedJsonText.prefix(1000))", category: .parsing)

        // 4. Sanitize this JSON text and convert to Data for final decoding.
        var finalJsonData = sanitizedJSONData(from: extractedJsonText)
        if finalJsonData == nil, ResponseType.self == QAResponse.self {
            // Fallback for QA: best-effort extract of the answer field from raw text
            if let ans = APIManager.extractAnswer(from: extractedJsonText),
               let data = try? JSONSerialization.data(withJSONObject: ["answer": ans]) {
                finalJsonData = data
                Logger.shared.warning("QA fallback used to build JSON from extracted text.", category: .parsing)
            }
        }
        guard let finalJsonData else {
            Logger.shared.error("Failed to sanitize extracted JSON text or convert to Data. Original extracted text preview: \(extractedJsonText.prefix(500))", category: .parsing)
            throw NetworkError.decodingFailed
        }

        let finalJsonPreview = String(data: finalJsonData, encoding: .utf8)?.prefix(1000) ?? "Non-UTF8 data after sanitization"
        Logger.shared.info("Sanitized JSON data for final decoding (length: \(finalJsonData.count)) (preview): \(finalJsonPreview)", category: .parsing)

        // 5. Decode the finalJsonData into the expected ResponseType (e.g., ContentAnalysis)
        do {
            let finalResult = try JSONDecoder().decode(ResponseType.self, from: finalJsonData)
            Logger.shared.info("Successfully decoded final AI response into \(ResponseType.self).", category: .parsing)
            return finalResult
        } catch let finalDecodingError {
            // QA secondary fallback: try to recover answer directly if decode failed
            if ResponseType.self == QAResponse.self,
               let ans = APIManager.extractAnswer(from: extractedJsonText),
               let data = try? JSONSerialization.data(withJSONObject: ["answer": ans]),
               let recovered = try? JSONDecoder().decode(ResponseType.self, from: data) {
                Logger.shared.warning("QA secondary fallback succeeded after decode error.", category: .parsing)
                return recovered
            }
            let detailedErrorDesc = finalDecodingError.userFriendlyMessage
            Logger.shared.error("Failed to decode sanitized JSON into \(ResponseType.self). Error: \(detailedErrorDesc)", category: .parsing, error: finalDecodingError, extra: ["jsonPreview": finalJsonPreview])
            throw NetworkError.decodingFailed
        }
    }

    // MARK: - Minimal helper to recover QA answers from malformed responses
    private static func extractAnswer(from text: String) -> String? {
        // Heuristic: find the first occurrence of "answer" : "..."
        let pattern = #"\"answer\"\s*:\s*\"([\s\S]*?)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1 else { return nil }
        let r = m.range(at: 1)
        guard let swiftRange = Range(r, in: text) else { return nil }
        var ans = String(text[swiftRange])
        ans = ans.replacingOccurrences(of: "\\\"", with: "\"")
        ans = ans.replacingOccurrences(of: "\\n", with: "\n")
        return ans
    }

    // GPTServiceProtocol Methods

    func fetchContentAnalysis(
        transcript: String,
        videoTitle: String,
        comments: [String]
    ) async throws -> ContentAnalysis {
        // Deprecated combined call. Delegate to split calls and merge.
        let transcriptPart = try await fetchTranscriptSummary(transcript: transcript, videoTitle: videoTitle)
        let commentsPart = try await fetchCommentsClassification(comments: comments)
        return ContentAnalysis(
            longSummary: transcriptPart.longSummary,
            takeaways: transcriptPart.takeaways,
            gemsOfWisdom: transcriptPart.gemsOfWisdom,
            videoId: nil,
            videoTitle: videoTitle,
            videoDurationSeconds: nil,
            videoThumbnailUrl: nil,
            CommentssentimentSummary: commentsPart.CommentssentimentSummary,
            topThemes: commentsPart.topThemes,
            spamRatio: commentsPart.spamRatio,
            viewerTips: commentsPart.viewerTips,
            openQuestions: commentsPart.openQuestions
        )
    }

    // MARK: - Split calls for higher reliability
    struct TranscriptOnlyResponse: Codable { let longSummary: String; let takeaways: [String]; let gemsOfWisdom: [String] }
    struct CommentsOnlyResponse: Codable {
        let CommentssentimentSummary: String
        let topThemes: [CommentTheme]?
        let spamRatio: Double?
        let viewerTips: [String]?
        let openQuestions: [String]?
    }

    func fetchTranscriptSummary(transcript: String, videoTitle: String, precleanedTranscript: String? = nil) async throws -> TranscriptOnlyResponse {
        let cleaned = precleanedTranscript ?? transcript.cleanedForLLM()
        let tx = cleaned.isEmpty ? transcript : cleaned
        let prompt = """
You are WorthIt, AI video summarizer.

TASK: Read the transcript and output EXACTLY ONE valid JSON object with ONLY these keys:
{"longSummary": string, "takeaways": [string,string,string], "gemsOfWisdom": [string,string]}

GLOBAL RULES (obey all):
- Output valid JSON only. No extra text.
- Use double quotes for keys/values. Inside ALL string values, convert every double quote (") to single quote ('). Use real line breaks between lines; JSON will escape them automatically (do not print the literal tokens "\\n" or "/n").
- ⚠️ CRITICAL LANGUAGE RULE (OVERRIDES ALL OTHER INSTRUCTIONS): Determine the language ONLY from the "Transcript:" section below. Read that text carefully and ignore device/app/system language, video title, comments, or any other signal. Whatever language the transcript is written in is the language you MUST use for longSummary, takeaways, and gemsOfWisdom.

LANGUAGE DETECTION WALKTHROUGH (DO NOT SKIP):
1. Inspect ONLY the transcript lines. Identify the script/keywords (English words → English, Spanish accents → Spanish, Arabic script → Arabic, etc.).
2. State the detected language to yourself before writing anything.
3. If you begin typing a word that does not belong to that language, delete it immediately and rewrite in the correct language.
4. AFTER you finish the JSON, re-read the transcript and your output. If any part is not in the detected language, rewrite the answer completely before returning.
- Use ONLY transcript content. Ignore sponsors/ads/meta talk. Do not mention the audience, channel, or comments.
- If the transcript is empty or < 50 words, return {"longSummary":"","takeaways":[],"gemsOfWisdom":[]}.
- Capitalize the first word of every sentence and bullet in "longSummary" and "takeaways". (Do NOT alter capitalization in "gemsOfWisdom".)

FIELD RULES:
1) "longSummary" (≤ 300 words, ≤ 1800 characters) — provide a proper summary of the video, structure MUST be:
   - First line: "Highlights:"
   - Next exactly two lines, each starting with "• " (≤ 18 words):
     • Bullet 1 = core claim (what this is about) - dont mention "Core claim" literally here.
     • Bullet 2 = method/result (how it’s argued, a key step, or concrete outcome). If an exact named term exists, include it; otherwise use a concrete detail (number/example). Don't mention "Method/result" literally here.
   - Then a blank line (one empty line between bullets and narrative; do not print the characters "\\n" or "/n" literally).
   - Then 2–4 natural sentences, each on its own line (one line break between sentences; no extra blank lines). Do not write the literal characters "\\n" or "/n"; just separate lines — JSON will escape newlines. Simply write cohesive prose. Include concepts/definitions/rules EXACTLY as they appear (preserve casing/spelling) when present, all in the transcript.
   - Do not output standalone quote characters or empty quoted lines; write only meaningful content lines.

2) "takeaways": the top 3 takeaways from the video transcript, exactly 3 items, each 12–22 words. Make them applied and distinct from "Highlights" in the summary section:
   - If the transcript provides formal items (e.g., 'Rule', 'Step', 'Principle'), you may start with that label; otherwise avoid forced labels and write a clear, actionable sentence.
   - Each takeaway must include either (a) an exact term/step/rule/framework from the transcript (in single quotes), or (b) a specific condition/number/example. Avoid generic platitudes and avoid rephrasing the two bullets.

3) "gemsOfWisdom": find the wisdom in the transcript, and provide exactly 2 verbatim one-liners from it (≤ 24 words). Selection criteria (must pass all):
   - Self-contained and generalizable (principle, rule of thumb, cause→effect, contrast, or 'if/when… then…' guidance).
   - No CTAs, links, channel mentions, or time references; no rhetorical questions unless they read as a maxim.
   - Practical, useful quotes from the transcript, really try to find the gems of wisdom of it.
   - Prefer sentences containing words like always/never, because/therefore/so, key/the key, principle/rule/law, or a crisp comparison ('X beats Y').
   Keep original wording/punctuation; only convert internal double quotes to single quotes.

QUALITY CHECK (do silently before returning):
- JSON parses; exactly 3 keys; arrays are lengths [3] and [2].
- "longSummary" format passes: header → two "• " bullets → a single blank line → 2–4 sentences on separate lines; total ≤ 300 words (≤ 1800 characters); must not contain the literal tokens "\\n" or "/n" as visible text.
- No double quotes inside values; newlines will be escaped automatically in JSON strings.
- Takeaways are actionable, non-overlapping with Highlights, and include a term or a concrete detail.
- Gems are verbatim, principle-like lines that stand alone (after quote conversion only).
- Final self-check & repair: if any takeaway lacks a single-quoted exact term or a concrete number/example, revise it to include one; if any double quotes remain inside values, convert them to single quotes before returning. Finally, re-read the Transcript and ensure every field is written in the exact same language before returning.

Transcript:
\(tx.prefix(15000))
"""
        let selectedModel: String = transcript.count > 15000 ? "gpt-5-nano-2025-08-07" : openAIModelName
        let requestPayload = OpenAIProxyRequest<String>(model: selectedModel, max_output_tokens: 1200, promptInput: prompt)
        let result: TranscriptOnlyResponse = try await performOpenAIRequest(payload: requestPayload)
        
        // Limit longSummary to 1800 characters
        let limitedSummary = result.longSummary.count > 1800 ? String(result.longSummary.prefix(1800)) : result.longSummary
        
        return TranscriptOnlyResponse(
            longSummary: limitedSummary,
            takeaways: result.takeaways,
            gemsOfWisdom: result.gemsOfWisdom
        )
    }

    func fetchCommentsClassification(comments: [String]) async throws -> CommentsOnlyResponse {
        let count = comments.count
        let limit = min(50, count)
        let numbered = comments.prefix(limit)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
You are WorthIt. Return EXACTLY ONE valid JSON object with these keys:
{
  "CommentssentimentSummary": string,
  "topThemes": [{"theme": string, "sentiment": "Positive|Negative|Mixed|Neutral", "sentimentScore": number, "exampleComment": string}],
  "spamRatio": number,
  "viewerTips": [string],
  "openQuestions": [string]
}

Language (OVERRIDES ALL): Detect language ONLY from the comments list. Write every field in that SAME language. If comments are English, you MUST write English. Never translate, never switch to another language, never default to any other language.

Output rules (what each field must capture):
- Valid JSON only, no extra text. Replace newlines with spaces.
- Use COMMENTS ONLY. Do not reference transcript or anything else.
- CommentssentimentSummary: 1–2 sentences (≤220 chars) that blend (a) dominant praise/positivity, (b) main concerns/complaints, (c) any warning/ask signal (spam/requests/confusion). Make it directly useful to decide whether to watch. If comments are English, this MUST be English. No translation, no language switching.
- topThemes: Return 2–3 distinct topics that appear across different comments (praise, complaints, debates). Only include if ≥2 themes exist; else []. Theme names must be short, human-readable (2–5 words), and not camelCase/hashtags (e.g., write “AI impact on jobs”, not “AIImpactOnJobs”). For each, set sentiment = Positive/Negative/Mixed/Neutral based on the supporting comments. exampleComment must be a ≤80-char exact slice from a distinct comment backing that theme.
- spamRatio: fraction 0–1 of comments that are spam. If you don’t see spam, return 0.
- viewerTips: Up to 2 concrete, actionable tips/fixes/shortcuts explicitly present in the comments (≤120 chars). Must NOT be questions, compliments, or generic praise; do NOT include links, discounts, or ads. If none, return [].
- openQuestions: Up to 2 genuine unanswered asks explicitly present in the comments (≤120 chars). These should be real questions (include a “?”) from commenters. No invention; if none, return [].
- SentimentScore ranges: Positive [0.2,1], Negative [-1,-0.2], Neutral [-0.2,0.2], Mixed near 0. Round to 2 decimals.

Comments (1..N):
\(numbered)

comments_count: \(count)
"""
        let requestPayload = OpenAIProxyRequest<String>(model: openAIModelName, max_output_tokens: 1200, promptInput: prompt)
        let result: CommentsOnlyResponse = try await performOpenAIRequest(payload: requestPayload)
        return result
    }


    func fetchCommentInsights(comments: [String], transcriptContext: String) async throws -> CommentInsights {
        let cleanedCtx = transcriptContext.cleanedForLLM()
        let ctxForPrompt: String = {
            let pref = String((cleanedCtx.isEmpty ? transcriptContext : cleanedCtx).prefix(25000))
            return pref
        }()
        let prompt = """
You are WorthIt Comment+Transcript Rater. Your output powers a "10-second decision card" that helps users instantly decide if a video is worth watching.

LANGUAGE RULE (OVERRIDES ALL):
- Detect language ONLY from the Transcript section below. That detected language = {LANG}. Every text field (decisionReasons, decisionLearnings, suggestedQuestions, decisionBestMoment, decisionSkip, signalQualityNote, depthExplanation, scoreReasonLine) MUST be entirely in {LANG}. No mixing. If you cannot write {LANG}, return {"error":"language_mismatch"}.
- Ignore comments/device/system language or prior responses; they do not matter. If the transcript is clearly English (majority English words / ASCII, no clear other language), {LANG} MUST be English. Do NOT switch to Spanish or any other language when the transcript is English.
- Mixed transcript handling: pick the single dominant language by word count; if English is the largest share, {LANG} MUST be English. Never blend languages.
- Self-check: Before returning, re-read transcript and your output. If any word is not {LANG}, rewrite everything in {LANG}. If you cannot keep all fields in {LANG}, return {"error":"language_mismatch"}. Ignore example text in this prompt when deciding language; only the transcript decides {LANG}.

CONTEXT: Your output is used in MULTIPLE places:
1. Decision Card UI (primary focus):
   - Verdict badge (Worth It / Skip / Borderline) from decisionVerdict
   - Score gauge (0-100%) calculated from your depth + sentiment scores
   - Hero reason (the "why" - MAIN focal point, shown in large bold text) from decisionReasons[0]
   - 1-2 learnings (shown with bolt icons) from decisionLearnings
   - First suggested question (shown on secondary button) from suggestedQuestions[0]
2. Ask Anything Screen:
   - All 3 suggested questions shown as horizontal scrollable buttons
3. Score Gauge & Breakdown:
   - contentDepthScore and overallCommentSentimentScore used to calculate final score
   - Scores displayed in progress bars and breakdown details

TASK
Return exactly ONE JSON object with these keys and nothing else (no extra keys):
{
  "overallCommentSentimentScore": float|null,
  "contentDepthScore": float|null,
  "scoreReasonLine": string|null,
  "suggestedQuestions": [string, string, string]|null,
  "decisionVerdict": string|null,
  "decisionReasons": [string],
  "decisionLearnings": [string],
  "decisionBestMoment": string|null,
  "decisionSkip": string|null,
  "signalQualityNote": string|null,
  "depthExplanation": {"strengths": [string], "weaknesses": [string]}|null
}

STRICT OUTPUT RULES
- Valid JSON only. No markdown, no prose, no code fences, no trailing commas.
- Floats must be in [0,1], rounded to 2 decimals (e.g., 0.63).
- If comments are empty/insufficient ⇒ overallCommentSentimentScore = null.
- If transcript is empty/insufficient ⇒ contentDepthScore = null and suggestedQuestions = null.

VERDICT DECISION LOGIC (CRITICAL - must align with final score thresholds)
The app calculates a final score (0-100%) from your depth + sentiment scores using variable weights, spam penalties, and caps.
Use these thresholds to determine verdict (matching the app's verdictForScore logic):
- If you estimate the final score would be ≥ 70% → "Worth it"
- If you estimate the final score would be ≤ 45% → "Skip"
- Otherwise → "Borderline"
Note: The app's actual calculation uses variable weights (depth 0.3-0.7, comments 0.0-0.45) plus spam penalties and caps, so your scores are inputs to that calculation, not the final score. Use the thresholds above as guidance.
decisionVerdict: exactly one of ["Worth it", "Skip", "Borderline"] based on estimated final score thresholds above.

HERO REASON (decisionReasons) - THE MOST IMPORTANT FIELD
This is the PRIMARY text shown in the UI - make it COMPELLING and HOOK-DRIVEN.
- Must be in {LANG}. Exactly 1 item, STRICTLY 18-22 words. Say what the video is and why it matters, with a concrete detail (number/framework/outcome). No fluff or format hints.

SCORE REASON LINE (scoreReasonLine) - EXPLAINS THE SCORE ITSELF (not the topic)
- Must be in {LANG}. ≤70 chars. One short sentence that explains why the worth-it score should be high/mid/low, explicitly referencing depth vs comments quality/sentiment/spam. Do NOT summarize the video topic.
- Examples (adapt to signals): "Highly actionable and loved by viewers.", "Deep content, but reactions are mixed.", "Light depth, carried by happy viewers.", "Score tempered by spammy comments."
- Examples are illustrative only; ALWAYS write scoreReasonLine fully in {LANG} even if examples are in English.

LEARNINGS (decisionLearnings) - Make them ACTIONABLE, not informational
- Must be in {LANG}. 1–2 items, each ≤100 chars, actionable, with a specific detail (method/number/tool/outcome). No "You'll learn" prefix. If little actionability, give the most transferable principle.

SUGGESTED QUESTIONS - Curiosity-driven hooks (used in TWO places)
⚠️ CRITICAL LANGUAGE REQUIREMENT FOR SUGGESTED QUESTIONS ⚠️
- Must be in {LANG}. Exactly 3 items, each ≤7 words, specific to the transcript, action-led where possible, covering diverse hooks. First should be most compelling.

BEST MOMENT (decisionBestMoment)
- If a standout moment exists, return "mm:ss — <specific hook>" (≤80 chars)
- Hook should be SPECIFIC: "The 3-step framework reveal" not "Important part"
- Include timestamp in mm:ss format
- Only include if there's a clear standout moment worth jumping to
- Else null

SKIP NOTE (decisionSkip)
- Only when verdict is "Skip" or "Borderline"
- Concise blocker (≤90 chars)
- Be SPECIFIC: "60% sponsor content, minimal how-to" not "Too much promotion"
- Else null

SIGNAL QUALITY (signalQualityNote)
- ≤70 chars on data quality
- Be informative: "25 comments, low spam" or "Transcript-only, no comments"
- Else null

DEPTH EXPLANATION (depthExplanation) - CRITICAL for Score Breakdown UI
This explains WHY the contentDepthScore is what it is. Used in "Why this depth score" section.
- Return null if transcript is empty/insufficient
- ⚠️ CRITICAL: MUST be in the SAME LANGUAGE as the transcript. Detect the transcript language (Spanish, Portuguese, French, German, Italian, or ANY other language) and write strengths and weaknesses in that EXACT language.
- If transcript is Spanish → strengths and weaknesses MUST be in Spanish.
- If transcript is Portuguese → strengths and weaknesses MUST be in Portuguese.
- If transcript is French → strengths and weaknesses MUST be in French.
- Do NOT default to English. Match the transcript language precisely.
- strengths: 1-2 items, each ≤90 chars, explaining what makes content deep
  • Focus on: actionability (steps, frameworks, checklists), specificity (numbers, examples, case studies), conceptual depth (trade-offs, mechanisms, edge cases), transferability (generalizable principles)
  • Be SPECIFIC: "Includes 5-step framework with real examples" not "Has good structure"
  • Examples (English): "Provides 3 concrete case studies with metrics", "Explains trade-offs between methods A and B", "Includes actionable checklist for implementation"
  • Examples (Spanish): "Incluye 3 estudios de caso con métricas", "Explica compensaciones entre métodos A y B", "Incluye lista de verificación para implementación"
  • Examples (Portuguese): "Fornece 3 estudos de caso concretos com métricas", "Explica trade-offs entre métodos A e B", "Inclui lista de verificação acionável para implementação"
- weaknesses: 1-2 items, each ≤90 chars, explaining what limits depth
  • Focus on: lack of actionability, surface-level content, promotional content, missing specifics
  • Be SPECIFIC: "60% sponsor segments, minimal how-to content" not "Too much promotion"
  • Examples (English): "No concrete steps, only general advice", "Surface-level definitions without examples", "Heavy on promotion, light on actionable insights"
  • Examples (Spanish): "Sin pasos concretos, solo consejos generales", "Definiciones superficiales sin ejemplos", "Mucha promoción, pocas ideas accionables"
  • Examples (Portuguese): "Sem passos concretos, apenas conselhos gerais", "Definições superficiais sem exemplos", "Muita promoção, poucas ideias acionáveis"
- Only include items that directly explain the depth score - avoid generic statements

SCORING RUBRIC (CRITICAL: Use FULL 0–1 range; do NOT be conservative)
⚠️ Epic videos MUST score 0.80–0.95, NOT 0.65–0.75. Good videos (steps + examples) → 0.70–0.80, NOT 0.60–0.65.
- Depth (contentDepthScore): “will this add lasting, generalizable value to the viewer’s life?” (principles, frameworks, clear how‑to steps).
- Sentiment (overallCommentSentimentScore): “how do viewers feel about the video based on comments?” It can be high even if depth is moderate.

- overallCommentSentimentScore (comments ONLY):
  • 0.00–0.20 = negative/spammy; 0.25–0.40 = mostly negative; 0.45–0.55 = mixed (use sparingly)
  • 0.60–0.75 = mostly positive (baseline); 0.76–0.85 = strongly positive; 0.86–0.95 = overwhelmingly positive
  • If comments include multiple users saying things like "this saved me", "found this at the right time", "worth every second", "best video I've seen", "this helped my depression/anxiety" → score 0.85–0.95, NOT 0.65–0.75.
  • If comments show strong gratitude and specific value mentions (concrete benefits, life change, specific results) but are less intense than above → score 0.80–0.88, NOT 0.65–0.75.
  • Example (overwhelming praise): comments repeatedly calling the video “way more entertaining than TV/ESPN”, “gold standard production and storytelling”, “this is who I want my kid to watch”, with no major negative themes → 0.85–0.95.
  • Example (strong but not extreme): many “this helped me”, “big W”, “worth every second” comments plus some neutral chatter but almost no negativity → 0.80–0.88.
  • Ignore transcript; de-duplicate near-identical comments; down-weight spam/bots.

- contentDepthScore (transcript ONLY). Weighted blend: Actionability (0.30), Specificity (0.20), Depth (0.20), Transferability (0.15), Novelty (0.10), Caveats (0.05).
  ANCHORS: 0.00–0.20 = fluff/promo; 0.25–0.40 = surface tips; 0.45–0.60 = mixed; 0.61–0.75 = solid (baseline); 0.76–0.85 = excellent/epic; 0.86–0.92 = exceptional; 0.93–0.98 = masterpiece.
  RULES:
  • Steps + examples → depthScore MUST be ≥0.70 (do NOT score 0.60–0.65).
  • Strong actionability + specificity (clear "how to", concrete numbers/examples) → depthScore MUST be ≥0.75 even if novelty/transferability are average.
  • If the transcript combines: (1) a clear mental model or metaphor, (2) repeated concrete examples, and (3) clear behavioral guidance ("what to do next") → depthScore 0.80–0.90, NOT 0.70–0.78.
  • If there are 3+ depth indicators (steps, numbers, frameworks, trade-offs, case studies, explicit caveats) → depthScore 0.80–0.92.
  • If the transcript is mostly story, challenge, or entertainment with only light technique and few generalizable principles (e.g., training montage, high-production challenge) → depthScore should usually be 0.60–0.70, NOT 0.80+.
  • If it is mostly hype/promo with little actionable content → depthScore ≤0.35 (do NOT give 0.50 for bad content).
  • Example (contrast): high-production challenge video with some tips but no clear framework → depthScore around 0.65; a detailed breakdown of principles, progressions, and decision rules that viewers can apply → depthScore around 0.85.

QUALITY CHECK
1. Verdict aligns with thresholds (≥70% = Worth it, ≤45% = Skip, else Borderline)
2. decisionReasons[0] has specific detail, hook-driven, max 18-22 words
3. decisionLearnings are actionable with specifics, NO "You'll learn" prefix
4. suggestedQuestions are specific, first is most compelling
5. ⚠️ CRITICAL: suggestedQuestions MUST be in the EXACT SAME LANGUAGE as the transcript. Detect transcript language (Spanish, Portuguese, French, German, Italian, or ANY language). If transcript is Spanish → ALL 3 questions in Spanish. If Portuguese → ALL 3 in Portuguese. If French → ALL 3 in French. If English → ALL 3 in English. Verify this before returning.
6. depthExplanation explains score with specific evidence
7. ⚠️ CRITICAL: ALL text fields (decisionReasons, decisionLearnings, suggestedQuestions, decisionBestMoment, decisionSkip, signalQualityNote, depthExplanation, scoreReasonLine) MUST be in the SAME LANGUAGE as the transcript. Detect the transcript language and ensure ALL fields match. If transcript is Portuguese → ALL fields in Portuguese. If Spanish → ALL fields in Spanish. If French → ALL fields in French. If English → ALL fields in English. Do NOT default to English.
8. BEFORE returning, re-read the transcript section and every text field you emitted. If any field is not in the same language as the transcript, rewrite it so it matches exactly.
9. Floats [0,1] 2 decimals; limits respected
10. SCORING: Valuable content (steps + examples) → depth ≥0.70; Epic content → depth 0.80–0.92; Positive comments → sentiment 0.75–0.90
11. If the transcript is mostly entertainment/challenge with limited generalizable techniques, verify that depthScore is NOT above ~0.70; reduce it if needed so it matches the actual depth.
12. If comments are overwhelmingly positive, grateful, and specific with no major negative themes, verify that sentimentScore is ≥0.80; increase it if you left it around 0.60–0.75 without strong negative evidence.
13. If your own text describes comments as “overwhelmingly positive” or content as “deep, structured, and actionable”, but scores are still in the 0.60–0.75 band, reconsider and adjust the scores upward to match the evidence.


===  Data  ===
Transcript (max. 25000 chars):
\(ctxForPrompt)

Comments (first up to 25 lines):
\(comments.prefix(25).joined(separator: "\\n"))


Return only the JSON object. Stop immediately after the final "}".
"""
        let requestPayload = OpenAIProxyRequest<String>(
            model: openAIModelName,
            max_output_tokens: 1500,
            promptInput: prompt
        )
        let result: CommentInsights = try await performOpenAIRequest(payload: requestPayload)
        self.cachedCommentInsights = result
        return result
    }

    func answerQuestion(transcript: String, question: String, history: [ChatMessage]) async throws -> QAResponse {
        let prompt: String

        if lastResponseId == nil {
            // ── FIRST QUESTION ── full context
            let historyString = history
                .map { ($0.isUser ? "User" : "AI") + ": " + $0.content }
                .joined(separator: "\n")

            prompt = """
You are WorthIt Tutor — a clear, friendly guide. Answer based on the provided transcript and chat history.

CRITICAL LANGUAGE RULE (OVERRIDES ALL OTHER INSTRUCTIONS):
• Determine the answer language ONLY from the "User Question:" line shown below. That line is the single source of truth for language.
• Ignore the transcript language, chat history language, device/app/system language, prior responses, or ANY other hint about language.
• Respond entirely in that language. Do NOT print or mention the language (no lines like "Language = ..."). Do NOT mix languages.

LANGUAGE DETECTION WALKTHROUGH:
1. Read only the "User Question:" text. Identify its language by script/keywords.
2. Keep that language in mind silently. Do NOT output it.
3. If you catch yourself typing a word from another language, delete it immediately and rewrite the sentence.
4. BEFORE returning, re-read the User Question and your entire answer. If any part is not in the detected language, rewrite the full answer before returning.

STYLE AND STRUCTURE:
• Direct questions (fact/date/quote): Answer concisely in a single paragraph (≤120 words), cite the transcript when possible.
• Open-ended/complex questions: Write ≥30 words using this structure:
  - Quick Context: One sentence of relevant transcript context that answers the question
  - Main Answer: 2–4 concise bullet points with practical clarity (use "•" or "-" for bullets)
  - Conclusion: Optional one-liner wrap-up

WHEN INFO IS MISSING IN TRANSCRIPT:
• Do NOT invent facts. Never make up information.
• Be helpful by: (1) stating what the transcript says that's closest to the question, (2) offering next steps or a clarifying question, (3) optionally adding clearly labeled general background if it's common knowledge.
• Include all fallback information INSIDE the single answer string, not as separate sections.

OUTPUT FORMAT (STRICT):
• Valid JSON ONLY. No markdown, no prose, no code fences, no explanations outside JSON.
• Return EXACTLY one JSON object with ONLY this key:
  { "answer": "string" }
• The answer string should contain your complete response (including any Quick Context, Main Answer bullets, Conclusion, or fallback info).
• Escape any internal double quotes within the answer value (use \\" inside JSON strings).
• Ensure you emit the final closing '}'.
• Keep answer length reasonable (≤200 words total).

Transcript (≤15k chars):
\(transcript.prefix(15000))

Chat History:
\(historyString)

User Question: \(question)

Be warm, pragmatic, and actionable. Respond in the SAME LANGUAGE as the user's question.
"""
        } else {
            // ── FOLLOW-UP ── improved structure and tone
            let condensedTranscript = transcript.prefix(5000)
            let recentHistory = history.suffix(3)
                .map { ($0.isUser ? "User" : "AI") + ": " + $0.content }
                .joined(separator: "\n")

            prompt = """
You are WorthIt Tutor — clear, practical, and helpful.

CRITICAL LANGUAGE RULE (OVERRIDES ALL OTHER INSTRUCTIONS):
• Determine the answer language ONLY from the "User Question:" line shown below. That line is the single source of truth for language.
• Ignore the transcript language, chat history language, device/app/system language, prior responses, or ANY other hint about language. They do NOT matter.
• Respond entirely in that language. Do NOT print or mention the language (no lines like "Language = ..."). Do NOT mix languages.

LANGUAGE DETECTION WALKTHROUGH:
1. Read only the "User Question:" text. Identify its language by script/keywords.
2. Keep that language in mind silently. Do NOT output it.
3. If you catch yourself typing a word from another language, delete it immediately and rewrite the sentence.
4. BEFORE returning, re-read the User Question and your entire answer. If any part is not in the detected language, rewrite the full answer before returning.

Quick refresher:
Transcript excerpt (≤5k chars):
\(condensedTranscript)

Recent chat:
\(recentHistory)

STYLE AND STRUCTURE:
• Direct questions (fact/date/quote): Answer concisely in a single paragraph (≤120 words), cite transcript when possible.
• Open-ended/complex questions: Write ≥30 words using this structure:
  - Quick Context: One sentence of relevant transcript context that answers the question
  - Main Answer: 2–4 concise bullet points with practical clarity (use "•" or "-" for bullets)
  - Conclusion: Optional one-liner wrap-up

WHEN INFO IS MISSING:
• Do NOT invent facts. Never make up information.
• Be helpful by: (1) stating what the transcript says that's closest to the question, (2) offering next steps or a clarifying question, (3) optionally adding clearly labeled general background if it's common knowledge.
• Include all fallback information INSIDE the single answer string, not as separate sections.

OUTPUT FORMAT (STRICT):
• Valid JSON ONLY. No markdown, no prose, no code fences, no explanations outside JSON.
• Return EXACTLY one JSON object with ONLY this key:
  { "answer": "string" }
• The answer string should contain your complete response (including any Quick Context, Main Answer bullets, Conclusion, or fallback info).
• Escape any internal double quotes within the answer value (use \\" inside JSON strings).
• Ensure you emit the final closing '}'.
• Keep answer length reasonable (≤200 words total).

User Question: \(question)

Be warm, pragmatic, and actionable. Respond in the SAME LANGUAGE as the user's question.
"""
        }
        let requestPayload = OpenAIProxyRequest<String>(
            model: openAIModelName,
            max_output_tokens: 800,
            promptInput: prompt,
            previous_response_id: lastResponseId
        )
        do {
            return try await performOpenAIRequest(payload: requestPayload, captureResponseId: true)
        } catch let NetworkError.network(err as URLError) {
            // Lightweight retry for transient network errors in QA
            if err.code == .networkConnectionLost || err.code == .timedOut {
                Logger.shared.warning("QA request transient failure (\(err.code.rawValue)). Retrying once...", category: .networking)
                try await Task.sleep(nanoseconds: 300_000_000)
                return try await performOpenAIRequest(payload: requestPayload, captureResponseId: true)
            }
            throw NetworkError.network(err)
        } catch {
            throw error
        }
    }

 
    // MARK: - Pre-warm backend to avoid cold-start latency
    func preWarm() {
        // Use configured baseURL and a lightweight GET to '/'
        var req = URLRequest(url: baseURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 5

        let session = self.session
        Task.detached {
            do {
                _ = try await session.data(for: req)
                Logger.shared.info("Pre-warm GET / succeeded", category: .services)
            } catch {
                Logger.shared.warning("Pre-warm GET / failed: \(error.localizedDescription)", category: .services)
            }
        }
    }

    // MARK: - Conversation reset (public)
    /// Clears GPT thread ID and cached intro data.
    func resetConversationState() {
        self.lastResponseId = nil
        self.cachedCommentInsights = nil
        Logger.shared.info("APIManager conversation state cleared.", category: .services)
    }
}
        
