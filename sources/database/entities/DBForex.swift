import Foundation
import Decimals
import SQLite3

extension Database.Market {
    /// Database representation of a Foreign Exchange market.
    ///
    /// This structure is `Hashable` and `Equatable` for storage convenience purposes; however, the hash/equatable value is just the epic.
    public struct Forex: Hashable {
        /// Instrument identifier.
        public let epic: IG.Market.Epic
        /// The two currencies involved in this forex market.
        public let currencies: Self.Currencies
        /// Group of codes identifying this Forex market depending on context.
        public let identifiers: Self.Identifiers
        /// Basic information to calculate all values when dealing on this Forex market.
        public let information: Self.DealingInformation
        /// Restrictions while dealing on this market.
        public let restrictions: Self.Restrictions
    }
}

extension Database.Market.Forex {
    /// The base and counter currencies of a foreign exchange market.
    public struct Currencies: Equatable {
        /// The traditionally "strong" currency.
        public let base: Currency.Code
        /// The traditionally "weak" currency (on which the units are measured).
        public let counter: Currency.Code
    }
    
    /// Identifiers for a Forex markets.
    public struct Identifiers {
        /// Instrument name.
        public let name: String
        /// The name of a natural grouping of a set of IG markets.
        ///
        /// It typically represents the underlying 'real-world' market (normal and mini markets share the same identifier).
        /// This identifier is primarily used in our market research services, such as client sentiment, and may be found on the /market/{epic} service
        public let market: String
        /// Chart code.
        public let chart: String?
        /// Retuers news code.
        public let reuters: String
    }
    
    /// Specific information for the given Forex market.
    public struct DealingInformation {
        /// The amount of counter currency per contract.
        ///
        /// For example, the EUR/USD market has a contract size of $100,000 per contract.
        public let contractSize: Int
        /// Basic information about "Price Interest Point".
        public let pip: Self.Pip
        /// Number of decimal positions for market levels.
        public let levelDecimalPlaces: Int
        /// Slippage is the difference between the level of a stop order and the actual price at which it was executed.
        ///
        /// It can occur during periods of higher volatility when market prices move rapidly or gap
        /// - note: It is expressed as a percentage (e.g. 50%).
        public let slippageFactor: Decimal64
        /// Basic information about the "Guaranteed Stop" (or limited risk stop).
        public let guaranteedStop: Self.GuaranteedStop
        /// Margin information and requirements.
        public let margin: Self.Margin
        
        /// Price interest point.
        public struct Pip {
            /// What is the value of one pip (i.e. Price Interest Point).
            public let value: Int
            /// Number of decimal positions for pip representation.
            public let decimalPlaces: Int
        }
        
        /// Limited risk stop.
        public struct GuaranteedStop {
            /// The premium (indicated in points) "paid" for a *guaranteed stop*.
            public let premium: Decimal64
            /// The number of points to add on each side of the market as an additional spread when placing a guaranteed stop trade.
            public let extraSpread: Decimal64
        }
        
        /// Margin requirements and deposit bands.
        public struct Margin {
            /// Margin requirement factor.
            public let factor: Decimal64
            /// Deposit bands.
            ///
            /// Its value is always expressed on the *counter* currency.
            public let depositBands: Self.Bands
            
            /// A band is a collection of ranges and its associated deposit factos (in `%`).
            ///
            /// All ranges are `RangeExpression`s where `Bound` is set to `Decimal`. The last range is of `PartialRangeFrom` type (because it includes the lower bound till infinity), while all previous ones are of `Range` type.
            public struct Bands: RandomAccessCollection {
                public typealias Element = (range: Any, depositFactor: Decimal64)
                /// The underlying storage.
                fileprivate let storage: [_StoredElement]
            }
        }
    }
    
