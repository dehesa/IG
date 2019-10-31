import Combine
import Foundation

extension IG.API.Request {
    /// List of endpoints related to navigation nodes.
    public struct Nodes {
        /// Pointer to the actual API instance in charge of calling the endpoints.
        fileprivate unowned let api: IG.API
        
        /// Hidden initializer passing the instance needed to perform the endpoint.
        /// - parameter api: The instance calling the actual endpoints.
        init(api: IG.API) {
            self.api = api
        }
    }
}

extension IG.API.Request.Nodes {
    /// Returns the navigation node with the given id and all the children till a specified depth.
    /// - attention: For depths bigger than 0, several endpoints are hit (one for each node, it can easily be 100); thus, the callback may take a while. Be mindful of bigger depths.
    /// - parameter identifier: The identifier for the targeted node. If `nil`, the top-level nodes are returned.
    /// - parameter name: The name for the targeted name. If `nil`, the name of the node is not set on the returned `Node` instance.
    /// - parameter depth: The depth at which the tree will be travelled.  A negative integer will default to `0`.
    /// - returns: *Future* forwarding the node identified by the parameters recursively filled with the subnodes and submarkets till the given `depth`.
    public func get(identifier: String?, name: String? = nil, depth: Self.Depth = .none) -> IG.API.Publishers.Discrete<IG.API.Node> {
        let layers = depth.value
        guard layers > 0 else {
            return Self.get(api: self.api, node: .init(identifier: identifier, name: name))
        }
        
        return Self.iterate(api: self.api, node: .init(identifier: identifier, name: name), depth: layers)
    }

    // MARK: GET /markets/{searchTerm}
    
