//
//  MockBackend.swift
//  Sparky
//
//  Created by Hasan Malik on 2026-01-31.
//
import Foundation

// MARK: - Models

struct CareProviderSlot: Identifiable, Codable {
    let id: String
    let providerName: String
    let careType: String          // "clinic", "mentalHealth", "hospitalTrip"
    let day: String               // "Monday"
    let time24: String            // "09:30"
    var isBooked: Bool
}

struct DriverAvailability: Identifiable, Codable {
    let id: String
    let driverName: String
    let day: String               // "Monday"
    let pickupTime24: String      // "08:30"
    var isTaken: Bool
}

struct CarePlanOption: Identifiable {
    let id = UUID()
    let careType: String
    let providerSlot: CareProviderSlot
    let driver: DriverAvailability
    let pickupTime24: String
}

// MARK: - Backend

final class MockBackend {

    private(set) var providerSlots: [CareProviderSlot] = []
    private(set) var drivers: [DriverAvailability] = []

    init() {
        seedData()
    }

    private func seedData() {
        providerSlots = [
            .init(id: "p1", providerName: "Nurse Amina", careType: "clinic",       day: "Monday",    time24: "10:30", isBooked: false),
            .init(id: "p2", providerName: "Dr. Chen",    careType: "clinic",       day: "Tuesday",   time24: "14:00", isBooked: false),
            .init(id: "p3", providerName: "Dr. Patel",   careType: "clinic",       day: "Wednesday", time24: "09:15", isBooked: false),

            .init(id: "m1", providerName: "Counsellor Jo", careType: "mentalHealth", day: "Tuesday", time24: "11:00", isBooked: false),
            .init(id: "m2", providerName: "Counsellor Jo", careType: "mentalHealth", day: "Thursday", time24: "15:00", isBooked: false),

            .init(id: "h1", providerName: "Cardiology Intake", careType: "hospitalTrip", day: "Friday", time24: "09:00", isBooked: false)
        ]

        drivers = [
            .init(id: "d1", driverName: "John (SUV)",   day: "Monday",    pickupTime24: "09:15", isTaken: false),
            .init(id: "d2", driverName: "Marie",        day: "Tuesday",   pickupTime24: "10:00", isTaken: false),
            .init(id: "d3", driverName: "Evan (Ramp)",  day: "Wednesday", pickupTime24: "08:30", isTaken: false),
            .init(id: "d4", driverName: "John (SUV)",   day: "Friday",    pickupTime24: "07:00", isTaken: false),
        ]
    }

    // MARK: - Planning

    func computeCarePlans(for careType: String) -> [CarePlanOption] {
        let slots = providerSlots.filter { !$0.isBooked && $0.careType == careType }
        let availableDrivers = drivers.filter { !$0.isTaken }

        var options: [CarePlanOption] = []

        for slot in slots {
            for driver in availableDrivers where driver.day == slot.day {
                // driver pickup must be <= appointment time (simple MVP rule)
                if timeToMinutes(driver.pickupTime24) <= timeToMinutes(slot.time24) {
                    options.append(
                        CarePlanOption(
                            careType: careType,
                            providerSlot: slot,
                            driver: driver,
                            pickupTime24: driver.pickupTime24
                        )
                    )
                }
            }
        }

        // Sort by soonest day (rough) then earliest appointment time
        return options.sorted {
            dayRank($0.providerSlot.day) < dayRank($1.providerSlot.day)
            || (dayRank($0.providerSlot.day) == dayRank($1.providerSlot.day)
                && timeToMinutes($0.providerSlot.time24) < timeToMinutes($1.providerSlot.time24))
        }
    }

    // MARK: - Booking

    func book(plan: CarePlanOption) {
        if let i = providerSlots.firstIndex(where: { $0.id == plan.providerSlot.id }) {
            providerSlots[i].isBooked = true
        }
        if let j = drivers.firstIndex(where: { $0.id == plan.driver.id }) {
            drivers[j].isTaken = true
        }
    }

    // MARK: - Helpers

    private func timeToMinutes(_ t: String) -> Int {
        // "HH:mm"
        let parts = t.split(separator: ":")
        guard parts.count == 2 else { return 0 }
        let h = Int(parts[0]) ?? 0
        let m = Int(parts[1]) ?? 0
        return h * 60 + m
    }

    private func dayRank(_ day: String) -> Int {
        switch day.lowercased() {
        case "monday": return 1
        case "tuesday": return 2
        case "wednesday": return 3
        case "thursday": return 4
        case "friday": return 5
        case "saturday": return 6
        case "sunday": return 7
        default: return 99
        }
    }
}
