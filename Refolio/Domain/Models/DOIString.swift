import Foundation

enum DOIString {
    /// Canonicalizes a DOI for storage and comparison: strips `doi:` and
    /// `https://doi.org/` style prefixes, then requires a `10.` registrant prefix.
    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:"] {
            if value.lowercased().hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                break
            }
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("10."), !value.contains(where: \.isWhitespace) else {
            return nil
        }
        return value
    }
}
