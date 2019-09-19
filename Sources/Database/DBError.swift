extension IG.DB {
    /// Instance wrapping any error generated by the database used for caching.
    ///
    /// Most `underlyingError`s will be returned from the SQLite database.
    public struct Error: IG.Error {
        public let type: Self.Kind
        public internal(set) var message: String
        public internal(set) var suggestion: String
        public internal(set) var underlyingError: Swift.Error?
        public internal(set) var context: [(title: String, value: Any)] = []
        /// The internal SQLite code returned from an SQLite operation.
        internal var code: SQLite.Result?
        
        /// Designated initializer, filling all required error fields.
        /// - parameter type: The error type.
        /// - parameter message: A brief explanation on what happened.
        /// - parameter suggestion: A helpful suggestion on how to avoid the error.
        /// - parameter code: The `SQLite` low-level response code origin of the error.
        /// - parameter error: The underlying error that happened right before this error was created.
        internal init(_ type: Self.Kind, _ message: String, suggestion: String, code: SQLite.Result? = nil, underlying error: Swift.Error? = nil) {
            self.type = type
            self.message = message
            self.suggestion = suggestion
            self.code = code
            self.underlyingError = error
        }
    }
}

extension IG.DB.Error {
    /// The type of Database error raised.
    public enum Kind: CaseIterable {
        /// The Database instance couldn't be found.
        case sessionExpired
        /// The request parameters given are invalid.
        case invalidRequest
        /// A database request was executed, but an error was returned by low-level layers.
        case callFailed
        /// The fetched response from the database is invalid.
        case invalidResponse
    }
    
    /// A factory function for `.sessionExpired` API errors.
    /// - parameter message: A brief explanation on what happened.
    /// - parameter suggestion: A helpful suggestion on how to avoid the error.
    internal static func sessionExpired(message: Self.Message = .sessionExpired, suggestion: Self.Suggestion = .keepSession) -> Self {
        self.init(.sessionExpired, message.rawValue, suggestion: suggestion.rawValue)
    }
    
    /// A factory function for `.invalidRequest` database errors.
    /// - parameter message: A brief explanation on what happened.
    /// - parameter error: The underlying error that is the source of the error being initialized.
    /// - parameter suggestion: A helpful suggestion on how to avoid the error.
    internal static func invalidRequest(_ message: Self.Message, underlying error: Swift.Error? = nil, suggestion: Self.Suggestion) -> Self {
        self.init(.invalidRequest, message.rawValue, suggestion: suggestion.rawValue, underlying: error)
    }
    
    /// A factory function for `.callFailed` database errors.
    /// - parameter message: A brief explanation on what happened.
    /// - parameter code: The `SQLite` low-level response code origin of the error.
    /// - parameter error: The underlying error that is the source of the error being initialized.
    /// - parameter suggestion: A helpful suggestion on how to avoid the error.
    internal static func callFailed(_ message: Self.Message, code: SQLite.Result, underlying error: Swift.Error? = nil, suggestion: Self.Suggestion = .reviewError) -> Self {
        self.init(.callFailed, message.rawValue, suggestion: suggestion.rawValue, code: code, underlying: error)
    }
    
    /// A factory function for `.invalidResponse` database errors.
    /// - parameter message: A brief explanation on what happened.
    /// - parameter error: The underlying error that is the source of the error being initialized.
    /// - parameter suggestion: A helpful suggestion on how to avoid the error.
    internal static func invalidResponse(_ message: Self.Message, underlying error: Swift.Error? = nil, suggestion: Self.Suggestion) -> Self {
        self.init(.invalidResponse, message.rawValue, suggestion: suggestion.rawValue, underlying: error)
    }
}

extension IG.DB.Error {
    /// Namespace for messages reused over the framework.
    internal struct Message: IG.ErrorNameSpace {
        let rawValue: String; init(_ trustedValue: String) { self.rawValue = trustedValue }
        
        static var  sessionExpired: Self { .init("The \(IG.DB.printableDomain) instance wasn't found") }
        static var  compilingSQL:   Self { .init("An error occurred trying to compile a SQL statement") }
        static func querying(_ type: IG.DebugDescriptable.Type) -> Self { .init("An error occurred querying a table for \"\(type.printableDomain)\"") }
        static func storing(_ type: IG.DebugDescriptable.Type) -> Self  { .init("An error occurred storing values on \"\(type.printableDomain)\" table") }
        static var  valueNotFound:  Self { .init("The requested value couldn't be found") }
    }
    
    /// Namespace for suggestions reused over the framework.
    internal struct Suggestion: IG.ErrorNameSpace {
        let rawValue: String; init(_ trustedValue: String) { self.rawValue = trustedValue }
        
        static var keepSession: Self { .init("The \(IG.DB.printableDomain) functionality is asynchronous; keep around the \(IG.DB.self) instance while a response hasn't been received") }
        static var readDocs: Self    { .init("Read the request documentation and be sure to follow all requirements") }
        static var reviewError: Self { .init("Review the returned error and try to fix the problem") }
        static var fileBug: Self     { .init("A unexpected error was encountered. Please contact the repository maintainer and attach this debug print") }
        static var valueNotFound: Self { .init("The value is not in the database. Please introduce it, before trying to query it") }
    }
}

extension IG.DB.Error: IG.ErrorPrintable {
    static var printableDomain: String {
        return "IG.\(IG.DB.self).\(IG.DB.Error.self)"
    }
    
    var printableType: String {
        switch self.type {
        case .sessionExpired:  return "Session expired"
        case .invalidRequest:  return "Invalid request"
        case .callFailed:      return "Database call failed"
        case .invalidResponse: return "Invalid response"
        }
    }
    
    func printableMultiline(level: Int) -> String {
        let levelPrefix    = Self.debugPrefix(level: level+1)
        let sublevelPrefix = Self.debugPrefix(level: level+2)
        
        var result = "\(Self.printableDomain) (\(self.printableType))"
        result.append("\(levelPrefix)Error message: \(self.message)")
        result.append("\(levelPrefix)Suggestions: \(self.suggestion)")
        
        if let code = self.code {
            result.append("\(levelPrefix)SQLite code: ")
            if let name = code.name {
                result.append(name)
            } else {
                result.append(String(describing: code.rawValue))
            }
            
            let message = code.description
            result.append("\(levelPrefix)SQLite message: \(message)")
            if let documentation = code.verbose, documentation != message {
                result.append("\(levelPrefix)SQLite documentation: \(documentation)")
            }
        }
        
        if !self.context.isEmpty {
            result.append("\(levelPrefix)Error context: \(IG.ErrorHelper.representation(of: self.context, itemPrefix: sublevelPrefix, maxCharacters: Self.maxCharsPerLine))")
        }
        
        let errorStr = "\(levelPrefix)Underlying error: "
        if let errorRepresentation = IG.ErrorHelper.representation(of: self.underlyingError, level: level, prefixCount: errorStr.count, maxCharacters: Self.maxCharsPerLine) {
            result.append(errorStr)
            result.append(errorRepresentation)
        }
        
        return result
    }
}
