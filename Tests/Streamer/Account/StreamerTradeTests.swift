import XCTest
import ReactiveSwift
@testable import IG

final class StreamerTradeTests: XCTestCase {
    /// Tests for the stream confirmation subscription.
    func testAccountTrade() {
        let scheduler = QueueScheduler(suffix: ".streamer.market.test")
        let streamer = Test.makeStreamer(autoconnect: .yes(timeout: 1.5, queue: scheduler))
        
        let accountIdentifier = Test.account.identifier
        self.test( streamer.deals.subscribe(to: accountIdentifier, updates: .all, snapshot: true), value: { (update) in
            print(update)
        }, take: 1, timeout: 2, on: scheduler)
        
        self.test( streamer.session.unsubscribeAll(), take: 1, timeout: 2, on: scheduler) {
            XCTAssertEqual($0.count, 1)
        }
        
        self.test( streamer.session.disconnect(), timeout: 2, on: scheduler) {
            XCTAssertNotNil($0.last)
            XCTAssertEqual($0.last!, .disconnected(isRetrying: false))
        }
    }
    
    func testChain() {
        let scheduler = QueueScheduler(suffix: ".streamer.market.test")
        
        let api = Test.makeAPI(credentials: Test.credentials.api)
        let streamer = Test.makeStreamer(autoconnect: .yes(timeout: 1.5, queue: scheduler))
        
        var dealId: API.Deal.Identifier! = nil
        _ = streamer.deals.subscribe(to: Test.account.identifier, updates: .all, snapshot: false).startWithResult {
            switch $0 {
            case .success(let update):
                print("\n###### Update ######")
                print(update)
                
                if let confirmation = update.confirmation {
                    dealId = confirmation.identifier
                }
                
                if let position = update.position {
                    dealId = position.identifier
                }
            case .failure(let error):
                print(error)
            }
        }
        
        try! SignalProducer.empty(after: 1, on: scheduler).wait().get()
        print("\n------- 1. Update stream setup. -------\n")
        
        let epic: Epic = "CS.D.EURUSD.MINI.IP"
        let market = try! api.markets.get(epic: epic).single()!.get()
        let level = market.snapshot.price!.lowest - (0.0001 * 30)
        
        _ = try! api.workingOrders.create(epic: epic, currency: .usd, direction: .buy, type: .limit, size: 1, level: level, limit: .distance(50), stop: (.distance(50), .exposed), expiration: .tillDate(Date().addingTimeInterval(60*60*5))).single()!.get()
        print("\n------- 2. Working order created. -------\n")
        
        try! SignalProducer.empty(after: 1, on: scheduler).wait().get()
        print("\n------- 3. Waited one second. -------\n")
        
        guard let orderIdentifier = dealId else {
            print("Failed to get the dealId.")
            fatalError("No deal identifier obtained.")
        }
        
        let newLevel = level + 0.0001*50
        try! api.workingOrders.update(identifier: orderIdentifier, type: .limit, level: newLevel, limit: nil, stop: nil, expiration: .tillCancelled).wait().get()
        print("\n------- 4. Working order modified. -------\n")
        
        try! SignalProducer.empty(after: 1, on: scheduler).wait().get()
        print("\n------- 5. Waited one second. -------\n")
        
        try! api.workingOrders.delete(identifier: dealId).wait().get()
        print("\n------- 6. Working order deleted. -------\n")
        
        try! SignalProducer.empty(after: 1, on: scheduler).wait().get()
        print("\n------- 7. Waited one second. -------\n")
        
        self.test( streamer.session.unsubscribeAll(), take: 1, timeout: 2, on: scheduler) {
            XCTAssertEqual($0.count, 1)
        }
        
        print("\n------- 8. Unsubscribed to everything. -------\n")
        
        self.test( streamer.session.disconnect(), timeout: 2, on: scheduler) {
            XCTAssertNotNil($0.last)
            XCTAssertEqual($0.last!, .disconnected(isRetrying: false))
        }
        
        print("\n------- 9. Disconnected -------\n")
    }
}