    /// Restrictions applied when dealing on a Forex market.
    public struct Restrictions {
        /// Minimum deal size (expressed in points).
        public let minimumDealSize: Decimal64
        /// Minimum and maximum distances for limits and normal stops
        internal let regularDistance: Self.Distance.Regular
        /// Minimum and maximum allowed stops (limited risk).
        public let guarantedStopDistance: Self.Distance.Variable
        /// Restrictions related to trailing stops.
        public let trailingStop: Self.TrailingStop
        
        /// Minimum and maximum allowed limits.
        public var limitDistance: Self.Distance.Regular { self.regularDistance }
        /// Minimum and maximum allowed stops (exposed risk).
        public var stopDistance: Self.Distance.Regular { self.regularDistance }
        
        /// Minimum and maximum values for diatances.
        public struct Distance {
            /// Distances where the minimum is always expressed in points and the maximum as percentage.
            public struct Regular {
                /// The minimum distance (expressed in pips).
                public let minimum: Decimal64
                /// The maximum allowed distance (expressed as percentage)
                public let maximumAsPercentage: Decimal64
            }
            /// Distances where the minimum can be expressed in points or percentage, but the maximum is always expressed in percentage.
            public struct Variable {
                /// The minimum distance (expressed in pips).
                public let minimumValue: Decimal64
                /// The unit on which the `minimumValue` is expressed as.
                public let minimumUnit: Database.Unit
                /// The maximum allowed distance (expressed as percentage)
                public let maximumAsPercentage: Decimal64
            }
        }
        
        /// Restrictions related to trailing stops.
        public struct TrailingStop {
            /// Whether trailing stops are available.
            public let isAvailable: Bool
            /// Minimum trailing stop increment expressed (in pips).
            public let minimumIncrement: Decimal64
        }
    }
}

extension Database.Market.Forex {
    /// Calculate the margin requirements for a given deal (identify by its size, price, and stop).
    ///
    /// IG may offer reduced margins on "tier 1" positions with a non-guaranteed stop (it doesn't apply to higher tiers/bands).
    /// - parameter size: The size of the targeted given deal.
    /// - parameter level: The price at which the deal will be opened.
    /// - parameter stop: The stop that will be used for the deal being operated.
    /// - returns: The margin requirement expressed as a value of the counter currency.
    public func margin(size: Decimal64, level: Decimal64, stop: Self.Stop?) -> Decimal64 {
        let marginFactor = self.information.margin.depositBands.depositFactor(size: size) >> 2
        let quantity = size * Decimal64(exactly: self.information.contractSize)!

        switch stop {
        case .none:
            return quantity * level * marginFactor
        case .level(let level, risk: .exposed):
            let distance = (level - level).magnitude
            let marginNoStop = quantity * level * marginFactor
            let marginWithStop = (marginNoStop * self.information.slippageFactor) + (quantity * distance)
            return min(marginNoStop, marginWithStop)
        case .level(let level, risk: .limited):
            let distance = (level - level).magnitude
            return (quantity * distance) + self.information.guaranteedStop.premium
        case .distance(let distance, risk: .exposed):
            let marginNoStop = quantity * level * marginFactor
            let marginWithStop = (marginNoStop * self.information.slippageFactor) + (quantity * distance)
            return min(marginNoStop, marginWithStop)
        case .distance(let distance, risk: .limited):
            return (quantity * distance) + self.information.guaranteedStop.premium
        }
    }
    
    /// The level/price at which the user doesn't want to incur more lose.
    public enum Stop: Equatable {
        /// Absolute value of the stop (e.g. 1.653 USD/EUR).
        case level(Decimal64, risk: IG.Deal.Stop.Risk = .exposed)
        /// Relative stop over an undisclosed reference level.
        case distance(Decimal64, risk: IG.Deal.Stop.Risk = .exposed)
    }
}

extension Database.Market.Forex.DealingInformation.Margin.Bands {
    /// Returns the deposit factor (expressed as a percentage `%`).
    /// - parameter size: The size of a given position.
    public func depositFactor(size: Decimal64) -> Decimal64 {
        var result = self.storage[0].value
        for element in self.storage {
            guard size >= element.lowerBound else { return result }
            result = element.value
        }
        return result
    }
    
