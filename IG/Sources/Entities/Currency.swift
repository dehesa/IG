import Foundation

/// Base for all monetary units
public protocol CurrencyType {
    /// Three letter code standardize by ISO 4217.
    static var code: IG.Currency.Code { get }
    /// The standard name for the currency.
    static var name: String { get }
    /// The number of decimal places used to express any minor units for the currency.
    static var minorUnit: Int { get }
    /// The country where this currency is minted.
    static var country: String { get }
}

/// Namespace for currencies.
public enum Currency {
    /// ISO 4217 currency codes.
    public enum Code: String, ExpressibleByStringLiteral, LosslessStringConvertible, Hashable, Comparable, Codable {
        /// Canadian Dollar.
        case cad = "CAD"
        /// United States Dollar.
        case usd = "USD"
        /// Mexican Peso.
        case mxn = "MXN"
        /// Brazilian Real.
        case brl = "BRL"
        /// British Pound Sterling.
        case gbp = "GBP"
        /// Norwegian Krone.
        case nok = "NOK"
        /// Swedish Krona.
        case sek = "SEK"
        /// Danish Krone.
        case dkk = "DKK"
        /// European Union Euro.
        case eur = "EUR"
        /// Swiss Franc.
        case chf = "CHF"
        /// Czech Koruna.
        case czk = "CZK"
        /// Hungarian Forint.
        case huf = "HUF"
        /// Polish Zloty.
        case pln = "PLN"
        /// Russian Ruble.
        case rub = "RUB"
        /// Turkish Lira.
        case `try` = "TRY"
        /// South African Rand.
        case zar = "ZAR"
        /// Indian Rupee.
        case inr = "INR"
        /// Singapore Dollar.
        case sgd = "SGD"
        /// Chinese Yuan Renminbi
        case cny = "CNY"
        /// Hong Kong Dollar
        case hkd = "HKD"
        /// New Taiwan Dollar.
        case twd = "TWD"
        /// South Korean Won.
        case krw = "KRW"
        /// Japanese Yen.
        case jpy = "JPY"
        /// Philippine Piso.
        case php = "PHP"
        /// Indonesian Rupiah.
        case idr = "IDR"
        /// Australian Dollar.
        case aud = "AUD"
        /// New Zealand Dollar.
        case nzd = "NZD"
        
        public init(stringLiteral value: String) {
            guard let currency = Self.init(rawValue: value) else {
                fatalError("The given string \"\(value)\" couldn't be identified as a currency")
            }
            self = currency
        }
        
        public init?(rawValue: String) {
            guard rawValue.utf8.count == 3 else { return nil }
            
            switch rawValue {
            case "CAD": self = .cad
            case "USD": self = .usd
            case "MXN": self = .mxn
            case "BRL": self = .brl
            case "GBP": self = .gbp
            case "NOK": self = .nok
            case "SEK": self = .sek
            case "DKK": self = .dkk
            case "EUR": self = .eur
            case "CHF": self = .chf
            case "CZK": self = .czk
            case "HUF": self = .huf
            case "PLN": self = .pln
            case "RUB": self = .rub
            case "TRY", "TRL": self = .try
            case "ZAR": self = .zar
            case "INR": self = .inr
            case "SGD": self = .sgd
            case "CNY", "CNH": self = .cny
            case "HKD": self = .hkd
            case "TWD": self = .twd
            case "KRW": self = .krw
            case "JPY": self = .jpy
            case "PHP": self = .php
            case "IDR": self = .idr
            case "AUD": self = .aud
            case "NZD": self = .nzd
            default: return nil
            }
        }
        
        public init?(_ description: String) {
            self.init(rawValue: description)
        }
        
        public static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        public var description: String {
            return self.rawValue
        }
    }
}

// MARK: - Currency List

extension IG.Currency {
    /// Canadian Dollar.
    public enum CAD: IG.CurrencyType {
        public static var code: IG.Currency.Code { .cad }
        public static var name: String { "Canadian Dollar" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Canada" }
    }
    
    /// United States Dollar.
    public enum USD: IG.CurrencyType {
        public static var code: IG.Currency.Code { .usd }
        public static var name: String { "US Dollar" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "United States" }
    }
    
    /// Mexican Peso.
    public enum MXN: IG.CurrencyType {
        public static var code: IG.Currency.Code { .mxn }
        public static var name: String { "Mexican Peso" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Mexico" }
    }
    
    /// Brazilian Real.
    public enum BRL: IG.CurrencyType {
        public static var code: IG.Currency.Code { .brl }
        public static var name: String { "Brazilian Real" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Brazil" }
    }
    
    /// British Pound Sterling.
    public enum GBP: IG.CurrencyType {
        public static var code: IG.Currency.Code { .gbp }
        public static var name: String { "Pound Sterling" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Great Britian" }
    }
    
