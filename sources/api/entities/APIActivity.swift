import Foundation
import Decimals

extension API {
    /// A trading activity on the given account.
    public struct Activity {
        /// The date of the activity item.
        public let date: Date
        /// Activity description.
        public let summary: String
        /// Activity configuration values.
        public let deal: Self.Deal
        /// Activity details.
        public let details: Self.Details
    }
}

extension API.Activity {
    /// Overarching deal configuration values.
    public struct Deal: Identifiable {
        /// Deal identifier.
        public let id: IG.Deal.Identifier
        /// Transient deal reference for an unconfirmed trade.
        public let reference: IG.Deal.Reference?
        /// Deal affected by an activity.
        public let actions: [API.Activity.Action]
        /// Action status.
        public let status: Self.Status
        
        /// Activity status.
        ///
        /// The optional `details`' properties will be set or they will be `nil`, depending on whether this value is accepted or rejected.
        public enum Status: Hashable {
            /// The activity has been accepted.
            case accepted
            /// The activity has been rejected.
            case rejected
            /// The activity status is unknown.
            case unknown
        }
    }
}

extension API.Activity {
    /// Deal affected by an activity.
    public struct Action {
        /// Affected deal identifier.
        public let dealId: IG.Deal.Identifier
        /// Action type.
        public let type: Self.Kind
        
        /// The action type.
        ///
        /// Refects who is the receiver of the action on what status has been changed to.
        public enum Kind: Hashable {
            /// The action affects a position and its status has been modified to the one given here.
            case position(status: API.Activity.Action.PositionStatus)
            /// The action affects a working order and its status has been modified to the one given here.
            /// - parameter status: The working order status (e.g. opened, amended, etc.).
            /// - parameter type: The type of working order (whether "limit" or "stop" order). If the status is `.deleted`, the `type` might be `nil`.
            case workingOrder(status: API.Activity.Action.WorkingOrderStatus, type: IG.Deal.WorkingOrder?)
            /// The action is of unknown character.
            case unknown
        }
        
        /// Position's action status.
        public enum PositionStatus: Hashable {
            /// The deal represents an open position creation.
            case opened
            /// A deal position stop and/or limit has been amended.
            case amendedBoundary
            /// The position has rolled for a fixed interval to the next.
            case rolled
            /// The position has been closed (partially or fully).
            case closed(Self.Completion)
            /// The position has been closed.
            case deleted
            /// The type of position closure.
            public enum Completion: Hashable {
                /// The position has only been partially closed (i.e. there are still remaining size.
                case partially
                /// The position has been fully closed.
                case fully
            }
        }
        
        /// Working order's action status.
        public enum WorkingOrderStatus: Hashable {
            /// The deal represents a working order creation.
            case opened
            /// A working order has been amended/updated (i.e. the level, limit, or stop has been changed).
            case amended
            /// The working order has rolled for a fixed interval to the next.
            case rolled
            /// The working order has been successfully filled and thus transformed into a position.
            case filled
            /// The working order has been deleted.
            case deleted
        }
    }
}

extension API.Activity {
    /// The details of the given activity object.
    public struct Details {
        /// Activity type.
        public let type: Self.Kind
        /// Instrument epic identifier.
        public let epic: IG.Market.Epic
        /// The period of the activity item.
        public let expiry: IG.Market.Expiry
        /// A financial market, which may refer to an underlying financial market, or the market being offered in terms of an IG instrument. IG instruments are organised in the form a navigable market hierarchy.
        public let marketName: String
        /// The currency denomination.
        public let currency: Currency.Code
        /// Deal direction.
        public let direction: IG.Deal.Direction
        /// Deal size.
        public let size: Decimal64
        /// Instrument price at which the activity has been "commited".
        ///
        /// If the deal has been accepted, this property always return a value. If the deal has been rejected, this property may be `nil` (although not in all cases).
        public let level: Decimal64?
        /// Level at which the user is happy to take profit.
        public let limit: (level: Decimal64, distance: Decimal64)?
        /// Stop for the targeted deal
        public let stop: (level: Decimal64, distance: Decimal64, risk: IG.Deal.Stop.Risk, trailing: IG.Deal.Stop.TrailingData)?
        /// The channel which triggered the activity.
        public let channel: Self.Channel
    }
}

