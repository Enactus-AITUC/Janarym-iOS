import Foundation

enum OpenAIClient {

    enum HTTPMethod: String {
        case post = "POST"
    }

    static func request(
        path: String,
        method: HTTPMethod = .post,
        body: Data? = nil,
        contentType: String = "application/json"
    ) -> URLRequest {
        let url = URL(string: "\(AppConfig.openAIBaseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(AppConfig.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30
        return request
    }
}
