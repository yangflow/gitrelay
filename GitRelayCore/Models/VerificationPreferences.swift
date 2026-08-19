import Foundation

struct VerificationPreferences: Equatable, Codable {
    var frequency: VerificationFrequency
    var sampleSize: Int

    static let `default` = VerificationPreferences(frequency: .week1, sampleSize: 3)

    static let sampleSizeRange = 1...50

    init(frequency: VerificationFrequency = .week1, sampleSize: Int = 3) {
        self.frequency = frequency
        self.sampleSize = Self.clampedSampleSize(sampleSize)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decodeIfPresent(VerificationFrequency.self, forKey: .frequency) ?? .week1
        sampleSize = Self.clampedSampleSize(
            try container.decodeIfPresent(Int.self, forKey: .sampleSize) ?? 3
        )
    }

    static func clampedSampleSize(_ value: Int) -> Int {
        min(max(value, sampleSizeRange.lowerBound), sampleSizeRange.upperBound)
    }
}
