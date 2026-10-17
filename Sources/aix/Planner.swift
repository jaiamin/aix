import AixCore
import FoundationModels

@Generable
enum Kind {
    case runOnThisMac, explainConcept
}

@Generable
struct Plan {
    // Decided first, so a question can never come back with something to run.
    @Guide(description: "runOnThisMac: do something, or find out something about this Mac or its files (my ip, RAM, time, how do I…). explainConcept: only for what a term, option or symbol means.")
    var kind: Kind

    // Commands come first (explanation-first made the model refuse doable requests), and are
    // capped so it doesn't append steps nobody asked for.
    @Guide(description: "Shell commands to run in order, usually just one. No markdown. Empty only if the request should be refused.", .maximumCount(3))
    var commands: [String]

    // Optional so derailed output (see Prompt.clean) still yields commands.
    @Guide(description: "For commands: one short sentence starting with a verb, like \"Shows free disk space.\" For a question: the answer in 1-3 sentences. With no commands: why.")
    var explanation: String?

    var script: String { commands.isEmpty ? "" : "set -e\n" + commands.joined(separator: "\n") }
}

struct PlannerError: Error, CustomStringConvertible {
    let description: String
}

/// One session, so refinements and fixes keep the conversation.
@MainActor
final class Planner {
    private let session: LanguageModelSession

    init(instructions: String) throws {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            throw PlannerError(description: "Apple Intelligence is off. Turn it on in System Settings → Apple Intelligence & Siri.")
        case .unavailable(.modelNotReady):
            throw PlannerError(description: "The Apple Intelligence model is still downloading. Try again in a few minutes.")
        case .unavailable(.deviceNotEligible):
            throw PlannerError(description: "This Mac can't run Apple Intelligence (it needs Apple silicon).")
        case .unavailable:
            throw PlannerError(description: "Apple Intelligence is unavailable right now.")
        }
        session = LanguageModelSession(model: model, instructions: instructions)
        session.prewarm()
    }

    /// Streams the plan into `live` as it's generated.
    func plan(_ prompt: String, live: Live) async throws -> Plan {
        var plan: Plan
        do {
            plan = try await stream(prompt, into: live)
        } catch where Self.isRetryable(error) {
            debug("first attempt failed: \(error)")
            live.reset()
            // Greedy decoding sometimes loops or breaks the format; retry with some randomness.
            do {
                plan = try await respond(prompt, GenerationOptions(temperature: 0.5, maximumResponseTokens: 300))
            } catch where Self.isRetryable(error) {
                debug("retry failed: \(error)")
                throw PlannerError(description: "Couldn't produce a usable plan. Try rewording the request.")
            }
        }
        plan.commands = plan.kind == .explainConcept ? [] : plan.commands.map(Prompt.clean).filter { !$0.isEmpty }
        return plan
    }

    /// A plain-text answer, for `aix explain`.
    func explain(_ prompt: String) async throws -> String {
        let text = try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: 250)).content
        return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Xcode 27 renamed `sampling:` to `samplingMode:`; support building with either.
    #if compiler(>=6.4)
    private static let greedy = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 300)
    #else
    private static let greedy = GenerationOptions(sampling: .greedy, maximumResponseTokens: 300)
    #endif

    private func stream(_ prompt: String, into live: Live) async throws -> Plan {
        var last: GeneratedContent?
        for try await snapshot in session.streamResponse(to: prompt, generating: Plan.self, options: Self.greedy) {
            let partial = snapshot.content
            let commands = partial.kind == .explainConcept ? [] : partial.commands ?? []
            live.show(Terminal.planLines(explanation: partial.explanation, commands: commands))
            last = snapshot.rawContent
        }
        guard let last else { throw PlannerError(description: "The model returned nothing.") }
        return try Plan(last)
    }

    private func respond(_ prompt: String, _ options: GenerationOptions) async throws -> Plan {
        try await session.respond(to: prompt, generating: Plan.self, options: options).content
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? LanguageModelSession.GenerationError else { return true }
        switch error {
        case .guardrailViolation, .refusal, .exceededContextWindowSize, .assetsUnavailable,
             .unsupportedLanguageOrLocale, .rateLimited, .concurrentRequests:
            return false
        default:
            return true
        }
    }
}
