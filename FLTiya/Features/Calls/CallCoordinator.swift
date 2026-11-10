import AVFoundation
import Foundation
import Observation

/// App-wide foreground signaling. Server state must stay confirmed before
/// media can remain active; no timer or client friendship flag grants access.
@MainActor
@Observable
final class CallCoordinator {
    private(set) var call: FriendCall?
    private(set) var currentUserID: UUID?
    private(set) var isWorking = false
    private(set) var isConnecting = false
    private(set) var isServiceAvailable: Bool?
    var errorMessage: String?
    let media: any CallMediaSession

    @ObservationIgnored private let service: any CallService
    @ObservationIgnored private let requestPermissions: (CallKind) async -> Bool
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var callEpoch = UUID()
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var connectedCallID: UUID?
    @ObservationIgnored private var dismissedCalls: Set<UUID> = []

    var isIncoming: Bool { call?.calleeID == currentUserID && call?.status == .ringing }

    init(service: any CallService, media: any CallMediaSession,
         requestPermissions: @escaping (CallKind) async -> Bool = CallCoordinator.permissions) {
        self.service = service
        self.media = media
        self.requestPermissions = requestPermissions
    }

    func activate(userID: UUID?) async {
        let previous = call
        let previousUser = currentUserID
        epoch = UUID()
        callEpoch = UUID()
        currentUserID = userID
        call = nil
        isWorking = false
        isConnecting = false
        refreshing = false
        connectedCallID = nil
        isServiceAvailable = nil
        errorMessage = nil
        dismissedCalls = []
        await media.disconnect()
        if let previous, let previousUser {
            _ = try? await service.request(CallRequest(action: "end", callID: previous.id), userID: previousUser)
        }
    }

    func monitor(userID: UUID?) async {
        await activate(userID: userID)
        guard userID == currentUserID, let userID, !Task.isCancelled else { return }
        let monitorEpoch = epoch
        while !Task.isCancelled, epoch == monitorEpoch, currentUserID == userID {
            if foreground { await refresh() }
            do { try await Task.sleep(for: .seconds(call == nil ? 5 : 3)) }
            catch { break }
        }
        // A retired monitor cannot clear the next account's media or state.
        if epoch == monitorEpoch { await activate(userID: nil) }
    }

    func refresh() async {
        guard foreground, let userID = currentUserID, !refreshing, !Task.isCancelled else { return }
        let requestEpoch = epoch
        let previousID = call?.id
        var ownedCallID = previousID
        var ownedRevision = callEpoch
        refreshing = true
        defer { if epoch == requestEpoch { refreshing = false } }
        do {
            if isServiceAvailable == nil {
                let response = try await service.request(CallRequest(action: "availability"), userID: userID)
                guard isCurrent(requestEpoch, userID) else { return }
                isServiceAvailable = response.available == true
            }
            let response = try await service.request(CallRequest(action: "state", callID: previousID), userID: userID)
            guard isCurrent(requestEpoch, userID), call?.id == previousID else { return }
            if let received = response.call, dismissedCalls.contains(received.id) {
                _ = try? await service.request(CallRequest(action: "end", callID: received.id), userID: userID)
                return
            }
            guard let received = response.call, !received.status.isTerminal else {
                if call != nil {
                    let reason = response.call?.status == .rejected ? "The call was declined."
                        : response.call?.status == .missed ? "No answer. Please try again later." : "The call ended."
                    await clearCall(message: reason)
                }
                return
            }
            call = received
            ownedCallID = received.id
            ownedRevision = callEpoch
            if received.status == .accepted {
                let heartbeat = try await service.request(CallRequest(action: "heartbeat", callID: received.id), userID: userID)
                guard isCurrent(requestEpoch, userID), call?.id == received.id else { return }
                guard heartbeat.call?.status == .accepted else {
                    await clearCall(message: "The call ended.")
                    return
                }
                if connectedCallID == received.id, !media.isConnected, !isConnecting {
                    await finish(message: "The connection was lost. Please try again.")
                } else {
                    await connectIfNeeded(received, userID: userID)
                }
            }
        } catch {
            guard isCurrent(requestEpoch, userID) else { return }
            if call != nil, call?.id == ownedCallID, callEpoch == ownedRevision {
                await finish(message: Self.message(for: error))
            }
            // Idle polling failures do not repeatedly interrupt browsing.
        }
    }

    func startCall(to peerID: UUID, kind: CallKind) async {
        guard foreground, let userID = currentUserID, call == nil, !isWorking, peerID != userID else { return }
        let requestEpoch = epoch
        let revision = callEpoch
        isWorking = true
        errorMessage = nil
        defer { if epoch == requestEpoch, callEpoch == revision { isWorking = false } }
        do {
            let availability = try await service.request(CallRequest(action: "availability"), userID: userID)
            guard isCurrent(requestEpoch, userID), callEpoch == revision else { return }
            isServiceAvailable = availability.available == true
            guard availability.available == true else { throw CallFailure.serviceUnavailable }
            guard await requestPermissions(kind) else {
                if isCurrent(requestEpoch, userID) { errorMessage = Self.permissionMessage(kind) }
                return
            }
            guard isCurrent(requestEpoch, userID), callEpoch == revision, call == nil else { return }
            let response = try await service.request(CallRequest(action: "create", targetUserID: peerID, kind: kind), userID: userID)
            guard isCurrent(requestEpoch, userID), callEpoch == revision else {
                if let lateCall = response.call {
                    _ = try? await service.request(CallRequest(action: "end", callID: lateCall.id), userID: userID)
                }
                return
            }
            guard let created = response.call, created.callerID == userID, created.peerID == peerID else {
                throw CallFailure.invalidResponse
            }
            call = created
        } catch {
            if isCurrent(requestEpoch, userID), callEpoch == revision { errorMessage = Self.message(for: error) }
        }
    }

