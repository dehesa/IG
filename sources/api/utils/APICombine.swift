import Conbini
import Combine
import Foundation

internal extension API {
    /// Intermediate types passed around in the Combine pipelines.
    enum Transit {
        /// API pipeline's first stage variables: the API instance to use and some computed values (or `Void`).
        typealias Instance<T> = (api: API, values: T)
        /// API pipeline's second stage variables: the API instance to use, the URL request to perform, and some computed values (or `Void`).
        typealias Request<T> = (api: API, request:URLRequest, values: T)
        /// API pipeline's third stage variables: the request that has been performed, the response and payload received, and some computed values (or `Void`).
        typealias Call<T> = (request: URLRequest, response: HTTPURLResponse, data: Data, values: T)
        /// Previous paginated page values: the previous successful request and its metadata.
        typealias PreviousPage<M> = (request: URLRequest, metadata: M)
    }
}

internal extension API {
    /// Publisher sending downstream the receiving `API` instance. If the instance has been deallocated when the chain is activated, a failure is sent downstream.
    /// - returns: A Publisher sending an `API` instance and completing immediately once it is activated.
    @_transparent var publisher: DeferredResult<API.Transit.Instance<Void>,IG.Error> {
        DeferredResult { [weak self] in
            guard let self = self else { return .failure(._deallocatedAPI()) }
            return .success( (self,()) )
        }
    }
    
    /// Publisher sending downstream the receiving `API` instance and some computed values. If the instance has been deallocated or the values cannot be generated, the publisher fails.
    /// - parameter valuesGenerator: Closure generating the values to be send downstream along with the `API` instance.
    /// - returns: A Publisher sending an `API` instance along with some computed values and completing immediately once it is activated.
    func publisher<T>(_ valuesGenerator: @escaping (_ api: API) throws -> T) -> DeferredResult<API.Transit.Instance<T>,IG.Error> {
        DeferredResult { [weak self] in
            guard let self = self else { return .failure(._deallocatedAPI()) }
            do {
                let values = try valuesGenerator(self)
                return .success( (self, values) )
            } catch let error as IG.Error {
                return .failure( error )
            } catch let underlyingError {
                return .failure( IG.Error._invalidPrecomputedValues(error: underlyingError) )
            }
        }
    }
}

internal extension Publisher {
    /// Transforms the upstream `API` instance and computed values into a URL request with the properties specified as arguments.
    /// - parameter method: The HTTP method of the endpoint.
    /// - parameter relativeURL: The relative URL to be appended to the API instance root URL.
    /// - parameter version: The API endpoint version number (to be included in the HTTP header).
    /// - parameter usingCredentials: Whether the request shall include credential headers.
    /// - parameter queryGenerator: Optional array of queries to be attached to the request.
    /// - parameter headGenerator: Optional/Additional headers to be included in the request.
    /// - parameter bodyGenerator: Optional body generator to include in the request.
    /// - returns: Each value event is transformed into a valid `URLRequest` and is passed along an `API` instance and some computed values.
    func makeRequest<T>(_ method: API.HTTP.Method, _ relativeURL: String, version: Int, credentials usingCredentials: Bool,
                        queries queryGenerator: ((_ values: T) throws -> [URLQueryItem])? = nil,
                        headers headGenerator:  ((_ values: T) throws -> [API.HTTP.Header.Key:String])? = nil,
                        body    bodyGenerator:  ((_ values: T) throws -> (contentType: API.HTTP.Header.Value.ContentType, data: Data))? = nil
                       ) -> Publishers.TryMap<Self,API.Transit.Request<T>> where Output==API.Transit.Instance<T> {
        self.tryMap { (api, values) in
            var request = URLRequest(url: api.rootURL.appendingPathComponent(relativeURL))
            request.httpMethod = method.description
            
            do {
                if let queries = try queryGenerator?(values) {
                    try request.addQueries(queries)
                }

                let credentials = (!usingCredentials) ? nil : try api.channel.credentials ?> IG.Error._unfoundCredentials(request: request)
                request.addHeaders(version: version, credentials: credentials, try headGenerator?(values))

                if let body = try bodyGenerator?(values) {
                    request.addValue(body.contentType.description, forHTTPHeaderField: API.HTTP.Header.Key.requestType.rawValue)
                    request.httpBody = body.data
                }
            } catch let error as IG.Error {
                throw error
            } catch let underlyingError {
                throw IG.Error._unableToFormRequest(request: request, error: underlyingError)
            }

            return (api, request, values)
        }
    }
    
