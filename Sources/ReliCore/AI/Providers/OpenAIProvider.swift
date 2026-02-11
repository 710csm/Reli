import Foundation

/// An AI client that delegates generation of Markdown reports to the OpenAI API.
/// To enable this provider you must supply an API key either via the
/// `OPENAI_API_KEY` environment variable or by constructing the provider
/// directly with a key. The default model is GPT‑4. If you wish to use a
/// different model you may supply one at initialisation.
public struct OpenAIProvider: AIClient {
    private let apiKey: String
    private let model: String

    /// Creates a new provider. If the supplied API key is empty the provider
    /// will throw an error upon invocation.
    ///
    /// - Parameters:
    ///   - apiKey: your OpenAI API key
    ///   - model: the model identifier to use
    public init(apiKey: String = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "", model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    /// Sends the prompt to the OpenAI completions API and returns the
    /// resulting Markdown. The implementation uses `URLSession` for the
    /// network request. You may customise headers or endpoints here.
    public func generateMarkdown(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "OpenAIProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])
        }
        // Assemble the request payload.
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a helpful assistant."],
            ["role": "user", "content": prompt]
        ]
        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.2
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        // Create the request.
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        // Perform the request.
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "Bad response from OpenAI: \(body)"])
        }
        // Decode the response JSON.
        let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard
            let choices = root?["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw NSError(domain: "OpenAIProvider", code: -3, userInfo: [NSLocalizedDescriptionKey: "Malformed response from OpenAI"])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
