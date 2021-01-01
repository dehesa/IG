import Foundation
import Decimals
import SQLite3

extension Database {
    /// Candle price information.
    @frozen public struct Price {
        /// Snapshot date.
        public let date: Date
        /// Open session price.
        public var open: Self.Point
        /// Close session price.
        public var close: Self.Point
        /// Lowest price.
        public var lowest: Self.Point
        /// Highest price.
        public var highest: Self.Point
        /// Last traded volume.
        public var volume: Int
    }
    
    /// Price proceeding from a `Streamer` session that has been processed by the database.
    public struct PriceWrapper {
        /// The identifier for the sourcing market.
        public let epic: IG.Market.Epic
        /// The actual price.
        public let price: Database.Price
        /// The price resolution (e.g. one second, five minutes, etc.).
        public let interval: Streamer.Chart.Aggregated.Interval
        
        public init(epic: IG.Market.Epic, price: Database.Price, interval: Streamer.Chart.Aggregated.Interval) {
            self.epic = epic
            self.price = price
            self.interval = interval
        }
    }
}

extension Database.Price {
    /// Price Snap.
    public struct Point: Decodable {
        /// Bid price (i.e. the price another trader is willing to buy for).
        ///
        /// The _bid price_ is always lower than the _ask price_.
        public var bid: Decimal64
        /// Ask price (i.e. the price another trader will sell at).
        ///
        /// The _ask price_ is always higher than the _bid price_.
        public var ask: Decimal64
        /// The middle price between the *bid* and the *ask* price.
        @_transparent public var mid: Decimal64 { self.bid + Decimal64(5, power: -1).unsafelyUnwrapped * (self.ask - self.bid) }
    }
}

// MARK: -

extension Database.Price {
    internal static let tableNamePrefix: String = "Price_"
    
    internal static func tableDefinition(name: String) -> String { """
        CREATE TABLE '\(name)' (
            date     INTEGER NOT NULL,
            openBid  INTEGER NOT NULL,
            openAsk  INTEGER NOT NULL,
            closeBid INTEGER NOT NULL,
            closeAsk INTEGER NOT NULL,
            lowBid   INTEGER NOT NULL,
            lowAsk   INTEGER NOT NULL,
            highBid  INTEGER NOT NULL,
            highAsk  INTEGER NOT NULL,
            volume   INTEGER NOT NULL,
            
            PRIMARY KEY(date)
        ) WITHOUT ROWID;
        """
    }
}

internal extension Database.Price {
    typealias Indices = (date: Int32, openBid: Int32, openAsk: Int32, closeBid: Int32, closeAsk: Int32, lowBid: Int32, lowAsk: Int32, highBid: Int32, highAsk: Int32, volume: Int32)
    
    init(statement s: SQLite.Statement, indices: Indices = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)) {
        self.date = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int(s, indices.date)))
        self.open = Point(statement: s, indices: (indices.openBid, indices.openAsk))
        self.close = Point(statement: s, indices: (indices.closeBid, indices.closeAsk))
        self.lowest = Point(statement: s, indices: (indices.lowBid, indices.lowAsk))
        self.highest = Point(statement: s, indices: (indices.highBid, indices.highAsk))
        self.volume = Int(sqlite3_column_int(s, indices.volume))
    }
    
    func _bind(to statement: SQLite.Statement, indices: Indices = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)) {
        sqlite3_bind_int(statement, indices.date, Int32(self.date.timeIntervalSince1970))
        self.open.bind(to: statement, indices: (indices.openBid, indices.openAsk))
        self.close.bind(to: statement, indices: (indices.closeBid, indices.closeAsk))
        self.lowest.bind(to: statement, indices: (indices.lowBid, indices.lowAsk))
        self.highest.bind(to: statement, indices: (indices.highBid, indices.highAsk))
        sqlite3_bind_int(statement, indices.volume, Int32(self.volume))
    }
}

internal extension Database.Price.Point {
    fileprivate typealias _Indices = (bid: Int32, ask: Int32)
    static let powerOf10: Int = 5
    
    fileprivate init(statement s: SQLite.Statement, indices: _Indices) {
        self.bid = Decimal64(.init(sqlite3_column_int(s, indices.bid)), power: -Self.powerOf10)!
        self.ask = Decimal64(.init(sqlite3_column_int(s, indices.ask)), power: -Self.powerOf10)!
    }
    
    fileprivate func bind(to statement: SQLite.Statement, indices: _Indices) {
        sqlite3_bind_int(statement, indices.bid, .init(clamping: self.bid << Self.powerOf10))
        sqlite3_bind_int(statement, indices.ask, .init(clamping: self.ask << Self.powerOf10))
    }
}

internal extension Database.Request.Prices {
    /// SQLite query to insert a `Database.Price` in the database.
    /// - parameter epic: The market epic being targeted.
    static func _priceInsertionQuery(epic: IG.Market.Epic) -> (tableName: String, query: String) {
        var tableName = Database.Price.tableNamePrefix
        tableName.append(epic.description)
        
        let query = """
        INSERT INTO '\(tableName)' VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) ON CONFLICT(date) DO UPDATE SET
            openBid=excluded.openBid, openAsk=excluded.openAsk,
            closeBid=excluded.closeBid, closeAsk=excluded.closeAsk,
            lowBid=excluded.lowBid, lowAsk=excluded.lowAsk,
            highBid=excluded.highBid, highAsk=excluded.highAsk,
            volume=excluded.volume
        """
        
        return (tableName, query)
    }
    
    /// Returns a Boolean indicating whether the market is currently stored in the database.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - parameter sqlite: SQLite pointer priviledge access.
    static func _existsMarket(epic: IG.Market.Epic, sqlite: SQLite.Database) throws -> Bool {
        var statement: SQLite.Statement? = nil
        defer { sqlite3_finalize(statement) }
        
        let query = "SELECT 1 FROM \(Database.Market.tableName) WHERE epic=?1"
        try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
        try sqlite3_bind_text(statement, 1, epic.description, -1, SQLite.Destructor.transient).expects(.ok) { IG.Error._bindingFailed(code: $0) }
        
        switch sqlite3_step(statement).result {
        case .row:  return true
        case .done: return false
        case let c: throw IG.Error._unfoundTable(epic: epic, code: c)
        }
    }
    
    /// Returns a Boolean indicating whether the price table exists in the database.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - parameter sqlite: SQLite pointer priviledge access.
    static func _existsPriceTable(epic: IG.Market.Epic, sqlite: SQLite.Database) throws -> Bool {
        var statement: SQLite.Statement? = nil
        defer { sqlite3_finalize(statement) }
        
        let query = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1"
        try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
        
        let tableName = Database.Price.tableNamePrefix.appending(epic.description)
        sqlite3_bind_text(statement, 1, tableName, -1, SQLite.Destructor.transient)
        
        switch sqlite3_step(statement).result {
        case .row:  return true
        case .done: return false
        case let c: throw IG.Error._unfoundTable(epic: epic, code: c)
        }
    }
}

private extension IG.Error {
    /// Error raised when a SQLite command couldn't be compiled.
    static func _compilationFailed(code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "An error occurred trying to compile a SQL statement.", info: ["Error code": code])
    }
    /// Error raised when a SQLite binding couldn't take place.
    static func _bindingFailed(code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "An error occurred binding attributes to a SQL statement.", info: ["Error code": code])
    }
    /// Error raised when a SQLite table couldn't be found.
    static func _unfoundTable(epic: IG.Market.Epic, code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "SQLite couldn't verify the existance of the market.", info: ["Epic": epic, "Error code": code])
    }
}