extension API.Activity.Details {
    /// Activity Type.
    public enum Kind {
        /// Position activity.
        /// - parameter boundary: If `true`, the deal represent a change in the limit and/or stop exclusively.
        case position(boundary: Bool)
        /// Working order activity.
        /// - parameter expiration: The time at which the working order expires. When the hosting activity represents a working order deletion, `expiration` is `nil`.
        case workingOrder(expiration: IG.Deal.WorkingOrder.Expiration?)
        /// System generated activity.
        case system
    }
    
    /// Trigger channel.
    public enum Channel: Hashable {
        /// Activity performed through the platform's internal system.
        case system
        /// Activity performed through the platform's website.
        case web
        /// Activity performed through the mobile app.
        case mobile
        /// Activity performed through the API.
        case api
        /// Activity performed through an outside dealer.
        case dealer
        /// Activity performed through the financial FIX system.
        case fix
    }
}

// MARK: -

extension API.Activity: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        let formatter = try decoder.userInfo[API.JSON.DecoderKey.computedValues] as? DateFormatter ?> DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "No DateFormatter was found on the decoder's userInfo.")
        self.date = try container.decode(Date.self, forKey: .date, with: formatter)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.deal = try .init(from: decoder)
        self.details = try .init(from: decoder)
    }
    
    private enum _Keys: String, CodingKey {
        case date
        case summary = "description"
    }
}

extension API.Activity.Deal: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.id = try container.decode(IG.Deal.Identifier.self, forKey: .dealId)
        
        switch try container.decode(String.self, forKey: .dealStatus) {
        case "ACCEPTED": self.status = .accepted
        case "REJECTED": self.status = .rejected
        case "UNKNOWN":  self.status = .unknown
        case let value: throw DecodingError.dataCorruptedError(forKey: .dealStatus, in: container, debugDescription: "Invalid deal status '\(value)'.")
        }
        
        let detailsContainer = try container.nestedContainer(keyedBy: _Keys._DetailKeys.self, forKey: .details)
        self.reference = try detailsContainer.decodeIfPresent(IG.Deal.Reference.self, forKey: .dealReference)
        self.actions = try detailsContainer.decode([API.Activity.Action].self, forKey: .actions)
    }
    
    private enum _Keys: String, CodingKey {
        case dealId, dealStatus = "status"
        case details
        
        enum _DetailKeys: String, CodingKey {
            case dealReference, actions
        }
    }
}

extension API.Activity.Action: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.dealId = try container.decode(IG.Deal.Identifier.self, forKey: .dealId)

        switch try container.decode(String.self, forKey: .type) {
        case "POSITION_OPENED":           self.type = .position(status: .opened)
        case "POSITION_ROLLED":           self.type = .position(status: .rolled)
        case "STOP_LIMIT_AMENDED":        self.type = .position(status: .amendedBoundary)
        case "POSITION_PARTIALLY_CLOSED": self.type = .position(status: .closed(.partially))
        case "POSITION_CLOSED":           self.type = .position(status: .closed(.fully))
        case "POSITION_DELETED":          self.type = .position(status: .deleted)
        case "LIMIT_ORDER_OPENED":    self.type = .workingOrder(status: .opened,  type: .limit)
        case "LIMIT_ORDER_FILLED":    self.type = .workingOrder(status: .filled,  type: .limit)
        case "LIMIT_ORDER_AMENDED":   self.type = .workingOrder(status: .amended, type: .limit)
        case "LIMIT_ORDER_ROLLED":    self.type = .workingOrder(status: .rolled,  type: .limit)
        case "LIMIT_ORDER_DELETED":   self.type = .workingOrder(status: .deleted, type: .limit)
        case "STOP_ORDER_OPENED":     self.type = .workingOrder(status: .opened,  type: .stop)
        case "STOP_ORDER_FILLED":     self.type = .workingOrder(status: .filled,  type: .stop)
        case "STOP_ORDER_AMENDED":    self.type = .workingOrder(status: .amended, type: .stop)
        case "STOP_ORDER_ROLLED":     self.type = .workingOrder(status: .rolled,  type: .stop)
        case "STOP_ORDER_DELETED":    self.type = .workingOrder(status: .deleted, type: .stop)
        case "WORKING_ORDER_DELETED": self.type = .workingOrder(status: .deleted, type: nil)
        case "UNKNOWN":      self.type = .unknown
        case let type: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid action type '\(type)'.")
        }
    }

    private enum _Keys: String, CodingKey {
        case dealId = "affectedDealId"
        case type = "actionType"
    }
}

