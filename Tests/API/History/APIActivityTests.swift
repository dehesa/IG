import XCTest
import ReactiveSwift
@testable import IG

/// Tests API history activity related enpoints
final class APIActivityTests: APITestCase {
    /// Tests paginated activity retrieval.
    func testActivities() {
        var components = DateComponents()
        components.timeZone = TimeZone(abbreviation: "CET")
        (components.year, components.month, components.day) = (2019, 01, 01)
        (components.hour, components.minute) = (0, 0)
        
        var counter = 0
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let endpoint = self.api.activity(from: date, detailed: false).on(completed: {
            XCTAssertGreaterThan(counter, 0)
        }, value: {
            counter += $0.count
        })
        
        self.test("Activities (history)", endpoint, signingProcess: .oauth, timeout: 1)
    }
}
