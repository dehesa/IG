import Combine
import Decimals
import SQLite3

extension Database.Request.Markets {
    /// Contains all functionality related to Database Forex.
    public struct Forex {
        /// Pointer to the actual database instance in charge of the low-level objects.
        fileprivate unowned let _database: Database
        /// Hidden initializer passing the instance needed to perform the database fetches/updates.
        internal init(database: Database) { self._database = database }
    }
}

extension Database.Request.Markets.Forex {
    /// Returns all forex markets.
    ///
    /// If there are no forex markets in the database yet, an empty array will be returned.
    public func getAll() -> AnyPublisher<[Database.Market.Forex],Database.Error> {
        self._database.publisher { _ in
                "SELECT * FROM \(Database.Market.Forex.tableName)"
            }.read { (sqlite, statement, query, _) in
                try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { .callFailed(.compilingSQL, code: $0) }
                
                var result: [Database.Market.Forex] = .init()
                while true {
                    switch sqlite3_step(statement).result {
                    case .row:  result.append(.init(statement: statement!))
                    case .done: return result
                    case let e: throw Database.Error.callFailed(.querying(Database.Market.Forex.self), code: e)
                    }
                }
            }.mapError(Database.Error.transform)
            .eraseToAnyPublisher()
    }
    
    /// Discrete publisher returning the markets stored in the database matching the given epics.
    ///
    /// Depending on the `expectsAll` argument, this method will return the exact number of market forex or a subset of them.
    /// - parameter epics: The forex market epics identifiers.
    /// - parameter expectsAll: Boolean indicating whether an error should be emitted if not all markets are in the database.
    public func get(epics: Set<IG.Market.Epic>, expectsAll: Bool) -> AnyPublisher<Set<Database.Market.Forex>,Database.Error> {
        self._database.publisher { _ -> String in
                let values = (1...epics.count).map { "?\($0)" }.joined(separator: ", ")
                return "SELECT * FROM \(Database.Market.Forex.tableName) WHERE epic IN (\(values))"
            }.read { (sqlite, statement, query, _) in
                var result: Set<Database.Market.Forex> = .init()
                guard !epics.isEmpty else { return result }
                
                try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { .callFailed(.compilingSQL, code: $0) }
                
                for (index, epic) in epics.enumerated() {
                    try sqlite3_bind_text(statement, Int32(index + 1), epic.rawValue, -1, SQLite.Destructor.transient).expects(.ok) { .callFailed(.bindingAttributes, code: $0) }
                }
                
                loop: while true {
                    switch sqlite3_step(statement).result {
                    case .row: result.insert(.init(statement: statement!))
                    case .done: break loop
                    case let e: throw Database.Error.callFailed(.querying(Database.Market.Forex.self), code: e)
                    }
                }
                
                guard (epics.count == result.count) || !expectsAll else {
                    throw Database.Error.invalidResponse(.valueNotFound, suggestion: .init("\(epics.count) were provided, however only \(result.count) were found"))
                }
                return result
            }.mapError(Database.Error.transform)
            .eraseToAnyPublisher()
    }
    
    /// Returns the market stored in the database matching the given epic.
    ///
    /// If the market is not in the database, a `.invalidResponse` error will be returned.
    /// - parameter epic: The forex market epic identifier.
    public func get(epic: IG.Market.Epic) -> AnyPublisher<Database.Market.Forex,Database.Error> {
        self._database.publisher { _ in
                "SELECT * FROM \(Database.Market.Forex.tableName) WHERE epic=?1"
            }.read { (sqlite, statement, query, _) in
                try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { .callFailed(.compilingSQL, code: $0) }

                try sqlite3_bind_text(statement, 1, epic.rawValue, -1, SQLite.Destructor.transient).expects(.ok) { .callFailed(.bindingAttributes, code: $0) }

                switch sqlite3_step(statement).result {
                case .row: return .init(statement: statement!)
                case .done: throw Database.Error.invalidResponse(.valueNotFound, suggestion: .valueNotFound)
                case let e: throw Database.Error.callFailed(.querying(Database.Market.Forex.self), code: e)
                }
            }.mapError(Database.Error.transform)
            .eraseToAnyPublisher()
    }
    