    /// Returns the last band.
    public var last: (range: PartialRangeFrom<Decimal64>, depositFactor: Decimal64)? {
        self.storage.last.map { ($0.lowerBound..., $0.value) }
    }
}

extension Database.Market.Forex {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.epic)
    }
    
    public static func == (lhs: Database.Market.Forex, rhs: Database.Market.Forex) -> Bool {
        lhs.epic == rhs.epic
    }
}

// MARK: -

extension Database.Market.Forex: DBTable {
    internal static let tableName: String = Database.Market.tableName.appending("_Forex")
    
    internal static var tableDefinition: String {
        """
        CREATE TABLE \(Self.tableName) (
            epic       TEXT    NOT NULL UNIQUE CHECK( LENGTH(epic) BETWEEN 6 AND 30 ),
            base       TEXT    NOT NULL        CHECK( LENGTH(base) == 3 ),
            counter    TEXT    NOT NULL        CHECK( LENGTH(counter) == 3 ),

            name       TEXT    NOT NULL UNIQUE CHECK( LENGTH(name) > 0 ),
            marketId   TEXT    NOT NULL        CHECK( LENGTH(marketId) > 0 ),
            chartId    TEXT                    CHECK( LENGTH(chartId) > 0 ),
            reutersId  TEXT    NOT NULL        CHECK( LENGTH(reutersId) > 0 ),

            contSize   INTEGER NOT NULL        CHECK( contSize > 0 ),
            pipVal     INTEGER NOT NULL        CHECK( pipVal > 0 ),
            placePip   INTEGER NOT NULL        CHECK( placePip >= 0 ),
            placeLevel INTEGER NOT NULL        CHECK( placeLevel >= 0 ),
            slippage   INTEGER NOT NULL        CHECK( slippage >= 0 ),
            premium    INTEGER NOT NULL        CHECK( premium >= 0 ),
            extra      INTEGER NOT NULL        CHECK( extra >= 0 ),
            margin     INTEGER NOT NULL        CHECK( margin >= 0 ),
            bands      TEXT    NOT NULL        CHECK( LENGTH(bands) > 0 ),

            minSize    INTEGER NOT NULL        CHECK( minSize >= 0 ),
            minDista   INTEGER NOT NULL        CHECK( minDista >= 0 ),
            maxDista   INTEGER NOT NULL        CHECK( maxDista >= 0 ),
            minRisk    INTEGER NOT NULL        CHECK( minRisk >= 0 ),
            riskUnit   INTEGER NOT NULL        CHECK( trailing BETWEEN 0 AND 1 ),
            trailing   INTEGER NOT NULL        CHECK( trailing BETWEEN 0 AND 1 ),
            minStep    INTEGER NOT NULL        CHECK( minStep >= 0 ),

            CHECK( base != counter ),
            FOREIGN KEY(epic) REFERENCES Markets(epic)
        );
        """
    }
}

internal extension Database.Market.Forex {
    typealias Indices = (epic: Int32, base: Int32, counter: Int32, identifiers: Self.Identifiers.Indices, information: Self.DealingInformation.Indices, restrictions: Self.Restrictions.Indices)

    init(statement s: SQLite.Statement, indices: Indices = (0, 1, 2, (3, 4, 5, 6), (7, 8, 9, 10, 11, 12, 13, 14, 15), (16, 17, 18, 19, 20, 21, 22)) ) {
        self.epic = IG.Market.Epic(String(cString: sqlite3_column_text(s, indices.epic)))!
        self.currencies = .init(base:    Currency.Code(String(cString: sqlite3_column_text(s, indices.base)))!,
                                counter: Currency.Code(String(cString: sqlite3_column_text(s, indices.counter)))!)
        self.identifiers  = .init(statement: s, indices: indices.identifiers)
        self.information  = .init(statement: s, indices: indices.information)
        self.restrictions = .init(statement: s, indices: indices.restrictions)
    }