    func accept() async {
        guard foreground, isIncoming, let incoming = call, let userID = currentUserID, !isWorking else { return }
        let requestEpoch = epoch
        let revision = callEpoch
        isWorking = true
        defer { if epoch == requestEpoch, callEpoch == revision { isWorking = false } }
        do {
            guard await requestPermissions(incoming.kind) else {
                if isCurrent(requestEpoch, userID) { errorMessage = Self.permissionMessage(incoming.kind) }
                return
            }
            guard isCurrent(requestEpoch, userID), call?.id == incoming.id else { return }
            let response = try await service.request(CallRequest(action: "accept", callID: incoming.id), userID: userID)
            guard isCurrent(requestEpoch, userID), call?.id == incoming.id else { return }
            guard let accepted = response.call, accepted.status == .accepted else { throw CallFailure.invalidResponse }
            call = accepted
            await connectIfNeeded(accepted, userID: userID)
        } catch {
            guard isCurrent(requestEpoch, userID), call?.id == incoming.id else { return }
            if case CallFailure.server(let code) = error,
               ["call_not_ringing", "call_unavailable"].contains(code) {
                // Another device may have accepted. Retire only this UI; it
                // has no authority to hang up the selected device's call.
                await clearCall(message: Self.message(for: error))
                return
            }
            await finish(message: Self.message(for: error))
        }
    }

    func reject() async { await finish(action: "reject") }

    func finish(action: String = "end", message: String? = nil) async {
        guard let ended = call, let userID = currentUserID else { return }
        dismissedCalls.insert(ended.id)
        let requestEpoch = epoch
        await clearCall(message: message)
        do { _ = try await service.request(CallRequest(action: action, callID: ended.id), userID: userID) }
        catch {
            if epoch == requestEpoch, message == nil {
                errorMessage = "The call stopped on this device. Server closure couldn't be confirmed and will be retried."
            }
        }
    }

    func setForeground(_ value: Bool) async {
        foreground = value
        if !value {
            // Permission sheets make the scene inactive, not background. Only
            // an actual background transition ends this foreground-only call.
            callEpoch = UUID()
            isWorking = false
            if call != nil { await finish() } else { await media.disconnect() }
        } else {
            isServiceAvailable = nil
        }
    }

    func friendshipRemoved(with userID: UUID) async {
        if call?.peerID == userID { await finish(message: "You are no longer friends. The call ended.") }
    }

    private func connectIfNeeded(_ accepted: FriendCall, userID: UUID) async {
        guard connectedCallID != accepted.id, !isConnecting, foreground else { return }
        let requestEpoch = epoch
        let revision = callEpoch
        isConnecting = true
        defer { if epoch == requestEpoch, callEpoch == revision { isConnecting = false } }
        do {
            let response = try await service.request(CallRequest(action: "token", callID: accepted.id), userID: userID)
            guard isCurrent(requestEpoch, userID), call?.id == accepted.id, callEpoch == revision else { return }
            guard response.call?.status == .accepted, let rtc = response.rtc else { throw CallFailure.invalidResponse }
            #if DEBUG
            // A local hardware check must release capture before RTC owns it.
            await DeviceCheckModel.stopActiveCheck()
            guard isCurrent(requestEpoch, userID), call?.id == accepted.id, callEpoch == revision else { return }
            #endif
            try await media.connect(url: rtc.url, token: rtc.token, video: accepted.kind == .video)
            guard isCurrent(requestEpoch, userID), call?.id == accepted.id, callEpoch == revision else { return }
            guard media.isConnected else { throw CallFailure.invalidResponse }
            connectedCallID = accepted.id
        } catch {
            guard isCurrent(requestEpoch, userID), call?.id == accepted.id, callEpoch == revision else { return }
            await finish(message: Self.message(for: error))
        }
    }

    private func clearCall(message: String?) async {
        callEpoch = UUID()
        call = nil
        connectedCallID = nil
        isConnecting = false
        isWorking = false
        if let message { errorMessage = message }
        await media.disconnect()
    }

    private func isCurrent(_ requestEpoch: UUID, _ userID: UUID) -> Bool {
        epoch == requestEpoch && currentUserID == userID && foreground && !Task.isCancelled
    }

    private static func message(for error: Error) -> String {
        if let failure = error as? CallFailure { return failure.message }
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return "We couldn't confirm the call. Check your connection and try again."
    }

    private static func permissionMessage(_ kind: CallKind) -> String {
        kind == .video ? "Allow microphone and camera access in Settings to make a video call."
            : "Allow microphone access in Settings to make a voice call."
    }

    private static func permissions(_ kind: CallKind) async -> Bool {
        guard await permission(.audio) else { return false }
        if kind == .voice { return true }
        return await permission(.video)
    }

    private static func permission(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }
}