    /// Norwegian Krone.
    public enum NOK: IG.CurrencyType {
        public static var code: IG.Currency.Code { .nok }
        public static var name: String { "Norwegian Krone" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Norway" }
    }
    
    /// Swedish Krona.
    public enum SEK: IG.CurrencyType {
        public static var code: IG.Currency.Code { .sek }
        public static var name: String { "Swedish Krona" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Sweden" }
    }
    
    /// Danish Krone.
    public enum DKK: IG.CurrencyType {
        public static var code: IG.Currency.Code { .dkk }
        public static var name: String { "Danish Krone" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Denmark" }
    }
    
    /// European Union Euro.
    public enum EUR: IG.CurrencyType {
        public static var code: IG.Currency.Code { .eur }
        public static var name: String { "Euro" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Europe" }
    }
    
    /// Swiss Franc.
    public enum CHF: IG.CurrencyType {
        public static var code: IG.Currency.Code { .chf }
        public static var name: String { "Swiss Franc" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Switzerland" }
    }
    
    /// Czech Koruna.
    public enum CZK: IG.CurrencyType {
        public static var code: IG.Currency.Code { .czk }
        public static var name: String { "Czech Koruna" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Czech Republic" }
    }
    
    /// Hungarian Forint.
    public enum HUF: IG.CurrencyType {
        public static var code: IG.Currency.Code { .huf }
        public static var name: String { "Forint" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Hungary" }
    }
    
    /// Polish Zloty.
    public enum PLN: IG.CurrencyType {
        public static var code: IG.Currency.Code { .pln }
        public static var name: String { "Zloty" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Poland" }
    }
    
    /// Russian Ruble.
    public enum RUB: IG.CurrencyType {
        public static var code: IG.Currency.Code { .rub }
        public static var name: String { "Russian Ruble" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Russia" }
    }
    
    /// Turkish Lira.
    public enum TRY: IG.CurrencyType {
        public static var code: IG.Currency.Code { .try }
        public static var name: String { "Turkish Lira" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Turkey" }
    }
    
    /// South African Rand.
    public enum ZAR: IG.CurrencyType {
        public static var code: IG.Currency.Code { .zar }
        public static var name: String { "Rand" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "South Africa" }
    }
    
    /// Indian Rupee.
    public enum INR: IG.CurrencyType {
        public static var code: IG.Currency.Code { .inr }
        public static var name: String { "Indian Rupee" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "India" }
    }
    
    /// Singapore Dollar.
    public enum SGD: IG.CurrencyType {
        public static var code: IG.Currency.Code { .sgd }
        public static var name: String { "Singapore Dollar" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Singapore" }
    }
    
    /// Chinese Yuan Renminbi
    public enum CNY: IG.CurrencyType {
        public static var code: IG.Currency.Code { .cny }
        public static var name: String { "Yuan Renminbi" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "China" }
    }
    
    /// Hong Kong Dollar
    public enum HKD: IG.CurrencyType {
        public static var code: IG.Currency.Code { .hkd }
        public static var name: String { "Hong Kong Dollar" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "China" }
    }
    
    /// New Taiwan Dollar.
    public enum TWD: IG.CurrencyType {
        public static var code: IG.Currency.Code { .twd }
        public static var name: String { "New Taiwan Dollar" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "New Taiwan" }
    }
    
    /// South Korean Won.
    public enum KRW: IG.CurrencyType {
        public static var code: IG.Currency.Code { .krw }
        public static var name: String { "Won" }
        public static var minorUnit: Int { 0 }
        public static var country: String { "Korea" }
    }
    
    /// Japanese Yen.
    public enum JPY: IG.CurrencyType {
        public static var code: IG.Currency.Code { .jpy }
        public static var name: String { "Yen" }
        public static var minorUnit: Int { 0 }
        public static var country: String { "Japan" }
    }
    
    /// Philippine Piso.
    public enum PHP: IG.CurrencyType {
        public static var code: IG.Currency.Code { .php }
        public static var name: String { "Philippine Piso" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Philippines" }
    }
    
    /// Indonesian Rupiah.
    public enum IDR: IG.CurrencyType {
        public static var code: IG.Currency.Code { .idr }
        public static var name: String { "Rupiah" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Indonesia" }
    }
    
    /// Australian Dollar.
    public enum AUD: IG.CurrencyType {
        public static var code: IG.Currency.Code { .aud }
        public static var name: String { "Australian Dollar" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "Australia" }
    }
    
    /// New Zealand Dollar.
    public enum NZD: IG.CurrencyType {
        public static var code: IG.Currency.Code { .nzd }
        public static var name: String { "New Zealand Dollar" }
        public static var minorUnit: Int { 2 }
        public static var country: String { "New Zealand" }
    }
}