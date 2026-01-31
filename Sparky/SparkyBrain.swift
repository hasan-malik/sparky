//
//  SparkyBrain.swift
//  Sparky
//
//  Created by Hasan Malik on 2026-01-31.
//

import Foundation

final class SparkyBrain {

    private let backend: MockBackend

    init(backend: MockBackend) {
        self.backend = backend
    }

    enum Mode {
        case idle
        case triage(step: TriageStep, context: TriageContext)
        case appointment(step: AppointmentStep, context: AppointmentContext)
        case transport(step: TransportStep, context: TransportContext)
    }

    private var mode: Mode = .idle

    // MARK: - Public entry

    func handle(userText: String) -> String {
        let text = userText.lowercased()

        // If user says reset-ish, always return to idle
        if text.contains("start over") || text.contains("reset") || text.contains("nevermind") {
            mode = .idle
            return "No problem. Do you want help with a care question, an appointment, or a ride?"
        }

        // If we’re mid-flow, continue that flow
        switch mode {
        case .triage(let step, let ctx):
            return continueTriage(step: step, ctx: ctx, userText: text)
        case .appointment(let step, let ctx):
            return continueAppointment(step: step, ctx: ctx, userText: text)
        case .transport(let step, let ctx):
            return continueTransport(step: step, ctx: ctx, userText: text)
        case .idle:
            break
        }

        // Otherwise, pick a flow from intent
        if looksLikeTransport(text) {
            mode = .transport(step: .askWhen, context: TransportContext())
            return "Okay — I can help with a ride. What day and time do you need to leave?"
        }

        if looksLikeAppointment(text) {
            mode = .appointment(step: .askPreference, context: AppointmentContext())
            return "Sure. Do mornings or afternoons work better for you?"
        }

        // Default to triage if user talks about symptoms/feeling unwell/emergency
        if looksLikeHealthConcern(text) {
            mode = .triage(step: .intro, context: TriageContext())
            return "I’m here with you. Let’s take this one step at a time."
        }

        return "I can help with a care question, an appointment, or a ride. What would you like to do?"
    }

    // MARK: - Intent helpers

    private func looksLikeHealthConcern(_ t: String) -> Bool {
        let keywords = ["sick","unwell","fever","pain","dizzy","faint","vomit","cough","injury","emergency","er","hurt","bleeding","anxious","panic"]
        return keywords.contains(where: t.contains)
    }

    private func looksLikeAppointment(_ t: String) -> Bool {
        let keywords = ["appointment","doctor","clinic","nurse","reschedule","book","referral"]
        return keywords.contains(where: t.contains)
    }

    private func looksLikeTransport(_ t: String) -> Bool {
        let keywords = ["ride","drive","transport","pickup","pick up","car","volunteer","hospital trip"]
        return keywords.contains(where: t.contains)
    }

    // MARK: - TRIAGE FLOW

    enum TriageStep {
        case intro
        case askRedFlags
        case askUrgency
    }

    struct TriageContext {
        var hasRedFlags: Bool? = nil
        var isUrgent: Bool? = nil
    }

    private func continueTriage(step: TriageStep, ctx: TriageContext, userText: String) -> String {
        var ctx = ctx

        switch step {

        case .intro:
            mode = .triage(step: .askRedFlags, context: ctx)
            return """
            I’m not a doctor, but I can help you decide what to do next.
            Let me ask a couple of quick questions.
            """

        case .askRedFlags:
            if let ans = parseYesNo(userText) {
                ctx.hasRedFlags = ans

                if ans == true {
                    mode = .idle
                    return """
                    Thank you for telling me.
                    That could be serious.

                    If you can, please call emergency services right now.
                    If you’d like, I can help arrange a ride to the hospital once you’re safe.
                    """
                } else {
                    mode = .triage(step: .askUrgency, context: ctx)
                    return """
                    Okay.

                    Is the problem getting worse quickly,
                    or is the pain very severe — like an 8 out of 10?
                    """
                }
            }

            return """
            Just to be sure —
            are you having severe chest pain,
            trouble breathing,
            or signs of a stroke?
            Please say yes or no.
            """

        case .askUrgency:
            if let ans = parseYesNo(userText) {
                ctx.isUrgent = ans
                mode = .idle

                if ans == true {
                    return """
                    Thanks for letting me know.

                    That sounds urgent.
                    I recommend going to the clinic today,
                    or the emergency department if the clinic is closed.

                    Would you like help booking a same-day clinic visit
                    or arranging a ride?
                    """
                } else {
                    return """
                    Thank you.

                    This doesn’t sound like an emergency right now.
                    A clinic visit would be a good next step.

                    I can help book an appointment for you.
                    Do mornings or afternoons work better?
                    """
                }
            }

            return """
            Is it getting worse quickly,
            or is the pain very severe?
            Please say yes or no.
            """
        }
    }

