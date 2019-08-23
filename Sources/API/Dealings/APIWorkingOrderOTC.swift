import ReactiveSwift
import Foundation

extension API.Request.WorkingOrders {
    
    // MARK: POST /workingorders/otc
    
    /// Creates an OTC working order.
    /// - parameter epic: Instrument epic identifer.
    /// - parameter expiry: The date (and sometimes "time") at which a spreadbet or CFD will automatically close against some predefined market value should the bet remain open beyond its last dealing time. Some CFDs do not expire.
    /// - parameter currency: The currency code (3 letters).
    /// - parameter direction: Deal direction (whether buy or sell).
    /// - parameter type: The working order type.
    /// - parameter size: Deal size. Precision shall not be more than 12 decimal places.
    /// - parameter level: Price at which to execute the working order.
    /// - parameter limit: The limit level/distance at which the user will like to take profit once the working order has been transformed into a position.
    /// - parameter stop: The stop level/distance at which the user doesn't want to incur more losses once the working order has been transformed into a position. Trailing stops are not allowed on working orders.
    /// - parameter forceOpen: Enabling force open when creating a new position or working order will enable a second position to be opened on a market.
    /// - parameter expiration: Indicates when the working order expires if its triggers hasn't been met.
    /// - parameter reference: A user-defined reference (e.g. `RV3JZ2CWMHG1BK`) identifying the submission of the order. If `nil` a reference will be created by the server and return as the result of this enpoint.
    /// - returns: The transient deal reference (for an unconfirmed trade) wrapped in a SignalProducer's value.
    public func create(epic: IG.Epic, expiry: IG.Deal.Expiry = .none, currency: IG.Currency.Code, direction: IG.Deal.Direction,
                       type: API.WorkingOrder.Kind, size: Decimal, level: Decimal, limit: IG.Deal.Limit?, stop: (type: IG.Deal.Stop.Kind, risk: IG.Deal.Stop.Risk)?, forceOpen: Bool = true,
                       expiration: API.WorkingOrder.Expiration, reference: IG.Deal.Reference? = nil) -> SignalProducer<IG.Deal.Reference,API.Error> {
        return SignalProducer(api: self.api) { (_) -> Self.PayloadCreation in
                return try .init(epic: epic, expiry: expiry, currency: currency, direction: direction, type: type, size: size, level: level, limit: limit, stop: stop, forceOpen: forceOpen, expiration: expiration, reference: reference)
            }.request(.post, "workingorders/otc", version: 2, credentials: true, body: { (_, payload) in
                let data = try JSONEncoder().encode(payload)
                return (.json, data)
            }).send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (w: Self.WrapperReference) in w.dealReference }
    }
    
    // MARK: PUT /workingorders/otc/{dealId}
    
    /// Updates an OTC working order.
    /// - parameter identifier: A permanent deal reference for a confirmed working order.
    /// - parameter type: The working order type.
    /// - parameter level: Price at which to execute the working order.
    /// - parameter limit: Passing a value, will set a limit level (replacing the previous one, if any). Setting this argument to `nil` will delete the limit on the working order.
    /// - parameter stop: Passing a value will set a stop level (replacing the previous one, if any). Setting this argument to `nil` will delete the stop working order.
    /// - parameter expiration: The time at which the working order deletes itself.
    /// - returns: The transient deal reference (for an unconfirmed trade) wrapped in a SignalProducer's value.
    public func update(identifier: IG.Deal.Identifier, type: API.WorkingOrder.Kind, level: Decimal, limit: IG.Deal.Limit?, stop: IG.Deal.Stop.Kind?, expiration: API.WorkingOrder.Expiration) -> SignalProducer<IG.Deal.Reference,API.Error> {
        return SignalProducer(api: self.api) { (_) -> Self.PayloadUpdate in
                return try .init(type: type, level: level, limit: limit, stop: stop, expiration: expiration)
            }.request(.put, "workingorders/otc/\(identifier.rawValue)", version: 2, credentials: true, body: { (_, payload) in
                let data = try JSONEncoder().encode(payload)
                return (.json, data)
            }).send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (w: Self.WrapperReference) in w.dealReference }
    }
    
    // MARK: DELETE /workingorders/otc/{dealId}
    
    /// Deletes an OTC working order.
    /// - parameter identifier: A permanent deal reference for a confirmed working order.
    public func delete(identifier: IG.Deal.Identifier) -> SignalProducer<IG.Deal.Reference,API.Error> {
        return SignalProducer(api: self.api)
            .request(.delete, "workingorders/otc/\(identifier.rawValue)", version: 2, credentials: true)
            .send(expecting: .json)
            .validateLadenData(statusCodes: 200)
            .decodeJSON()
            .map { (w: Self.WrapperReference) in w.dealReference }
    }
    
}

