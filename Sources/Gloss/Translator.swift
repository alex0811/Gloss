import Foundation

/// 唯一的翻译客户端：OpenAI 兼容协议（DeepSeek / OpenAI / Ollama / 各类中转通用），
/// 换服务商 = 换配置，不为任何一家写专属 client。
enum Translator {
    static func translate(
        _ text: String,
        prompt: String = systemPrompt
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(text: text, prompt: prompt, into: continuation)
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
        prompt: String,
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let model = AppConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw APIError(message: "未完成配置：请在设置里选一个模型")
        }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text],
            ],
        ]

        let request = try OpenAIAPI.request("chat/completions", body: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "服务未返回有效响应")
        }
        guard http.statusCode == 200 else {
            var raw = ""
            for try await line in bytes.lines {
                raw += line
                if raw.count > 2000 { break }
            }
            throw OpenAIAPI.failure(status: http.statusCode, body: raw)
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
}
