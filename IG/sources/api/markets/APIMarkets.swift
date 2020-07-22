import Combine
import Foundation
import Decimals

extension API.Request {
    /// List of endpoints related to API markets.
    public struct Markets {
        /// Pointer to the actual API instance in charge of calling the endpoint.
        @usableFromInline internal unowned let api: API
        /// Hidden initializer passing the instance needed to perform the endpoint.
        /// - parameter api: The instance calling the actual endpoint.
        @usableFromInline internal init(api: API) { self.api = api }
    }
}

extension API.Request.Markets {
    
    // MARK: GET /markets/{epic}
    
    /// Returns the details of a given market.
    /// - parameter epic: The market epic to target onto. It cannot be empty.
    /// - returns: Information about the targeted market.
    public func get(epic: IG.Market.Epic) -> AnyPublisher<API.Market,IG.Error> {
        self.api.publisher { (api) -> DateFormatter in
                guard let timezone = api.channel.credentials?.timezone else {
                    throw IG.Error(.api(.invalidRequest), "No credentials were found on the API instance.", help: "Log in before calling this request.")
                }
                return DateFormatter.iso8601NoSeconds.deepCopy(timeZone: timezone)
            }.makeRequest(.get, "markets/\(epic.rawValue)", version: 3, credentials: true)
            .send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default(values: true, date: true))
            .mapError(errorCast)
            .eraseToAnyPublisher()
        
    }
    
    // MARK: GET /markets
    
    /// Returns the details of the given markets.
    /// - attention: The array argument `epics` can't be bigger than 50.
    /// - parameter epics: The market epics to target onto.
    /// - returns: Extended information of all the requested markets.
    public func get(epics: Set<IG.Market.Epic>) -> AnyPublisher<[API.Market],IG.Error> {
        Self._get(api: self.api, epics: epics)
    }
    
    /// Returns the details of the given markets.
    ///
    /// This endpoint circumvents `get(epics:)` limitation of quering for 50 markets and publish the results as several values.
    /// - parameter epics: The market epics to target onto. It cannot be empty.
    /// - returns: Extended information of all the requested markets.
    public func getContinuously(epics: Set<IG.Market.Epic>) -> AnyPublisher<[API.Market],IG.Error> {
        let maxEpicsPerChunk = 50
        guard epics.count > maxEpicsPerChunk else { return Self._get(api: api, epics: epics) }
        
        return self.api.publisher({ _ in epics.chunked(into: maxEpicsPerChunk) })
            .flatMap { (api, chunks) -> PassthroughSubject<[API.Market],IG.Error> in
                let subject = PassthroughSubject<[API.Market],IG.Error>()
                
                /// Closure retrieving the chunk at the given index through the given API instance.
                var fetchChunk: ((_ api: API, _ index: Int)->AnyCancellable?)! = nil
                /// `Cancellable` to stop fetching chunks.
                var cancellable: AnyCancellable? = nil
                
                fetchChunk = { (chunkAPI: API, chunkIndex) in
                    Self._get(api: chunkAPI, epics: chunks[chunkIndex])
                        .sink(receiveCompletion: { [weak weakAPI = chunkAPI] in
                            if case .failure(let error) = $0 {
                                subject.send(completion: .failure(error))
                                cancellable = nil
                                return
                            }
                            
                            let nextChunk = chunkIndex + 1
                            guard nextChunk < chunks.count else {
                                subject.send(completion: .finished)
                                cancellable = nil
                                return
                            }
                            
                            guard let api = weakAPI else {
                                subject.send(completion: .failure(IG.Error(.api(.sessionExpired), "The API instance has been deallocated.", help: "The API functionality is asynchronous. Keep around the API instance while the request/response is being processed.")))
                                cancellable = nil
                                return
                            }
                            
                            cancellable = fetchChunk(api, nextChunk)
                        }, receiveValue: { subject.send($0) })
                }
                
                defer { cancellable = fetchChunk(api, 0) }
                return subject
            }.eraseToAnyPublisher()
    }
    
    /// Returns the details of the given markets.
    /// - parameter epics: The market epics to target onto. It cannot be empty or greater than 50.
    /// - returns: Extended information of all the requested markets.
    private static func _get(api: API, epics: Set<IG.Market.Epic>) -> AnyPublisher<[API.Market],IG.Error> {
        guard !epics.isEmpty else {
            return Result.Publisher([]).eraseToAnyPublisher()
        }
        
        return api.publisher { (api) -> DateFormatter in
                let epicRange = 1...50
                guard epicRange.contains(epics.count) else {
                    let message = "Only between 1 to 50 markets can be queried at the same time."
                    let suggestion = (epics.isEmpty) ? "Request at least one market" : "The request tried to query \(epics.count) markets. Restrict the query to \(epicRange.upperBound) (included)."
                    throw IG.Error(.api(.invalidRequest), message, help: suggestion)
                }
                
                guard let timezone = api.channel.credentials?.timezone else {
                    throw IG.Error(.api(.invalidRequest), "No credentials were found on the API instance.", help: "Log in before calling this request.")
                }
                return DateFormatter.iso8601NoSeconds.deepCopy(timeZone: timezone)
            }.makeRequest(.get, "markets", version: 2, credentials: true, queries: { _ in
                [.init(name: "filter", value: "ALL"),
                 .init(name: "epics", value: epics.map { $0.rawValue }.joined(separator: ",")) ]
            }).send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default(values: true, date: true)) { (l: _WrapperList, _) in l.marketDetails }
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
}

// MARK: - Request Entities

extension API.Request.Markets {
    private struct _WrapperList: Decodable {
        let marketDetails: [API.Market]
    }
}