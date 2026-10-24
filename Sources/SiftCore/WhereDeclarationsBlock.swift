//
// Copyright © Agulhas Labs
//

import Foundation

extension WhereRenderer {
    /// The declarations block of a `where` answer: its lines, the paths it cites, and the extension listings its rows were annotated from.
    struct DeclarationsBlock {
        let lines: [String]
        let cited: [String]
        let extensionListings: DeclaredExtensions.Listings
        let printedExtensions: Set<Int64>
    }

    /// The last line of a `--decl` answer: what it left out, and the query, as the caller wrote it, that covers it.
    static func declarationsOnlyPointer(query: String) -> String {
        "`where \(query)` without --decl covers its uses, extensions, conformers, callers and overrides."
    }

    /// The most lines a declaration may span for `--decl` to print its source under its row.
    ///
    /// Measured on the 022c bench transcripts: a definition lookup was followed by a ranged Read in 3 of 3 runs on a 17-line enum and in 2 of 3 on a 4-line function, a request, its result and the path-scoped rule's load (about 650 tokens net) to see the body the row only pointed at.
    static var inlinedDeclarationLineCap: Int {
        30
    }

    /// The most source lines one `--decl` answer prints under its rows, so a name with several small declarations stays the size of one lookup.
    static var inlinedAnswerLineCap: Int {
        40
    }

    /// The heading, the rows (an extension with its member count and mark), the cut line and the compact form's `signatures:` line.
    ///
    /// Under `declarationsOnly` a cut line that would name rows the extensions block lists points on to the answer that has the block instead, since `--offset` pages none of this.
    func declarationsBlock(_ declarations: [SymbolRow], query: String, written: String, declarationsOnly: Bool) throws -> DeclarationsBlock {
        var lines: [String] = []
        var cited: [String] = []
        let compact = declarations.count > Self.compactDeclarationThreshold
        lines.append("declarations (\(declarations.count)):")
        filesCollector?.recordDeclarationsHeading("declarations (\(declarations.count)):")
        // A type's own declaration leads its extensions, whatever its file sorts as: it is the row that says what the
        // name is, and a reader who takes the head of a long list of extensions would otherwise never see it.
        let listed = declarations.filter { $0.kind != .extensionKind } + declarations.filter { $0.kind == .extensionKind }
        // Every declaration, not the listed ones: the view names each file that declares the query, past the list's cap too.
        try filesCollector?.recordDeclarations(listed, qualifiedName: qualifiedName(of:))
        // An extension printed here is not printed again by the block under its type, and carries what that block would have said of it: its member count, and the mark on a row that may not be the type's.
        let extensionListings = try extensionListings(of: declarations)
        let printedExtensions = Set(listed.prefix(Self.listCap).filter { $0.kind == .extensionKind }.map(\.id))
        var inlinedTotal = 0
        var stillInlining = declarationsOnly && !compact
        for row in listed.prefix(Self.listCap) {
            cited.append(row.path)
            let (memberCount, mark) = try DeclaredExtensions.annotation(of: row, listings: extensionListings, owners: declarations, in: store)
            try lines.append(row.declarationLine(qualifiedName: qualifiedName(of: row), compact: compact, condition: IfConfigLabel.label(for: row, source: fileSource), memberCount: memberCount, mark: mark))
            // Rows go in printed order. Only a row that would take the total past the cap ends inlining, so the answer never shows a gap;
            // a row over the row cap, an extension and an unreadable or stale row are skipped and the rows after them go on.
            if stillInlining, let source = inlinedSource(of: row) {
                if inlinedTotal + source.count <= Self.inlinedAnswerLineCap {
                    lines += source
                    inlinedTotal += source.count
                } else {
                    stillInlining = false
                }
            }
        }
        if declarations.count > Self.listCap {
            var tail = DeclaredExtensions.truncationTail(cut: listed.dropFirst(Self.listCap), listings: extensionListings, printed: printedExtensions, blockCap: Self.listCap)
            if declarationsOnly, !tail.isEmpty {
                tail = " — where \(written) lists " + tail.dropFirst(2)
            }
            lines.append("  truncated: \(declarations.count - Self.listCap) more declarations\(tail)")
        }
        if compact {
            lines.append("  signatures: digest \(query) for any one of these")
        }
        return DeclarationsBlock(lines: lines, cited: cited, extensionListings: extensionListings, printedExtensions: printedExtensions)
    }

    /// The row's own lines, numbered as Read numbers them, or `nil` where it is an extension, spans more than the per-row cap, or its file cannot be read or ends before the row does.
    private func inlinedSource(of row: SymbolRow) -> [String]? {
        let count = row.endLine - row.line + 1
        guard row.kind != .extensionKind, count >= 1, count <= Self.inlinedDeclarationLineCap,
              let text = fileSource?(row.path) else { return nil }
        let all = text.components(separatedBy: "\n")
        guard row.endLine <= all.count else { return nil }
        let own = all[(row.line - 1) ..< row.endLine].map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        return ReadNumbering.numbered(own, from: row.line, cited: nil)
    }
}
