import Foundation

/// GET /models：给设置页的下拉列表做候选。
/// 只是「候选」——服务商不支持这个接口时如实报错，模型照样可以手填。
enum ModelCatalog {
    static func fetch() async throws -> [String] {
        let request = try OpenAIAPI.request("models")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "服务未返回有效响应")
        }
        guard http.statusCode == 200 else {
            throw OpenAIAPI.failure(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["data"] as? [[String: Any]]
        else {
            throw APIError(message: "读不懂返回内容：该服务可能不支持 /models，模型请手填")
        }
        // 去重：下拉用 id 做 identity，服务商重复返回同名模型时不能让它塌掉
        let ids = Set(list.compactMap { $0["id"] as? String }.filter { !$0.isEmpty })
        guard !ids.isEmpty else {
            throw APIError(message: "该服务没有返回任何模型，模型请手填")
        }
        return ids.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
