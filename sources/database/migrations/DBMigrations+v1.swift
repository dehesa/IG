import Foundation
import SQLite3

extension Database {
    /// Namespace for all defined migrations.
    enum Migration {}
}

extension Database.Migration {
    /// The initial database configuration settings.
    /// - parameter channel: The SQLite database connection.
    /// - throws: `IG.Error` exclusively.
    internal static func toVersion1(channel: Database.Channel) throws {
        try channel.write { (database) throws -> Void in
            // Set the application identifier for the database
            try database.set(applicationId: Database.applicationId)
            
            let types: [DBTable.Type] = [Database.Application.self, Database.Market.self, Database.Market.Forex.self]
            // Create all tables
            for type in types {
                try sqlite3_exec(database, type.tableDefinition, nil, nil, nil).expects(.ok) {
                    IG.Error._tableCreationFailed(type: type, code: $0)
                }
            }
            
            // Set the version number to first version.
            try database.set(version: .v1)
        }
    }
}

private extension IG.Error {
    /// Error raised when a SQLite table cannot be created.
    static func _tableCreationFailed(type: DBTable.Type, code: SQLite.Result) -> Self {
        Self(.database(.callFailed), "The SQL statement to create a table for '\(type.self)' failed to execute", info: ["Error code": code])
    }
}
