import Testing
@testable import PlacementPrep

@Suite("CSVParser")
struct CSVParserTests {

    @Test func plainRows() {
        #expect(CSVParser.rows(from: "a,b,c\nd,e,f") == [["a", "b", "c"], ["d", "e", "f"]])
    }

    @Test func quotedFieldWithCommas() {
        let rows = CSVParser.rows(from: #"EASY,Two Sum,"Array, Hash Table""# + "\n")
        #expect(rows == [["EASY", "Two Sum", "Array, Hash Table"]])
    }

    @Test func escapedQuotes() {
        // `"He said ""hi"""` and `""""` (a field holding a single quote).
        let text = "\"He said \"\"hi\"\"\",x\n\"\"\"\",y\n"
        let rows = CSVParser.rows(from: text)
        #expect(rows == [["He said \"hi\"", "x"], ["\"", "y"]])
    }

    @Test func quotedFieldKeepsNewlines() {
        let rows = CSVParser.rows(from: "\"line one\nline two\",z\n")
        #expect(rows == [["line one\nline two", "z"]])
    }

    /// Swift treats "\r\n" as a single Character, so CSVParser works on Unicode scalars
    /// to see CRLF as a row end (regression: CRLF files used to collapse into one row).
    @Test(arguments: [
        ("a,b\r\nc,d\r\n", [["a", "b"], ["c", "d"]]),
        ("a,b\r\nc,d", [["a", "b"], ["c", "d"]]),
        ("a,\"b\"\r\nc,d", [["a", "b"], ["c", "d"]]),
        ("a,b\r\n\r\nc,d\r\n\r\n", [["a", "b"], ["c", "d"]]),
    ])
    func crlfLineEndings(text: String, expected: [[String]]) {
        #expect(CSVParser.rows(from: text) == expected)
    }

    @Test(arguments: [
        ("a,b\rc,d\r", [["a", "b"], ["c", "d"]]),
        ("a,b\rc,d", [["a", "b"], ["c", "d"]]),
        ("a,\"b\"\rc,d", [["a", "b"], ["c", "d"]]),
        ("a,b\r\rc,d", [["a", "b"], ["c", "d"]]),
    ])
    func crOnlyLineEndings(text: String, expected: [[String]]) {
        #expect(CSVParser.rows(from: text) == expected)
    }

    @Test func mixedLineEndings() {
        #expect(CSVParser.rows(from: "a,b\r\nc,d\ne,f\rg,h") == [["a", "b"], ["c", "d"], ["e", "f"], ["g", "h"]])
    }

    @Test func crlfInsideQuotesIsPreserved() {
        #expect(CSVParser.rows(from: "\"x\r\ny\",z\n") == [["x\r\ny", "z"]])
    }

    @Test func lineBreaksInsideQuotesArePreservedInCRLFFile() {
        let text = "id,notes\r\n1,\"first\r\nsecond\rthird\nfourth\"\r\n2,plain\r\n"
        #expect(CSVParser.rows(from: text) == [
            ["id", "notes"],
            ["1", "first\r\nsecond\rthird\nfourth"],
            ["2", "plain"],
        ])
    }

    @Test func trailingNewlineDoesNotAddRow() {
        #expect(CSVParser.rows(from: "a,b\n") == [["a", "b"]])
        #expect(CSVParser.rows(from: "a,b\n\n") == [["a", "b"]])
        #expect(CSVParser.rows(from: "a,b") == [["a", "b"]])
    }

    @Test func blankLinesAreSkippedButEmptyFieldsKept() {
        #expect(CSVParser.rows(from: "a,b\n\nc,\n") == [["a", "b"], ["c", ""]])
        #expect(CSVParser.rows(from: ",") == [["", ""]])
    }

    @Test func emptyInput() {
        #expect(CSVParser.rows(from: "").isEmpty)
        #expect(CSVParser.keyedRows(from: "").isEmpty)
    }

    @Test func keyedRowsMapsHeader() {
        let text = """
        Difficulty,Title,Topics
        EASY,Two Sum,"Array, Hash Table"
        HARD,Median of Two Sorted Arrays,Binary Search

        """
        let rows = CSVParser.keyedRows(from: text)
        #expect(rows.count == 2)
        #expect(rows[0] == ["Difficulty": "EASY", "Title": "Two Sum", "Topics": "Array, Hash Table"])
        #expect(rows[1]["Title"] == "Median of Two Sorted Arrays")
        #expect(rows[1]["Topics"] == "Binary Search")
    }

    @Test func keyedRowsDropsRowsWithWrongFieldCount() {
        let text = "A,B\n1,2\n3\n4,5,6\n7,8\n"
        #expect(CSVParser.keyedRows(from: text) == [["A": "1", "B": "2"], ["A": "7", "B": "8"]])
    }

    @Test func keyedRowsHeaderOnly() {
        #expect(CSVParser.keyedRows(from: "A,B\n").isEmpty)
    }

    @Test func keyedRowsWithCRLFHeader() {
        let rows = CSVParser.keyedRows(from: "Title,Link\r\nTwo Sum,https://x\r\n")
        #expect(rows == [["Title": "Two Sum", "Link": "https://x"]])
    }

    @Test func keyedRowsWithCROnlyLineEndings() {
        let rows = CSVParser.keyedRows(from: "Title,Link\rTwo Sum,https://x\r")
        #expect(rows == [["Title": "Two Sum", "Link": "https://x"]])
    }

    /// `Dictionary(uniqueKeysWithValues:)` used to trap on duplicate header names.
    @Test func keyedRowsWithDuplicateHeadersKeepsFirstColumn() {
        let text = "Title,Link,Title\nTwo Sum,https://x,Duplicate\nThree Sum,https://y,Other\n"
        let rows = CSVParser.keyedRows(from: text)
        #expect(rows == [
            ["Title": "Two Sum", "Link": "https://x"],
            ["Title": "Three Sum", "Link": "https://y"],
        ])
    }
}