extension API.Activity.Details: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        let detailsContainer = try container.nestedContainer(keyedBy: _Keys._DetailKeys.self, forKey: .details)
        
        switch try container.decode(String.self, forKey: .type) {
        case "POSITION":            self.type = .position(boundary: false)
        case "EDIT_STOP_AND_LIMIT": self.type = .position(boundary: true)
        case "WORKING_ORDER":
            switch try detailsContainer.decodeIfPresent(String.self, forKey: .expiration) {
            case .none: self.type = .workingOrder(expiration: nil)
            case "GTC": self.type = .workingOrder(expiration: .tillCancelled)
            case let value?:
                guard let formatter = decoder.userInfo[API.JSON.DecoderKey.computedValues] as? DateFormatter else {
                    throw DecodingError.dataCorruptedError(forKey: .expiration, in: detailsContainer, debugDescription: "No DateFormatter was found on the decoder's userInfo.")
                }
                let date = try formatter.date(from: value) ?> DecodingError.dataCorruptedError(forKey: .expiration, in: detailsContainer, debugDescription: formatter.parseErrorLine(date: value))
                self.type = .workingOrder(expiration: .tillDate(date))
            }
        case "SYSTEM": self.type = .system
        case let value: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid activity type '\(value)'.")
        }
        
        self.epic = try container.decode(IG.Market.Epic.self, forKey: .epic)
        self.expiry = try container.decodeIfPresent(IG.Market.Expiry.self, forKey: .expiry) ?? .none
        
        switch try container.decode(String.self, forKey: .channel) {
        case "SYSTEM":         self.channel = .system
        case "WEB":            self.channel = .web
        case "MOBILE":         self.channel = .mobile
        case "PUBLIC_WEB_API": self.channel = .api
        case "DEALER":         self.channel = .dealer
        case "PUBLIC_FIX_API": self.channel = .fix
        case let value: throw DecodingError.dataCorruptedError(forKey: .channel, in: container, debugDescription: "Invalid activity channel '\(value)'.")
        }
        
        self.marketName = try detailsContainer.decode(String.self, forKey: .marketName)
        self.currency = try detailsContainer.decode(Currency.Code.self, forKey: .currency)
        self.direction = try detailsContainer.decode(IG.Deal.Direction.self, forKey: .direction)
        self.size = try detailsContainer.decode(Decimal64.self, forKey: .size)
        self.level = try detailsContainer.decodeIfPresent(Decimal64.self, forKey: .level)
        
        switch (try detailsContainer.decodeIfPresent(Decimal64.self, forKey: .limitLevel), try detailsContainer.decodeIfPresent(Decimal64.self, forKey: .limitDistance)) {
        case (.none, .none): self.limit = nil
        case (let l?, let d?): self.limit = (l, d)
        default: throw DecodingError.dataCorruptedError(forKey: .limitLevel, in: detailsContainer, debugDescription: "Invalid limit.")
        }
        
        if let stopLevel = try detailsContainer.decodeIfPresent(Decimal64.self, forKey: .stopLevel),
           let stopDistance = try detailsContainer.decodeIfPresent(Decimal64.self, forKey: .stopDistance) {
            let risk: IG.Deal.Stop.Risk = (try detailsContainer.decode(Bool.self, forKey: .isStopGuaranteed)) ? .limited : .exposed
            switch (try detailsContainer.decodeIfPresent(Decimal64.self, forKey: .stopTrailingDistance), try detailsContainer.decodeIfPresent(Decimal64.self, forKey: .stopTrailingIncrement)) {
            case (.none, .none): self.stop = (stopLevel, stopDistance, risk, .static)
            case (let d?, let i?): self.stop = (stopLevel, stopDistance, risk, .dynamic(distance: d, increment: i))
            default: throw DecodingError.dataCorruptedError(forKey: .stopTrailingDistance, in: detailsContainer, debugDescription: "Invalid trailing stop.")
            }
        } else { self.stop = nil }
    }
    
    private enum _Keys: String, CodingKey {
        case epic, expiry = "period"
        case type, channel
        case details
        
        enum _DetailKeys: String, CodingKey {
            case currency
            case direction, marketName, size
            case level, limitLevel, limitDistance
            case stopLevel, stopDistance, isStopGuaranteed = "guaranteedStop"
            case stopTrailingDistance = "trailingStopDistance", stopTrailingIncrement = "trailingStep"
            case expiration = "goodTillDate"
        }
    }
}
