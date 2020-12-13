import IG
import ConbiniForTesting
import XCTest

/// Tests API history activity related enpoints
final class APIActivityTests: XCTestCase {
    override func setUp() {
        self.continueAfterFailure = false
    }
    
    /// Tests paginated activity retrieval.
    func testActivities() {
        let api = API()
        api.session.login(type: .oauth, key: "<#API key#>", user: ["<#Username#>", "<#Password#>"])
            .expectsCompletion(timeout: 1.2, on: self)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        
        let date = formatter.date(from: "2019.10.01")!
        let activities = api.accounts.getActivityContinuously(from: date)
            .expectsAll(timeout: 10, on: self)
            .flatMap { $0 }
        XCTAssertFalse(activities.isEmpty)
        
        print()
        
        for activity in activities {
            XCTAssertGreaterThan(activity.date, date)
            XCTAssertFalse(activity.summary.isEmpty)
            print(activity.summary)
        }
        
        print("\n\(activities.count)\n")
    }
}
