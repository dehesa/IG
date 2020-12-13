import Foundation
import Decimals

extension Streamer {
    /// Confirmation data returned just after opening a position or a working order.
    public struct Confirmation {
        /// Transaction date.
        public let date: Date
        /// Transaction configuration values.
        public let deal: Self.Deal
        /// Position/WorkingOrder details.
        public let details: Self.Details
    }
}

extension Streamer.Confirmation {
    /// Overarching deal configuration values.
    public struct Deal: Identifiable {
        /// Deal identifier.
        public let id: IG.Deal.Identifier
        /// Transient deal reference for an unconfirmed trade.
        public let reference: IG.Deal.Reference
        /// Affected deals.
        public let affectedDeals: [Streamer.Confirmation.AffectedDeal]
        /// Deal status (whether the operation has been accepted or rejected).
        public let status: Self.Status
    }
    
    /// Deals affected by the overarching transaction.
    public struct AffectedDeal: Identifiable {
        /// Identifier for the affected deal.
        public let id: IG.Deal.Identifier
        /// Status for affected deal.
        public let status: IG.Deal.Status
    }
}

extension Streamer.Confirmation.Deal {
    /// The confirmation status.
    ///
    /// The optional `details`' properties will be set or they will be `nil`, depending on whether this value is accepted or rejected.
    public enum Status: Equatable {
        /// The deal this confirmation is pointing to has been accepted.
        case accepted
        /// The deal this confirmation is pointing to has been rejected.
        case rejected(reason: RejectionReason?)
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.accepted, .accepted), (.rejected, .rejected): return true
            default: return false
            }
        }
    }
}

extension Streamer.Confirmation {
    /// The confirmation details. Many of its property will be `nil` if the overarching deal has been rejected.
    public struct Details {
        /// Instrument epic identifier.
        public let epic: IG.Market.Epic
        /// Instrument expiration period.
        public let expiry: IG.Market.Expiry?
        /// The position/workingOrder status.
        public let status: IG.Deal.Status?
        /// Deal direction.
        public let direction: IG.Deal.Direction
        /// The deal size.
        public let size: Decimal64?
        /// Instrument price.
        public let level: Decimal64?
        /// The level (i.e. instrument's price) at which the user is happy to "take profit".
        public let limit: IG.Deal.Boundary?
        /// The level at which the user doesn't want to incur more losses.
        public let stop: (type: IG.Deal.Boundary, risk: IG.Deal.Stop.Risk, trailing: IG.Deal.Stop.Trailing)?
        /// Profit (value and currency).
        public let profit: IG.Deal.ProfitLoss?
        /// User channel.
        public let channel: String
    }
}

// MARK: -

extension Streamer.Confirmation: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.date = try container.decode(Date.self, forKey: .date, with: DateFormatter.iso8601)
        self.deal = try .init(from: decoder)
        self.details = try .init(from: decoder)
    }
    
    private enum _Keys: String, CodingKey {
        case date
    }
}

extension Streamer.Confirmation.Deal: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.id = try container.decode(IG.Deal.Identifier.self, forKey: .dealId)
        self.reference = try container.decode(IG.Deal.Reference.self, forKey: .dealReference)
        switch try container.decode(String.self, forKey: .dealStatus) {
        case "ACCEPTED": self.status = .accepted
        case "REJECTED": self.status = .rejected(reason: try container.decodeIfPresent(Self.Status.RejectionReason.self, forKey: .reason))
        case let value: throw DecodingError.dataCorruptedError(forKey: .dealStatus, in: container, debugDescription: "The confirmation deal status '\(value)' is not supported.")
        }
        self.affectedDeals = try container.decode([Streamer.Confirmation.AffectedDeal].self, forKey: .affectedDeals)
    }
    
    private enum _Keys: String, CodingKey {
        case dealId, dealReference, dealStatus, reason, affectedDeals
    }
}

