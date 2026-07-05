import SwiftUI
import ImageIO

struct PhotoExifInfo: Hashable, Sendable {
    let camera: String?
    let lens: String?
    let focalLength: String?
    let aperture: String?
    let shutterSpeed: String?
    let iso: String?
    let capturedAt: String?

    var hasAnyValue: Bool {
        camera != nil || lens != nil || focalLength != nil || aperture != nil ||
        shutterSpeed != nil || iso != nil || capturedAt != nil
    }

    static func load(from path: String, fallbackDate: Date) -> PhotoExifInfo {
        guard !path.isEmpty,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PhotoExifInfo(capturedAt: format(date: fallbackDate))
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let make = clean(tiff?[kCGImagePropertyTIFFMake] as? String)
        let model = clean(tiff?[kCGImagePropertyTIFFModel] as? String)
        let camera = [make, model]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty

        let lens = clean(exif?[kCGImagePropertyExifLensModel] as? String)
        let focalLength = formatFocalLength(exif?[kCGImagePropertyExifFocalLength])
        let aperture = formatAperture(exif?[kCGImagePropertyExifFNumber])
        let shutterSpeed = formatShutterSpeed(exif?[kCGImagePropertyExifExposureTime])
        let iso = formatISO(exif?[kCGImagePropertyExifISOSpeedRatings])
        let capturedAt = clean(exif?[kCGImagePropertyExifDateTimeOriginal] as? String) ?? format(date: fallbackDate)

        return PhotoExifInfo(
            camera: camera,
            lens: lens,
            focalLength: focalLength,
            aperture: aperture,
            shutterSpeed: shutterSpeed,
            iso: iso,
            capturedAt: capturedAt
        )
    }

    private init(capturedAt: String?) {
        self.camera = nil
        self.lens = nil
        self.focalLength = nil
        self.aperture = nil
        self.shutterSpeed = nil
        self.iso = nil
        self.capturedAt = capturedAt
    }

    private init(camera: String?, lens: String?, focalLength: String?, aperture: String?, shutterSpeed: String?, iso: String?, capturedAt: String?) {
        self.camera = camera
        self.lens = lens
        self.focalLength = focalLength
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.capturedAt = capturedAt
    }

    private static func clean(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func formatFocalLength(_ value: Any?) -> String? {
        guard let focalLength = doubleValue(value), focalLength > 0 else { return nil }
        return String(format: "%.0f mm", focalLength)
    }

    private static func formatAperture(_ value: Any?) -> String? {
        guard let aperture = doubleValue(value), aperture > 0 else { return nil }
        return String(format: "f/%.1f", aperture)
    }

    private static func formatShutterSpeed(_ value: Any?) -> String? {
        guard let seconds = doubleValue(value), seconds > 0 else { return nil }
        if seconds >= 1 {
            return String(format: "%.1f s", seconds)
        }
        return "1/\(Int(round(1 / seconds))) s"
    }

    private static func formatISO(_ value: Any?) -> String? {
        if let values = value as? [Int], let first = values.first {
            return "ISO \(first)"
        }
        if let values = value as? [NSNumber], let first = values.first {
            return "ISO \(first.intValue)"
        }
        if let number = value as? NSNumber {
            return "ISO \(number.intValue)"
        }
        return nil
    }

    private static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

actor PhotoExifCache {
    static let shared = PhotoExifCache()

    private var cache: [String: PhotoExifInfo] = [:]

    func info(for path: String, fallbackDate: Date) -> PhotoExifInfo {
        let key = "\(path)|\(fallbackDate.timeIntervalSince1970)"
        if let cached = cache[key] {
            return cached
        }

        let info = PhotoExifInfo.load(from: path, fallbackDate: fallbackDate)
        cache[key] = info
        return info
    }

    func clear() {
        cache.removeAll()
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
