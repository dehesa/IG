import Foundation

internal extension URLRequest {
    /// Convenience function to append the given URL queries to the receiving URL request.
    /// - parameter newQueries: URL queries to be appended at the end of the given URL.
    /// - throws: `IG.Error` of `.api(.invalidRequest)` type if the receiving request have no URL (or cannot be transformed into `URLComponents`) or the given queries cannot be appended to the receiving request URL.
    mutating func addQueries(_ newQueries: [URLQueryItem]) throws {
        guard !newQueries.isEmpty else {
            return
        }
        
        guard let previousURL = self.url else { throw IG.Error._emptyURL(request: self) }
        guard var components = URLComponents(url: previousURL, resolvingAgainstBaseURL: true) else { throw IG.Error._malformed(request: self) }
        
        if let previousQueries = components.queryItems {
            // If there are previous queries, replace previous query names by the new ones.
            var result: [URLQueryItem] = []
            for previousQuery in previousQueries where !newQueries.contains(where: { $0.name == previousQuery.name }) {
                result.append(previousQuery)
            }
            
            result.append(contentsOf: newQueries)
            components.queryItems = result
        } else {
            components.queryItems = newQueries
        }
        
        guard let url = components.url else {
            let representation = newQueries.map { "\($0.name): \($0.value ?? "")" }.joined(separator: ", ")
            throw IG.Error._invalid(request: self, queries: representation)
        }
        self.url = url
    }
    
    /// Convenience function to add header key/value pairs to a URL request header.
    /// - parameter version: The versioning number of the API endpoint being called.
    /// - parameter credentials: Credentials to access priviledge endpoints.
    /// - parameter headers: key/value pairs to be added as URL request headers.
    mutating func addHeaders(version: Int? = nil, credentials: API.Credentials? = nil, _ headers: [API.HTTP.Header.Key:String]? = nil) {
        if let version = version {
            self.addValue(String(version), forHTTPHeaderField: API.HTTP.Header.Key.version.rawValue)
        }
        
        if let credentials = credentials {
            for (k, v) in credentials.requestHeaders {
                self.addValue(v, forHTTPHeaderField: k.rawValue)
            }
        }
        
        if let headers = headers {
            for (key, value) in headers {
                self.addValue(value, forHTTPHeaderField: key.rawValue)
            }
        }
    }
}

private extension IG.Error {
    /// Error raised when an empty URL is received.
    static func _emptyURL(request: URLRequest) -> Self {
        Self(.api(.invalidRequest), "New queries couldn't be appended to a receiving request, since the request URL was found empty.", help: "Read the request documentation and be sure to follow all requirements.", info: ["Request": request])
    }
    /// Error raised when the request cannot be transformed in independent URL components.
    static func _malformed(request: URLRequest) -> Self {
        Self(.api(.invalidRequest), "New queries couldn't be appended to a receiving request, since the request URL cannot be transmuted into '\(URLComponents.self)'.", help: "Read the request documentation and be sure to follow all requirements.", info: ["Request": request])
    }
    /// Error raised when a new URL request cannot be formed by appending the given URL queries.
    static func _invalid(request: URLRequest, queries: String) -> Self {
        Self(.api(.invalidRequest), "A new URL from the previous request and the given queries couldn't be formed.", help: "Read the request documentation and be sure to follow all requirements.", info: ["Request": request, "Queries": queries])
    }
}