extension Streamer.Confirmation.AffectedDeal: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id = "dealId", status
    }
}

extension Streamer.Confirmation.Details: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _Keys.self)
        self.status = try container.decodeIfPresent(IG.Deal.Status.self, forKey: .status)
        self.epic = try container.decode(IG.Market.Epic.self, forKey: .epic)
        self.expiry = try container.decodeIfPresent(IG.Market.Expiry.self, forKey: .expiry)
        self.direction = try container.decode(IG.Deal.Direction.self, forKey: .direction)
        self.size = try container.decodeIfPresent(Decimal64.self, forKey: .size)
        self.level = try container.decodeIfPresent(Decimal64.self, forKey: .level)
        
        switch (try container.decodeIfPresent(Decimal64.self, forKey: .limitLevel), try container.decodeIfPresent(Decimal64.self, forKey: .limitDistance)) {
        case (.none, .none): self.limit = nil
        case (let l?, .none): self.limit = .level(l)
        case (.none, let d?): self.limit = .distance(d)
        default: throw DecodingError.dataCorruptedError(forKey: .limitLevel, in: container, debugDescription: "Invalid limit.")
        }
        
        let stop: IG.Deal.Boundary?
        switch (try container.decodeIfPresent(Decimal64.self, forKey: .stopLevel), try container.decodeIfPresent(Decimal64.self, forKey: .stopDistance)) {
        case (.none, .none): stop = nil
        case (let l?, .none): stop = .level(l)
        case (.none, let d?): stop = .distance(d)
        default: throw DecodingError.dataCorruptedError(forKey: .stopLevel, in: container, debugDescription: "Invalid stop.")
        }
        
        if let stop = stop {
            let risk: IG.Deal.Stop.Risk = (try container.decode(Bool.self, forKey: .isStopGuaranteed)) ? .limited : .exposed
            let trailing: IG.Deal.Stop.Trailing = (try container.decode(Bool.self, forKey: .isStopTrailing)) ? .dynamic : .static
            self.stop = (stop, risk, trailing)
        } else { self.stop = nil }
        
        switch (try container.decodeIfPresent(Decimal64.self, forKey: .profitValue), try container.decodeIfPresent(Currency.Code.self, forKey: .profitCurrency)) {
        case (let v?, let c?): self.profit = .init(value: v, currency: c)
        case (.none, .none): self.profit = nil
        case (.none, .some), (.some, .none): throw DecodingError.dataCorruptedError(forKey: .profitValue, in: container, debugDescription: "Invalid P&L. Both the value and currency must be set at the same time.")
        }
        
        self.channel = try container.decode(String.self, forKey: .channel)
    }
    
    private enum _Keys: String, CodingKey {
        case status
        case epic, expiry
        case direction
        case size, level
        case limitLevel, limitDistance
        case stopLevel, stopDistance, isStopGuaranteed = "guaranteedStop", isStopTrailing = "trailingStop"
        case profitValue = "profit", profitCurrency = "profitCurrency"
        case channel
    }
}

extension Streamer.Confirmation.Deal.Status {
    /// Description of trading operation error.
    public enum RejectionReason: String, Equatable, Decodable {
        /// The operation resulted in an unknown result condition. Check transaction history or contact support for further information.
        case unknown = "UNKNOWN"
        /// An error has occurred but no detailed information is available. Check transaction history or contact support for further information.
        case generalError = "GENERAL_ERROR"
        
