import Combine
import Foundation

extension IG.API.Request.Accounts {
    
    // MARK: GET /operations/application

    /// Returns a list of client-owned applications.
    /// - returns: *Future* forwarding all user's applications.
    public func getApplications() -> AnyPublisher<[IG.API.Application],IG.API.Error> {
        self.api.publisher
            .makeRequest(.get, "operations/application", version: 1, credentials: true)
            .send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default())
            .mapError(IG.API.Error.transform)
            .eraseToAnyPublisher()
    }

    // MARK: PUT /operations/application

    /// Alters the details of a given user application.
    /// - parameter key: The API key of the application that will be modified. If `nil`, the application being modified is the one that the API instance has credentials for.
    /// - parameter status: The status to apply to the receiving application.
    /// - parameter allowance: `overall`: Per account request per minute allowance. `trading`: Per account trading request per minute allowance.
    /// - returns: *Future* forwarding the newly set targeted application values.
    public func updateApplication(key: IG.API.Key? = nil, status: IG.API.Application.Status, accountAllowance allowance: (overall: UInt, trading: UInt)) -> AnyPublisher<IG.API.Application,IG.API.Error> {
        self.api.publisher { (api) throws -> _PayloadUpdate in
                let apiKey = try (key ?? api.channel.credentials?.key) ?> IG.API.Error.invalidRequest(.noCredentials, suggestion: .logIn)
                return .init(key: apiKey, status: status, overallAccountRequests: allowance.overall, tradingAccountRequests: allowance.trading)
            }.makeRequest(.put, "operations/application", version: 1, credentials: true, body: { (payload) in
                return (.json, try JSONEncoder().encode(payload))
            }).send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default())
            .mapError(IG.API.Error.transform)
            .eraseToAnyPublisher()
    }
}

// MARK: - Entities

private extension IG.API.Request.Accounts {
    /// Let the user updates one parameter of its application.
    struct _PayloadUpdate: Encodable {
        ///.API key to be added to the request.
        let key: IG.API.Key
        /// Desired application status.
        let status: IG.API.Application.Status
        /// Per account request per minute allowance.
        let overallAccountRequests: UInt
        /// Per account trading request per minute allowance.
        let tradingAccountRequests: UInt
        
        private enum CodingKeys: String, CodingKey {
            case key = "apiKey", status
            case overallAccountRequests = "allowanceAccountOverall"
            case tradingAccountRequests = "allowanceAccountTrading"
        }
    }
}

extension IG.API {
    /// Client application.
    public struct Application: Decodable {
        /// Application API key identifying the application and the developer.
        public let key: IG.API.Key
        /// Application name given by the developer.
        public let name: String
        ///  Application status.
        public let status: Self.Status
        /// What the platform allows the application or account to do (e.g. requests per minute).
        public let permission: Self.Permission
        /// The limits at which the receiving application is constrained to.
        public let allowance: Self.Allowance
        /// Application creation date (referencing UTC dates, although no time data is stored).
        public let creationDate: Date
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Self.CodingKeys.self)
            self.key = try container.decode(IG.API.Key.self, forKey: .key)
            self.name = try container.decode(String.self, forKey: .name)
            self.status = try container.decode(IG.API.Application.Status.self, forKey: .status)
            self.permission = try Self.Permission(from: decoder)
            self.allowance = try Self.Allowance(from: decoder)
            self.creationDate = try container.decode(Date.self, forKey: .creationDate, with: IG.API.Formatter.date)
        }
        
        internal enum CodingKeys: String, CodingKey {
            case name, key = "apiKey"
            case status, creationDate = "createdDate"
        }
    }
}

extension IG.API.Application {
    /// Application status in the platform.
    public enum Status: String, Codable {
        /// The application is enabled and thus ready to receive/send data.
        case enabled = "ENABLED"
        /// The application has been disabled by the developer.
        case disabled = "DISABLED"
        /// The application has been revoked by the admins.
        case revoked = "REVOKED"
    }
}

extension IG.API.Application {
    /// The platform allowance to the application's and account's allowances (e.g. requests per minute).
    public struct Permission: Decodable {
        /// Boolean indicating if access to equity prices is permitted.
        public let accessToEquityPrices: Bool
        /// Boolean indicating if quote orders are permitted.
        public let areQuoteOrdersAllowed: Bool
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: _CodingKeys.self)
            self.accessToEquityPrices = try container.decode(Bool.self, forKey: .equities)
            self.areQuoteOrdersAllowed = try container.decode(Bool.self, forKey: .quoteOrders)
        }
        
        enum _CodingKeys: String, CodingKey {
            case equities = "allowEquities"
            case quoteOrders = "allowQuoteOrders"
        }
    }
}

extension IG.API.Application {
    /// The limits constraining an API application.
    public struct Allowance: Decodable {
        /// Overal application request per minute allowance.
        public let overallRequests: Int
        /// Account related requests per minute allowance.
        public let account: Self.Account
        /// Concurrent subscriptioon limit per lightstreamer connection.
        public let subscriptionsLimit: Int
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: _CodingKeys.self)
            self.overallRequests = try container.decode(Int.self, forKey: .requests)
            self.subscriptionsLimit = try container.decode(Int.self, forKey: .subscriptions)
            self.account = try Account(from: decoder)
        }
        
        private enum _CodingKeys: String, CodingKey {
            case requests = "allowanceApplicationOverall"
            case subscriptions = "concurrentSubscriptionsLimit"
        }
    }
}

extension IG.API.Application.Allowance {
    /// Limit and allowances for the targeted account.
    public struct Account: Decodable {
        /// Per account request per minute allowance.
        public let overallRequests: Int
        /// Per account trading request per minute allowance.
        public let tradingRequests: Int
        /// Historical price data data points per minute allowance.
        public let historicalDataRequests: Int
        
        private enum CodingKeys: String, CodingKey {
            case overallRequests = "allowanceAccountOverall"
            case tradingRequests = "allowanceAccountTrading"
            case historicalDataRequests = "allowanceAccountHistoricalData"
        }
    }
}

// MARK: - Functionality

extension IG.API.Application: IG.DebugDescriptable {
    internal static var printableDomain: String { "\(IG.API.printableDomain).\(Self.self)" }
    
    public var debugDescription: String {
        var result = IG.DebugDescription(Self.printableDomain)
        result.append("key", self.key)
        result.append("name", self.name)
        result.append("status", self.status)
        result.append("permission", self.permission) {
            $0.append("access to equities", $1.accessToEquityPrices)
            $0.append("quote orders allowed", $1.areQuoteOrdersAllowed)
        }
        result.append("allowance", self.allowance) {
            $0.append("overall requests", $1.overallRequests)
            $0.append("account", $1.account) {
                $0.append("overall requests", $1.overallRequests)
                $0.append("trading requests", $1.tradingRequests)
                $0.append("price requests", $1.historicalDataRequests)
            }
            $0.append("concurrent subscription limit", $1.subscriptionsLimit)
        }
        result.append("creation", self.creationDate, formatter: IG.API.Formatter.date)
        return result.generate()
    }
}