    /// Returns the forex markets matching the given currency.
    /// - parameter currency: A currency used as base or counter in the result markets.
    /// - parameter otherCurrency: A currency matching the first argument. It is optional.
    public func get(currency: Currency.Code, _ otherCurrency: Currency.Code? = nil) -> AnyPublisher<[Database.Market.Forex],Database.Error> {
        self._database.publisher { _ -> (query: String, binds: [(index: Int32, text: Currency.Code)]) in
                var sql = "SELECT * FROM \(Database.Market.Forex.tableName) WHERE "
            
                var binds: [(index: Int32, text: Currency.Code)] = [(1, currency)]
                switch otherCurrency {
                case .none:  sql.append("base=?1 OR counter=?1")
                case let c?: sql.append("(base=?1 AND counter=?2) OR (base=?2 AND counter=?1)")
                    binds.append((2, c))
                }
            
                return (sql, binds)
            }.read { (sqlite, statement, input, _) in
                try sqlite3_prepare_v2(sqlite, input.query, -1, &statement, nil).expects(.ok) { .callFailed(.compilingSQL, code: $0) }
                
                for (index, currency) in input.binds {
                    sqlite3_bind_text(statement, index, currency.rawValue, -1, SQLite.Destructor.transient)
                }
                
                var result: [Database.Market.Forex] = .init()
                while true {
                    switch sqlite3_step(statement).result {
                    case .row:  result.append(.init(statement: statement!))
                    case .done: return result
                    case let e: throw Database.Error.callFailed(.querying(Database.Market.Forex.self), code: e)
                    }
                }
            }.mapError(Database.Error.transform)
            .eraseToAnyPublisher()
    }
    
    /// Returns the forex markets in the database matching the given currencies.
    ///
    /// If there are no forex markets matching the given requirements, an empty array will be returned.
    /// - parameter base: The base currency code (or `nil` if this requirement is not needed).
    /// - parameter counter: The counter currency code (or `nil` if this requirement is not needed).
    public func get(base: Currency.Code?, counter: Currency.Code?) -> AnyPublisher<[Database.Market.Forex],Database.Error> {
        guard base != nil || counter != nil else { return self.getAll() }
        
        return self._database.publisher { _ -> (query: String, binds: [(index: Int32, text: Currency.Code)]) in
            var sql = "SELECT * FROM \(Database.Market.Forex.tableName) WHERE "
            
            let binds: [(index: Int32, text: Currency.Code)]
            switch (base, counter) {
            case (let b?, .none):  sql.append("base=?1");    binds = [(1, b)]
            case (.none,  let c?): sql.append("counter=?2"); binds = [(2, c)]
            case (let b?, let c?): sql.append("base=?1 AND counter=?2"); binds = [(1, b), (2, c)]
            case (.none,  .none):  fatalError()
            }
            
            return (sql, binds)
        }.read { (sql, statement, input, _) in
            for (index, currency) in input.binds {
                sqlite3_bind_text(statement, index, currency.rawValue, -1, SQLite.Destructor.transient)
            }
            
            var result: [Database.Market.Forex] = .init()
            while true {
                switch sqlite3_step(statement).result {
                case .row:  result.append(.init(statement: statement!))
                case .done: return result
                case let e: throw Database.Error.callFailed(.querying(Database.Market.Forex.self), code: e)
                }
            }
        }.mapError(Database.Error.transform)
        .eraseToAnyPublisher()
    }