// MARK: - Supporting Entities

extension API.Request.WorkingOrders {
    private struct PayloadCreation: Encodable {
        let epic: IG.Epic
        let expiry: IG.Deal.Expiry
        let currency: IG.Currency.Code
        let direction: IG.Deal.Direction
        let type: API.WorkingOrder.Kind
        let level: Decimal
        let size: Decimal
        let limit: IG.Deal.Limit?
        let stop: IG.Deal.Stop?
        let forceOpen: Bool
        let expiration: API.WorkingOrder.Expiration
        let reference: IG.Deal.Reference?
        
        init(epic: IG.Epic, expiry: IG.Deal.Expiry, currency: IG.Currency.Code, direction: IG.Deal.Direction, type: API.WorkingOrder.Kind, size: Decimal, level: Decimal, limit: IG.Deal.Limit?, stop: (type: IG.Deal.Stop.Kind, risk: IG.Deal.Stop.Risk)?, forceOpen: Bool, expiration: API.WorkingOrder.Expiration, reference: IG.Deal.Reference?) throws {
            self.epic = epic
            self.expiry = expiry
            self.currency = currency
            self.direction = direction
            self.type = type
            self.size = try {
                guard size.isNormal, case .plus = size.sign else {
                    throw API.Error.invalidRequest("The position size number is invalid", suggestion: "The position size must be a positive valid number greater than zero").set { $0.context.append(("Working order size", size)) }
                }
                return size
            }()
            self.level = try {
                guard level.isFinite else {
                    throw API.Error.invalidRequest("The given working order level is invalid.", suggestion: "Input a valid number as level.").set { $0.context.append(("Working order level", level)) }
                }
                return level
            }()
            self.limit = try limit.map { (limit) in
                guard limit.isValid(on: direction, from: level) else {
                    throw API.Error.invalidRequest("The given limit is invalid.", suggestion: API.Error.Suggestion.validLimit).set { $0.context.append(("Working order limit", limit)) }
                }
                return limit
            }
            self.stop = try stop.map { (stop) in
                let entity: IG.Deal.Stop?
                switch stop.type {
                case .distance(let d): entity = IG.Deal.Stop.distance(d, risk: stop.risk, trailing: .static)
                case .position(let l): entity = IG.Deal.Stop.position(level: l, risk: stop.risk, trailing: .static, direction, from: l)
                }
                
                guard let result = entity else {
                    throw API.Error.invalidRequest("The given stop is invalid", suggestion: API.Error.Suggestion.validStop)
                }
                
                if case .limited = stop.risk, case .position = stop.type {
                    throw API.Error.invalidRequest("The given stop is invalid.", suggestion: #"Only working order's stop distances may be "guaranteed stops" (or limited risk)."#).set { $0.context.append(("Working order stop", stop)) }
                }
                
                return result
            }
            self.forceOpen = forceOpen
            self.expiration = try { // Check that the expiration date is at least one second later than now.
                if case .tillDate(let date) = expiration, date <= Date(timeIntervalSinceNow: 1) {
                    throw API.Error.invalidRequest("The working order expiration date is invalid", suggestion: "The expiration date must be later than the current date.").set { $0.context.append(("Working order expiration", date)) }
                }
                return expiration
            }()
            self.reference = reference
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Self.CodingKeys.self)
            try container.encode(self.epic, forKey: .epic)
            try container.encode(self.expiry, forKey: .expiry)
            try container.encode(self.currency, forKey: .currency)
            try container.encode(self.direction, forKey: .direction)
            try container.encode(self.type, forKey: .type)
            try container.encode(self.size, forKey: .size)
            try container.encode(self.level, forKey: .level)
            
            switch self.limit?.type {
            case .none: break
            case .position(let level): try container.encode(level, forKey: .limitLevel)
            case .distance(let dista): try container.encode(dista, forKey: .limitDistance)
            }
            
            if let stop = self.stop {
                switch stop.type {
                case .position(let level): try container.encode(level, forKey: .stopLevel)
                case .distance(let dista): try container.encode(dista, forKey: .stopDistance)
                }
                
                switch stop.risk {
                case .exposed: try container.encode(false, forKey: .isStopGuaranteed)
                case .limited: try container.encode(true,  forKey: .isStopGuaranteed)
                }
            } else {
                try container.encode(false, forKey: .isStopGuaranteed)
            }
            
            try container.encode(self.forceOpen, forKey: .forceOpen)
            
            switch self.expiration {
            case .tillCancelled:
                try container.encode(API.WorkingOrder.Expiration.CodingKeys.tillCancelled.rawValue, forKey: .expiration)
            case .tillDate(let date):
                try container.encode(API.WorkingOrder.Expiration.CodingKeys.tillDate.rawValue, forKey: .expiration)
                try container.encode(date, forKey: .expirationDate, with: API.Formatter.humanReadable)
            }
            try container.encodeIfPresent(self.reference, forKey: .reference)
        }
        
