//
//  MockBackend.swift
//  Sparky
//
//  Created by Hasan Malik on 2026-01-31.
//

import Foundation

// MARK: - Models

struct ClinicSlot: Codable {
    let id: String
    let day: String
    let time: String
    let provider: String
    let preference: String // "morning" or "afternoon"
    var isBooked: Bool
}

struct Driver: Codable {
    let id: String
    let name: String
    let notes: String
    let availability: [String] // simple strings like "tomorrow morning", "tuesday 9am"
}

struct DriverOption {
    let id: String
    let name: String
    let whenDescription: String
}

// MARK: - Mock Backend

final class MockBackend {

    private var slots: [ClinicSlot] = []
    private var drivers: [Driver] = []

    init() {
        loadMockData()
    }

    private func loadMockData() {
        // You can expand these anytime. Keep them small for demo clarity.
        let slotsJSON = """
        [
          { "id":"s1", "day":"Monday", "time":"10:30 AM", "provider":"Nurse Amina", "preference":"morning", "isBooked":false },
          { "id":"s2", "day":"Tuesday", "time":"2:00 PM", "provider":"Dr. Chen", "preference":"afternoon", "isBooked":false },
          { "id":"s3", "day":"Wednesday", "time":"9:15 AM", "provider":"Dr. Patel", "preference":"morning", "isBooked":false },
          { "id":"s4", "day":"Thursday", "time":"3:30 PM", "provider":"Nurse Amina", "preference":"afternoon", "isBooked":false }
        ]
        """

        let driversJSON = """
        [
          { "id":"d1", "name":"John", "notes":"SUV, good in snow", "availability":["tomorrow morning","tuesday 9am","thursday afternoon"] },
          { "id":"d2", "name":"Marie", "notes":"Sedan, can do pharmacy runs", "availability":["monday afternoon","wednesday morning"] },
          { "id":"d3", "name":"Evan", "notes":"Truck, wheelchair-friendly ramp", "availability":["tomorrow afternoon","friday morning"] }
        ]
        """

        let decoder = JSONDecoder()
        self.slots = (try? decoder.decode([ClinicSlot].self, from: Data(slotsJSON.utf8))) ?? []
        self.drivers = (try? decoder.decode([Driver].self, from: Data(driversJSON.utf8))) ?? []
    }

    // MARK: - Appointments

    func findNextClinicSlot(preference: SparkyBrain.TimePreference) -> ClinicSlot {
        let prefString = (preference == .morning) ? "morning" : "afternoon"
        if let s = slots.first(where: { !$0.isBooked && $0.preference == prefString }) {
            return s
        }
        // fallback: any unbooked
        return slots.first(where: { !$0.isBooked }) ?? ClinicSlot(id: "none", day: "Soon", time: "TBD", provider: "Clinic", preference: prefString, isBooked: false)
    }

    func bookClinicSlot(slotID: String) {
        if let idx = slots.firstIndex(where: { $0.id == slotID }) {
            slots[idx].isBooked = true
        }
    }

    // MARK: - Transportation

    func findDriver(forWhen whenText: String) -> DriverOption {
        let t = whenText.lowercased()

        // naive matching: find a driver whose availability string appears in user text OR shares a keyword
        for d in drivers {
            for a in d.availability {
                let al = a.lowercased()
                if t.contains(al) || sharesKeyword(t, al) {
                    return DriverOption(id: d.id, name: d.name, whenDescription: "(\(a))")
                }
            }
        }

        // fallback: first driver with any availability
        if let d = drivers.first, let a = d.availability.first {
            return DriverOption(id: d.id, name: d.name, whenDescription: "(\(a))")
        }

        return DriverOption(id: "none", name: "a volunteer", whenDescription: "(soon)")
    }

    func requestRide(driverID: String, when: String) {
        // For demo: just print; in production you'd write to DB / notify driver
        print("Ride requested: driver=\(driverID) when=\(when)")
    }

    private func sharesKeyword(_ user: String, _ availability: String) -> Bool {
        let keys = ["tomorrow","monday","tuesday","wednesday","thursday","friday","morning","afternoon","9","10","2","3"]
        let u = keys.filter { user.contains($0) }
        let a = keys.filter { availability.contains($0) }
        return !Set(u).intersection(Set(a)).isEmpty
    }
}