    /// Returns all markets matching the search term.
    ///
    /// The search term cannot be an empty string.
    /// - parameter searchTerm: The term to be used in the search. This parameter is mandatory and cannot be empty.
    /// - returns: *Future* forwarding all markets matching the search term.
    public func getMarkets(matching searchTerm: String) -> IG.API.Publishers.Discrete<[IG.API.Node.Market]> {
        self.api.publisher { (api) -> String in
                guard !searchTerm.isEmpty else {
                    let message = "Search for markets failed! The search term cannot be empty"
                    throw IG.API.Error.invalidRequest(.init(message), suggestion: .readDocs)
                }
                return searchTerm
            }.makeRequest(.get, "markets", version: 1, credentials: true, queries: { [.init(name: "searchTerm", value: $0)] })
            .send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .default(date: true)) { (w: Self.WrapperSearch, _) in w.markets }
            .mapError(IG.API.Error.transform)
            .eraseToAnyPublisher()
    }

    // MARK: GET /marketnavigation/{nodeId}
    
    /// Returns all data of the given navigation node.
    ///
    /// The subnodes are not recursively retrieved; thus only a flat hierarchy will be built with this endpoint..
    /// - parameter node: The entity targeting a specific node. Only the identifier is used.
    /// - returns: *Future* forwarding a *full* node.
    private static func get(api: API, node: IG.API.Node) -> IG.API.Publishers.Discrete<IG.API.Node> {
        api.publisher
            .makeRequest(.get, "marketnavigation/\(node.identifier ?? "")", version: 1, credentials: true)
            .send(expecting: .json, statusCode: 200)
            .decodeJSON(decoder: .custom({ (request, response, _) -> JSONDecoder in
                guard let dateString = response.allHeaderFields[IG.API.HTTP.Header.Key.date.rawValue] as? String,
                      let date = IG.API.Formatter.humanReadableLong.date(from: dateString) else {
                    let message = "The response date couldn't be extracted from the response header"
                    throw IG.API.Error.invalidResponse(message: .init(message), request: request, response: response, suggestion: .fileBug)
                }
                
                return JSONDecoder().set {
                    $0.userInfo[IG.API.JSON.DecoderKey.responseDate] = date
                    
                    if let identifier = node.identifier {
                        $0.userInfo[IG.API.JSON.DecoderKey.nodeIdentifier] = identifier
                    }
                    if let name = node.name {
                        $0.userInfo[IG.API.JSON.DecoderKey.nodeName] = name
                    }
                }
            }))
            .mapError(IG.API.Error.transform)
            .eraseToAnyPublisher()
    }
    
    /// Returns the navigation node indicated by the given node argument as well as all its children till a given depth.
    /// - parameter node: The entity targeting a specific node. Only the identifier is used for identification purposes.
    /// - parameter depth: The depth at which the tree will be travelled.  A negative integer will default to `0`.
    /// - returns: *Future* forwarding the node given as an argument with complete subnodes and submarkets information.
    private static func iterate(api: API, node: IG.API.Node, depth: Int) -> IG.API.Publishers.Discrete<IG.API.Node> {
        // 1. Retrieve the targeted node.
        return Self.get(api: api, node: node).flatMap { [weak weakAPI = api] (node) -> AnyPublisher<IG.API.Node,IG.API.Error> in
            let countdown = depth - 1
            // 2. If there aren't any more levels to drill down into or the target node doesn't have subnodes, send the targeted node.
            guard countdown >= 0, let subnodes = node.subnodes, !subnodes.isEmpty else {
                return Just(node).setFailureType(to: IG.API.Error.self).eraseToAnyPublisher()
            }
            // 3. Check the API instance is still there.
            guard let api = weakAPI else {
                return Fail<IG.API.Node,IG.API.Error>(error: .sessionExpired()).eraseToAnyPublisher()
            }
            
            /// The result of this combine pipeline.
            let subject = PassthroughSubject<IG.API.Node,IG.API.Error>()
            /// The root node from which to look for subnodes.
            var parent = node
            /// This closure retrieves the child node at the `parent` index `childIndex` and calls itself recursively until there are no more children in `parent.subnodes`.
            var fetchChildren: ((_ api: API, _ childIndex: Int, _ childDepth: Int) -> AnyCancellable?)! = nil
            /// `Cancellable` to stop fetching the `parent.subnodes`.
            var childrenFetchingCancellable: AnyCancellable? = nil
            
            fetchChildren = { (childAPI, childIndex, childDepth) in
                // 5. Retrieve the child node indicated by the index.
                Self.iterate(api: childAPI, node: parent.subnodes![childIndex], depth: childDepth)
                    .sink(receiveCompletion: {
                        if case .failure(let error) = $0 {
                            subject.send(completion: .failure(error))
                            childrenFetchingCancellable = nil
                            return
                        }
                        // 6. Check if there is a "next" sibling.
                        let nextChildIndex = childIndex + 1
                        // 7. If there aren't any more siblings, forward the parent downstream since we have retrieved all the information.
                        guard nextChildIndex < parent.subnodes!.count else {
                            subject.send(parent)
                            subject.send(completion: .finished)
                            childrenFetchingCancellable = nil
                            return
                        }
                        // 8. If the API instance has been deallocated, forward an error downstream.
                        guard let api = weakAPI else {
                            subject.send(completion: .failure(.sessionExpired()))
                            childrenFetchingCancellable?.cancel()
                            return
                        }
                        // 9. If there are more siblings, keep iterating.
                        childrenFetchingCancellable = fetchChildren(api, nextChildIndex, childDepth)
                    }, receiveValue: { parent.subnodes![childIndex] = $0 })
            }
            
            // 4. Retrieve children nodes, starting by the first one.
            defer { childrenFetchingCancellable = fetchChildren(api, 0, countdown) }
            return subject.eraseToAnyPublisher()
        }.eraseToAnyPublisher()
    }
}

// MARK: - Entities

extension IG.API.Request.Nodes {
    /// Express the depth of a computed tree.
    public enum Depth: ExpressibleByNilLiteral, ExpressibleByIntegerLiteral {
        /// No depth (outside the targeted node).
        case none
        /// Number of subnodes layers under the targeted node will be queried.
        case layers(UInt)
        /// All nodes under the targeted node will be queried.
        case all
        