    /// Perform the request specified as upstream value on the `API`'s session passed along with it.
    ///
    /// The operator will also check that the network package received has the appropriate `HTTPURLResponse` header, is of the expected type (e.g. JSON) and it has the expected response status code (if any has been indicated).
    /// - parameter type: The HTTP content type expected as a result.
    /// - parameter statusCodes: If not `nil`, the sequence indicates all *viable*/supported status codes.
    /// - returns: Publisher forwarding  downstream the endpoint request, response, received blob/data, and any pre-computed values.
    /// - returns: Each value event triggers a network call. This publisher forwards the response of that network call.
    func send<S,T>(expecting type: API.HTTP.Header.Value.ContentType? = nil,
                   statusCodes: S? = nil
                  ) -> Publishers.FlatMap< Publishers.TryMap< Publishers.MapError<URLSession.DataTaskPublisher,IG.Error>, API.Transit.Call<T>>, Self> where Self.Output==API.Transit.Request<T>, Self.Failure==Swift.Error, S:Sequence, S.Element==Int {
        self.flatMap { (api, request, values) in
            api.channel.session
                .dataTaskPublisher(for: request)
                .mapError { IG.Error._unknownInternal(error: $0, request: request) }
                .tryMap { (data, response) in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw IG.Error._invalidURL(response: response, request: request, data: data)
                    }
                    
                    if let expectedCodes = statusCodes, !expectedCodes.contains(httpResponse.statusCode) {
                        throw IG.Error._invalidResponse(code: httpResponse.statusCode, expected: expectedCodes, request: request, response: httpResponse, data: data)
                    }
                    
                    return (request, httpResponse, data, values)
                }
        }
    }
    
    /// Perform the request specified as upstream value on the `API`'s session passed along with it.
    ///
    /// The operator will also check that the network package received has the appropriate `HTTPURLResponse` header, is of the expected type (e.g. JSON) and it has the expected response status code (if any has been indicated).
    /// - parameter type: The HTTP content type expected as a result.
    /// - parameter codes: List of HTTP status codes expected (i.e. the endpoint call is considered successful).
    /// - returns: Each value event triggers a network call. This publisher forwards the response of that network call.
    func send<T>(expecting type: API.HTTP.Header.Value.ContentType? = nil,
                 statusCode codes: Int...
                ) ->  Publishers.FlatMap< Publishers.TryMap< Publishers.MapError<URLSession.DataTaskPublisher,IG.Error>, API.Transit.Call<T>>, Self> where Self.Output==API.Transit.Request<T>, Self.Failure==Swift.Error {
        self.send(expecting: type, statusCodes: codes)
    }
    
    /// Similar than `send(expecting:statusCodes:)`, this method executes one (or many) requests on the passed API instance.
    ///
    /// The initial request is received as a value and is evaluated on the `pageRequestGenerator` closure. If the closure returns a `URLRequest`, that endpoint will be performed. If the closure returns `nil`, the publisher will complete.
    /// - parameter pageRequestGenerator: All data needed to compile a request for the next page. If `nil` is returned, the request won't be performed and the publisher will complete. On the other hand, if an error is thrown, it will be forwarded as a failure event.
    /// - parameter pageCall: The actual combine pipeline sending the request and decoding the result. The values/errors will be forwarded to the returned publisher.
    /// - returns: A continuous publisher returning the values from `pageCall` as soon as they arrive. Only when `nil` is returned on the `pageRequestGenerator` closure, will the returned publisher complete.
    func sendPaginating<T,M,R,P>(request pageRequestGenerator: @escaping (_ api: API, _ initial: (request: URLRequest, values: T), _ previous: API.Transit.PreviousPage<M>?) throws -> URLRequest?,
                                 call pageCall: @escaping (_ pageRequest: Result<API.Transit.Request<T>,Swift.Error>.Publisher, _ values: T) -> P
                                ) -> Publishers.FlatMap<DeferredPassthrough<R,Swift.Error>,Self> where Self.Output==API.Transit.Request<T>, Self.Failure==Swift.Error, P:Publisher, P.Output==(M,R), P.Failure==IG.Error {
        self.flatMap(maxPublishers: .max(1)) { (api, initialRequest, values) in
            DeferredPassthrough<R,Swift.Error> { (subject) in
                typealias Iterator = (_ previous: API.Transit.PreviousPage<M>?) -> Void
                /// Recursive closure fed with the last successfully retrieved page (or `nil` at the very beginning).
                var iterator: Iterator? = nil
                /// Cancellable used to detached the current page download task.
                var pageCancellable: AnyCancellable? = nil
                /// Closure that must be called once the pagination process finishes, so the state can be cleaned.
                let sendCompletion: (_ subject: PassthroughSubject<R,Swift.Error>,
                                     _ completion: Subscribers.Completion<IG.Error>,
                                     _ previous: API.Transit.PreviousPage<M>?,
                                     _ pageCancellable: inout AnyCancellable?,
                                     _ iterator: inout Iterator?) -> Void = { (subject, completion, previous, pageCancellable, iterator) in
                    iterator = nil
                    if let cancellation = pageCancellable {
                        pageCancellable = nil
                        cancellation.cancel()
                    }
                    
                    switch completion {
                    case .finished:
                        subject.send(completion: .finished)
                    case .failure(let error):
                        if let previous = previous {
                            error.errorUserInfo["Last successful page request"] = previous.request
                            error.errorUserInfo["Last successful page metadata"] = previous.metadata
                        }
                        subject.send(completion: .failure(error))
                    }
                }
                
                iterator = { [weak weakAPI = api] (previous) in
                    // 1. Check whether the API instance is still available
                    guard let api = weakAPI else {
                        return sendCompletion(subject, .failure(IG.Error._deallocatedAPI()), previous, &pageCancellable, &iterator)
                    }
                    // 2. Fetch the next page request
                    let nextRequest: URLRequest?
                    do {
                        nextRequest = try pageRequestGenerator(api, (initialRequest, values), previous)
                    } catch let error as IG.Error {
                        return sendCompletion(subject, .failure(error), previous, &pageCancellable, &iterator)
                    } catch let error {
                        return sendCompletion(subject, .failure(IG.Error._invalidPaginated(request: initialRequest, error: error)), previous, &pageCancellable, &iterator)
                    }
                    // 3. If there isn't a new request, it means we have successfully retrieved all pages
                    guard let pageRequest = nextRequest else {
                        return sendCompletion(subject, .finished, previous, &pageCancellable, &iterator)
                    }
                    // 4. If there is a new request, execute it as a network call in order to retrieve the page (only one value shall be returned)
                    var pageResult: (metadata: M, output: R)? = nil
                    pageCancellable = pageCall(.init((api, pageRequest, values)), values).sink(receiveCompletion: {
                        if case .failure = $0 {
                            return sendCompletion(subject, $0, previous, &pageCancellable, &iterator)
                        }
                        
                        guard let result = pageResult else {
                            return sendCompletion(subject, .failure(IG.Error._emptyPaginated(request: pageRequest)), previous, &pageCancellable, &iterator)
                        }
                        
                        subject.send(result.output)
                        
                        guard let next = iterator else {
                            return sendCompletion(subject, .failure(IG.Error._deallocatedAPI()), previous, &pageCancellable, &iterator)
                        }
                        
                        pageCancellable = nil
                        defer { pageResult = nil }
                        return next((pageRequest, result.metadata))
                    }, receiveValue: { (metadata, output) in
                        if let previouslyStored = pageResult {
                            let error = IG.Error._conflictedPaginatedResults(info: [
                                "Request": pageRequest,
                                "Previous result metadata": previouslyStored.metadata,
                                "Previous result output": previouslyStored.output,
                                "Conflicting result metadata": metadata,
                                "Conflicting result metadata": output
                            ])
                            pageResult = nil
                            return sendCompletion(subject, .failure(error), previous, &pageCancellable, &iterator)
                        }
                        pageResult = (metadata, output)
                    })
                }
                
                iterator?(nil)
            }
        }
    }
    
    /// Decodes the JSON payload with a given `JSONDecoder`.
    /// - parameter decoder: Enum indicating how the `JSONDecoder` is created/obtained.
    /// - returns: Each value event triggers a JSON decoding process. This publisher forwards the response of that process.
    func decodeJSON<T,R>(decoder: API.JSON.Decoder<T>, result: R.Type = R.self) -> Publishers.TryMap<Self,R> where Self.Output==API.Transit.Call<T>, R: Decodable {
        self.tryMap { (request, response, data, values) -> R in
            var stage: Int = 0
            do {
                let jsonDecoder = try decoder.makeDecoder(request: request, response: response, values: values); stage += 1
                return try jsonDecoder.decode(R.self, from: data)
            } catch let error as IG.Error {
                throw error
            } catch let error {
                throw IG.Error._unableToDecode(stage: stage, request: request, response: response, data: data, error: error)
            }
        }
    }
    
    /// Decodes the JSON payload with a given `JSONDecoder` and then performs a transformation to the result.
    /// - parameter decoder: Enum indicating how the `JSONDecoder` is created/obtained.
    /// - parameter transform: Transformation to be applied to the result of the JSON decoding.
    /// - returns: Each value event triggers a JSON decoding process. This publisher forwards the response of that process after being transformed by the closure.
    func decodeJSON<T,R,W>(decoder: API.JSON.Decoder<T>, transform: @escaping (_ decoded: R, _ call: (request: URLRequest, response: HTTPURLResponse)) throws -> W) -> Publishers.TryMap<Self,W> where Self.Output==API.Transit.Call<T>, R:Decodable {
        self.tryMap { (request, response, data, values) -> W in
            var stage: Int = 0
            do {
                let jsonDecoder = try decoder.makeDecoder(request: request, response: response, values: values); stage += 1
                let payload = try jsonDecoder.decode(R.self, from: data); stage += 1
                return try transform(payload, (request, response))
            } catch let error as IG.Error {
                throw error
            } catch let error {
                throw IG.Error._unableToDecode(stage: stage, request: request, response: response, data: data, error: error)
            }
        }
    }
}

