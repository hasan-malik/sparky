//
//  SparkyBrain.swift
//  Sparky
//
//  Created by Hasan Malik on 2026-01-31.
//
import Foundation

final class SparkyBrain {

    private let backend: MockBackend
    init(backend: MockBackend) { self.backend = backend }

    enum Mode {
        case idle
        case triage(step: TriageStep, ctx: TriageContext)
        case planning(careType: String, options: [CarePlanOption], chosenIndex: Int)
    }

    private var mode: Mode = .idle

    // MARK: - Entry

    func handle(userText: String) -> String {
        let t = userText.lowercased()

        // universal commands
        if t.contains("start over") || t.contains("reset") {
            mode = .idle
            return "No problem. Tell me what’s going on, and I’ll help with care, appointments, and rides."
        }

        switch mode {
        case .triage(let step, let ctx):
            return continueTriage(step: step, ctx: ctx, userText: t)
        case .planning(let careType, let options, let chosen):
            return continuePlanning(careType: careType, options: options, chosenIndex: chosen, userText: t)
        case .idle:
            break
        }

        // If user talks about symptoms, start triage
        if looksLikeHealthConcern(t) {
            mode = .triage(step: .askRedFlags, ctx: .init())
            return """
            I’m here with you. 
            
            I’m not a doctor, but I can help you decide what to do next.
            
            Are you having severe chest pain, trouble breathing, or face drooping?
            """

        }

        // Direct requests
        if t.contains("ride") || t.contains("drive") || t.contains("transport") {
            return "Totally. For today’s demo, I’ll set this up when we book an appointment — tell me what care you need first."
        }

        return "Tell me what’s going on, and I’ll help you figure out the right care and book a ride if needed."
    }

    // MARK: - TRIAGE (polished)

    enum TriageStep { case askRedFlags, askUrgency }
    struct TriageContext { var answeredIntro = false }

    private func continueTriage(step: TriageStep, ctx: TriageContext, userText: String) -> String {
        switch step {

        case .askRedFlags:
            if let ans = parseYesNo(userText) {
                if ans {
                    mode = .idle
                    return """
                    Thank you for telling me.
                    That could be serious.

                    If you can, please call emergency services right now.
                    If you want, I can still help plan a hospital ride after you’re safe.
                    """
                } else {
                    mode = .triage(step: .askUrgency, ctx: .init())
                    return "Okay. Is the pain getting worse quickly, or is it very severe — like an 8 out of 10?"
                }
            }
            return "Please say yes or no: severe chest pain, trouble breathing, or stroke signs?"

        case .askUrgency:
            if let ans = parseYesNo(userText) {
                // Decide care type based on urgency + keywords
                let careType = classifyCareType(from: userText, urgent: ans)
                return startPlanning(for: careType)
            }
            return "Would you say it’s getting worse quickly, or the pain is very severe? Please say yes or no."
        }
    }

    // MARK: - PLANNING FLOW

    private func startPlanning(for careType: String) -> String {
        let options = backend.computeCarePlans(for: careType)

        if options.isEmpty {
            mode = .idle
            if careType == "hospitalTrip" {
                return "I couldn’t find a driver and hospital slot that line up right now. I recommend calling the clinic so staff can coordinate manually."
            }
            return "I couldn’t find a matching appointment and driver right now. Would you like me to try a different time, or just book the appointment without a ride?"
        }

        // Offer top 2 for demo
        let top = Array(options.prefix(2))
        mode = .planning(careType: careType, options: top, chosenIndex: 0)

        let first = top[0]
        let firstText = formatPlan(first)

        if top.count == 1 {
            return """
            Okay. I can set this up for you.

            Option: \(firstText)
            Should I book it?
            """
        } else {
            let secondText = formatPlan(top[1])
            return """
            Okay. I can set this up for you. Here are two options:

            1) \(firstText)
            
            2) \(secondText)

            Which one do you want?
            """
        }
    }