    // MARK: - APPOINTMENT FLOW

    enum AppointmentStep { case askPreference, proposeSlot, confirm }
    struct AppointmentContext {
        var preference: TimePreference? = nil
        var proposed: ClinicSlot? = nil
    }

    private func continueAppointment(step: AppointmentStep, ctx: AppointmentContext, userText: String) -> String {
        var ctx = ctx

        switch step {
        case .askPreference:
            if let pref = parseTimePreference(userText) {
                ctx.preference = pref
                let slot = backend.findNextClinicSlot(preference: pref)
                ctx.proposed = slot
                mode = .appointment(step: .confirm, context: ctx)
                return "I found an opening: \(slot.day) at \(slot.time) with \(slot.provider). Should I book it?"
            }
            return "Got it. Do mornings or afternoons work better for you?"

        case .confirm:
            if let ans = parseYesNo(userText) {
                if ans == true, let slot = ctx.proposed {
                    backend.bookClinicSlot(slotID: slot.id)
                    mode = .idle
                    return "Done. You’re booked for \(slot.day) at \(slot.time). Do you also need a ride?"
                } else {
                    // offer the next best
                    let slot = backend.findNextClinicSlot(preference: ctx.preference ?? .morning)
                    ctx.proposed = slot
                    mode = .appointment(step: .confirm, context: ctx)
                    return "No worries. How about \(slot.day) at \(slot.time) with \(slot.provider)? Should I book that?"
                }
            }
            return "Should I book that appointment? Please say yes or no."

        case .proposeSlot:
            mode = .idle
            return "Do you want to book an appointment?"
        }
    }

    // MARK: - TRANSPORT FLOW

    enum TransportStep { case askWhen, proposeDriver, confirm }
    struct TransportContext {
        var whenText: String? = nil
        var proposed: DriverOption? = nil
    }

    private func continueTransport(step: TransportStep, ctx: TransportContext, userText: String) -> String {
        var ctx = ctx

        switch step {
        case .askWhen:
            // Keep it simple: treat user text as the “when”
            ctx.whenText = userText
            let option = backend.findDriver(forWhen: userText)
            ctx.proposed = option
            mode = .transport(step: .confirm, context: ctx)
            return "Okay. \(option.name) can drive you \(option.whenDescription). Should I request that ride?"

        case .confirm:
            if let ans = parseYesNo(userText) {
                if ans == true, let opt = ctx.proposed {
                    backend.requestRide(driverID: opt.id, when: opt.whenDescription)
                    mode = .idle
                    return "All set. I requested a ride with \(opt.name) \(opt.whenDescription). Do you need help with anything else?"
                } else {
                    let option = backend.findDriver(forWhen: ctx.whenText ?? "soon")
                    ctx.proposed = option
                    mode = .transport(step: .confirm, context: ctx)
                    return "No problem. Another option is \(option.name), \(option.whenDescription). Should I request that one?"
                }
            }
            return "Should I request that ride? Please say yes or no."

        case .proposeDriver:
            mode = .idle
            return "Do you want me to request a ride?"
        }
    }

    // MARK: - Parsing helpers

    private func parseYesNo(_ t: String) -> Bool? {
        let yes = ["yes","yeah","yep","please","sure","ok","okay","do it","book it"]
        let no  = ["no","nope","nah","don’t","dont","not"]
        if yes.contains(where: t.contains) { return true }
        if no.contains(where: t.contains) { return false }
        return nil
    }

    enum TimePreference { case morning, afternoon }
    private func parseTimePreference(_ t: String) -> TimePreference? {
        if t.contains("morn") { return .morning }
        if t.contains("after") { return .afternoon }
        // also accept yes/no-ish if user answers weirdly
        if t.contains("am") { return .morning }
        if t.contains("pm") { return .afternoon }
        return nil
    }
}

