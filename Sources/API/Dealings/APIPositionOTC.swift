import ReactiveSwift
import Foundation

extension API.Request.Positions {
    
    // MARK: POST /positions/otc
    
    /// Creates a new position.
    ///
    /// This endpoint creates a "transient" position (identified by the returned deal reference).
    /// The position is not really open till the server confirms the "transient" position and gives the user a deal identifier.
    /// - parameter epic: Instrument epic identifer.
    /// - parameter expiry: The date (and sometimes "time") at which a spreadbet or CFD will automatically close against some predefined market value should the bet remain open beyond its last dealing time. Some CFDs do not expire.
    /// - parameter currency: The currency code (3 letters).
    /// - parameter direction: Deal direction (whether buy or sell).
    /// - parameter order: Describes how the user's order must be executed (and at which level).
    /// - parameter strategy: The order fill strategy.
    /// - parameter size: Deal size. Precision shall not be more than 12 decimal places.
    /// - parameter limit: The limit level/distance at which the user will like to take profit). It can be marked as a distance from the buy/sell level, or as an absolute value, or none (in which the position is open).
    /// - parameter stop: The stop at which the user doesn't want to incur more losses.
    /// - parameter forceOpen: Enabling force open when creating a new position or working order will enable a second position to be opened on a market. This variable will be set to `true` if the limit and/or the stop are set.
    /// - parameter reference: A user-defined reference (e.g. `RV3JZ2CWMHG1BK`) identifying the submission of the order. If `nil` a reference will be created by the server and return as the result of this enpoint.
    /// - returns: The transient deal reference (for an unconfirmed trade).
    public func create(epic: Epic, expiry: API.Expiry = .none, currency: Currency,
                       direction: API.Position.Direction, order: API.Position.Order, strategy: API.Position.Order.Strategy,
                       size: Double, limit: Self.Limit?, stop: Self.Stop?,
                       forceOpen: Bool = true, reference: API.Position.Reference? = nil) -> SignalProducer<API.Position.Reference,API.Error> {
        return SignalProducer(api: self.api)
            .request(.post, "positions/otc", version: 2, credentials: true, body: { (_,_) in
                let payload = Self.PayloadCreation(epic: epic, expiry: expiry, currency: currency, direction: direction, order: order, strategy: strategy, size: size, limit: limit, stop: stop, forceOpen: forceOpen, reference: reference)
                let data = try JSONEncoder().encode(payload)
                return (.json, data)
            }).send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (w: Self.WrapperReference) in w.dealReference }
    }
    
    // MARK: PUT /positions/otc/{dealId}
    
    /// Edits an opened position (identified by the `dealId`).
    ///
    /// This endpoint modifies an openned position. The returned refence is not considered as taken into effect until the server confirms the "transient" position reference and give the user a deal identifier.
    /// - parameter dealId: A permanent deal reference for a confirmed trade.
    /// - parameter limit: .Passing a value, will set a limit level (replacing the previous one, if any). Setting this argument to `nil` will delete the limit on the position.
    /// - parameter stop: Passing a value will set a stop level (replacing the previous one, if any). Setting this argument to `nil` will delete the stop position.
    /// - returns: The transient deal reference (for an unconfirmed trade) wrapped in a SignalProducer's value.
    public func update(identifier: API.Position.Identifier, limit: Double?, stop: (level: Double, trailing: (distance: Double, increment: Double)?)?) -> SignalProducer<API.Position.Reference,API.Error> {
        return SignalProducer(api: self.api)  { (_) -> Self.PayloadUpdate in
                guard limit != nil || stop != nil else {
                    throw API.Error.invalidRequest(underlyingError: nil, message: "Position update failed! No parameters were provided.")
                }
                return .init(limit: limit, stop: stop)
            }.request(.put, "positions/otc/\(identifier.rawValue)", version: 2, credentials: true, body: { (_, payload) in
                let data = try JSONEncoder().encode(payload)
                return (.json, data)
            }).send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (w: Self.WrapperReference) in w.dealReference }
    }

    
    // MARK: DELETE /positions/otc
    
    /// Closes one or more positions.
    /// - parameter request: A filter to match the positions to be deleted.
    /// - returns: The transient deal reference (for an unconfirmed trade) wrapped in a SignalProducer's value.
    public func delete(matchedBy identification: Self.Identification, direction: API.Position.Direction,
                       order: API.Position.Order, strategy: API.Position.Order.Strategy, size: Double) -> SignalProducer<API.Position.Reference,API.Error> {
        return SignalProducer(api: self.api)
            .request(.post, "positions/otc", version: 1, credentials: true, headers: { (_,_) in
                [._method: API.HTTP.Method.delete.rawValue]
            }, body: { (_,_) in
                let payload = Self.PayloadDeletion(identification: identification, direction: direction, order: order, strategy: strategy, size: size)
                let data = try JSONEncoder().encode(payload)
                return (.json, data)
            }).send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (w: Self.WrapperReference) in w.dealReference }
    }
}