        private enum CodingKeys: String, CodingKey {
            case epic, expiry
            case currency = "currencyCode"
            case direction, type, size, level
            case limitLevel, limitDistance
            case stopLevel, stopDistance, isStopGuaranteed = "guaranteedStop"
            case forceOpen
            case expiration = "timeInForce"
            case expirationDate = "goodTillDate"
            case reference = "dealReference"
        }
    }
}

extension API.Request.WorkingOrders {
    private struct PayloadUpdate: Encodable {
        let type: API.WorkingOrder.Kind
        let level: Decimal
        let limit: IG.Deal.Limit?
        let stop: IG.Deal.Stop?
        let expiration: API.WorkingOrder.Expiration
        
        init(type: API.WorkingOrder.Kind, level: Decimal, limit: IG.Deal.Limit?, stop: IG.Deal.Stop.Kind?, expiration: API.WorkingOrder.Expiration) throws {
            // Check that the stop distance is a positive number (if it is set).
            if case .distance(let distance) = stop {
                guard distance.isNormal, case .plus = distance.sign else {
                    var error: API.Error = .invalidRequest("The given stop is invalid.", suggestion: "The stop distance must be a valid number and greater than zero.")
                    error.context.append(("Position stop distance", distance))
                    throw error
                }
            }
            // Check that the expiration date is at least one second later than now.
            if case .tillDate(let date) = expiration {
                guard date > Date(timeIntervalSinceNow: 1) else {
                    var error: API.Error = .invalidRequest("The working order expiration date is invalid", suggestion: "The expiration date must be later than the current date.")
                    error.context.append(("Working order expiration", date))
                    throw error
                }
            }
            self.type = type
            self.level = level
            self.limit = limit
            self.stop = try stop.map { (type) in
                let result: IG.Deal.Stop?
                switch type {
                case .position(let l): result = .position(level: l)
                case .distance(let d): result = .distance(d)
                }
                return try result ?! API.Error.invalidRequest("The given stop is invalid.", suggestion: API.Error.Suggestion.validStop).set { $0.context.append(("Working order stop", type)) }
            }
            self.expiration = expiration
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Self.CodingKeys.self)
            try container.encode(self.type, forKey: .type)
            try container.encode(self.level, forKey: .level)
            
            switch self.limit?.type {
            case .none: break
            case .position(let l): try container.encode(l, forKey: .limitLevel)
            case .distance(let d): try container.encode(d, forKey: .limitDistance)
            }
            
            switch stop?.type {
            case .none: break
            case .position(let l): try container.encode(l, forKey: .stopLevel)
            case .distance(let d): try container.encode(d, forKey: .stopDistance)
            }
            
            switch self.expiration {
            case .tillCancelled:
                try container.encode(API.WorkingOrder.Expiration.CodingKeys.tillCancelled.rawValue, forKey: .expiration)
            case .tillDate(let date):
                try container.encode(API.WorkingOrder.Expiration.CodingKeys.tillDate.rawValue, forKey: .expiration)
                try container.encode(date, forKey: .expirationDate, with: API.Formatter.humanReadable)
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case type, level
            case limitLevel, limitDistance
            case stopLevel, stopDistance
            case expiration = "timeInForce"
            case expirationDate = "goodTillDate"
        }
    }
}

// MARK: Response Entities

extension API.Request.WorkingOrders {
    private struct WrapperReference: Decodable {
        let dealReference: IG.Deal.Reference
    }
}
