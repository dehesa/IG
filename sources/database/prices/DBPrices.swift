import Combine
import Conbini
import Foundation
import Decimals
import SQLite3

extension Database.Request {
    /// Contains all functionality related to the history of prices.
    @frozen public struct Prices {
        /// Pointer to the actual database instance in charge of the low-level objects.
        private unowned let _database: Database
        /// Hidden initializer passing the instance needed to perform the database fetches/updates.
        @usableFromInline internal init(database: Database) { self._database = database }
    }
}

extension Database.Request.Prices {
    /// Returns all dates for which there are prices stored in the database.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - parameter from: The date from which to start the query. If `nil`, the date at the beginning of the database is assumed.
    /// - parameter to: The date from which to end the query. If `nil`, the date at the end of the database is assumed.
    /// - returns: The dates under which there are prices or an empty array if no data has been previously stored for that timeframe.
    public func getAvailableDates(epic: IG.Market.Epic, from: Date? = nil, to: Date? = nil) -> AnyPublisher<[Date],IG.Error> {
        self._database.publisher { _ -> (tableName: String, query: String) in
            let tableName = Database.Price.tableNamePrefix.appending(epic.description)
            var query = "SELECT date FROM '\(tableName)'"
            switch (from, to) {
            case (let from?, let to?):
                guard from <= to else { throw IG.Error._invalidDates() }
                query.append(" WHERE date BETWEEN ?1 AND ?2")
            case (.some, .none): query.append(" WHERE date >= ?1")
            case (.none, .some): query.append(" WHERE date <= ?1")
            case (.none, .none): break
            }
            query.append(" ORDER BY date ASC")
            return (tableName, query)
        }.read { (sqlite, statement, input) in
            var result: [Date] = .init()
            // 1. Check the price table is there
            guard try Self._existsPriceTable(epic: epic, sqlite: sqlite) else { return result }
            // 2. Compile the SQL statement
            try sqlite3_prepare_v2(sqlite, input.query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
            // 3. Add the variables to the statement
            switch (from, to) {
            case (let from?, let to?):sqlite3_bind_int(statement, 1, Int32(from.timeIntervalSince1970))
                                      sqlite3_bind_int(statement, 2, Int32(to.timeIntervalSince1970))
            case (let from?, .none):  sqlite3_bind_int(statement, 1, Int32(from.timeIntervalSince1970))
            case (.none, let to?):    sqlite3_bind_int(statement, 1, Int32(to.timeIntervalSince1970))
            case (.none, .none):      break
            }
            // 4. Retrieve data
            while true {
                switch sqlite3_step(statement).result {
                case .row:
                    let date = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int(statement!, 0)))
                    result.append(date)
                case .done: return result
                case let c: throw IG.Error._queryFailed(code: c)
                }
            }
        }.mapError(errorCast)
        .eraseToAnyPublisher()
    }
    
    /// Returns the first available date for which there are prices stored in the database.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - returns: The date furthest in the past stored in the database.
    public func getFirstDate(epic: IG.Market.Epic) -> AnyPublisher<Date?,IG.Error> {
        self._database.publisher { _  in "SELECT MIN(date) FROM '\(Database.Price.tableNamePrefix.appending(epic.description))'" }
            .read { (sqlite, statement, query) in
                try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
                switch sqlite3_step(statement).result {
                case .row:  return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int(statement!, 0)))
                case .done: return nil
                case let c: throw IG.Error._queryFailed(code: c)
                }
            }.mapError(errorCast)
            .eraseToAnyPublisher()
    }
    
    /// Returns the last available date for which there are prices stored in the database.
    /// - warning: The table existance is not check before using this method.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - returns: The date from "newest" date stored in the database. If `nil`, no price points are for the given table.
    public func getLastDate(epic: IG.Market.Epic) -> AnyPublisher<Date?,IG.Error> {
        self._database.publisher { _ in "SELECT MAX(date) FROM '\(Database.Price.tableNamePrefix.appending(epic.description))'" }
            .read { (sqlite, statement, query) in
                try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
                switch sqlite3_step(statement).result {
                case .row:  return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int(statement!, 0)))
                case .done: return nil
                case let c: throw IG.Error._queryFailed(code: c)
                }
            }.mapError(errorCast)
            .eraseToAnyPublisher()
    }
    
    /// Returns the number of price points for the given date interval.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - parameter from: The date from which to start the query. If `nil`, the date at the beginning of the database is assumed.
    /// - parameter to: The date from which to end the query. If `nil`, the date at the end of the database is assumed.
    public func count(epic: IG.Market.Epic, from: Date? = nil, to: Date? = nil) -> AnyPublisher<Int,IG.Error> {
        self._database.publisher { _ -> String in
                let tableName = Database.Price.tableNamePrefix.appending(epic.description)
                var query = "SELECT COUNT(*) FROM '\(tableName)'"
                switch (from, to) {
                case (let from?, let to?):
                    guard from <= to else { throw IG.Error._invalidDates() }
                    query.append(" WHERE date BETWEEN ?1 AND ?2")
                case (.some, .none): query.append(" WHERE date >= ?1")
                case (.none, .some): query.append(" WHERE date <= ?1")
                case (.none, .none): break
                }
                query.append(" ORDER BY date ASC")
                return query
            }.read { (sqlite, statement, query) in
                try sqlite3_prepare_v2(sqlite, query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
                // 3. Add the variables to the statement
                switch (from, to) {
                case (let from?, let to?):sqlite3_bind_int(statement, 1, Int32(from.timeIntervalSince1970))
                                          sqlite3_bind_int(statement, 2, Int32(to.timeIntervalSince1970))
                case (let from?, .none):  sqlite3_bind_int(statement, 1, Int32(from.timeIntervalSince1970))
                case (.none, let to?):    sqlite3_bind_int(statement, 1, Int32(to.timeIntervalSince1970))
                case (.none, .none):      break
                }
                switch sqlite3_step(statement).result {
                case .row:  return Int(sqlite3_column_int(statement!, 0))
                case .done: fatalError()
                case let c: throw IG.Error._queryFailed(code: c)
                }
            }.mapError(errorCast)
            .eraseToAnyPublisher()
    }
}