    func _bind(to statement: SQLite.Statement, indices: Indices = (1, 2, 3, (4, 5, 6, 7), (8, 9, 10, 11, 12, 13, 14, 15, 16), (17, 18, 19, 20, 21, 22, 23))) {
        sqlite3_bind_text(statement, indices.epic, self.epic.description, -1, SQLite.Destructor.transient)
        sqlite3_bind_text(statement, indices.base, self.currencies.base.description, -1, SQLite.Destructor.transient)
        sqlite3_bind_text(statement, indices.counter, self.currencies.counter.description, -1, SQLite.Destructor.transient)
        self.identifiers._bind(to: statement, indices: indices.identifiers)
        self.information._bind(to: statement, indices: indices.information)
        self.restrictions._bind(to: statement, indices: indices.restrictions)
    }
}

internal extension Database.Market.Forex.Identifiers {
    typealias Indices = (name: Int32, market: Int32, chart: Int32, reuters: Int32)

    init(statement: SQLite.Statement, indices: Indices) {
        self.name = String(cString: sqlite3_column_text(statement, indices.name))
        self.market = String(cString: sqlite3_column_text(statement, indices.market))
        self.chart = sqlite3_column_text(statement, indices.chart).map { String(cString: $0) }
        self.reuters = String(cString: sqlite3_column_text(statement, indices.reuters))
    }

    fileprivate func _bind(to statement: SQLite.Statement, indices: Indices) {
        sqlite3_bind_text(statement, indices.name, self.name, -1, SQLite.Destructor.transient)
        sqlite3_bind_text(statement, indices.market, self.market, -1, SQLite.Destructor.transient)
        self.chart.unwrap(none: { sqlite3_bind_null(statement, indices.chart) },
                          some: { sqlite3_bind_text(statement, indices.chart, $0, -1, SQLite.Destructor.transient) })
        sqlite3_bind_text (statement, indices.reuters, self.reuters, -1, SQLite.Destructor.transient)
    }
}

internal extension Database.Market.Forex.DealingInformation {
    typealias Indices = (contractSize: Int32, pipValue: Int32, pipPlaces: Int32, levelPlaces: Int32, slippage: Int32, premium: Int32, extra: Int32, factor: Int32, bands: Int32)

    init(statement: SQLite.Statement, indices: Indices) {
        self.contractSize = Int(sqlite3_column_int64(statement, indices.contractSize))
        self.pip = .init(value: Int(sqlite3_column_int64(statement, indices.pipValue)),
                         decimalPlaces: Int(sqlite3_column_int(statement, indices.pipPlaces)))
        self.levelDecimalPlaces = Int(sqlite3_column_int(statement, indices.levelPlaces))
        self.slippageFactor = Decimal64(sqlite3_column_int64(statement, indices.slippage), power: -1)!
        self.guaranteedStop = .init(premium: Decimal64(sqlite3_column_int64(statement, indices.premium), power: -2)!,
                                    extraSpread: Decimal64(sqlite3_column_int64(statement, indices.extra), power: -2)!)
        self.margin = .init(factor: Decimal64(sqlite3_column_int64(statement, indices.factor), power: -3)!,
                            depositBands: .init(underlying: String(cString: sqlite3_column_text(statement, indices.bands))))
    }

    fileprivate func _bind(to statement: SQLite.Statement, indices: Indices) {
        sqlite3_bind_int64(statement, indices.contractSize, Int64(self.contractSize))
        sqlite3_bind_int64(statement, indices.pipValue,     Int64(self.pip.value))
        sqlite3_bind_int  (statement, indices.pipPlaces,    Int32(self.pip.decimalPlaces))
        sqlite3_bind_int  (statement, indices.levelPlaces,  Int32(self.levelDecimalPlaces))
        sqlite3_bind_int64(statement, indices.slippage,     Int64(clamping: self.slippageFactor << 1))
        sqlite3_bind_int64(statement, indices.premium,      Int64(clamping: self.guaranteedStop.premium << 2))
        sqlite3_bind_int64(statement, indices.extra,        Int64(clamping: self.guaranteedStop.extraSpread << 2))
        sqlite3_bind_int64(statement, indices.factor,       Int64(clamping: self.margin.factor << 3))
        sqlite3_bind_text (statement, indices.bands, self.margin.depositBands.encode(), -1, SQLite.Destructor.transient)
    }
}

