import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Keeps the auth clients' JSON header stable when the generator adds UTF-8 metadata.
struct JSONContentTypeMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if request.headerFields[.contentType] == "application/json; charset=utf-8" {
            request.headerFields[.contentType] = "application/json"
        }
        return try await next(request, body, baseURL)
    }
}