extension Database.Request.Prices {
    /// Returns historical prices for a particular instrument.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - parameter from: The date from which to start the query (included). If `nil`, the retrieved data starts with the first ever recorded price.
    /// - parameter to: The date at which to end the query (included). If `nil`, the retrieved data ends with the last recorded price.
    /// - returns: The requested price points or an empty array if no data has been previously stored for that timeframe.
    public func get(epic: IG.Market.Epic, from: Date? = nil, to: Date? = nil) -> AnyPublisher<[Database.Price],IG.Error> {
        self._database.publisher { _ -> (tableName: String, query: String) in
            let tableName = Database.Price.tableNamePrefix.appending(epic.description)
            var query = "SELECT * FROM '\(tableName)'"
            switch (from, to) {
            case (let from?, let to?):
                guard from <= to else { throw IG.Error._invalidDates() }
                query.append(" WHERE date BETWEEN ?1 AND ?2")
            case (.some, .none): query.append(" WHERE date >= ?1")
            case (.none, .some): query.append(" WHERE date <= ?1")
            case (.none, .none): break
            }
            query.append(" ORDER BY date ASC")
            return (tableName, query)
        }.read { (sqlite, statement, input) in
            var result: [Database.Price] = []
            // 1. Check the price table is there.
            guard try Self._existsPriceTable(epic: epic, sqlite: sqlite) else { return result }
            // 2. Compile the SQL statement
            try sqlite3_prepare_v2(sqlite, input.query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
            // 3. Add the variables to the statement
            switch (from, to) {
            case (let from?, let to?):sqlite3_bind_int(statement, 1, Int32(from.timeIntervalSince1970))
                                      sqlite3_bind_int(statement, 2, Int32(to.timeIntervalSince1970))
            case (let from?, .none):  sqlite3_bind_int(statement, 1, Int32(from.timeIntervalSince1970))
            case (.none, let to?):    sqlite3_bind_int(statement, 1, Int32(to.timeIntervalSince1970))
            case (.none, .none): break
            }
            
            while true {
                switch sqlite3_step(statement).result {
                case .row:  result.append(Database.Price(statement: statement!))
                case .done: return result
                case let c: throw IG.Error._queryFailed(code: c)
                }
            }
        }.mapError(errorCast)
        .eraseToAnyPublisher()
    }
    
    /// Returns the first price starting from a given date to an optional end date (or the last stored price) which matches the buying or selling price.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - parameter from: The date from which to start the query.
    /// - parameter to: The date from which to end the query. If `nil`, all prices from `from` to the end available prices will be searched.
    /// - parameter buying: The buying price at which to match the price.
    /// - parameter selling: The selling price at which to match the price.
    /// - returns: A signal with price point matching the closure as value.
    public func first(epic: IG.Market.Epic, from: Date, to: Date?, buying: Decimal64, selling: Decimal64) -> AnyPublisher<Database.Price?,IG.Error> {
        return self._database.publisher { _ -> (tableName: String, query: String) in
            let tableName = Database.Price.tableNamePrefix.appending(epic.description)
            var query = "SELECT * FROM '\(tableName)'"
            
            if let to = to {
                guard from <= to else { throw IG.Error._invalidDates() }
                query.append(" WHERE date BETWEEN ?1 AND ?2")
            } else {
                query.append(" WHERE date > ?1")
            }
            
            let buyPrice = Int32(clamping: buying << Database.Price.Point.powerOf10)
            query.append(" AND (\(buyPrice) <= highBid")
            let sellPrice = Int32(clamping: selling << Database.Price.Point.powerOf10)
            query.append(" OR \(sellPrice) >= lowAsk)")
            
            query.append(" ORDER BY date ASC LIMIT 1")
            return (tableName, query)
        }.write { (sqlite, statement, input) in
            // 1. Compile the SQL statement (there is no check for price table).
            try sqlite3_prepare_v2(sqlite, input.query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
            // 3. Add the variables to the statement
            sqlite3_bind_int(statement, 1, Int32(from.timeIntervalSince1970))
            if let to = to { sqlite3_bind_int(statement, 2, Int32(to.timeIntervalSince1970)) }
            
            // 4. Retrieve data
            switch sqlite3_step(statement).result {
            case .row:  return .init(statement: statement!)
            case .done: return nil
            case let c: throw IG.Error._queryFailed(code: c)
            }
        }.mapError(errorCast)
        .eraseToAnyPublisher()
    }
}

extension Database.Request.Prices {
    /// Updates the database with the information received from the server.
    /// - requires: The market must be in the database before storing its price points.
    /// - parameter prices: The array of price points that have arrived from the server.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - returns: A publisher that completes successfully (without sending any value) if the operation has been successful.
    public func update(_ prices: [API.Price], epic: IG.Market.Epic) -> AnyPublisher<Never,IG.Error> {
        guard !prices.isEmpty else { return Empty().eraseToAnyPublisher() }
        
        return self._database.publisher { _ in
                Self._priceInsertionQuery(epic: epic)
            }.write { (sqlite, statement, input) -> Void in
                // 1. Check the epic is on the Markets table.
                guard try Self._existsMarket(epic: epic, sqlite: sqlite) else { throw IG.Error._unfoundMarket(epic: epic) }
                // 2. Check the existance of the price table or create it if it is not there.
                if try !Self._existsPriceTable(epic: epic, sqlite: sqlite) {
                    try sqlite3_exec(sqlite, Database.Price.tableDefinition(name: input.tableName), nil, nil, nil).expects(.ok) {
                        IG.Error._tableCreationFailed(name: input.tableName, code: $0)
                    }
                }
                // 3. Add the data to the database.
                try sqlite3_prepare_v2(sqlite, input.query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
                for p in prices {
                    guard let v = p.volume else { throw IG.Error._unfoundVolume() }
                    let price = Database.Price(date: p.date,
                                            open: .init(bid: p.open.bid, ask: p.open.ask),
                                            close: .init(bid: p.close.bid, ask: p.close.ask),
                                            lowest: .init(bid: p.lowest.bid, ask: p.lowest.ask),
                                            highest: .init(bid: p.highest.bid, ask: p.highest.ask),
                                            volume: .init(clamping: v))
                    price._bind(to: statement!)
                    try sqlite3_step(statement).expects(.done) { IG.Error._storingFailed(code: $0) }
                    sqlite3_clear_bindings(statement)
                    sqlite3_reset(statement)
                }
            }.ignoreOutput()
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
    
    /// Updates the database with the given price points.
    /// - requires: The market must be in the database before storing its price data.
    /// - parameter prices: The array of price points that have been modified or will be added.
    /// - parameter epic: Instrument's epic (such as `CS.D.EURUSD.MINI.IP`).
    /// - returns: A publisher that completes successfully (without sending any value) if the operation has been successful.
    public func update(_ prices: [Database.Price], epic: IG.Market.Epic) -> AnyPublisher<Never,IG.Error> {
        guard !prices.isEmpty else { return Empty().eraseToAnyPublisher() }
        
        return self._database.publisher { _ in
                Self._priceInsertionQuery(epic: epic)
            }.write { (sqlite, statement, input) -> Void in
                // 1. Check the epic is on the Markets table.
                guard try Self._existsMarket(epic: epic, sqlite: sqlite) else { throw IG.Error._unfoundMarket(epic: epic) }
                // 2. Check the existance of the price table or create it if it is not there.
                if try !Self._existsPriceTable(epic: epic, sqlite: sqlite) {
                    try sqlite3_exec(sqlite, Database.Price.tableDefinition(name: input.tableName), nil, nil, nil).expects(.ok) {
                        IG.Error._tableCreationFailed(name: input.tableName, code: $0)
                    }
                }
                // 3. Add the data to the database.
                try sqlite3_prepare_v2(sqlite, input.query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
                for p in prices {
                    p._bind(to: statement!)
                    try sqlite3_step(statement).expects(.done) { IG.Error._storingFailed(code: $0) }
                    sqlite3_clear_bindings(statement)
                    sqlite3_reset(statement)
                }
            }.ignoreOutput()
            .mapError(errorCast)
            .eraseToAnyPublisher()
    }
}

extension Publisher where Output==Streamer.Chart.Aggregated, Failure==IG.Error {
    /// Updates the database with the price values provided on the stream.
    ///
    /// The returned publisher forwards any previous error or generates `IG.Error` on some specific scenarios. If upstream there were no errors you can safely forcecast the error to the database error.
    /// - warning: For performance reasons, this operator assumes the database instance exists and it doesn't check whether the targeted market is currently stored in the database. Please check the market basic information is stored and there is a price table for the epic before calling this operator.
    /// - parameter database: Database where the price data will be stored.
    /// - parameter ignoringInvalidPrices: Boolean indicating whether invalid price data should be ignored or throw an error (and therefore break the pipeline. Even when this argument is set to `true`, the publisher may generate errors, such as when the database pointer disappears or there is a writting error.
    public func updatePrice(database: Database, ignoringInvalidPrices: Bool) -> AnyPublisher<Database.PriceWrapper,IG.Error> {
        self.tryCompactMap { [unowned(unsafe) database] (price) -> Database.Transit<(query: String, data: Database.PriceWrapper)>? in
            guard let date = price.candle.date,
                  let openBid = price.candle.open.bid,
                  let openAsk = price.candle.open.ask,
                  let closeBid = price.candle.close.bid,
                  let closeAsk = price.candle.close.ask,
                  let lowestBid = price.candle.lowest.bid,
                  let lowestAsk = price.candle.lowest.ask,
                  let highestBid = price.candle.highest.bid,
                  let highestAsk = price.candle.highest.ask,
                  let volume = price.candle.numTicks else {
                guard !ignoringInvalidPrices else { return nil }
                throw IG.Error._missingProperties()
            }
            
            let query = Database.Request.Prices._priceInsertionQuery(epic: price.epic).query
            let streamPrice = Database.PriceWrapper(
                    epic: price.epic,
                    price: .init(date: date, open: .init(bid: openBid, ask: openAsk),
                                close: .init(bid: closeBid, ask: closeAsk),
                                lowest: .init(bid: lowestBid, ask: lowestAsk),
                                highest: .init(bid: highestBid, ask: highestAsk), volume: volume),
                    interval: price.interval)
            return (database, (query, streamPrice))
        }.mapError(errorCast)
        .write { (sqlite, statement, input) -> Database.PriceWrapper in
            try sqlite3_prepare_v2(sqlite, input.query, -1, &statement, nil).expects(.ok) { IG.Error._compilationFailed(code: $0) }
            input.data.price._bind(to: statement!)
            try sqlite3_step(statement).expects(.done) { IG.Error._storingFailed(code: $0) }
            sqlite3_clear_bindings(statement)
            sqlite3_reset(statement)
            return input.data
        }.eraseToAnyPublisher()
    }
}

private extension IG.Error {
    /// Error raised when the DB instance is deallocated.
    static func _deallocatedDB() -> Self {
        Self(.database(.sessionExpired), "The DB instance has been deallocated.", help: "The DB functionality is asynchronous. Keep around the API instance while the request/response is being processed.")
    }
}

private extension IG.Error {
    /// Error raised when a SQLite command couldn't be compiled.
    static func _compilationFailed(code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "An error occurred trying to compile a SQL statement.", info: ["Error code": code])
    }
    /// Error raised when a SQLite table fails.
    static func _queryFailed(code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "An error occurred querying the SQLite table.", info: ["Table": Database.Price.self, "Error code": code])
    }
    /// Error raised when storing fails.
    static func _storingFailed(code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "An error occurred storing values on '\(Database.Price.self)'.", info: ["Error code": code])
    }
    /// Error raised when a price is missing properties.
    static func _missingProperties() -> Self {
        Self(.database(.invalidRequest), "The emitted price value is missing some properties", help: "Retry the connection")
    }
    /// Error raised when the _from_ and _to_ date interval are invalid.
    static func _invalidDates() -> Self {
        Self(.database(.invalidRequest), "The 'from' date must indicate a date before the 'to' date", help: "Read the request documentation and be sure to follow all requirements.")
    }
    /// Error raised when the market epic couldn't be found in the SQLite database.
    static func _unfoundMarket(epic: IG.Market.Epic) -> Self {
        Self(.database(.invalidRequest), "The market epic must be in the database before storing its price points.", help: "Store explicitly the market and the call this function again.", info: ["Epic": epic])
    }
    /// Error raised when the SQLite table couldn't be created.
    static func _tableCreationFailed(name: String, code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "The SQL statement to create a table for '\(name)' failed to execute.", info: ["Error code": code])
    }
    /// Error raised when no volume has been found in a price.
    static func _unfoundVolume() -> Self {
        Self(.database(.invalidRequest), "There must be volume for the price point to be stored in the database.", help: "A unexpected error was encountered. Please contact the repository maintainer and attach this debug print.")
    }
}