internal extension Database.Market.Forex.Restrictions {
    typealias Indices = (dealSize: Int32, minDistance: Int32, maxDistance: Int32, guaranteedStopDistance: Int32, guaranteedStopUnit: Int32, trailing: Int32, minStep: Int32)

    init(statement: SQLite.Statement, indices: Indices) {
        self.minimumDealSize = Decimal64(sqlite3_column_int64(statement, indices.dealSize), power: -2)!
        self.regularDistance = .init(minimum: Decimal64(sqlite3_column_int64(statement, indices.minDistance), power: -2)!,
                                     maximumAsPercentage: Decimal64(sqlite3_column_int64(statement, indices.maxDistance), power: -1)!)
        self.guarantedStopDistance = .init(minimumValue: Decimal64(sqlite3_column_int64(statement, indices.guaranteedStopDistance), power: -2)!,
                                           minimumUnit: Database.Unit(rawValue: Int(sqlite3_column_int(statement, indices.guaranteedStopUnit)))!,
                                           maximumAsPercentage: self.regularDistance.maximumAsPercentage)
        self.trailingStop = .init(isAvailable: Bool(sqlite3_column_int(statement, indices.trailing)),
                                  minimumIncrement: Decimal64(sqlite3_column_int64(statement, indices.minStep), power: -1)!)
    }

    fileprivate func _bind(to statement: SQLite.Statement, indices: Indices) {
        sqlite3_bind_int64(statement, indices.dealSize,               Int64(clamping: self.minimumDealSize << 2))
        sqlite3_bind_int64(statement, indices.minDistance,            Int64(clamping: self.regularDistance.minimum << 2))
        sqlite3_bind_int64(statement, indices.maxDistance,            Int64(clamping: self.regularDistance.maximumAsPercentage << 1))
        sqlite3_bind_int64(statement, indices.guaranteedStopDistance, Int64(clamping: self.guarantedStopDistance.minimumValue << 2))
        sqlite3_bind_int  (statement, indices.guaranteedStopUnit,     Int32(self.guarantedStopDistance.minimumUnit.rawValue))
        sqlite3_bind_int  (statement, indices.trailing,               Int32(self.trailingStop.isAvailable))
        sqlite3_bind_int64(statement, indices.minStep,                Int64(clamping: self.trailingStop.minimumIncrement << 1))
    }
}

// MARK: Margins

extension Database.Market.Forex.DealingInformation.Margin.Bands {
    fileprivate typealias _StoredElement = (lowerBound: Decimal64, value: Decimal64)
    /// The character separators used in encoding/decoding.
    private static let _separator: (numbers: Character, elements: Character) = (":", "|")

    /// Designated initializer.
    fileprivate init(underlying: String) {
        self.storage = underlying.split(separator: Self._separator.elements).map {
            let strings = $0.split(separator: Self._separator.numbers)
            precondition(strings.count == 2, "The given forex margin band '\(String($0))' is invalid since it contains \(strings.count) elements. Only 2 are expected")
            let lowerBound = Decimal64(String(strings[0]))!
            let factor = Decimal64(String(strings[1]))!
            return (lowerBound, factor)
        }

        precondition(!self.storage.isEmpty, "The given forex market since to have no margin bands. This behavior is not expected")
    }

