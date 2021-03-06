import Combine
import Decimals
import Foundation

extension Streamer.Request {
    /// Contains all functionality related to Streamer accounts.
    @frozen public struct Accounts {
        /// Pointer to the actual Streamer instance in charge of calling the Lightstreamer server.
        private unowned let _streamer: Streamer
        /// Hidden initializer passing the instance needed to perform the endpoint.
        /// - parameter streamer: The instance calling the actual subscriptions.
        @usableFromInline internal init(streamer: Streamer) { self._streamer = streamer }
    }
}

extension Streamer.Request.Accounts {
    
    // MARK: ACCOUNT:ACCID
    
    /// Subscribes to the given account and returns in the response the specified attribute/fields.
    ///
    /// The only way to unsubscribe is to not hold the signal producer returned and have no active observer in the signal.
    /// - parameter account: The account identifier.
    /// - parameter fields: The account properties/fields bieng targeted.
    /// - parameter snapshot: Boolean indicating whether a "beginning" package should be sent with the current state of the market.
    /// - parameter queue: `DispatchQueue` processing the received values and where the value is forwarded. If `nil`, the internal `Streamer` queue will be used.
    /// - returns: Signal producer that can be started at any time.
    public func subscribe(account: IG.Account.Identifier, fields: Set<Streamer.Account.Field>, snapshot: Bool = true, queue: DispatchQueue? = nil) -> AnyPublisher<Streamer.Account,IG.Error> {
        let item = "ACCOUNT:\(account)"
        let properties = fields.map { $0.rawValue }
        
        return self._streamer.channel
            .subscribe(on: queue ?? self._streamer.queue, mode: .merge, items: [item], fields: properties, snapshot: snapshot)
            .tryMap { [fields] in try Streamer.Account(id: account, update: $0, fields: fields) }
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
}

// MARK: - Request Entities
    
extension Streamer.Account {
    /// Possible fields to subscribe to when querying account data.
    public enum Field: String, CaseIterable {
        /// Total cash balance on your account.
        case funds = "FUNDS"
        /// Amount cash available to trade value, after account balance, profit and loss, and minimum deposit amount have been considered.
        case cashAvailable = "AVAILABLE_CASH"
        /// Amount of cash available to trade.
        case tradeAvailable = "AVAILABLE_TO_DEAL"
        /// Account minimum deposit value required for margins.
        case deposit = "DEPOSIT"
        
        /// The amount required from a client (in addition to any deposit due) to cover losses when a price moves adversely.
        case margin = "MARGIN"
        /// Margin for limited risk.
        case marginLimitedRisk = "MARGIN_LR"
        /// Margin for non-limited risk.
        case marginNonLimitedRisk = "MARGIN_NLR"
        
        /// Net value of your account (`funds` plus or minus running profit/loss).
        case equity = "EQUITY"
        /// Percentage of `equity` used by `margin`.
        ///
        /// Your position could be automatically closed if this reaches 100%.
        case equityUsed = "EQUITY_USED"
        
        /// Account profit and loss value.
        case profitLoss = "PNL"
        /// Profit/Loss for limited risk.
        case profitLossLimitedRisk = "PNL_LR"
        /// Profit/Loss for non-limited risk.
        case profitLossNonLimitedRisk = "PNL_NLR"
    }
}

extension Set where Element == Streamer.Account.Field {
    /// Returns all queryable fields.
    @_transparent public static var all: Self {
        .init(Element.allCases)
    }
}
