import Conbini
import Combine
import Foundation

/// High-level instance containing all services that can communicate with the IG platform.
public final class Services {
    /// Queue handling all children low-level services.
    public let queue: DispatchQueue
    /// Instance letting you query any API endpoint.
    public let api: IG.API
    /// Instance letting you subscribe to lightsreamer events.
    public let streamer: IG.Streamer
    /// Instance letting you query a databse for caching purposes.
    public let database: IG.Database
    
    /// Designated initializer specifying every single service.
    ///
    /// By calling this initializer you are forfeiting the conveniences provided by the other initializers; that is, validate credentials, logging in the API, set all queues to a concurrent target queue (for performance reasons).
    /// Please, take note that this initializer do not assures the API is already log in or any credential input is valid
    /// - parameter api: The HTTP API manager.
    /// - parameter streamer: The Lightstreamer event manager.
    /// - parameter database: The Database manager.
    public init(queue: DispatchQueue, api: IG.API, streamer: IG.Streamer, database: IG.Database) {
        self.queue = queue
        self.api = api
        self.streamer = streamer
        self.database = database
    }
    
    /// Factory method for all services, which are log into with the provided user credentials.
    ///
    /// The `streamer` service still requires a further `streamer.session.connect()` call.
    /// - parameter databaseLocation: The location of the database (whether "in-memory" or file system).
    /// - parameter serverURL: The base/root URL for all HTTP endpoint calls. The default URL points to IG's production environment.
    /// - parameter apiKey: [API key](https://labs.ig.com/gettingstarted) given by the IG platform identifying the usage of the IG endpoints.
    /// - parameter user: User name and password to log into an IG account.
    /// - returns: A fully initialized `Services` instance with all services enabled (and logged in).
    public static func make(withDatabase databaseLocation: IG.Database.Location, serverURL: URL = IG.API.rootURL, apiKey: IG.API.Key, user: IG.API.User) -> AnyPublisher<IG.Services,IG.Services.Error> {
        let queue = _makeQueue(targetQueue: nil)
        let api = IG.API(rootURL: serverURL, credentials: nil, targetQueue: queue, qos: queue.qos)
        return api.session.login(type: .certificate, key: apiKey, user: user)
            .mapError(Self.Error.api)
            .flatMap { _ in _make(with: api, queue: queue, location: databaseLocation) }
            .eraseToAnyPublisher()
    }
    
    /// Factory method for all services, which are log into with the provided user token (whether OAuth or Certificate).
    ///
    /// The `streamer` service still requires a further `streamer.session.connect()` call.
    /// - parameter databaseLocation: The location of the database (whether "in-memory" or file system).
    /// - parameter serverURL: The base/root URL for all HTTP endpoint calls. The default URL points to IG's production environment.
    /// - parameter apiKey: [API key](https://labs.ig.com/gettingstarted) given by the IG platform identifying the usage of the IG endpoints.
    /// - parameter token: The API token (whether OAuth or certificate) to use to retrieve all user's data.
    /// - returns: A fully initialized `Services` instance with all services enabled (and logged in).
    public static func make(withDatabase databaseLocation: IG.Database.Location, serverURL: URL = IG.API.rootURL, apiKey: IG.API.Key, token: IG.API.Token) -> AnyPublisher<IG.Services,IG.Services.Error> {
        let queue = _makeQueue(targetQueue: nil)
        let api = IG.API(rootURL: serverURL, credentials: nil, targetQueue: queue, qos: queue.qos)
        
        /// This closure  creates  the remaining subservices from the given api key and token.
        /// - requires: The `token` passed to this closure must be valid and already tested. If not, an error event will be sent.
        let signal: (_ token: IG.API.Token) -> Publishers.FlatMap<AnyPublisher<IG.Services,IG.Services.Error>,Publishers.MapError<AnyPublisher<IG.API.Session,IG.API.Error>,IG.Services.Error>> = { (token) in
            return api.session.get(key: apiKey, token: token)
                .mapError(Self.Error.api)
                .flatMap { (session) -> AnyPublisher<IG.Services,IG.Services.Error> in
                    api.channel.credentials = .init(client: session.client, account: session.account, key: apiKey, token: token, streamerURL: session.streamerURL, timezone: session.timezone)
                    return _make(with: api, queue: queue, location: databaseLocation)
                }
        }
        
        guard token.expirationDate > Date() else {
            switch token.value {
            case .certificate:
                return Fail(error: .api(error: .invalidRequest("The given certificate token has expired and it cannot be refreshed (it must be renewed)", suggestion: "Log in with your username and password")))
                    .eraseToAnyPublisher()
            case .oauth(_, let refreshToken, _,_):
                return api.session.refreshOAuth(token: refreshToken, key: apiKey)
                    .mapError { Self.Error.api(error: .transform($0)) }
                    .flatMap { signal($0) }
                    .eraseToAnyPublisher()
            }
        }
        
        return signal(token)
            .eraseToAnyPublisher()
    }
}