    /// Encodes the receiving margin bands into a single `String`.
    fileprivate func encode() -> String {
        self.storage.map {
            var result = String()
            result.append($0.lowerBound.description)
            result.append(Self._separator.numbers)
            result.append($0.value.description)
            return result
        }.joined(separator: .init(Self._separator.elements))
    }

    public var startIndex: Int {
        self.storage.startIndex
    }

    public var endIndex: Int {
        self.storage.endIndex
    }

    public subscript(position: Int) -> (range: Any, depositFactor: Decimal64) {
        let element = self.storage[position]
        let nextIndex = position + 1
        if nextIndex < self.storage.endIndex {
            let (upperBound, _) = self.storage[nextIndex]
            return (element.lowerBound..<upperBound, element.value)
        } else {
            return (element.lowerBound..., element.value)
        }
    }

    public func index(before i: Int) -> Int {
        self.storage.index(before: i)
    }

    public func index(after i: Int) -> Int {
        self.storage.index(after: i)
    }
}

// MARK: API

extension Database.Market.Forex {
    /// Returns a Boolean indicating whether the given API market can be represented as a database Forex market.
    /// - parameter market: The market information received from the platform's server.
    internal static func isCompatible(market: API.Market) -> Bool {
        guard market.instrument.type == .currencies,
            let codes = Self._currencyCodes(from: market),
            codes.base != codes.counter else { return false }
        return true
    }

    /// Check whether the given API market instance is a valid Forex Database market and returns inferred values.
    /// - parameter market: The market information received from the platform's server.
    internal static func _inferred(from market: API.Market) -> Result<(base: Currency.Code, counter: Currency.Code, marketId: String, contractSize: Decimal64, guaranteedStopUnit: Database.Unit, bands: Self.DealingInformation.Margin.Bands),IG.Error> {
        // 1. Check the type is .currency
        guard market.instrument.type == .currencies else {
            return .failure(._inferralError(epic: market.instrument.epic, "is not of 'currency' type"))
        }

        // 2. Check that currencies can be actually inferred and they are not equal
        guard let currencies = Self._currencyCodes(from: market), currencies.base != currencies.counter else {
            return .failure(._inferralError(epic: market.instrument.epic, "is not of 'currency' type"))
        }
        // 3. Check the market identifier
        guard let marketId = market.id else {
            return .failure(._inferralError(epic: market.instrument.epic, "doesn't contain a market identifier"))
        }
        // 4. Check the contract size
        guard let contractSize = market.instrument.contractSize else {
            return .failure(._inferralError(epic: market.instrument.epic, "doesn't contain a contract size"))
        }
        // 5. Check the slippage factor unit
        guard market.instrument.slippageFactor.unit == .percentage else {
            return .failure(._inferralError(epic: market.instrument.epic, "has a slippage factor unit of '\(market.instrument.slippageFactor.unit)' when '.percentage' was expected"))
        }
        // 6. Check the guaranteed stop premium unit
        guard market.instrument.limitedRiskPremium.unit == .points else {
            return .failure(._inferralError(epic: market.instrument.epic, "has a limit risk premium unit of '\(market.instrument.limitedRiskPremium.unit)' when '.points' was expected"))
        }
        // 7. Check the margin unit
        guard market.instrument.margin.unit == .percentage else {
            return .failure(._inferralError(epic: market.instrument.epic, "has a margin unit of '\(market.instrument.margin.unit)' when '.percentage' was expected"))
        }
        // 8. Check the margin deposit bands
        let apiBands = market.instrument.margin.depositBands.sorted { $0.minimum < $1.minimum }

        guard let code = apiBands.first?.currency else {
            return .failure(._inferralError(epic: market.instrument.epic, "doesn't have margin bands"))
        }

        guard apiBands.allSatisfy({ $0.currency == code }) else {
            return .failure(._inferralError(epic: market.instrument.epic, "margin bands have different currency units"))
        }

        for index in 0..<apiBands.count-1 {
            guard let max = apiBands[index].maximum else {
                let representation = apiBands.map { "\($0.minimum)..<\($0.maximum.map { String(describing: $0) } ?? "max") \($0.currency) -> \($0.margin)%" }.joined(separator: ", ")
                return .failure(._inferralError(epic: market.instrument.epic, "expected a maximum at index '\(index)' for deposit bands [\(representation)]"))
            }

            guard max == apiBands[index+1].minimum else {
                let representation = apiBands.map { "\($0.minimum)..<\($0.maximum.map { String(describing: $0) } ?? "max") \($0.currency) -> \($0.margin)%" }.joined(separator: ", ")
                return .failure(._inferralError(epic: market.instrument.epic, "doesn't have contiguous deposit bands [\(representation)]"))
            }
        }

        let bands = Self.DealingInformation.Margin.Bands(storage: apiBands.map { ($0.minimum, $0.margin) })
        // 9. Check the minimum deal size units.
        guard market.rules.minimumDealSize.unit == .points else {
            return .failure(._inferralError(epic: market.instrument.epic, "has a minimum deal size unit of '\(market.rules.limit.mininumDistance.unit)' when '.points' was expected"))
        }

        // 10. Check the limit units (they are the same as the stop units).
        guard market.rules.limit.mininumDistance.unit == .points else {
            return .failure(._inferralError(epic: market.instrument.epic, "has a minimum limit distance unit of '\(market.rules.limit.mininumDistance.unit)' when '.points' was expected"))
        }

        guard market.rules.limit.maximumDistance.unit == .percentage else {
            return .failure(._inferralError(epic: market.instrument.epic, "has a maximum limit distance unit of '\(market.rules.limit.maximumDistance.unit)' when '.percentage' was expected"))
        }
        // 11. Check the guaranteed stop units.
        let unit: Database.Unit
        switch market.rules.stop.minimumLimitedRiskDistance.unit {
        case .points: unit = .points
        case .percentage: unit = .percentage
        }
        // 12. Check the trailing units.
        guard market.rules.stop.trailing.minimumIncrement.unit == .points else {
            return .failure(._inferralError(epic: market.instrument.epic, "has a minimum trailing step increment unit of '\(market.rules.stop.trailing.minimumIncrement.unit)' when '.points' was expected"))
        }

        return .success((currencies.base, currencies.counter, marketId, contractSize, unit, bands))
    }

