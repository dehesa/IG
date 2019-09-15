import ReactiveSwift
import Foundation

extension IG.API.Request.Session {
    
    // MARK: POST /session
    
    /// Performs the OAuth login request to the dealing system with the login credential passed as parameter.
    /// - note: No credentials are needed for this endpoint.
    /// - parameter key: API key given by the IG platform identifying the usage of the IG endpoints.
    /// - parameter user: User name and password to log in into an IG account.
    /// - returns: `SignalProducer` with the new refreshed credentials.
    internal func loginOAuth(key: IG.API.Key, user: IG.API.User) -> SignalProducer<IG.API.Credentials,IG.API.Error> {
        return SignalProducer(api: self.api)
            .request(.post, "session", version: 3, credentials: false, headers: { (_,_) in [.apiKey: key.rawValue] }, body: { (_,_) in
                let payload = Self.PayloadOAuth(user: user)
                let data = try JSONEncoder().encode(payload)
                return (.json, data)
            }).send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (r: IG.API.Session.OAuth) in
                let token = IG.API.Credentials.Token(.oauth(access: r.tokens.accessToken, refresh: r.tokens.refreshToken, scope: r.tokens.scope, type: r.tokens.type), expirationDate: r.tokens.expirationDate)
                return IG.API.Credentials(client: r.clientId, account: r.accountId, key: key, token: token, streamerURL: r.streamerURL, timezone: r.timezone)
            }
    }

    // MARK: POST /session/refresh-token

    /// Refreshes a trading session token, obtaining new session for subsequent API.
    /// - note: No credentials are needed for this endpoint.
    /// - parameter token: The OAuth refresh token (don't confuse it with the OAuth access token).
    /// - parameter key: API key given by the IG platform identifying the usage of the IG endpoints.
    /// - returns: SignalProducer with the new refreshed credentials.
    internal func refreshOAuth(token: String, key: IG.API.Key) -> SignalProducer<IG.API.Credentials.Token,IG.API.Error> {
        return SignalProducer(api: self.api) { _ -> Self.TemporaryRefresh in
                guard !token.isEmpty else {
                    let error: IG.API.Error = .invalidRequest("The OAuth refresh token cannot be empty", suggestion: IG.API.Error.Suggestion.readDocs)
                    throw error
                }
            
                return .init(refreshToken: token, apiKey: key)
            }.request(.post, "session/refresh-token", version: 1, credentials: false, headers: { (_, values: TemporaryRefresh) in
                [.apiKey: values.apiKey.rawValue]
            }, body: { (_, values: TemporaryRefresh) in
                (.json, try JSONEncoder().encode(["refresh_token": values.refreshToken]))
            }).send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (r: IG.API.Session.OAuth.Token) in
                return .init(.oauth(access: r.accessToken, refresh: r.refreshToken, scope: r.scope, type: r.type), expirationDate: r.expirationDate)
            }
    }
}

// MARK: - Supporting Entities

// MARK: Request Entities

extension IG.API.Request.Session {
    private struct PayloadOAuth: Encodable {
        let user: IG.API.User
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Self.CodingKeys.self)
            try container.encode(self.user.name, forKey: .identifier)
            try container.encode(self.user.password, forKey: .password)
        }
        
        private enum CodingKeys: String, CodingKey {
            case identifier, password
        }
    }
    
    private struct TemporaryRefresh {
        let refreshToken: String
        let apiKey: IG.API.Key
    }
}

// MARK: Response Entities

extension IG.API.Session {
    /// Oauth credentials used to access the IG platform.
    fileprivate struct OAuth: Decodable {
        /// Client identifier.
        let clientId: IG.Client.Identifier
        /// Active account identifier.
        let accountId: IG.Account.Identifier
        /// Lightstreamer endpoint for subscribing to account and price updates.
        let streamerURL: URL
        /// Timezone of the active account.
        let timezone: TimeZone
        /// The OAuth token granting access to the platform
        let tokens: Self.Token
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Self.CodingKeys.self)
            self.clientId = try container.decode(IG.Client.Identifier.self, forKey: .clientId)
            self.accountId = try container.decode(IG.Account.Identifier.self, forKey: .accountId)
            self.streamerURL = try container.decode(URL.self, forKey: .streamerURL)
            
            /// - bug: The server returns one hour less for the timezone offset. I believe this is due not accounting for the summer time. Check in winter!
            let timezoneOffset = (try container.decode(Int.self, forKey: .timezoneOffset)) + 1
            self.timezone = try TimeZone(secondsFromGMT: timezoneOffset * 3_600) ?! DecodingError.dataCorruptedError(forKey: .timezoneOffset, in: container, debugDescription: "The timezone offset couldn't be migrated to UTC/GMT")
            
            self.tokens = try container.decode(IG.API.Session.OAuth.Token.self, forKey: .tokens)
        }
        
        private enum CodingKeys: String, CodingKey {
            case clientId
            case accountId
            case timezoneOffset
            case streamerURL = "lightstreamerEndpoint"
            case tokens = "oauthToken"
        }
    }
}

extension IG.API.Session.OAuth {
    /// OAuth token with metadata information such as expiration date or refresh token.
    fileprivate struct Token: Decodable {
        /// Acess token expiration date.
        let expirationDate: Date
        /// The token actually used on the requests.
        let accessToken: String
        /// Token used when the `accessToken` has expired, to ask for another one.
        let refreshToken: String
        /// Scope of the access token.
        let scope: String
        /// Token type.
        let type: String
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Self.CodingKeys.self)
            
            self.accessToken = try container.decode(String.self, forKey: .accessToken)
            self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
            self.scope = try container.decode(String.self, forKey: .scope)
            self.type = try container.decode(String.self, forKey: .type)
            
            let secondsString = try container.decode(String.self, forKey: .expireInSeconds)
            let seconds = try TimeInterval(secondsString)
                ?! DecodingError.dataCorruptedError(forKey: .expireInSeconds, in: container, debugDescription: "The \"\(CodingKeys.expireInSeconds)\" value (i.e. \(secondsString) could not be transformed into a number")
            
            if let response = decoder.userInfo[IG.API.JSON.DecoderKey.responseHeader] as? HTTPURLResponse,
               let dateString = response.allHeaderFields[IG.API.HTTP.Header.Key.date.rawValue] as? String,
               let date = IG.API.Formatter.humanReadableLong.date(from: dateString) {
                self.expirationDate = date.addingTimeInterval(seconds)
            } else {
                self.expirationDate = Date(timeIntervalSinceNow: seconds)
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case scope
            case type = "token_type"
            case expireInSeconds = "expires_in"
        }
    }
}
