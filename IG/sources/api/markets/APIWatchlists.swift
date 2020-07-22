import Combine
import Foundation

extension API.Request {
    /// List of endpoints related to API watchlists.
    public struct Watchlists {
        /// Pointer to the actual API instance in charge of calling the endpoint.
        fileprivate unowned let _api: API
        /// Hidden initializer passing the instance needed to perform the endpoint.
        /// - parameter api: The instance calling the actual endpoint.
        @usableFromInline internal init(api: API) { self._api = api }
    }
}

extension API.Request.Watchlists {
    
    // MARK: POST /watchlists
    
    /// Creates a watchlist.
    /// - parameter name: Watchlist given name.
    /// - parameter epics: List of market epics to be associated to this new watchlist.
    /// - returns: *Future* forwarding the identifier of the created watchlist and a Boolean indicating whether the all epics where added to the watchlist).
    public func create(name: String, epics: [IG.Market.Epic]) -> AnyPublisher<(identifier: String, areAllInstrumentsAdded: Bool),IG.Error> {
        self._api.publisher { _ -> _PayloadCreation in
                guard !name.isEmpty else {
                    throw IG.Error(.api(.invalidRequest), "The watchlist name cannot be empty", help: "The watchlist name must contain at least one character")
                }
                return .init(name: name, epics: epics.uniqueElements)
            }.makeRequest(.post, "watchlists", version: 1, credentials: true, body: {
                (.json, try JSONEncoder().encode($0))
            }).send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default()) { (w: _WrapperCreation, _) in (w.identifier, w.areAllInstrumentsAdded) }
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }

    
    // MARK: GET /watchlists
    
    /// Returns all watchlists belonging to the active account.
    /// - returns: *Future* forwarding an array of watchlists.
    public func getAll() -> AnyPublisher<[API.Watchlist],IG.Error> {
        self._api.publisher
            .makeRequest(.get, "watchlists", version: 1, credentials: true)
            .send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default()) { (w: _WrapperList, _) in w.watchlists }
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
    
    // MARK: GET /watchlists/{watchlistId}
    
    /// Returns the targeted watchlist.
    /// - parameter identifier: The identifier for the watchlist being targeted.
    /// - returns: *Future* forwarding all markets under the targeted watchlist.
    public func getMarkets(from identifier: String) -> AnyPublisher<[API.Node.Market],IG.Error> {
        self._api.publisher { _ -> Void in
                guard !identifier.isEmpty else {
                    throw IG.Error(.api(.invalidRequest), "The watchlist identifier cannot be empty.", help: "Empty strings are not valid identifiers. Query the watchlist endpoint again and retrieve a proper watchlist identifier.")
                }
            }.makeRequest(.get, "watchlists/\(identifier)", version: 1, credentials: true)
            .send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default(date: true)) { (w: _WrapperWatchlist, _) in w.markets }
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
    
    // MARK: PUT /watchlists/{watchlistId}
    
    /// Adds a market to a watchlist.
    /// - parameter identifier: The identifier for the watchlist being targeted.
    /// - parameter epic: The market epic to be added to the watchlist.
    /// - returns: *Future* indicating the success of the operation.
    public func update(identifier: String, addingEpic epic: IG.Market.Epic) -> AnyPublisher<Never,IG.Error> {
        self._api.publisher { _ in
                guard !identifier.isEmpty else {
                    throw IG.Error(.api(.invalidRequest), "The watchlist identifier cannot be empty.", help: "Empty strings are not valid identifiers. Query the watchlist endpoint again and retrieve a proper watchlist identifier.")
                }
            }.makeRequest(.put, "watchlists/\(identifier)", version: 1, credentials: true, body: {
                (.json, try JSONEncoder().encode(["epic": epic]))
            }).send(expecting: .json, statusCode: 200)
            //.decodeJSON(decoder: .default()) { (_: Self.WrapperUpdate, _) in return }
            .ignoreOutput()
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }

    
    // MARK: DELETE /watchlists/{watchlistId}/{epic}
    
    /// Removes a market from a watchlist.
    /// - parameter identifier: The identifier for the watchlist being targeted.
    /// - parameter epic: The market epic to be removed from the watchlist.
    /// - returns: *Future* indicating the success of the operation.
    public func update(identifier: String, removingEpic epic: IG.Market.Epic) -> AnyPublisher<Never,IG.Error> {
        self._api.publisher { _ in
                guard !identifier.isEmpty else {
                    throw IG.Error(.api(.invalidRequest), "The watchlist identifier cannot be empty.", help: "Empty strings are not valid identifiers. Query the watchlist endpoint again and retrieve a proper watchlist identifier.")
                }
            }.makeRequest(.delete, "watchlists/\(identifier)/\(epic.rawValue)", version: 1, credentials: true)
            .send(expecting: .json, statusCode: 200)
            //.decodeJSON(decoder: .default()) { (_: Self.WrapperUpdate, _) in return }
            .ignoreOutput()
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
    
    // MARK: DELETE /watchlists/{watchlistId}
    
    /// Deletes the targeted watchlist.
    /// - parameter identifier: The identifier for the watchlist being targeted.
    /// - returns: *Future* indicating the success of the operation.
    public func delete(identifier: String) -> AnyPublisher<Never,IG.Error> {
        self._api.publisher { _ in
                guard !identifier.isEmpty else {
                    throw IG.Error(.api(.invalidRequest), "The watchlist identifier cannot be empty.", help: "Empty strings are not valid identifiers. Query the watchlist endpoint again and retrieve a proper watchlist identifier.")
                }
            }.makeRequest(.delete, "watchlists/\(identifier)", version: 1, credentials: true)
            .send(expecting: .json, statusCode: 200)
            //.decodeJSON(decoder: .default()) { (w: Self.WrapperUpdate, _) in return }
            .ignoreOutput()
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
}

// MARK: - Request Entities

private extension API.Request.Watchlists {
    struct _PayloadCreation: Encodable {
        let name: String
        let epics: [IG.Market.Epic]
    }
}

// MARK: Response Entities

private extension API.Request.Watchlists {
    struct _WrapperCreation: Decodable {
        let identifier: String
        let areAllInstrumentsAdded: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Self.CodingKeys.self)
            self.identifier = try container.decode(String.self, forKey: .identifier)
            let status = try container.decode(CodingKeys.Status.self, forKey: .status)
            self.areAllInstrumentsAdded = (status == .success)
        }

        private enum CodingKeys: String, CodingKey {
            case identifier = "watchlistId"
            case status = "status"
            
            enum Status: String, Decodable {
                case success = "SUCCESS"
                case notAllInstrumentAdded = "SUCCESS_NOT_ALL_INSTRUMENTS_ADDED"
            }
        }
    }
    
    struct _WrapperWatchlist: Decodable {
        let markets: [API.Node.Market]
    }
    
    struct _WrapperList: Decodable {
        let watchlists: [API.Watchlist]
    }
    
    struct _WrapperUpdate: Decodable {
        let status: Self.Status
        
        enum Status: String, Decodable {
            case success = "SUCCESS"
        }
    }
}