// MARK: - Supporting Entities

// MARK: Request Entities
//
extension API.Request.Positions {
    /// The type of limit being set.
    public enum Limit {
        /// The limit or stop is given explicitly (as a value).
        case position(level: Double)
        /// The limit or stop is measured as the distance from a given level.
        case distance(Double)
    }
    
    /// The level/price at which the user doesn't want to incur more lose.
    public enum Stop {
        /// Absolute value of the stop (e.g. 1.653 USD/EUR).
        /// - parameter isGuaranteed: Boolean indicating if a guaranteed stop is required. A guaranteed stop is a stop-loss order that puts an absolute limit on your liability, eliminating the chance of slippage and guaranteeing an exit price for your trade.
        case position(level: Double, isGuaranteed: Bool)
        /// Distance from the buy/sell level where the stop will be placed.
        /// - parameter isGuaranteed: Boolean indicating if a guaranteed stop is required. A guaranteed stop is a stop-loss order that puts an absolute limit on your liability, eliminating the chance of slippage and guaranteeing an exit price for your trade.
        case distance(Double, isGuaranteed: Bool)
        /// A distance from the buy/sell level stop with the tweak that the stop will be moved towards the current level in case of a favourable trade.
        /// - parameter distance: The distance from the buy/sell price.
        /// - parameter increment: The increment step in pips.
        case trailing(distance: Double, increment: Double)
    }
    
    private struct PayloadCreation: Encodable {
        let epic: Epic
        let expiry: API.Expiry
        let currency: Currency
        let direction: API.Position.Direction
        let order: API.Position.Order
        let strategy: API.Position.Order.Strategy
        let size: Double
        let limit: API.Request.Positions.Limit?
        let stop: API.Request.Positions.Stop?
        let forceOpen: Bool
        let reference: API.Position.Reference?
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Self.CodingKeys.self)
            try container.encode(self.epic, forKey: .epic)
            try container.encode(self.expiry, forKey: .expiry)
            try container.encode(self.currency, forKey: .currency)
            try container.encode(self.direction, forKey: .direction)
            
            try container.encode(self.order.rawValue, forKey: .order)
            switch order {
            case .limit(level: let level):
                try container.encode(level, forKey: .level)
            case .market:
                break
            case .quote(id: let quoteId, level: let level):
                try container.encode(quoteId, forKey: .quoteId)
                try container.encode(level, forKey: .level)
            }
            try container.encode(self.strategy, forKey: .fillStrategy)
            try container.encode(self.size, forKey: .size)
            
            var forceOpen = self.forceOpen
            
            if let limit = self.limit {
                forceOpen = true
                
                switch limit {
                case .position(let level): try container.encode(level, forKey: .limitLevel)
                case .distance(let distance): try container.encode(distance, forKey: .limitDistance)
                }
            }
            
            if let stop = self.stop {
                switch stop {
                case .position(let level, let isGuaranteed):
                    forceOpen = true
                    try container.encode(level, forKey: .stopLevel)
                    try container.encode(isGuaranteed, forKey: .isGuaranteedStop)
                case .distance(let distance, let isGuaranteed):
                    forceOpen = true
                    try container.encode(distance, forKey: .stopDistance)
                    try container.encode(isGuaranteed, forKey: .isGuaranteedStop)
                case .trailing(let distance, let increment):
                    try container.encode(false, forKey: .isGuaranteedStop)
                    try container.encode(true, forKey: .isTrailingStop)
                    try container.encode(distance, forKey: .stopDistance)
                    try container.encode(increment, forKey: .trailingStopIncrement)
                }
            } else {
                try container.encode(false, forKey: .isGuaranteedStop)
            }
            
