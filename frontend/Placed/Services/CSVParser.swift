import Foundation

enum CSVParser {
    /// Parses RFC 4180-style CSV. Rows end at "\n", "\r\n" or a lone "\r" outside quotes;
    /// inside quotes every character (including line breaks) is kept as field content.
    ///
    /// Iterates Unicode scalars rather than Characters: Swift treats "\r\n" as a single
    /// Character, and a quote or comma followed by a combining mark would merge into one
    /// Character too, so scalar-level matching is the only reliable way to see delimiters.
    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = String.UnicodeScalarView()
        var row: [String] = []
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
        }

        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let scalar = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if scalar == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
                continue
            }

            switch scalar {
            case "\"":
                inQuotes = true
            case ",":
                endField()
            case "\n":
                endRow()
            case "\r":
                // "\r\n" or a lone "\r" (classic Mac) both end the row.
                endRow()
                if let next = iterator.next(), next != "\n" {
                    pending = next
                }
            default:
                field.append(scalar)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            endRow()
        }

        return rows
    }

    static func keyedRows(from text: String) -> [[String: String]] {
        let all = rows(from: text)
        guard let header = all.first else { return [] }

        return all.dropFirst().compactMap { row in
            guard row.count == header.count else { return nil }
            // Duplicate header names: the first column wins (uniqueKeysWithValues would trap).
            return Dictionary(zip(header, row), uniquingKeysWith: { first, _ in first })
        }
    }
}
