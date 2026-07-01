import Foundation

@Observable
class AIService {
    enum AIProvider: String, CaseIterable, Identifiable {
        case gemini = "Google Gemini (Cloud)"
        case gemma = "Google Gemma (Local MLX)"
        var id: String { self.rawValue }
    }
    
    var selectedProvider: AIProvider = .gemini
    var isProcessing = false
    
    struct FastSummaryResult {
        let title: String
        let overview: String
        let keyDecisions: String
        let openQuestions: String
        let attendees: [String]
        let actionItems: [(speaker: String, task: String)]
    }

    private let systemPrompt = """
You are an expert Executive Meeting Assistant responsible for converting meeting transcripts into accurate, structured meeting notes.

Your primary goal is to produce notes that are factually correct, concise, complete, and immediately useful for participants.

## General Rules
- Base your output ONLY on information explicitly present in the transcript.
- Never invent attendees, decisions, action items, dates, owners, or conclusions.
- If information cannot be determined from the transcript, return null or an empty array instead of guessing.
- Ignore filler words, repeated phrases, greetings, interruptions, false starts, and casual conversation unless they affect the meaning of the discussion.
- Preserve all technical terminology, APIs, product names, code names, company names, metrics, and abbreviations exactly as spoken.
- Translate any Hindi or Hinglish into natural, professional English while preserving the original meaning.
- Always produce the output in English.
- Do not include markdown, explanations, or commentary outside the JSON response.
- Return ONLY valid JSON matching the required schema.
"""

    func generateSummary(
        transcript: String,
        using template: SummaryTemplate? = nil,
        onFastResult: @escaping (FastSummaryResult) -> Void,
        onOutlineStream: @escaping (String) -> Void,
        onInsightsComplete: @escaping (String) -> Void,
        onComplete: @escaping (Bool) -> Void,
        onError: @escaping (String) -> Void
    ) {
        isProcessing = true
        AppLogger.summary("Started summary generation. Transcript length: \(transcript.count) chars")
        
        if selectedProvider == .gemma {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onFastResult(FastSummaryResult(title: "Local Title", overview: "Local Overview", keyDecisions: "- Decided Local", openQuestions: "- Any questions?", attendees: ["Local User"], actionItems: [("Local User", "Do Local Task")]))
                onOutlineStream("### Local Outline\n- Point 1")
                onInsightsComplete("- Local Insight")
                self.isProcessing = false
                onComplete(true)
            }
            return
        }
        
        guard let apiKey = KeychainHelper.standard.readApiKey(), !apiKey.isEmpty else {
            isProcessing = false
            AppLogger.error("API Key not found in Keychain.")
            onError("API Key not found in Keychain.")
            return
        }
        
        var templateInstructions = ""
        if let template = template, !template.formatDescription.isEmpty {
            templateInstructions = "\nTemplate instructions:\n\(template.formatDescription)\n"
        }
        
        let fullPrompt = systemPrompt + templateInstructions + "\n\nTranscript:\n" + transcript
        