    /// Updates the database with the information received from the server.
    /// - note: This method is intended to be called from the update of generic markets. That is why, no transaction is performed here, since the parent method will wrap everything in its own transaction.
    /// - precondition: The market must be of currency type or an error will be returned.
    /// - parameter markets: The currency markets to be updated.
    /// - parameter sqlite: SQLite pointer priviledge access.
    internal static func update(markets: [API.Market], sqlite: SQLite.Database) throws {
        var statement: SQLite.Statement? = nil
        defer { sqlite3_finalize(statement) }
        
        let query = """
            INSERT INTO \(Database.Market.Forex.tableName) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23)
                ON CONFLICT(epic) DO UPDATE SET base=excluded.base, counter=excluded.counter,
                    name=excluded.name, marketId=excluded.marketId, chartId=excluded.chartId, reutersId=excluded.reutersId,
                    contSize=excluded.contSize, pipVal=excluded.pipVal, placePip=excluded.placePip, placeLevel=excluded.placeLevel, slippage=excluded.slippage, premium=excluded.premium, extra=excluded.extra, margin=excluded.margin, bands=excluded.bands,
                    minSize=excluded.minSize, minDista=excluded.minDista, maxDista=excluded.maxDista, minRisk=excluded.minRisk, riskUnit=excluded.riskUnit, trailing=excluded.trailing, minStep=excluded.minStep
            """
        try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { .callFailed(.compilingSQL, code: $0) }
        
        for m in markets {
            guard case .success(let inferred) = Database.Market.Forex._inferred(from: m) else { continue }
            // The pip value can also be inferred from: `instrument.pip.value`
            let forex = Database.Market.Forex(epic: m.instrument.epic,
                                           currencies:  .init(base: inferred.base, counter: inferred.counter),
                                           identifiers: .init(name: m.instrument.name, market: inferred.marketId, chart: m.instrument.chartCode, reuters: m.instrument.newsCode),
                                           information: .init(contractSize: Int(clamping: inferred.contractSize),
                                                              pip: .init(value: Int(clamping: m.instrument.lotSize), decimalPlaces: Int(log10(Double(m.snapshot.scalingFactor)))),
                                                              levelDecimalPlaces: m.snapshot.decimalPlacesFactor,
                                                              slippageFactor: m.instrument.slippageFactor.value,
                                                              guaranteedStop: .init(premium: m.instrument.limitedRiskPremium.value, extraSpread: m.snapshot.extraSpreadForControlledRisk),
                                                              margin: .init(factor: m.instrument.margin.factor, depositBands: inferred.bands)),
                                           restrictions: .init(minimumDealSize: m.rules.minimumDealSize.value,
                                                               regularDistance: .init(minimum: m.rules.limit.mininumDistance.value, maximumAsPercentage: m.rules.limit.maximumDistance.value),
                                                               guarantedStopDistance: .init(minimumValue: m.rules.stop.minimumLimitedRiskDistance.value,
                                                                                            minimumUnit: inferred.guaranteedStopUnit,
                                                                                            maximumAsPercentage: m.rules.limit.maximumDistance.value),
                                                               trailingStop: .init(isAvailable: m.rules.stop.trailing.areAvailable, minimumIncrement: m.rules.stop.trailing.minimumIncrement.value)))
            forex._bind(to: statement!)
            try sqlite3_step(statement).expects(.done) { .callFailed(.storing(Database.Market.Forex.self), code: $0) }
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
        }
    }
}

// MARK: - Entities

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
        
        @_transparent public func hash(into hasher: inout Hasher) {
            hasher.combine(self.epic)
        }
        
        @_transparent public static func == (lhs: Database.Market.Forex, rhs: Database.Market.Forex) -> Bool {
            lhs.epic == rhs.epic
        }
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
        fileprivate let regularDistance: Self.Distance.Regular
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

// MARK: - Functionality

// MARK: SQLite

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

