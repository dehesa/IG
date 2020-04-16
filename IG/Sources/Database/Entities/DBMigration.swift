import Foundation
import SQLite3

extension IG.Database {
    /// Migrates the hosted database from its version to a targeted version.
    /// - parameter toVersion: The desired database version.
    /// - throws: `IG.Database.Error` exclusively if the database is already on a higher version number or there were problems during migration.
    internal final func migrate(to toVersion: IG.Database.Migration.Version) throws {
        var info = try self._migrationInfo()
        guard info.version != toVersion else { return }
        guard info.version < toVersion else {
            let message = "The current database is already on a greater version than the one provided for migration"
            throw IG.Database.Error.invalidRequest(.init(message), suggestion: .reviewError)
        }
        
        repeat {
            let nextVersion = info.version.next!
            try self._migrateToNextVersion()
            info.version = nextVersion
        } while info.version != toVersion
    }
    
    /// Apply the needed migrations to reach the hosted database to the latest version.
    /// - throws: `IG.Database.Error` exclusively.
    internal final func migrateToLatestVersion() throws {
        var info = try self._migrationInfo()
        
        while let nextVersion = info.version.next {
            try self._migrateToNextVersion()
            info.version = nextVersion
        }
    }
    
    /// - precondition: The database version number is expected to be valid at this moment.
    /// - throws: `IG.Database.Error` exclusively.
    private final func _migrateToNextVersion() throws {
        typealias M = IG.Database.Migration
        switch M.Version(rawValue: try self.channel.unrestrictedAccess(M.version))! {
        case .v0: try M.initialMigration(channel: self.channel)
        case .v1: break
        }
    }
    
    /// - throws: `IG.Database.Error` exclusively.
    private final func _migrationInfo() throws -> (applicationID: Int32, version: IG.Database.Migration.Version) {
        // Retrieve the current database version
        let versionNumber = try self.channel.unrestrictedAccess(IG.Database.Migration.version)
        guard let version = IG.Database.Migration.Version(rawValue: versionNumber) else {
            if versionNumber > IG.Database.Migration.Version.latest.rawValue {
                throw IG.Database.Error.invalidResponse(.init("The database version number '\(versionNumber)' is not supported by your current library"), suggestion: "Update the library to work with the database")
            } else {
                throw IG.Database.Error.invalidResponse(.init("The database version number '\(versionNumber)' is invalid"), suggestion: .fileBug)
            }
        }
        
        // Retrieve the SQLite's file application identifier.
        let applicationID = try self.channel.unrestrictedAccess(IG.Database.Migration.applicationID)
        guard applicationID == IG.Database.Migration.applicationID || (applicationID == 0 && versionNumber == 0) else {
            throw IG.Database.Error.invalidRequest("The SQLite database file is not supported by this application", suggestion: "It seems you are trying to open a SQLite database belonging to another application")
        }
        
        return (applicationID, version)
    }
}

extension IG.Database {
    /// All migrations described in this database.
    internal enum Migration {
        /// Application ID "magic" number used to identify SQLite database files.
        internal static let applicationID: Int32 = 840797404
        
        /// The number of versions currently supported
        internal enum Version: Int, Comparable, CaseIterable {
            /// The version for database creation.
            case v0 = 0
            /// The initial version
            case v1 = 1
            
            /// The last described migration.
            static var latest: Self { Self.allCases.last! }
            
            /// Returns the next version from the current version.
            var next: Self? { Self.init(rawValue: self.rawValue + 1) }
            
            static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
        }
    }
}

extension IG.Database.Migration {
    /// Returns the SQLite's file application ID "magic" number.
    /// - precondition: This should only be called from the database queue.
    /// - parameter database: The SQLite database connection.
    internal static func applicationID(database: SQLite.Database) throws -> Int32 {
        var statement: SQLite.Statement? = nil
        defer { sqlite3_finalize(statement) }
        
        try sqlite3_prepare_v2(database, "PRAGMA application_id", -1, &statement, nil).expects(.ok) {
            .callFailed("The database's user version retrieval statement couldn't be compiled", code: $0)
        }
        
        try sqlite3_step(statement).expects(.row) {
            .callFailed("The database's user version couldn't be retrieved", code: $0)
        }
        
        return sqlite3_column_int(statement, 0)
    }
    
    /// Returns the database version for the given SQLite channel.
    /// - precondition: This should only be called from the database queue.
    /// - parameter database: The SQLite database connection.
    /// - returns: The number stored on the `PRAGMA user_version` field.
    internal static func version(database: SQLite.Database) throws -> Int {
        var statement: SQLite.Statement? = nil
        defer { sqlite3_finalize(statement) }
        
        try sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil).expects(.ok) {
            .callFailed("The database's user version retrieval statement couldn't be compiled", code: $0)
        }
        
        try sqlite3_step(statement).expects(.row) {
            .callFailed("The database's user version couldn't be retrieved", code: $0)
        }
        
        return Int(sqlite3_column_int(statement, 0))
    }
    
    /// Sets the SQLite's file application ID "magic" number.
    /// - precondition: This should only be called from the database queue.
    /// - parameter applicationID: The application's magic number (i.e. identifier).
    /// - parameter database: The SQLite database connection.
    internal static func setApplicationID(_ applicationID: Int32, database: SQLite.Database) throws {
        try sqlite3_exec(database, "PRAGMA application_id = \(applicationID)", nil, nil, nil).expects(.ok) {
            .callFailed("The database's user version couldn't be stored", code: $0)
        }
    }
    
    /// Sets the database user version number.
    /// - precondition: This should only be called from the database queue.
    /// - parameter version: The version number to be set to.
    /// - parameter database: The SQLite database connection.
    internal static func setVersion(_ version: Self.Version, database: SQLite.Database) throws {
        try sqlite3_exec(database, "PRAGMA user_version = \(version.rawValue)", nil, nil, nil).expects(.ok) {
            .callFailed("The database's user version couldn't be stored", code: $0)
        }
    }
}