    private func continuePlanning(careType: String, options: [CarePlanOption], chosenIndex: Int, userText: String) -> String {
        var chosen = chosenIndex
        
        // If they chose an option (one/two/first/second/1/2), store it and ask for yes/no
        if options.count > 1, let choice = parseOptionChoice(userText) {
            chosen = min(choice, options.count - 1)
            mode = .planning(careType: careType, options: options, chosenIndex: chosen)
            return """
            Got it. 
            
            Say “yes” to confirm the booking, or say “no” to choose another one.
            """
        }


        // If user confirms yes, book
        if let ans = parseYesNo(userText), ans == true {
            let plan = options[chosen]
            backend.book(plan: plan)
            mode = .idle

            return """
            Done — you’re booked.

            \(formatBooked(plan))

            If anything changes, just tell me “reschedule” and I’ll help.
            """
        }

        // If user explicitly says no, offer the other option or bail
        if let ans = parseYesNo(userText), ans == false {
            if options.count > 1 {
                let other = options[1 - chosen]
                mode = .planning(careType: careType, options: options, chosenIndex: 1 - chosen)
                return "No problem. How about: \(formatPlan(other)) — should I book that?"
            } else {
                mode = .idle
                return "No worries. Would you like to try a different day, or book the appointment without a ride?"
            }
        }



        // default prompt
        if options.count > 1 {
            return "Say “option 1” or “option 2”, and then say yes to book."
        } else {
            return "Should I book it? Please say yes or no."
        }
    }

    // MARK: - Classification

    private func classifyCareType(from t: String, urgent: Bool) -> String {
        let s = t.lowercased()

        // mental health keywords
        let mh = ["anxious", "panic", "depressed", "hopeless", "overwhelmed", "mental", "stress"]
        if mh.contains(where: s.contains) {
            return "mentalHealth"
        }

        // hospital trip keywords (specialist / surgery / cardiac)
        let hosp = ["surgery", "cardiac", "heart", "specialist", "hospital", "operation"]
        if hosp.contains(where: s.contains) {
            return "hospitalTrip"
        }

        // urgent but not red flags: still clinic by default in demo
        return "clinic"
    }

    // MARK: - Helpers

    private func looksLikeHealthConcern(_ t: String) -> Bool {
        let keywords = ["sick","unwell","fever","pain","dizzy","faint","vomit","cough","injury","hurt","bleeding","anxious","panic","depressed","stress"]
        return keywords.contains(where: t.contains)
    }

    private func parseYesNo(_ t: String) -> Bool? {
        let yes = ["yes","yeah","yep","please","sure","ok","okay","book","confirm","do it"]
        let no  = ["no","nope","nah","don’t","dont","not"]
        if yes.contains(where: t.contains) { return true }
        if no.contains(where: t.contains) { return false }
        return nil
    }
    
    private func parseOptionChoice(_ t: String) -> Int? {
        let s = t.lowercased()

        if s.contains("1") || s.contains("one") || s.contains("first") { return 0 }
        if s.contains("2") || s.contains("two") || s.contains("second") { return 1 }

        return nil
    }

    private func formatPlan(_ p: CarePlanOption) -> String {
        let care = prettyCare(p.careType)
        return "\(p.providerSlot.day) at \(prettyTime(p.providerSlot.time24)) for \(care) with \(p.providerSlot.providerName). Ride pickup: \(prettyTime(p.pickupTime24)) with \(p.driver.driverName)."
    }

    private func formatBooked(_ p: CarePlanOption) -> String {
        let care = prettyCare(p.careType)
        return "Appointment: \(p.providerSlot.day) \(prettyTime(p.providerSlot.time24)) with \(p.providerSlot.providerName) (\(care)). Ride: \(p.driver.driverName) pickup at \(prettyTime(p.pickupTime24))."
    }

    private func prettyCare(_ c: String) -> String {
        switch c {
        case "mentalHealth": return "mental health support"
        case "hospitalTrip": return "a hospital visit"
        default: return "a clinic visit"
        }
    }

    private func prettyTime(_ t: String) -> String {
        // convert "HH:mm" to "h:mm AM/PM"
        let parts = t.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return t }
        var hour = h
        let am = hour < 12
        if hour == 0 { hour = 12 }
        if hour > 12 { hour -= 12 }
        let mm = String(format: "%02d", m)
        return "\(hour):\(mm) \(am ? "AM" : "PM")"
    }
}