        /// The deal has been rejected because of an existing position. Either set the 'force open' to be true or cancel opposing position.
        case alreadyExistingPosition = "POSITION_ALREADY_EXISTS_IN_OPPOSITE_DIRECTION"
        /// The epic is due to expire shortly, client should deal in the next available contract.
        case closingMarket = "MARKET_CLOSING"
        /// The market is currently closed.
        case closedMarket = "MARKET_CLOSED"
        /// The market is currently closed with edits.
        case closedMarketEdits = "MARKET_CLOSED_WITH_EDITS"
        /// Resubmitted request does not match the original order.
        case conflictingOrder = "CONFLICTING_ORDER"
        /// The account is not enabled to trade
        case disabledAccount = "ACCOUNT_NOT_ENABLED_TO_TRADING"
        /// The order has been rejected as it is a duplicate of a previously issued order.
        case duplicatedOrder = "DUPLICATE_ORDER_ERROR"
        /// Exchange check failed. Please call in for assistance.
        case failedExchanged = "EXCHANGE_MANUAL_OVERRIDE"
        /// Cannot close this position. Either the position no longer exists, or the size available to close is less than the size specified.
        case failedPositionClose = "POSITION_NOT_AVAILABLE_TO_CLOSE"
        /// Invalid attempt to submit a spreadbet trade on a CFD account.
        case failedSpreadbetOpen = "REJECT_SPREADBET_ORDER_ON_CFD_ACCOUNT"
        /// The requested market was not found.
        case instrumentNotFound = "INSTRUMENT_NOT_FOUND"
        /// The account has not enough funds available for the requested trade.
        case insufficientFunds = "INSUFFICIENT_FUNDS"
        /// The requested operation has been attempted on the wrong direction.
        case invalidDirection = "WRONG_SIDE_OF_MARKET"
        /// Order expiry is less than the sprint market's minimum expiry. Check the sprint market's market details for the allowable expiries.
        case invalidExpirationDateMinimum = "EXPIRY_LESS_THAN_SPRINT_MARKET_MIN_EXPIRY"
        /// The expiry of the position would have fallen after the closing time of the market.
        case invalidExpirationDatePlace = "SPRINT_MARKET_EXPIRY_AFTER_MARKET_CLOSE"
        /// The working order has been set to expire on a past date.
        case invalidGoodTillDate = "GOOD_TILL_DATE_IN_THE_PAST"
        /// Instrument has an error.
        ///
        /// Check the order's currency is the instrument's currency (see the market's details); otherwise please contact support.
        case invalidInstrument = "CONTACT_SUPPORT_INSTRUMENT_ERROR"
        /// The limit level you have requested is closer to the market level than the existing stop. When the market is closed you can only move the limit order further away from the current market level.
        case invalidLevelLimitAway = "MOVE_AWAY_ONLY_LIMIT"
        /// The deal has been rejected because the limit level is inconsistent with current market price given the direction.
        case invalidLevelLimitWrongSide = "LIMIT_ORDER_WRONG_SIDE_OF_MARKET"
        /// The stop level you have requested is closer to the market level than the existing stop level. When the market is closed you can only move the stop level further away from the current market level.
        case invalidLevelStopAway = "MOVE_AWAY_ONLY_STOP"
        /// The market level has moved and has been rejected
        case invalidMarketLevel = "LEVEL_TOLERANCE_ERROR"
        /// Order declined during margin checks Check available funds.
        case invalidMargin = "MARGIN_ERROR"
        /// The order level you have requested is moving closer to the market level than the exisiting order level. When the market is closed you can only move the order further away from the current market level.
        case invalidOrderLevelAway = "MOVE_AWAY_ONLY_TRIGGER_LEVEL"
        /// The level of the attached stop or limit is not valid.
        case invalidOrderLevel = "ATTACHED_ORDER_LEVEL_ERROR"
        /// Invalid attempt to submit a CFD trade on a spreadbet account.
        case invalidOrderCFD = "REJECT_CFD_ORDER_ON_SPREADBET_ACCOUNT"
        /// Opening CR position in opposite direction to existing CR position not allowed.
        case invalidPositionCR = "OPPOSING_DIRECTION_ORDERS_NOT_ALLOWED"
        /// The order size exceeds the instrument's maximum configured value for auto-hedging the exposure of a deal.
        case invalidSizeMax = "MAX_AUTO_SIZE_EXCEEDED"
        /// The order size is too small.
        case invalidSizeMin = "MINIMUM_ORDER_SIZE_ERROR"
        /// Sorry we are unable to process this order. The stop or limit level you have requested is not a valid trading level in the underlying market.
        case invalidSpace = "CR_SPACING"
        /// The submitted strike level is invalid.
        case invalidStrikeLevel = "STRIKE_LEVEL_TOLERANCE"
        /// The trailing stop value is invalid.
        case invalidTrailingStop = "ATTACHED_ORDER_TRAILING_STOP_ERROR"
        /// Cannot change the stop type.
        case immutableStopType = "CANNOT_CHANGE_STOP_TYPE"
        /// The manual order timeout limit has been reached.
        case manualOrderTimeout = "MANUAL_ORDER_TIMEOUT"
        /// The market is currently offline.
        case marketOffline = "MARKET_OFFLINE"
        /// The market has been rolled to the next period.
        case marketRolled = "MARKET_ROLLED"
        /// We are not taking opening deals on a Controlled Risk basis on this market.
        case openTradesUnavailable = "CLOSING_ONLY_TRADES_ACCEPTED_ON_THIS_MARKET"
        /// Order declined; please contact Support.
        case orderDeclined = "ORDER_DECLINED"
        /// The order is locked and cannot be edited by the user.
        case orderLocked = "ORDER_LOCKED"
        /// The order has not been found.
        case orderNotFound = "ORDER_NOT_FOUND"
        /// The total position size at this stop level is greater than the size allowed on this market. Please reduce the size of the order.
        case overflowSize = "OVER_NORMAL_MARKET_SIZE"
        /// The total size of deals placed on this market in a short period has exceeded our limits. Please wait before attempting to open further positions on this market.
        case platformLimitReached = "FINANCE_REPEAT_DEALING"
        /// The market can only be traded over the phone.
        case phoneOnlyMarket = "MARKET_PHONE_ONLY"
        /// The position has not been found.
        case positionNotFound = "POSITION_NOT_FOUND"
        /// Ability to force open in different currencies on same market not allowed.
        case prohibitedForceOpen = "FORCE_OPEN_ON_SAME_MARKET_DIFFERENT_CURRENCY"
        /// The requested market is not allowed to this account.
        case prohibitedMarket = "MARKET_UNAVAILABLE_TO_CLIENT"
        /// The epic does not support 'Market' order type.
        case prohibitedMarketOrders = "MARKET_ORDERS_NOT_ALLOWED_ON_INSTRUMENT"
        /// The deal has been rejected to avoid having long and short open positions on the same market or having long and short open positions and working orders on the same epic.
        case prohibitedOpposingPositions = "OPPOSING_POSITIONS_NOT_ALLOWED"
        /// The market does not allow opening shorting positions.
        case prohibitedShorting = "MARKET_NOT_BORROWABLE"
        /// The market does not allow stop or limit attached orders.
        case prohibitStopLimit = "STOP_OR_LIMIT_NOT_ALLOWED"
        /// The order requires a stop.
        case requiredStop = "STOP_REQUIRED_ERROR"
        /// The market or the account do not allow for trailing stops.
        case prohibitedTrailingStop = "TRAILING_STOP_NOT_ALLOWED"
        /// Order size is not an increment of the value specified for the market.
        case sizeIncrement = "SIZE_INCREMENT"
        /// Position cannot be cancelled. Check transaction history or contact support for further information.
        case uncancellablePosition = "POSITION_NOT_AVAILABLE_TO_CANCEL"
        /// Position cannot be deleted as it has been partially closed.
        case unremovablePartiallyClosedPosition = "PARTIALY_CLOSED_POSITION_NOT_DELETED"
        /// Cannot remove the stop.
        case unremovableStop = "CANNOT_REMOVE_STOP"
        
        // Included here for completion purposes. It is received on a confirmation that has been accepted.
        // private static let success = "SUCCESS"
    }
}