    /// Returns the currencies for the given market.
    /// - parameter market: The market information received from the platform's server.
    private static func _currencyCodes(from market: API.Market) -> (base: Currency.Code, counter: Currency.Code)? {
        // A. The safest value is the pip meaning. However, it is not always there
        if let pip = market.instrument.pip?.meaning {
            // The pip meaning is divided in the meaning number and the currencies
            let components = pip.split(separator: " ")
            if components.count > 1 {
                let codes = components[1].split(separator: "/")
                if codes.count == 2, let counter = Currency.Code(String(codes[0])),
                    let base = Currency.Code(String(codes[1])) {
                    return (base, counter)
                }
            }
        }
        // B. Check the market identifier
        if let marketId = market.id, marketId.count == 6 {
            if let base = Currency.Code(String(marketId.prefix(3)) ),
                let counter = Currency.Code(String(marketId.suffix(3))) {
                return (base, counter)
            }
        }
        // C. Check the epic
        let epicSplit = market.instrument.epic.description.split(separator: ".")
        if epicSplit.count > 3 {
            let identifier = epicSplit[2]
            if let base = Currency.Code(String(identifier.prefix(3)) ),
                let counter = Currency.Code(String(identifier.suffix(3))) {
                return (base, counter)
            }
        }
        // Otherwise, return `nil` since the currencies couldn't be inferred.
        return nil
    }
}

private extension IG.Error {
    /// Error used on inferral functionality.
    static func _inferralError(epic: IG.Market.Epic, _ suffix: String) -> Self {
        Self(.database(.invalidRequest), "The API market '\(epic)' \(suffix)", help: "Review the returned error and try to fix the problem")
    }
}