            try container.encode(forceOpen, forKey: .forceOpen)
            try container.encode(self.reference, forKey: .reference)
        }
        
        private enum CodingKeys: String, CodingKey {
            case epic, expiry
            case currency = "currencyCode"
            case direction
            case order = "orderType", level, quoteId
            case fillStrategy = "timeInForce"
            case size
            case limitLevel, limitDistance
            case stopLevel, stopDistance, isGuaranteedStop = "guaranteedStop"
            case isTrailingStop = "trailingStop", trailingStopIncrement
            case forceOpen
            case reference = "dealReference"
        }
    }
    
    /// Identification mechanism at deletion time.
    public enum Identification {
        /// Permanent deal identifier for a confirmed trade.
        case identifier(API.Position.Identifier)
        /// Instrument epic identifier.
        case epic(Epic, expiry: API.Expiry)
    }
    
    private struct PayloadDeletion: Encodable {
        let identification: API.Request.Positions.Identification
        let direction: API.Position.Direction
        let order: API.Position.Order
        let strategy: API.Position.Order.Strategy
        let size: Double
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Self.CodingKeys.self)
            switch self.identification {
            case .identifier(let identifier):
                try container.encode(identifier, forKey: .identifier)
            case .epic(let epic, let expiry):
                try container.encode(epic, forKey: .epic)
                try container.encode(expiry, forKey: .expiry)
            }
            
            try container.encode(self.direction, forKey: .direction)
            try container.encode(self.order.rawValue, forKey: .order)
            switch order {
            case .limit(level: let level):
                try container.encode(level, forKey: .level)
            case .market:
                break
            case .quote(id: let quoteId, level: let level):
                try container.encode(quoteId, forKey: .quoteId)
                try container.encode(level, forKey: .level)
            }
            
            try container.encode(self.strategy, forKey: .fillStrategy)
            try container.encode(self.size, forKey: .size)
        }
        
        private enum CodingKeys: String, CodingKey {
            case identifier = "dealId"
            case epic, expiry
            case direction
            case order = "orderType", level, quoteId
            case fillStrategy = "timeInForce"
            case size
        }
    }
}

extension API.Position.Order {
    /// The representation understood by the server.
    fileprivate var rawValue: String {
        switch self {
        case .market: return "MARKET"
        case .limit: return "LIMIT"
        case .quote(_): return "QUOTE"
        }
    }
}

// MARK: Response Entities

extension API.Request.Positions {
    private struct WrapperReference: Decodable {
        let dealReference: API.Position.Reference
    }

    private struct PayloadUpdate: Encodable {
        let limit: Double?
        let stop: (level: Double, trailing: (distance: Double, increment: Double)?)?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Self.CodingKeys.self)
            
            if let limit = self.limit {
                try container.encodeIfPresent(limit, forKey: .limitLevel)
            } else {
                try container.encodeNil(forKey: .limitLevel)
            }
            
            guard let stop = self.stop else {
                try container.encodeNil(forKey: .stopLevel)
                try container.encode(false, forKey: .isTrailingStop)
                try container.encodeNil(forKey: .trailingStopDistance)
                return try container.encodeNil(forKey: .trailingStopIncrement)
            }
            
            try container.encode(stop.level, forKey: .stopLevel)
            guard let trailing = stop.trailing else {
                try container.encode(false, forKey: .isTrailingStop)
                try container.encodeNil(forKey: .trailingStopDistance)
                return try container.encodeNil(forKey: .trailingStopIncrement)
            }
            
            try container.encode(trailing.distance, forKey: .trailingStopDistance)
            try container.encode(trailing.increment, forKey: .trailingStopIncrement)
        }
        
        private enum CodingKeys: String, CodingKey {
            case limitLevel, stopLevel
            case isTrailingStop = "trailingStop"
            case trailingStopDistance
            case trailingStopIncrement
        }
    }
}
