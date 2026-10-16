import AixCore
import Foundation
import FoundationModels

@Generable
struct Plan {
    @Guide(description: "Shell commands to run in order, each a single line with no markdown. Empty if the request can't or shouldn't be done in a shell.")
    var commands: [String]

    @Guide(description: "One short sentence telling the user what the commands will do, or why there are none.")
    var explanation: String
}

struct PlannerError: Error, CustomStringConvertible {
    let description: String
}

/// Owns one model session so follow-ups (repairs, fixes after a failure) keep the conversation.
@MainActor
final class Planner {
    private(set) var session: LanguageModelSession
    private(set) var label: String
    private let instructions: String
    private let allowFallback: Bool

    init(choice: ModelChoice, instructions: String) throws {
        self.instructions = instructions
        allowFallback = choice == .auto
        switch choice {
        case .cloud:
            guard let s = Self.cloudSession(instructions) else {
                throw PlannerError(description: "Private Cloud Compute isn't available (needs macOS 27, Apple Intelligence and a network connection). Try -m local.")
            }
            (session, label) = (s, "cloud")
        case .auto:
            if let s = Self.cloudSession(instructions) {
                (session, label) = (s, "cloud")
            } else {
                (session, label) = (try Self.localSession(instructions), "on-device")
            }
        case .local:
            (session, label) = (try Self.localSession(instructions), "on-device")
        }
        session.prewarm()
    }

    func plan(_ prompt: String) async throws -> Plan {
        do {
            return try await respond(prompt)
        } catch where allowFallback && label == "cloud" && !Self.isContentRejection(error) {
            // Offline, out of quota, or missing the PCC entitlement (which still reports
            // isAvailable == true and then fails with ModelManagerError 1046): use on-device.
            session = try Self.localSession(instructions)
            label = "on-device"
            return try await respond(prompt)
        }
    }

    private func respond(_ prompt: String) async throws -> Plan {
        var plan = try await session.respond(to: prompt, generating: Plan.self, options: GenerationOptions(temperature: 0.2)).content
        plan.commands = plan.commands.map(Prompt.clean).filter { !$0.isEmpty }
        return plan
    }

    private static func cloudSession(_ instructions: String) -> LanguageModelSession? {
        guard #available(macOS 27, *) else { return nil }
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable, !model.quotaUsage.isLimitReached else { return nil }
        return LanguageModelSession(model: model, instructions: instructions)
    }

    private static func localSession(_ instructions: String) throws -> LanguageModelSession {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return LanguageModelSession(model: model, instructions: instructions)
        case .unavailable(.appleIntelligenceNotEnabled):
            throw PlannerError(description: "Apple Intelligence is turned off. Turn it on in System Settings → Apple Intelligence & Siri.")
        case .unavailable(.modelNotReady):
            throw PlannerError(description: "The on-device model is still downloading. Try again in a few minutes.")
        case .unavailable(.deviceNotEligible):
            throw PlannerError(description: "This Mac can't run Apple Intelligence (needs Apple silicon).")
        case .unavailable:
            throw PlannerError(description: "The on-device model is unavailable.")
        }
    }

    /// The model saw the request and said no; retrying on another model would just route around that.
    private static func isContentRejection(_ error: Error) -> Bool {
        switch error as? LanguageModelSession.GenerationError {
        case .guardrailViolation, .refusal: true
        default: false
        }
    }
}
