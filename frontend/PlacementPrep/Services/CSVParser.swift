import Foundation

/// Minimal RFC 4180 CSV reader.
///
/// A `split(separator: ",")` will not do for this data: the `Topics` column is
/// a quoted list that itself contains commas, e.g.
///
///     HARD,Trapping Rain Water,73.9,0.0067,https://…,"Array, Two Pointers, Stack"
///
/// so the parser has to track whether it is inside quotes. It also handles the
/// `""` escape for a literal quote, and both LF and CRLF line endings.
enum CSVParser {

    /// Splits raw CSV text into rows of fields. Empty trailing lines are dropped.
    ///
    /// Deliberately non-isolated and free of Foundation string bridging in the
    /// hot loop — it runs over ~2,300 rows per company off the main actor.
    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            endField()
            // Skip blank lines rather than emitting a row of one empty field.
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if character == "\"" {
                    // Look ahead: "" is an escaped quote, otherwise the field ends.
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
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
            case ",":
                endField()
            case "\n":
                endRow()
            case "\r":
                break // CRLF — the \n does the work.
            default:
                field.append(character)
            }
        }

        // Flush whatever the file ended on, if it wasn't a newline.
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }

        return rows
    }

    /// Parses text whose first row is a header, returning each subsequent row
    /// keyed by column name. Rows with the wrong arity are skipped rather than
    /// throwing — one malformed line should not lose a whole company.
    static func keyedRows(from text: String) -> [[String: String]] {
        let all = rows(from: text)
        guard let header = all.first else { return [] }

        return all.dropFirst().compactMap { row in
            guard row.count == header.count else { return nil }
            return Dictionary(uniqueKeysWithValues: zip(header, row))
        }
    }
}
