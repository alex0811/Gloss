import Foundation

struct TranslatorError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 唯一的翻译客户端：OpenAI 兼容协议（DeepSeek / OpenAI / Ollama / 各类中转通用），
/// 换服务商 = 换配置，不为任何一家写专属 client。
enum Translator {
    static func translate(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(text: text, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static let systemPrompt = """
    你是一名专业译者，在中文与英文之间互译：原文以英文为主译成简体中文，以中文为主译成英文。\
    只输出译文，不解释、不添加内容。保留原文的 Markdown 结构；代码块与行内代码原样保留不翻译；\
    专有名词与技术术语保持一致，必要时保留英文原词。译文忠实、简洁、通顺。
    """

    private static func stream(
        text: String,
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let base = AppConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = AppConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = AppConfig.apiKey
        guard !base.isEmpty, !model.isEmpty, !key.isEmpty else {
            throw TranslatorError(message: "未完成配置：请在设置里填入 Base URL、模型和 API Key")
        }
        let endpoint = base.hasSuffix("/") ? base + "chat/completions" : base + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw TranslatorError(message: "Base URL 无效：\(base)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslatorError(message: "服务未返回有效响应")
        }
        guard http.statusCode == 200 else {
            var raw = ""
            for try await line in bytes.lines {
                raw += line
                if raw.count > 2000 { break }
            }
            throw TranslatorError(message: "HTTP \(http.statusCode)：\(apiErrorMessage(from: raw) ?? raw)")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String,
                  !content.isEmpty
            else { continue }
            continuation.yield(content)
        }
    }

    private static func apiErrorMessage(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }
}
