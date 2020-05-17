import XCTest
import IG
import ConbiniForTesting
import Combine

final class StreamerTradeTests: XCTestCase {
    /// The test account being used for the tests in this class.
    private let _acc = Test.account(environmentKey: Test.defaultEnvironmentKey)
    
    /// Tests for the stream confirmation subscription.
    func testAccountTrade() {
        let (rootURL, creds) = self.streamerCredentials(from: self._acc)
        let streamer = Test.makeStreamer(rootURL: rootURL, credentials: creds, targetQueue: nil)
        
        streamer.session.connect().expectsCompletion(timeout: 2, on: self)
        XCTAssertTrue(streamer.session.status.isReady)
        
        streamer.accounts.subscribeToConfirmations(account: self._acc.identifier).expectsAtLeast(values: 1, timeout: 2, on: self) { (confirmation) in
            print(confirmation)
        }
        
        streamer.session.disconnect().expectsOne(timeout: 2, on: self)
        XCTAssertEqual(streamer.session.status, .disconnected(isRetrying: false))
    }

    func testChain() {
        let api = Test.makeAPI(rootURL: self._acc.api.rootURL, credentials: self.apiCredentials(from: self._acc), targetQueue: nil)
        
        let (rootURL, creds) = self.streamerCredentials(from: self._acc)
        let streamer = Test.makeStreamer(rootURL: rootURL, credentials: creds, targetQueue: nil)
        
        streamer.session.connect().expectsCompletion(timeout: 2, on: self)
        XCTAssertTrue(streamer.session.status.isReady)
        
        // 1. Subscribe to confirmations
        var dealId: IG.Deal.Identifier? = nil
        let cancellable = streamer.accounts.subscribeToConfirmations(account: self._acc.identifier, snapshot: false)
            .sink(receiveCompletion: {
                if case .failure(let error) = $0 {
                    XCTFail("The publisher failed unexpectedly with \(error)")
                }
            }, receiveValue: { (update) in
                print(update)
                guard case .none = dealId else { return }
                dealId = update.confirmation.dealIdentifier
            })
        self.wait(seconds: 0.8)
        
        // 2. Gather information
        let epic: IG.Market.Epic = "CS.D.EURUSD.MINI.IP"
        let market = api.markets.get(epic: epic).expectsOne(timeout: 2, on: self)
        let level = market.snapshot.price!.lowest - (0.0001 * 30)
        print("\n\nMarket level: \(market.snapshot.price!.mid!)\nWorking order level: \(level)\n\n")
        
        // 3. Create the working order
        api.workingOrders.create(epic: epic, currency: .usd, direction: .buy, type: .limit, size: 1, level: level, limit: .distance(50), stop: (.distance(50), .exposed), expiration: .tillDate(Date().addingTimeInterval(60*60*5)))
            .expectsOne(timeout: 2, on: self)
        self._wait(max: 1.2, interval: 0.2) { (expectation) in
            guard case .some = dealId else { return }
            expectation.fulfill()
        }
        
        self.wait(seconds: 1.5)
        
        // 4. Modify the working order
        let newLevel = level + 0.0005
        api.workingOrders.update(identifier: dealId!, type: .limit, level: newLevel, limit: nil, stop: nil, expiration: .tillCancelled)
            .expectsOne(timeout: 2, on: self)
        self.wait(seconds: 1)
        
        // 5. Delete working order
        api.workingOrders.delete(identifier: dealId!).expectsOne(timeout: 2, on: self)
        self.wait(seconds: 1)
        
        // 6. Unsubscribe & disconnect
        cancellable.cancel()
        streamer.session.disconnect().expectsOne(timeout: 2, on: self)
    }
}

extension StreamerTradeTests {
    /// Waits a maximum amount of seconds, executing the closure every amount of `interval` seconds.
    private func _wait(max maxWait: TimeInterval, interval: TimeInterval, checking: @escaping (XCTestExpectation)->Void) {
        precondition(interval < maxWait)
        
        let e = self.expectation(description: "Waiting a max of \(maxWait) seconds. Checking every \(interval) seconds.")
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in checking(e) }
        self.wait(for: [e], timeout: maxWait)
        timer.invalidate()
    }
}