private extension IG.Error {
    /// Error raised when the API instance is deallocated.
    static func _deallocatedAPI() -> Self {
        Self(.api(.sessionExpired), "The API instance has been deallocated.", help: "The API functionality is asynchronous. Keep around the API instance while the request/response is being processed.")
    }
    /// Error raised when the API credentials haven't been found.
    static func _unfoundCredentials(request: URLRequest) -> Self {
        Self(.api(.invalidRequest), "No credentials were found on the API instance.", help: "Log in before calling this request.", info: ["Request": request])
    }
    /// Error raised when the precomputed request values cannot be generated.
    static func _invalidPrecomputedValues(error: Swift.Error) -> Self {
        Self(.api(.invalidRequest), "The precomputed request values couldn't be generated.", help: "Read the request documentation and be sure to follow all requirements.", underlying: error)
    }
    /// Error raised when the URL request cannot be created.
    static func _unableToFormRequest(request: URLRequest, error: Swift.Error) -> Self {
        Self(.api(.invalidRequest), "The URL request couldn't be created.", help: "Read the request documentation and be sure to follow all requirements.", underlying: error, info: ["Request": request])
    }
    /// Error raised when an internal URL session error happened.
    static func _unknownInternal(error: Swift.Error, request: URLRequest) -> Self {
        Self(.api(.callFailed), "An internal session error occurred while calling the HTTP endpoint.", help: "Review the underlying error and try to fix the problem.", underlying: error, info: ["Request": request])
    }
    /// Error raised when the response is not of HTTP type.
    static func _invalidURL(response: URLResponse, request: URLRequest, data: Data) -> Self {
        Self(.api(.callFailed), "The received URL response was not of 'HTTPURLResponse' type.", help: "A unexpected error was encountered. Please contact the repository maintainer and attach this debug print.", info: ["Request": request, "Response": response, "Data": data])
    }
    /// Error raised when the response status code don't match expectations.
    static func _invalidResponse<S>(code: Int, expected: S, request: URLRequest, response: HTTPURLResponse, data: Data) -> Self where S:Sequence, S.Element==Int {
        Self(.api(.invalidResponse), "The URL response code '\(code)' was received, but only \(expected) codes were expected.", help: "Review the returned response and data, and try to fix the problem.", info: ["Request": request, "Response": response, "Data": data])
    }
    /// Error raised when the paginated request cannot be created.
    static func _invalidPaginated(request: URLRequest, error: Swift.Error) -> Self {
        Self(.api(.invalidRequest), "The paginated request couldn't be created.", underlying: error, info: ["Request": request])
    }
    /// Error raised when an empty page is received.
    static func _emptyPaginated(request: URLRequest) -> Self {
        Self(.api(.callFailed), "A page call returned empty.", help: "Review the returned error and try to fix the problem.", info: ["Request": request])
    }
    /// Error raised when
    static func _conflictedPaginatedResults(info: [String:Any]) -> Self {
        Self(.api(.callFailed), "A single page received two results.", help: "A unexpected error was encountered. Please contact the repository maintainer and attach this debug print.", info: info)
    }
    /// Error raised when a response body cannot be created.
    static func _unableToDecode(stage: Int, request: URLRequest, response: HTTPURLResponse, data: Data, error: Swift.Error) -> Self {
        let (reason, help): (String, String)
        switch stage {
        case 0:
            reason = "A JSON decoder couldn't be created."
            help = "Review the returned error and try to fix the problem."
        case 1:
            reason = "The response body could not be decoded as the expected type."
            help = "Contact the repo maintainer."
        default:
            reason = "The response body was decoded successfully from JSON, but it couldn't be transformed into the given type."
            help = "Contact the repo maintainer."
        }
        return Self(.api(.invalidResponse), reason, help: help, underlying: error, info: ["Request": request, "Response": response, "Data": data])
    }
}
