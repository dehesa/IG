import Foundation
import Decimals

extension Streamer {
    /// Open position data.
    public struct Update {
        /// The date at which the update has been generated/received.
        /// - attention: This is NOT the position creation date.
        public let date: Date
        /// Values related to deal representing the open position (and its origin if any).
        public let deal: Self.Deal
        /// The actual trade (whether a position or a working order).
        public let details: Self.Details
    }
}

extension Streamer.Update {
    /// Overarching deal representing an open position or a working order.
    public struct Deal: Identifiable {
        /// Permanent deal reference for a confirmed trade.
        public let id: IG.Deal.Identifier
        /// Transient deal reference for an unconfirmed trade.
        public let reference: IG.Deal.Reference
        /// Deal identifier of the originating deal.
        public let originId: IG.Deal.Identifier?
        /// The deal status.
        public let status: Self.Status
        
        /// The deal status.
        ///
        /// The optional `details`' properties will be set or they will be `nil`, depending on whether this value is accepted or rejected.
        public enum Status: Equatable {
            /// The deal has been accepted and the optional variables in `details` will be set.
            case accepted
            /// The deal status has been rejected. Check the `reason` for further information.
            case rejected(reason: String? = nil)
            
            public static func == (lhs: Self, rhs: Self) -> Bool {
                switch (lhs, rhs) {
                case (.accepted, .accepted), (.rejected, .rejected): return true
                default: return false
                }
            }
        }
    }
}

extension Streamer.Update {
    /// The details of the given trade.
    public struct Details {
        /// The position status.
        public let status: Self.Status
        /// The type of trade being updated.
        public let type: Self.Kind
        /// Instrument epic identifier.
        public let epic: IG.Market.Epic
        /// Instrument expiry period.
        public let expiry: IG.Market.Expiry
        /// Deal direction.
        public let direction: IG.Deal.Direction
        /// Deal size.
        public let size: Decimal64
        /// Level (instrument price) at which the position was openend.
        public let level: Decimal64
        /// The limit used on this deal (if any).
        public let limit: IG.Deal.Boundary?
        /// The stop used on this deal (if any).
        public let stop: (type: IG.Deal.Boundary, risk: IG.Deal.Stop.Risk)?
        /// User channel.
        public let channel: String
        
        /// The position status.
        public enum Status: Hashable {
            /// The targeted deal has been created/opened.
            case opened
            /// The targeted deal has been updated/amended.
            case updated
            /// The targeted deal has been deleted.
            case deleted
        }
        
        /// The trade type.
        public enum Kind {
            /// The deal references a market open position.
            case position
            /// The deal references a working order, not yet open as a position in the market.
            /// - parameter type: The working order type.
            /// - parameter expiration: Indicates when the working order expires if its triggers hasn't been met.
            /// - parameter currency: Working order currency ISO code.
            case workingOrder(_ type: IG.Deal.WorkingOrder, expiration: IG.Deal.WorkingOrder.Expiration, currency: Currency.Code?)
        }
    }
}

// MARK: -

extension Streamer.Update: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.date = try container.decode(Date.self, forKey: .date, with: .iso8601)
        self.deal = try .init(from: decoder)
        self.details = try .init(from: decoder)
    }
    
    private enum _Keys: String, CodingKey {
        case date = "timestamp"
    }
}

extension Streamer.Update.Deal: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.id = try container.decode(IG.Deal.Identifier.self, forKey: .dealId)
        self.reference = try container.decode(IG.Deal.Reference.self, forKey: .dealReference)
        self.originId = try container.decodeIfPresent(IG.Deal.Identifier.self, forKey: .dealIdOrigin)
        switch try container.decode(String.self, forKey: .dealStatus) {
        case "ACCEPTED": self.status = .accepted
        case "REJECTED": self.status = .rejected(reason: try container.decodeIfPresent(String.self, forKey: .reason))
        case let value: throw DecodingError.dataCorruptedError(forKey: .dealStatus, in: container, debugDescription: "Invalid deal status '\(value)'.")
        }
    }
    
    private enum _Keys: String, CodingKey {
        case dealId, dealReference, dealStatus, reason, dealIdOrigin
    }
}

extension Streamer.Update.Details: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.epic = try container.decode(IG.Market.Epic.self, forKey: .epic)
        self.expiry = try container.decode(IG.Market.Expiry.self, forKey: .expiry)
        
        switch try container.decode(String.self, forKey: .status) {
        case "OPEN": self.status = .opened
        case "UPDATED": self.status = .updated
        case "DELETED": self.status = .deleted
        case let value: throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Invalid OPU status '\(value)'.")
        }
        
        if let orderType = try container.decodeIfPresent(IG.Deal.WorkingOrder.self, forKey: .orderType) {
            let expiration: IG.Deal.WorkingOrder.Expiration
            switch try container.decode(String.self, forKey: .expiration) {
            case "GOOD_TILL_CANCELLED": expiration = .tillCancelled
            case "GOOD_TILL_DATE": expiration = .tillDate(try container.decode(Date.self, forKey: .expirationDate, with: DateFormatter.iso8601NoSeconds))
            case let value: throw DecodingError.dataCorruptedError(forKey: .expiration, in: container, debugDescription: "Invalid working order expiration '\(value)'.")
            }
            
            let currency = try container.decodeIfPresent(IG.Currency.Code.self, forKey: .currency)
            self.type = .workingOrder(orderType, expiration: expiration, currency: currency)
            self.limit = (try container.decodeIfPresent(Decimal64.self, forKey: .limitDistance)).map { .distance($0) }
            
            if let distance = try container.decodeIfPresent(Decimal64.self, forKey: .stopDistance) {
                self.stop = (.distance(distance), (try container.decode(Bool.self, forKey: .isStopGuaranteed)) ? .limited : .exposed)
            } else {
                self.stop = nil
            }
        } else {
            self.type = .position
            self.limit = (try container.decodeIfPresent(Decimal64.self, forKey: .limitLevel)).map { .level($0) }
            
            if let level = try container.decodeIfPresent(Decimal64.self, forKey: .stopLevel) {
                self.stop = (.level(level), (try container.decode(Bool.self, forKey: .isStopGuaranteed)) ? .limited : .exposed)
            } else {
                self.stop = nil
            }
        }
        
        self.direction = try container.decode(IG.Deal.Direction.self, forKey: .direction)
        self.size = try container.decode(Decimal64.self, forKey: .size)
        self.level = try container.decode(Decimal64.self, forKey: .level)
        self.channel = try container.decode(String.self, forKey: .channel)
    }
    
    private enum _Keys: String, CodingKey {
        case epic, expiry, status
        case orderType, expiration = "timeInForce", expirationDate = "goodTillDateISO", currency
        case limitLevel, limitDistance
        case stopLevel, stopDistance, isStopGuaranteed = "guaranteedStop"
        case direction, size, level, channel
    }
}
