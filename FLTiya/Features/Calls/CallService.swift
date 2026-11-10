import Foundation
import Supabase
import SwiftUI

enum CallKind: String, Codable, Sendable { case voice, video }

struct FriendCall: Decodable, Identifiable, Sendable {
    enum Status: String, Decodable, Sendable {
        case ringing, accepted, rejected, ended, missed
        var isTerminal: Bool { self != .ringing && self != .accepted }
    }
    let id: UUID
    let callerID: UUID
    let calleeID: UUID
    let kind: CallKind
    let status: Status
    let peerID: UUID
    let peerDisplayName: String
    var endedReason: String? = nil
    enum CodingKeys: String, CodingKey {
        case id, kind, status
        case callerID = "caller_id", calleeID = "callee_id", peerID = "peer_id"
        case peerDisplayName = "peer_display_name", endedReason = "ended_reason"
    }
}

struct CallRequest: Encodable, Sendable {
    let action: String
    var callID: UUID? = nil
    var targetUserID: UUID? = nil
    var kind: CallKind? = nil
    enum CodingKeys: String, CodingKey {
        case action, kind
        case callID = "call_id", targetUserID = "target_user_id"
    }
}

struct CallResponse: Decodable, Sendable {
    var call: FriendCall? = nil
    var rtc: RTCConnection? = nil
    var available: Bool? = nil
    struct RTCConnection: Decodable, Sendable {
        let url: String
        let token: String
    }
}

enum CallFailure: Error {
    case serviceUnavailable, accountChanged, server(String), invalidResponse
    var message: String {
        switch self {
        case .serviceUnavailable:
            return "Calls aren't available yet. LiveKit service setup is still required."
        case .accountChanged: return "Your session changed. Please sign in again."
        case .server(let code):
            switch code {
            case "call_busy": return "One of you is already in a call. Please try again later."
            case "call_unavailable": return "This call is no longer available. Only current friends can call each other."
            case "call_not_ringing", "call_not_accepted": return "This call has already changed. Please try again."
            case "invalid_session", "authentication_required": return "Please sign in again before calling."
            case "call_rate_limited": return "Please wait a moment before starting another call."
            default: return "We couldn't confirm the call. Check your connection and try again."
            }
        case .invalidResponse: return "We couldn't confirm the call. Please try again."
        }
    }
}

@MainActor
protocol CallService {
    func request(_ request: CallRequest, userID: UUID) async throws -> CallResponse
}

@MainActor
protocol CallMediaSession: AnyObject {
    var isConnected: Bool { get }
    var isMicrophoneEnabled: Bool { get }
    var isCameraEnabled: Bool { get }
    var isSpeakerEnabled: Bool { get }
    var errorMessage: String? { get }
    func connect(url: String, token: String, video: Bool) async throws
    func disconnect() async
    func toggleMicrophone() async
    func toggleCamera() async
    func toggleSpeaker()
    func switchCamera() async
}

@MainActor
final class SupabaseCallService: CallService {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }
    func request(_ request: CallRequest, userID: UUID) async throws -> CallResponse {
        guard client.auth.currentUser?.id == userID else { throw CallFailure.accountChanged }
        do {
            let response: CallResponse = try await client.functions.invoke("call-service",
                options: FunctionInvokeOptions(body: request, timeoutInterval: 12))
            guard client.auth.currentUser?.id == userID else { throw CallFailure.accountChanged }
            return response
        } catch let FunctionsError.httpError(_, data) {
            struct FailureBody: Decodable { let error: String }
            let code = (try? JSONDecoder().decode(FailureBody.self, from: data))?.error ?? "request_failed"
            if code == "calls_unavailable" { throw CallFailure.serviceUnavailable }
            throw CallFailure.server(code)
        }
    }
}

private struct CallCoordinatorKey: EnvironmentKey {
    static let defaultValue: CallCoordinator? = nil
}
extension EnvironmentValues {
    var callCoordinator: CallCoordinator? {
        get { self[CallCoordinatorKey.self] }
        set { self[CallCoordinatorKey.self] = newValue }
    }
}
