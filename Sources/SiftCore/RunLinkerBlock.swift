//
// Copyright © Agulhas Labs
//

import Foundation

/// The linker's own block of a link failure — an `Undefined symbols for architecture …:` header with its symbols, or one or more `duplicate symbol '…' in:` headers with their object files — and the `ld:` and `clang:` lines that close it, kept in a bounded form.
///
/// A header means nothing without its symbols, so they are kept, but a linker dumps one block per symbol and a hundred missing symbols would be a log again. Each symbol keeps its own line and its first references, and past ``RunDiagnosticRecord/linkerSymbolCap`` symbols one line says how many more there were.
///
/// Once a closing line has been taken, only closing lines continue the block: a further header opens the next block, so its symbols are counted against the cap of their own block.
struct RunLinkerBlock {
    let kind: Kind
    /// The lines kept: the header first, then the kept symbols, the omission line, the closing lines.
    private(set) var lines: [String]
    private var symbols = 0
    private var symbolIndent: Int?
    private var indentedKept = 0
    private var omissionWritten = false
    private var symbolLineCount: Int?

    /// Reads `line` as the opening of a block, with or without the manifest and product SwiftPM 6.4 puts before the linker's own words.
    init?(opening line: String) {
        let namesTheManifest = line.hasPrefix("Package.swift: ") || line.contains("/Package.swift: ")
        let linkerWords = line.hasPrefix("Undefined symbols") || line.hasPrefix("duplicate symbol ")
        var header = line
        if !linkerWords {
            guard namesTheManifest, let range = line.range(of: ": Undefined symbols") ?? line.range(of: ": duplicate symbol ") else {
                return nil
            }
            header = String(line[line.index(range.lowerBound, offsetBy: 2)...])
        }
        if header.hasPrefix("Undefined symbols") {
            kind = .undefined
        } else if header.hasPrefix("duplicate symbol ") {
            kind = .duplicate
            symbols = 1
        } else {
            return nil
        }
        lines = [header]
    }

    /// Takes `line` into the block, or returns false when the block has ended.
    mutating func accept(_ line: String) -> Bool {
        let namesTheManifest = line.hasPrefix("Package.swift: ") || line.contains("/Package.swift: ")
        if kind == .duplicate, symbolLineCount == nil, line.hasPrefix("duplicate symbol ") {
            symbols += 1
            indentedKept = 0
            if symbols <= RunDiagnosticRecord.linkerSymbolCap {
                lines.append(line)
            }
            return true
        }
        if line.first?.isWhitespace == true {
            acceptIndented(line)
            return true
        }
        guard line.hasPrefix("ld: ") || line.hasPrefix("clang: error:") || namesTheManifest && line.contains(": clang: error:") else {
            return false
        }
        writeOmission()
        symbolLineCount = symbolLineCount ?? lines.count
        lines.append(line)
        return true
    }

    /// What tells this block from another with the same header: the header and the symbols kept under it, without the closing lines, which carry the product's name.
    var identityLines: [String] {
        Array(lines.prefix(symbolLineCount ?? lines.count))
    }

    /// Adds the omission line if symbols were left out and it has not been written yet; called as the block closes too, for a log that ends before the linker's closing line.
    mutating func writeOmission() {
        guard !omissionWritten else {
            return
        }
        omissionWritten = true
        let omitted = symbols - RunDiagnosticRecord.linkerSymbolCap
        if omitted > 0 {
            lines.append("  … and \(omitted) more \(kind.word) symbols")
        }
    }

    private mutating func acceptIndented(_ line: String) {
        let indent = line.prefix { $0.isWhitespace }.count
        if kind == .undefined, indent <= (symbolIndent ?? indent) {
            symbolIndent = indent
            symbols += 1
            indentedKept = 0
            if symbols <= RunDiagnosticRecord.linkerSymbolCap {
                lines.append(line)
            }
            return
        }
        guard symbols <= RunDiagnosticRecord.linkerSymbolCap, indentedKept < kind.linesPerSymbol else {
            return
        }
        indentedKept += 1
        lines.append(line)
    }
}

extension RunLinkerBlock {
    enum Kind {
        case undefined
        case duplicate

        /// How many of a symbol's indented lines are kept: the first reference of an undefined symbol, the first two object files of a duplicate one.
        var linesPerSymbol: Int {
            switch self {
            case .undefined: 1
            case .duplicate: 2
            }
        }

        var word: String {
            switch self {
            case .undefined: "undefined"
            case .duplicate: "duplicate"
            }
        }
    }
}
