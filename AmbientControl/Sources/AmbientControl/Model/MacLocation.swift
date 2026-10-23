import CoreLocation
import Foundation

/// Finds where this Mac is: Location Services first, then an approximate
/// location from the internet connection (no permission needed).
@MainActor
final class MacLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func locate() async -> Location? {
        if let fix = await deviceLocation(), let place = await Self.describe(fix) {
            return place
        }
        return await Self.fromIP()
    }

    // MARK: - Location Services

    private func deviceLocation() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        default: break
        }
        return await withCheckedContinuation { cont in
            waiting.append(cont)
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            Task {
                try? await Task.sleep(for: .seconds(20))
                self.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        let conts = waiting
        waiting = []
        conts.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard !self.waiting.isEmpty else { return }
            switch manager.authorizationStatus {
            case .notDetermined: break
            case .denied, .restricted: self.finish(nil)
            default: manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private static func describe(_ fix: CLLocation) async -> Location? {
        let mark = try? await CLGeocoder().reverseGeocodeLocation(fix).first
        let parts = [mark?.locality ?? mark?.subAdministrativeArea, mark?.country].compactMap { $0 }
        return Location(name: parts.isEmpty ? "This Mac" : parts.joined(separator: ", "),
                        latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                        timeZone: mark?.timeZone?.identifier ?? TimeZone.current.identifier, auto: true)
    }

    // MARK: - Approximate, from the IP address

    private static func fromIP() async -> Location? {
        struct R: Decodable {
            struct TZ: Decodable { let id: String }
            let success: Bool; let city: String?; let country: String?
            let latitude: Double?; let longitude: Double?; let timezone: TZ?
        }
        guard let url = URL(string: "https://ipwho.is/"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(R.self, from: data), r.success,
              let lat = r.latitude, let lon = r.longitude else { return nil }
        let city = (r.city ?? "").replacingOccurrences(of: "Gemeente ", with: "")
        let name = [city, r.country ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        return Location(name: name.isEmpty ? "This Mac" : name, latitude: lat, longitude: lon,
                        timeZone: r.timezone?.id ?? TimeZone.current.identifier, auto: true)
    }
}