private extension IG.Services {
    /// Creates the queue "overlord" managing all services.
    /// - parameter targetQueue: The queue were all services work items end.
    static func _makeQueue(targetQueue: DispatchQueue?) -> DispatchQueue {
        DispatchQueue(label: Self.reverseDNS, qos: .default, attributes: .concurrent, autoreleaseFrequency: .inherit, target: targetQueue)
    }

    /// Creates a streamer from an API instance and package both in a `Services` structure.
    /// - parameter api: The API instance with valid credentials.
    /// - parameter queue: Concurrent queue used to synchronize all IG's events.
    /// - parameter location: The location of the database (whether "in-memory" or file system).
    /// - requires: Valid (not expired) credentials on the given `API` instance or an error event will be sent.
    static func _make(with api: IG.API, queue: DispatchQueue, location: IG.Database.Location) -> AnyPublisher<IG.Services,IG.Services.Error> {
        // Check that there is API credentials.
        guard var apiCredentials = api.channel.credentials else {
            return Fail(error: .api(error: .invalidRequest(.noCredentials, suggestion: .logIn)))
                .eraseToAnyPublisher()
        }
        // Check that they haven't expired.
        guard apiCredentials.token.expirationDate > Date() else {
            return Fail(error: .api(error: .invalidRequest("The given credentials have expired", suggestion: "Log in with your username and password")))
                .eraseToAnyPublisher()
        }
        
        let subServicesGenerator: ()->Result<IG.Services,IG.Services.Error> = {
            do {
                let secret = try IG.Streamer.Credentials(credentials: apiCredentials)
                let database = try IG.Database(location: location, targetQueue: queue)
                let streamer = IG.Streamer(rootURL: apiCredentials.streamerURL, credentials: secret, targetQueue: queue)
                return .success(.init(queue: queue, api: api, streamer: streamer, database: database))
            } catch let error as IG.Database.Error {
                return .failure(.database(error: error))
            } catch let error as IG.Streamer.Error {
                return .failure(.streamer(error: error))
            } catch let error as IG.API.Error {
                return .failure(.api(error: error))
            } catch let underlyingError {
                var error: IG.Streamer.Error = .invalidRequest(.init("An unknown error appeared while creating the \(IG.Streamer.self) and \(IG.Database.self) instance"), suggestion: .fileBug)
                error.underlyingError = underlyingError
                return .failure(.streamer(error: error))
            }
        }
        
        switch apiCredentials.token.value {
        case .oauth:
            return api.session.refreshCertificate()
                .mapError { Self.Error.api(error: IG.API.Error.transform($0)) }
                .flatMap { (token) -> Result<IG.Services,IG.Services.Error>.Publisher in
                    apiCredentials.token = token
                    return .init(subServicesGenerator())
                }.eraseToAnyPublisher()
        case .certificate:
            return DeferredResult(closure: subServicesGenerator)
                .eraseToAnyPublisher()
        }
    }
}


extension IG.Services {
    /// The reverse DNS identifier for the `API` instance.
    internal static var reverseDNS: String {
        Bundle.IG.identifier + ".services"
    }
}

extension IG.Services: IG.DebugDescriptable {
    internal static var printableDomain: String { "\(Bundle.IG.name).\(Self.self)" }
    
    public var debugDescription: String {
        var result = IG.DebugDescription(Self.printableDomain)
        result.append("queue", self.queue.label)
        result.append("queue QoS", String(describing: self.queue.qos.qosClass))
        result.append("api", self.api.rootURL.absoluteString)
        result.append("streamer", self.streamer.rootURL.absoluteString)
        result.append("databse", self.database.rootURL?.absoluteString ?? ":memory:")
        return result.generate()
    }
}