import Foundation

infix operator ?>
infix operator ?!
infix operator ∪: ComparisonPrecedence

extension Optional {
    /// Checks whether the value exists. If so, it returns it; if not, it throws the given error.
    /// - parameter lhs: Optional value to check for existance.
    /// - parameter rhs: Swift error to throw in case of no value.
    /// - returns: The value (non-optional) passed as parameter.
    /// - throws: The Swift error returned on the right hand-side autoclosure.
    @inlinable @_transparent public static func ?> (lhs: Self, rhs: @autoclosure ()->Swift.Error) throws -> Wrapped {
        switch lhs {
        case .some(let v): return v
        case .none: throw rhs()
        }
    }
    
    /// Checks whether the value exists. If so, it returns it; if not, it stops the program execution with the code writen in `rhs`.
    /// - parameter lhs: Optional value to check for existance.
    /// - parameter rhs: Closure halting the program execution.
    /// - returns: The value (non-optional) passed as parameter.
    @inlinable @_transparent public static func ?! (lhs: Self, rhs: @autoclosure ()->Never) -> Wrapped {
        guard let result = lhs else { rhs() }
        return result
    }
    
    /// Unwraps the receiving optional and execute the appropriate closure depending on whether the value is `.none` or `.some`.
    @discardableResult @inline(__always) func unwrap<T>(none: ()->T, `some`: (_ wrapped: Wrapped)->T) -> T {
        switch self {
        case .some(let v): return some(v)
        case .none: return none()
        }
    }
}

// MARK: - Euler

/// Creates a union of both passed collections.
public func ∪ <T>(lhs: Set<T>, rhs: Set<T>) -> Set<T> {
    lhs.union(rhs)
}

// MARK: - Set Up

public protocol SettableValue {}
public protocol SettableReference: class {}

public extension SettableValue {
    /// Makes the receiving value accessible within the passed block parameter and ends up returning the modified value.
    /// - parameter block: Closure executing a given task on the receiving function value.
    /// - returns: The modified value.
    @_transparent func set(with block: (inout Self) throws -> Void) rethrows -> Self {
        var copy = self
        try block(&copy)
        return copy
    }
}

public extension SettableReference {
    /// Makes the receiving reference accessible within the argument closure so it can be tweaked, before returning it again.
    /// - parameter block: Closure executing a given task on the receiving function value.
    /// - returns: The pre-set reference.
    @discardableResult @_transparent func set(with block: (Self) throws -> Void) rethrows -> Self {
        try block(self)
        return self
    }
}

extension Calendar: SettableValue {}
extension DateComponents: SettableValue {}
extension DateFormatter: SettableReference {}
extension NumberFormatter: SettableReference {}
extension JSONDecoder: SettableReference {}
extension Set: SettableValue {}
extension URLRequest: SettableValue {}