        let fastSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "overview": ["type": "string"],
                "keyDecisions": ["type": "array", "items": ["type": "string"]],
                "openQuestions": ["type": "array", "items": ["type": "string"]],
                "attendees": ["type": "array", "items": ["type": "string"]],
                "actionItems": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "task": ["type": "string"],
                            "owner": ["type": "string", "nullable": true]
                        ]
                    ]
                ]
            ],
            "required": ["title", "overview", "keyDecisions", "openQuestions", "attendees", "actionItems"]
        ]
        
        let slowSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "insights": ["type": "array", "items": ["type": "string"]],
                "outline": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "section": ["type": "string"],
                            "points": ["type": "array", "items": ["type": "string"]]
                        ]
                    ]
                ]
            ],
            "required": ["insights", "outline"]
        ]
        
        Task {
            async let fastCall: Bool = performFastCall(prompt: fullPrompt, schema: fastSchema, apiKey: apiKey, onFastResult: onFastResult, onError: { msg in
                AppLogger.error("Summary generation failed: \(msg)")
                DispatchQueue.main.async { onError(msg) }
            })
            async let slowCall: Bool = performSlowCall(prompt: fullPrompt, apiKey: apiKey, onOutlineStream: onOutlineStream, onInsightsComplete: onInsightsComplete, onError: { msg in
                AppLogger.error("Summary generation failed: \(msg)")
                DispatchQueue.main.async { onError(msg) }
            })
            
            let (fastSuccess, slowSuccess) = await (fastCall, slowCall)
            let success = fastSuccess && slowSuccess
            
            DispatchQueue.main.async {
                self.isProcessing = false
                if success {
                    AppLogger.summary("Successfully generated summary.")
                }
                onComplete(success)
            }
        }
    }
    
    private func performFastCall(prompt: String, schema: [String: Any], apiKey: String, onFastResult: @escaping (FastSummaryResult) -> Void, onError: @escaping (String) -> Void) async -> Bool {
        AppLogger.summary("Started fast summary generation (JSON format)")
        let instruction = "Generate the Title, Overview, Key Decisions, Open Questions, Attendees, and Action Items. Format strictly as JSON."
        do {
            let result = try await makeGeminiRequest(parts: [["text": instruction], ["text": prompt]], apiKey: apiKey, responseSchema: schema)
            return parseFastResult(result, onFastResult: onFastResult, onError: onError)
        } catch {
            onError("[FAST] Call failed: \(error.localizedDescription)")
            return false
        }
    }
    
    private func parseFastResult(_ jsonString: String, onFastResult: @escaping (FastSummaryResult) -> Void, onError: @escaping (String) -> Void) -> Bool {
        let clean = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = clean.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            DispatchQueue.main.async { onError("[FAST] Failed to parse result") }
            return false
        }
        
        let title = json["title"] as? String ?? "New Meeting"
        let overview = json["overview"] as? String ?? ""
        let kdArr = json["keyDecisions"] as? [String] ?? []
        let keyDecisions = kdArr.map { "- \($0)" }.joined(separator: "\n")
        let oqArr = json["openQuestions"] as? [String] ?? []
        let openQuestions = oqArr.map { "- \($0)" }.joined(separator: "\n")
        let attendees = json["attendees"] as? [String] ?? []
        
        var actionItems: [(String, String)] = []
        if let aiArr = json["actionItems"] as? [[String: Any]] {
            for item in aiArr {
                let task = item["task"] as? String ?? ""
                let owner = item["owner"] as? String ?? "Unknown"
                if !task.isEmpty { actionItems.append((owner, task)) }
            }
        }
        
        DispatchQueue.main.async {
            onFastResult(FastSummaryResult(title: title, overview: overview, keyDecisions: keyDecisions, openQuestions: openQuestions, attendees: attendees, actionItems: actionItems))
        }
        return true
    }
    
    private func performSlowCall(prompt: String, apiKey: String, onOutlineStream: @escaping (String) -> Void, onInsightsComplete: @escaping (String) -> Void, onError: @escaping (String) -> Void) async -> Bool {
        AppLogger.summary("Started slow summary generation (SSE stream)")
        let instruction = "Generate the Insights and Detailed Outline. Format your response exactly as follows:\n\n===INSIGHTS===\n- Insight 1\n- Insight 2\n\n===OUTLINE===\n### Section Name\n- Point 1\n\n[SUMMARY_END]"
        let model = UserDefaults.standard.string(forKey: "geminiModel") ?? "gemini-3.5-flash"
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            DispatchQueue.main.async { onError("Invalid streaming URL") }
            return false
        }
        
        var requestBody: [String: Any] = [
            "contents": [["parts": [["text": instruction], ["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 8192
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 minutes explicitly on the request
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                var errorBody = ""
                do {
                    for try await line in bytes.lines { errorBody += line }
                } catch {}
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async { onError("[SLOW] API Error \(code): \(errorBody)") }
                return false
            }
            
            var fullText = ""
            
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let dataString = line.dropFirst(6)
                if dataString == "[DONE]" { break }
                if let data = dataString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    
                    fullText += text
                    
                    let components = fullText.components(separatedBy: "===OUTLINE===")
                    let insightsPart = components[0].replacingOccurrences(of: "===INSIGHTS===", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if components.count > 1 {
                        var outlinePart = components[1]
                        let isEnd = outlinePart.contains("[SUMMARY_END]")
                        outlinePart = outlinePart.replacingOccurrences(of: "[SUMMARY_END]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        DispatchQueue.main.async {
                            onInsightsComplete(insightsPart)
                            onOutlineStream(outlinePart)
                        }
                        if isEnd {
                            break
                        }
                    } else {
                        DispatchQueue.main.async {
                            onInsightsComplete(insightsPart)
                        }
                    }
                }
            }
            return true
            
        } catch {
            DispatchQueue.main.async { onError("[SLOW] Network error during streaming: \(error)") }
            return false
        }
    }
    
    func chat(query: String, context: String, completion: @escaping (String) -> Void) {
        if selectedProvider == .gemma {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                completion("Gemma Local says: Based on the context, here is the answer to your query: '\(query)'")
            }
            return
        }
        
        guard let apiKey = KeychainHelper.standard.readApiKey() else {
            completion("API Key not found. Please add it in Settings.")
            return
        }
        let prompt = "Context from meeting: \(context)\n\nUser Question: \(query)\n\nAnswer concisely based only on the context."
        
        Task {
            do {
                let result = try await makeGeminiRequest(parts: [["text": prompt]], apiKey: apiKey)
                DispatchQueue.main.async { completion(result) }
            } catch {
                DispatchQueue.main.async { completion("Failed to get a response: \(error.localizedDescription)") }
            }
        }
    }
    
    func testApiKey(_ key: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let _ = try await makeGeminiRequest(parts: [["text": "Say Hello"]], apiKey: key)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    enum APIError: LocalizedError {
        case invalidURL
        case requestFailed(String)
        case decodeFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .requestFailed(let msg): return msg
            case .decodeFailed: return "Failed to decode response"
            }
        }
    }

    private func makeGeminiRequest(parts: [[String: Any]], apiKey: String, responseSchema: [String: Any]? = nil) async throws -> String {
        let model = UserDefaults.standard.string(forKey: "geminiModel") ?? "gemini-3.5-flash"
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else { throw APIError.invalidURL }
        
        var genConfig: [String: Any] = ["temperature": 0.2, "maxOutputTokens": 8192]
        if let schema = responseSchema {
            genConfig["responseMimeType"] = "application/json"
            genConfig["responseSchema"] = schema
        }
        
        let requestBody: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": genConfig
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // 2 minutes explicitly on the request
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                AppLogger.error("makeGeminiRequest API Error \(code): \(errorBody)")
                
                // Parse the specific error message from the JSON if possible
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDict = errorJson["error"] as? [String: Any],
                   let message = errorDict["message"] as? String {
                    throw APIError.requestFailed("API Error \(code): \(message)")
                }
                throw APIError.requestFailed("API Error \(code): \(errorBody)")
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let text = candidates.first?["content"] as? [String: Any],
               let parts = text["parts"] as? [[String: Any]],
               let string = parts.first?["text"] as? String {
                return string
            } else {
                let parseErrorMsg = "Parse Error: \(String(data: data, encoding: .utf8) ?? "")"
                AppLogger.error("makeGeminiRequest \(parseErrorMsg)")
                throw APIError.requestFailed(parseErrorMsg)
            }
        } catch let error as APIError {
            throw error
        } catch {
            AppLogger.error("makeGeminiRequest Network Error: \(error.localizedDescription)")
            throw error
        }
    }
}
