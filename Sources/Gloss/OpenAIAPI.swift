import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// OpenAI 兼容协议的公共部分：端点拼接、鉴权、错误解析。
/// chat/completions 与 models 共用这一份 —— 换服务商 = 换配置，不为任何一家写专属 client。
enum OpenAIAPI {
    /// baseURL 与路径的唯一拼接处，斜杠处理只此一份。
    /// 只校验 base 与 key：模型是不是空，由各自的调用方决定（拉模型列表时它本来就该是空的）。
    static func request(_ path: String, body: [String: Any]? = nil) throws -> URLRequest {
        let base = AppConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = AppConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            throw APIError(message: "未完成配置：请在设置里填入 Base URL")
        }
        guard !key.isEmpty else {
            throw APIError(message: "未完成配置：请在设置里填入 API Key 并点「保存」")
        }
        let endpoint = base.hasSuffix("/") ? base + path : base + "/" + path
        guard let url = URL(string: endpoint) else {
            throw APIError(message: "Base URL 无效：\(base)")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// provider 的错误体统一是 {"error": {"message": …}}；解析不出就把原文交出去，不吞。
    /// 但要截断：base URL 填错时返回的可能是整页 HTML，不能让它把浮层和设置窗撑爆。
    static func failure(status: Int, body raw: String) -> APIError {
        let detail = (errorMessage(from: raw) ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = detail.count > 300 ? String(detail.prefix(300)) + "…" : detail
        return APIError(message: "HTTP \(status)：\(shown)")
    }

    private static func errorMessage(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }
}
