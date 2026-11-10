import XCTest
@testable import FLTiya

@MainActor
final class CallCoordinatorTests: XCTestCase {
    private let user = UUID()
    private let peer = UUID()

    func testMissingServiceDoesNotRequestPermissionsOrCreateCall() async {
        let service = TestCallService()
        let media = TestCallMedia()
        var permissionRequests = 0
        let store = CallCoordinator(service: service, media: media) { _ in
            permissionRequests += 1
            return true
        }
        await store.activate(userID: user)
        await store.startCall(to: peer, kind: .voice)
        XCTAssertNil(store.call)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(permissionRequests, 0)
        XCTAssertFalse(service.actions.contains("create"))
        XCTAssertEqual(media.connectCount, 0)
    }

    func testPermissionDenialDoesNotRingPeer() async {
        let service = TestCallService()
        service.available = true
        let store = CallCoordinator(service: service, media: TestCallMedia()) { _ in false }
        await store.activate(userID: user)
        await store.startCall(to: peer, kind: .video)
        XCTAssertFalse(service.actions.contains("create"))
        XCTAssertNil(store.call)
    }

    func testIncomingRingingDoesNotAutomaticallyConnectOrPublishMedia() async {
        let service = TestCallService()
        let media = TestCallMedia()
        service.currentCall = sample(status: .ringing, incoming: true)
        let store = CallCoordinator(service: service, media: media) { _ in true }
        await store.activate(userID: user)
        await store.refresh()
        XCTAssertEqual(store.call?.id, service.currentCall?.id)
        XCTAssertTrue(store.isIncoming)
        XCTAssertEqual(media.connectCount, 0)
        XCTAssertFalse(service.actions.contains("token"))
    }

    func testRemoteEndDisconnectsAndClearsCall() async {
        let service = TestCallService()
        let media = TestCallMedia()
        service.currentCall = sample(status: .ringing, incoming: true)
        let store = CallCoordinator(service: service, media: media) { _ in true }
        await store.activate(userID: user)
        await store.refresh()
        service.currentCall = sample(status: .ended, incoming: true, id: store.call!.id)
        await store.refresh()
        XCTAssertNil(store.call)
        XCTAssertGreaterThan(media.disconnectCount, 0)
    }

    func testBackgroundEndsCallAndPreventsNewCalls() async {
        let service = TestCallService()
        let media = TestCallMedia()
        service.currentCall = sample(status: .ringing, incoming: true)
        let store = CallCoordinator(service: service, media: media) { _ in true }
        await store.activate(userID: user)
        await store.refresh()
        await store.setForeground(false)
        XCTAssertNil(store.call)
        XCTAssertTrue(service.actions.contains("end"))
        service.actions = []
        await store.startCall(to: peer, kind: .voice)
        XCTAssertFalse(service.actions.contains("create"))
    }

    func testServerFailureStopsMediaInsteadOfLeavingUnverifiedCall() async {
        let service = TestCallService()
        let media = TestCallMedia()
        service.currentCall = sample(status: .ringing, incoming: true)
        let store = CallCoordinator(service: service, media: media) { _ in true }
        await store.activate(userID: user)
        await store.refresh()
        service.shouldFail = true
        await store.refresh()
        XCTAssertNil(store.call)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertGreaterThan(media.disconnectCount, 0)
    }

    func testSecondDeviceAcceptanceConflictClearsOnlyLocalCall() async {
        let service = TestCallService()
        service.currentCall = sample(status: .ringing, incoming: true)
        let store = CallCoordinator(service: service, media: TestCallMedia()) { _ in true }
        await store.activate(userID: user)
        await store.refresh()
        service.handler = { request in
            if request.action == "accept" { throw CallFailure.server("call_not_ringing") }
            return CallResponse(call: service.currentCall)
        }
        await store.accept()
        XCTAssertNil(store.call)
        XCTAssertFalse(service.actions.contains("end"))
    }

    func testOldIdlePollFailureCannotEndNewOutgoingCall() async {
        let service = TestCallService()
        let outgoing = sample(status: .ringing, incoming: false)
        var suspended: CheckedContinuation<CallResponse, Error>?
        var availabilityCount = 0
        service.handler = { request in
            if request.action == "availability" {
                availabilityCount += 1
                if availabilityCount == 1 {
                    return try await withCheckedThrowingContinuation { suspended = $0 }
                }
                return CallResponse(available: true)
            }
            return CallResponse(call: outgoing)
        }
        let store = CallCoordinator(service: service, media: TestCallMedia()) { _ in true }
        await store.activate(userID: user)
        let retiredPoll = Task { await store.refresh() }
        for _ in 0..<100 where suspended == nil { await Task.yield() }
        guard let suspended else { XCTFail("Poll did not reach transport"); retiredPoll.cancel(); return }
        await store.startCall(to: peer, kind: .voice)
        suspended.resume(throwing: CallFailure.serviceUnavailable)
        await retiredPoll.value
        XCTAssertEqual(store.call?.id, outgoing.id)
        XCTAssertFalse(service.actions.contains("end"))
    }

    private func sample(status: FriendCall.Status, incoming: Bool, id: UUID = UUID()) -> FriendCall {
        FriendCall(id: id, callerID: incoming ? peer : user, calleeID: incoming ? user : peer,
                   kind: .voice, status: status, peerID: peer, peerDisplayName: "Other player")
    }
}

@MainActor
private final class TestCallService: CallService {
    var available = false
    var currentCall: FriendCall?
    var actions: [String] = []
    var shouldFail = false
    var handler: ((CallRequest) async throws -> CallResponse)?
    func request(_ request: CallRequest, userID: UUID) async throws -> CallResponse {
        actions.append(request.action)
        if let handler { return try await handler(request) }
        if shouldFail { throw CallFailure.serviceUnavailable }
        return CallResponse(call: currentCall, available: available)
    }
}

@MainActor
private final class TestCallMedia: CallMediaSession {
    var isConnected = false
    var isMicrophoneEnabled = false
    var isCameraEnabled = false
    var isSpeakerEnabled = false
    var errorMessage: String?
    var connectCount = 0
    var disconnectCount = 0
    func connect(url: String, token: String, video: Bool) async throws { connectCount += 1; isConnected = true }
    func disconnect() async { disconnectCount += 1; isConnected = false }
    func toggleMicrophone() async {}
    func toggleCamera() async {}
    func toggleSpeaker() {}
    func switchCamera() async {}
}
