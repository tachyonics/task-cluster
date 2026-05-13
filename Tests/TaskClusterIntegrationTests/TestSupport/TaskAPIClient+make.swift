import Foundation
import OpenAPIAsyncHTTPClient
import TaskAPI

/// Builds an OpenAPI-generated `Client` pointing at a running TaskCluster
/// service. The integration tests use this in place of a raw HTTP client so
/// request/response payloads stay type-checked against `openapi.yaml` —
/// schema drift between the spec and the test surfaces at compile time.
func makeTaskAPIClient(baseURL: String) throws -> Client {
    guard let url = URL(string: baseURL) else {
        throw TaskAPIClientError.invalidBaseURL(baseURL)
    }
    return Client(
        serverURL: url,
        transport: AsyncHTTPClientTransport()
    )
}

enum TaskAPIClientError: Error {
    case invalidBaseURL(String)
}