        public init(nilLiteral: ()) {
            self = .none
        }
        
        public init(integerLiteral value: UInt) {
            if value == 0 {
                self = .none
            } else {
                self = .layers(value)
            }
        }
        
        fileprivate var value: Int {
            switch self {
            case .none:
                return 0
            case .layers(let value):
                return Int(clamping: value)
            case .all:
                return Int.max
            }
        }
    }
}

extension IG.API.Request.Nodes {
    private struct WrapperSearch: Decodable {
        let markets: [IG.API.Node.Market]
    }
}

extension IG.API {
    /// Node within the Broker platform markets organization.
    public struct Node: Decodable {
        /// Node identifier.
        /// - note: The top of the tree will return `nil` for this property.
        public let identifier: String?
        /// Node name.
        public var name: String?
        /// The children nodes (subnodes) of `self`
        ///
        /// There can be three possible options:
        /// - `nil`if there hasn't be a query to ask for this node's subnodes.
        /// - Empty array if this node doesn't have any subnode.
        /// - Non-empty array if the node has children.
        public internal(set) var subnodes: [Self]?
        /// The markets organized under `self`
        ///
        /// There can be three possible options:
        /// - `nil`if there hasn't be a query to ask for this node's markets..
        /// - Empty array if this node doesn't have any market..
        /// - Non-empty array if the node has markets..
        public internal(set) var markets: [Self.Market]?
        
        fileprivate init(identifier: String?, name: String?) {
            self.identifier = identifier
            self.name = name
            self.subnodes = nil
            self.markets = nil
        }
        
        public init(from decoder: Decoder) throws {
            self.identifier = decoder.userInfo[IG.API.JSON.DecoderKey.nodeIdentifier] as? String
            self.name = decoder.userInfo[IG.API.JSON.DecoderKey.nodeName] as? String
            
            let container = try decoder.container(keyedBy: Self.CodingKeys.self)
            
            var subnodes: [IG.API.Node] = []
            if container.contains(.nodes), try !container.decodeNil(forKey: .nodes) {
                var array = try container.nestedUnkeyedContainer(forKey: .nodes)
                while !array.isAtEnd {
                    let nodeContainer = try array.nestedContainer(keyedBy: Self.CodingKeys.ChildKeys.self)
                    let id = try nodeContainer.decode(String.self, forKey: .id)
                    let name = try nodeContainer.decode(String.self, forKey: .name)
                    subnodes.append(.init(identifier: id, name: name))
                }
            }
            self.subnodes = subnodes
            
            if container.contains(.markets), try !container.decodeNil(forKey: .markets) {
                self.markets = try container.decode(Array<Self.Market>.self, forKey: .markets)
            } else {
                self.markets = []
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case nodes, markets
            
            enum ChildKeys: String, CodingKey {
                case id, name
            }
        }
    }
}

// MARK: - Functionality

extension IG.API.JSON.DecoderKey {
    /// Key for JSON decoders under which a node identifier will be stored.
    fileprivate static let nodeIdentifier = CodingUserInfoKey(rawValue: "IG_APINodeId")!
    /// Key for JSON decoders under which a node name will be stored.
    fileprivate static let nodeName = CodingUserInfoKey(rawValue: "IG_APINodeName")!
}

extension IG.API.Node: IG.DebugDescriptable {
    internal static var printableDomain: String {
        return "\(IG.API.printableDomain).\(Self.self)"
    }
    
    public var debugDescription: String {
        var result = IG.DebugDescription(Self.printableDomain)
        result.append("node ID", self.identifier)
        result.append("name", self.name)
        result.append("subnodes IDs", self.subnodes?.map { $0.identifier ?? IG.DebugDescription.Symbol.nil })
        result.append("markets", self.markets?.map { $0.instrument.epic } )
        return result.generate()
    }
}