fileprivate extension Database.Market.Forex {
    typealias _Indices = (epic: Int32, base: Int32, counter: Int32, identifiers: Self.Identifiers._Indices, information: Self.DealingInformation._Indices, restrictions: Self.Restrictions._Indices)
    
    init(statement s: SQLite.Statement, indices: _Indices = (0, 1, 2, (3, 4, 5, 6), (7, 8, 9, 10, 11, 12, 13, 14, 15), (16, 17, 18, 19, 20, 21, 22)) ) {
        self.epic = IG.Market.Epic(rawValue: String(cString: sqlite3_column_text(s, indices.epic)))!
        self.currencies = .init(base:    Currency.Code(rawValue: String(cString: sqlite3_column_text(s, indices.base)))!,
                                counter: Currency.Code(rawValue: String(cString: sqlite3_column_text(s, indices.counter)))!)
        self.identifiers  = .init(statement: s, indices: indices.identifiers)
        self.information  = .init(statement: s, indices: indices.information)
        self.restrictions = .init(statement: s, indices: indices.restrictions)
    }
    
    func _bind(to statement: SQLite.Statement, indices: _Indices = (1, 2, 3, (4, 5, 6, 7), (8, 9, 10, 11, 12, 13, 14, 15, 16), (17, 18, 19, 20, 21, 22, 23))) {
        sqlite3_bind_text(statement, indices.epic, self.epic.rawValue, -1, SQLite.Destructor.transient)
        sqlite3_bind_text(statement, indices.base, self.currencies.base.rawValue, -1, SQLite.Destructor.transient)
        sqlite3_bind_text(statement, indices.counter, self.currencies.counter.rawValue, -1, SQLite.Destructor.transient)
        self.identifiers._bind(to: statement, indices: indices.identifiers)
        self.information._bind(to: statement, indices: indices.information)
        self.restrictions._bind(to: statement, indices: indices.restrictions)
    }
}

fileprivate extension Database.Market.Forex.Identifiers {
    typealias _Indices = (name: Int32, market: Int32, chart: Int32, reuters: Int32)
    
    init(statement: SQLite.Statement, indices: _Indices) {
        self.name = String(cString: sqlite3_column_text(statement, indices.name))
        self.market = String(cString: sqlite3_column_text(statement, indices.market))
        self.chart = sqlite3_column_text(statement, indices.chart).map { String(cString: $0) }
        self.reuters = String(cString: sqlite3_column_text(statement, indices.reuters))
    }
    
    func _bind(to statement: SQLite.Statement, indices: _Indices) {
        sqlite3_bind_text(statement, indices.name, self.name, -1, SQLite.Destructor.transient)
        sqlite3_bind_text(statement, indices.market, self.market, -1, SQLite.Destructor.transient)
        self.chart.unwrap(none: { sqlite3_bind_null(statement, indices.chart) },
                          some: { sqlite3_bind_text(statement, indices.chart, $0, -1, SQLite.Destructor.transient) })
        sqlite3_bind_text (statement, indices.reuters, self.reuters, -1, SQLite.Destructor.transient)
    }
}

