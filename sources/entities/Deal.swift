import Decimals
import Foundation

/// Namespace for commonly used value/class types related to deals.
public enum Deal {
    /// Deal direction.
    @frozen public enum Direction: Hashable, CustomStringConvertible {
        /// Going "long"
        case buy
        /// Going "short"
        case sell
        
        /// Returns the opposite direction from the receiving direction.
        /// - returns: `.buy` if receiving is `.sell`, and `.sell` if receiving is `.buy`.
        public var oppossite: Direction {
            switch self {
            case .buy:  return .sell
            case .sell: return .buy
            }
        }
        
        public var description: String {
            switch self {
            case .buy: return "buy"
            case .sell: return "sell"
            }
        }
    }

    /// Position status.
    public enum Status: Hashable {
        /// A new deal has been created.
        case opened
        /// The targeted deal has been edited/updated.
        case amended
        /// The targeted deal has been partially or fully closed.
        case closed(Self.Completion)
        /// The targeted deal has been deleted.
        case deleted
        
        /// The completion status of a deal.
        ///
        /// A deal can be partially or fully closed.
        public enum Completion: Hashable {
            /// The target entity has only been partially closed.
            case partially
            /// The target entity has been fully closed.
            case fully
        }
    }

    /// Profit value and currency.
    public struct ProfitLoss {
        /// The actual profit value (it can be negative).
        public let value: Decimal64
        /// The profit currency.
        public let currency: Currency.Code
        
        /// Designated initializer.
        /// - parameter value: The profit value (can be negative).
        /// - parameter currency: The currency the value is framed on.
        internal init(value: Decimal64, currency: Currency.Code) {
            self.value = value
            self.currency = currency
        }
    }
    
    /// Working order type.
    public enum WorkingOrder: Hashable {
        /// An instruction to deal if the price moves to a more favourable level.
        ///
        /// This is an order to open a position by buying when the market reaches a lower level than the current price, or selling short when the market hits a higher level than the current price.
        /// This is suitable if you think the market price will **change direction** when it hits a certain level.
        case limit
        /// This is an order to buy when the market hits a higher level than the current price, or sell when the market hits a lower level than the current price.
        /// This is suitable if you think the market will continue **moving in the same direction** once it hits a certain level.
        case stop
        
        /// Describes when the working order will expire.
        @frozen public enum Expiration: Equatable {
            /// The order remains in place till it is explicitly cancelled.
            case tillCancelled
            /// The order remains in place till it is fulfill or the associated date is reached.
            case tillDate(Date)
        }
    }
}

// MARK: -

extension Deal.Direction: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case _Values.buy: self = .buy
        case _Values.sell: self = .sell
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid deal direction '\(value)'.")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .buy: try container.encode(_Values.buy)
        case .sell: try container.encode(_Values.sell)
        }
    }
    
    private enum _Values {
        static var buy: String { "BUY" }
        static var sell: String { "SELL"}
    }
}

extension Deal.Status: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "OPEN", "OPENED": self = .opened
        case "AMENDED": self = .amended
        case "PARTIALLY_CLOSED": self = .closed(.partially)
        case "FULLY_CLOSED", "CLOSED": self = .closed(.fully)
        case "DELETED": self = .deleted
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid deal status '\(value)'.")
        }
    }
}

extension IG.Deal.WorkingOrder: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case _Values.limit: self = .limit
        case _Values.stop: self = .stop
        case let value: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid working order type '\(value)'.")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .limit: try container.encode(_Values.limit)
        case .stop: try container.encode(_Values.stop)
        }
    }
    
    private enum _Values {
        static var limit: String { "LIMIT" }
        static var stop: String { "STOP" }
    }
}
