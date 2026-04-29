import Foundation

@MainActor
class RatingService {
    static let shared = RatingService()

    private let ratingKey = "com.photofilter.rating"
    private let defaults = UserDefaults.standard

    private init() {}

    func getRating(for photoId: String) -> Int {
        defaults.integer(forKey: "\(ratingKey).\(photoId)")
    }

    func setRating(_ rating: Int, for photoId: String) {
        defaults.set(rating, forKey: "\(ratingKey).\(photoId)")
    }

    func getAllRatings() -> [String: Int] {
        let dict = defaults.dictionaryRepresentation()
        var ratings: [String: Int] = [:]
        for (key, value) in dict {
            if key.hasPrefix(ratingKey + "."), let intValue = value as? Int {
                let photoId = String(key.dropFirst(ratingKey.count + 1))
                ratings[photoId] = intValue
            }
        }
        return ratings
    }
}