fileprivate extension Database.Market.Forex.DealingInformation {
    typealias _Indices = (contractSize: Int32, pipValue: Int32, pipPlaces: Int32, levelPlaces: Int32, slippage: Int32, premium: Int32, extra: Int32, factor: Int32, bands: Int32)
    
    init(statement: SQLite.Statement, indices: _Indices) {
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
    
    func _bind(to statement: SQLite.Statement, indices: _Indices) {
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

fileprivate extension Database.Market.Forex.Restrictions {
    typealias _Indices = (dealSize: Int32, minDistance: Int32, maxDistance: Int32, guaranteedStopDistance: Int32, guaranteedStopUnit: Int32, trailing: Int32, minStep: Int32)
    
    init(statement: SQLite.Statement, indices: _Indices) {
        self.minimumDealSize = Decimal64(sqlite3_column_int64(statement, indices.dealSize), power: -2)!
        self.regularDistance = .init(minimum: Decimal64(sqlite3_column_int64(statement, indices.minDistance), power: -2)!,
                                     maximumAsPercentage: Decimal64(sqlite3_column_int64(statement, indices.maxDistance), power: -1)!)
        self.guarantedStopDistance = .init(minimumValue: Decimal64(sqlite3_column_int64(statement, indices.guaranteedStopDistance), power: -2)!,
                                           minimumUnit: Database.Unit(rawValue: Int(sqlite3_column_int(statement, indices.guaranteedStopUnit)))!,
                                           maximumAsPercentage: self.regularDistance.maximumAsPercentage)
        self.trailingStop = .init(isAvailable: Bool(sqlite3_column_int(statement, indices.trailing)),
                                  minimumIncrement: Decimal64(sqlite3_column_int64(statement, indices.minStep), power: -1)!)
    }
    
    func _bind(to statement: SQLite.Statement, indices: _Indices) {
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

extension Database.Market.Forex {
    /// Calculate the margin requirements for a given deal (identify by its size, price, and stop).
    ///
    /// IG may offer reduced margins on "tier 1" positions with a non-guaranteed stop (it doesn't apply to higher tiers/bands).
    /// - parameter dealSize: The size of a given position.
    public func margin(forDealSize dealSize: Decimal64, price: Decimal64, stop: IG.Deal.Stop?) -> Decimal64 {
        let marginFactor = self.information.margin.depositBands.depositFactor(forDealSize: dealSize)
        let contractSize = Decimal64(exactly: self.information.contractSize)!
        
        guard let stop = stop else {
            return dealSize * contractSize * price * marginFactor
        }
        
        let stopDistance: Decimal64
        switch stop.type {
        case .distance(let distance): stopDistance = distance
        case .position(let level):    stopDistance = (level - price).magnitude
        }
        
        switch stop.risk {
        case .exposed:
            let marginNoStop = dealSize * contractSize * price * marginFactor
            let marginWithStop = (marginNoStop * self.information.slippageFactor) + (dealSize * contractSize * stopDistance)
            return min(marginNoStop, marginWithStop)
        case .limited(let premium):
            return (dealSize * contractSize * stopDistance) + (premium ?? self.information.guaranteedStop.premium)
        }
    }
}

extension Database.Market.Forex.DealingInformation.Margin.Bands {
    fileprivate typealias _StoredElement = (lowerBound: Decimal64, value: Decimal64)
    /// The character separators used in encoding/decoding.
    private static let _separator: (numbers: Character, elements: Character) = (":", "|")
    
    /// Designated initializer.
    fileprivate init(underlying: String) {
        self.storage = underlying.split(separator: Self._separator.elements).map {
            let strings = $0.split(separator: Self._separator.numbers)
            precondition(strings.count == 2, "The given forex margin band '\(String($0))' is invalid since it contains \(strings.count) elements. Only 2 are expected")
            guard let lowerBound = Decimal64(String(strings[0])), let factor = Decimal64(String(strings[1])) else { fatalError() }
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
    
    /// Returns the deposit factor (expressed as a percentage `%`).
    /// - parameter dealSize: The size of a given position.
    public func depositFactor(forDealSize dealSize: Decimal64) -> Decimal64 {
        var result = self.storage[0].value
        for element in self.storage {
            guard dealSize >= element.lowerBound else { return result }
            result = element.value
        }
        return result
    }
    
    /// Returns the last band.
    public var last: (range: PartialRangeFrom<Decimal64>, depositFactor: Decimal64)? {
        self.storage.last.map { ($0.lowerBound..., $0.value) }
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
    fileprivate static func _inferred(from market: API.Market) -> Result<(base: Currency.Code, counter: Currency.Code, marketId: String, contractSize: Decimal64, guaranteedStopUnit: Database.Unit, bands: Self.DealingInformation.Margin.Bands),Database.Error> {
        let error: (_ suffix: String) -> Database.Error = {
            .invalidRequest(.init("The API market '\(market.instrument.epic)' \($0)"), suggestion: .reviewError)
        }
        // 1. Check the type is .currency
        guard market.instrument.type == .currencies else {
            return .failure(error("is not of 'currency' type"))
        }
        
        // 2. Check that currencies can be actually inferred and they are not equal
        guard let currencies = Self._currencyCodes(from: market), currencies.base != currencies.counter else {
            return .failure(error("is not of 'currency' type"))
        }
        // 3. Check the market identifier
        guard let marketId = market.identifier else {
            return .failure(error("doesn't contain a market identifier"))
        }
        // 4. Check the contract size
        guard let contractSize = market.instrument.contractSize else {
            return .failure(error("doesn't contain a contract size"))
        }
        // 5. Check the slippage factor unit
        guard market.instrument.slippageFactor.unit == .percentage else {
            return .failure(error("has a slippage factor unit of '\(market.instrument.slippageFactor.unit)' when '.percentage' was expected"))
        }
        // 6. Check the guaranteed stop premium unit
        guard market.instrument.limitedRiskPremium.unit == .points else {
            return .failure(error("has a limit risk premium unit of '\(market.instrument.limitedRiskPremium.unit)' when '.points' was expected"))
        }
        // 7. Check the margin unit
        guard market.instrument.margin.unit == .percentage else {
            return .failure(error("has a margin unit of '\(market.instrument.margin.unit)' when '.percentage' was expected"))
        }
        // 8. Check the margin deposit bands
        let apiBands = market.instrument.margin.depositBands.sorted { $0.minimum < $1.minimum }
        
        guard let code = apiBands.first?.currencyCode else {
            return .failure(error("doesn't have margin bands"))
        }
        
        guard apiBands.allSatisfy({ $0.currencyCode == code }) else {
            return .failure(error("margin bands have different currency units"))
        }
        
        for index in 0..<apiBands.count-1 {
            guard let max = apiBands[index].maximum else {
                let representation = apiBands.map { "\($0.minimum)..<\($0.maximum.map { String(describing: $0) } ?? "max") \($0.currencyCode) -> \($0.margin)%" }.joined(separator: ", ")
                return .failure(error("expected a maximum at index '\(index)' for deposit bands [\(representation)]"))
            }
            
            guard max == apiBands[index+1].minimum else {
                let representation = apiBands.map { "\($0.minimum)..<\($0.maximum.map { String(describing: $0) } ?? "max") \($0.currencyCode) -> \($0.margin)%" }.joined(separator: ", ")
                return .failure(error("doesn't have contiguous deposit bands [\(representation)]"))
            }
        }
        
        let bands = Self.DealingInformation.Margin.Bands(storage: apiBands.map { ($0.minimum, $0.margin) })
        // 9. Check the minimum deal size units.
        guard market.rules.minimumDealSize.unit == .points else {
            return .failure(error("has a minimum deal size unit of '\(market.rules.limit.mininumDistance.unit)' when '.points' was expected"))
        }
        
        // 10. Check the limit units (they are the same as the stop units).
        guard market.rules.limit.mininumDistance.unit == .points else {
            return .failure(error("has a minimum limit distance unit of '\(market.rules.limit.mininumDistance.unit)' when '.points' was expected"))
        }
        
        guard market.rules.limit.maximumDistance.unit == .percentage else {
            return .failure(error("has a maximum limit distance unit of '\(market.rules.limit.maximumDistance.unit)' when '.percentage' was expected"))
        }
        // 11. Check the guaranteed stop units.
        let unit: Database.Unit
        switch market.rules.stop.minimumLimitedRiskDistance.unit {
        case .points: unit = .points
        case .percentage: unit = .percentage
        }
        // 12. Check the trailing units.
        guard market.rules.stop.trailing.minimumIncrement.unit == .points else {
            return .failure(error("has a minimum trailing step increment unit of '\(market.rules.stop.trailing.minimumIncrement.unit)' when '.points' was expected"))
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
                if codes.count == 2, let counter = Currency.Code(rawValue: .init(codes[0])),
                    let base = Currency.Code(rawValue: .init(codes[1])) {
                    return (base, counter)
                }
            }
        }
        // B. Check the market identifier
        if let marketId = market.identifier, marketId.count == 6 {
            if let base = Currency.Code(rawValue: .init(marketId.prefix(3)) ),
                let counter = Currency.Code(rawValue: .init(marketId.suffix(3))) {
                return (base, counter)
            }
        }
        // C. Check the epic
        let epicSplit = market.instrument.epic.rawValue.split(separator: ".")
        if epicSplit.count > 3 {
            let identifier = epicSplit[2]
            if let base = Currency.Code(rawValue: .init(identifier.prefix(3)) ),
                let counter = Currency.Code(rawValue: .init(identifier.suffix(3))) {
                return (base, counter)
            }
        }
        // Otherwise, return `nil` since the currencies couldn't be inferred.
        return nil
    }
}
