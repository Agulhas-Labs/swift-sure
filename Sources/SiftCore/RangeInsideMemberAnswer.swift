//
// Copyright © Agulhas Labs
//

/// The answer for lines of a file asked for by range that lie inside one long member: those lines alone, under one header naming the member and its whole range.
///
/// Serving a long member whole for a few lines inside it hands back many times what was asked — the ranged read a cited location replaces would have been the smaller answer. The lines are paged like a member body, by the same range and an offset. A single line asked for is the question a stack trace or a log line puts — which function is this in — so it is those lines with 3 either side, numbered as Read numbers them (the number right-aligned to 6 columns, a tab, the source line; the cited line marked with `>` for the first padding space), under the header that names the member and its whole range, with no declaration, skip markers or footer repeating what the header says.
struct RangeInsideMemberAnswer {
    let renderer: DigestRenderer

    /// Lines either side of a single line asked for inside a long member: enough to read the line in its place, where the whole member says far more than was asked.
    static var lineWindowContext: Int {
        3
    }

    /// The longest member a single line inside is served whole from: past it, the declaration and the line's window answer which function the line is in for a fraction of the member.
    static var singleLineMemberCeiling: Int {
        25
    }

    /// The lines `range` asks of `row`, or `nil` where the member is served whole as before: when it is within the ceiling for what was asked (`singleLineMemberCeiling` for one line, the source floor for a range), when the lines reach past it, or when they cover all of it.
    func answer(_ row: SymbolRow, range: DigestLineRange, walk: DigestRenderer.RangeWalk, source: [String], options: DigestOptions) throws -> String? {
        let memberStart = walk.start(of: row)
        let memberLines = row.endLine - row.line + 1
        let single = range.start == range.end
        guard memberLines > (single ? Self.singleLineMemberCeiling : SourcePassthrough.floorLineCeiling),
              memberStart <= range.start, range.end <= row.endLine,
              row.line < range.start || range.end < row.endLine,
              row.endLine <= source.count
        else {
            return nil
        }
        let window = single
            ? max(memberStart, range.start - Self.lineWindowContext) ... min(row.endLine, range.end + Self.lineWindowContext)
            : range.start ... range.end
        let asked = single
            ? "lines \(window.lowerBound)-\(window.upperBound) (line \(range.start) with up to \(Self.lineWindowContext) lines either side)"
            : range.spoken
        return try served(row, lines: source[(window.lowerBound - 1) ..< window.upperBound], asked: asked, cited: single ? range.start : nil, resumeTarget: range.path + range.suffix, options: options)
    }

    /// Whether `clipped` serves `row` as its lines inside `range`: the range cuts into it and it runs past the range's start or end by more than `lineWindowContext` lines.
    func clips(_ row: SymbolRow, range: DigestLineRange, walk: DigestRenderer.RangeWalk, source: [String]) -> Bool {
        (range.start < walk.start(of: row) || row.endLine < range.end)
            && (row.line < range.start - Self.lineWindowContext || row.endLine > range.end + Self.lineWindowContext)
            && row.endLine <= source.count
    }

    /// The part of `row` that `range` covers, where the range cuts into it and the member runs past the range's start or end by more than `lineWindowContext` lines, or `nil` where the member is served whole: it fits the range to within that margin, or the range lies inside it (`answer` decides that case).
    ///
    /// A leaf a range only partly covers costs more whole than clipped, whatever its length, so its lines inside the range are served under the header that names the leaf and its whole range. The call that pages the clipped lines is passed in.
    func clipped(_ row: SymbolRow, range: DigestLineRange, walk: DigestRenderer.RangeWalk, source: [String], options: DigestOptions, resumeTarget: String) throws -> String? {
        guard clips(row, range: range, walk: walk, source: source) else {
            return nil
        }
        let memberStart = walk.start(of: row)
        let window = max(range.start, memberStart) ... min(range.end, row.endLine)
        let asked = "lines \(window.lowerBound)-\(window.upperBound)"
        return try served(row, lines: source[(window.lowerBound - 1) ..< window.upperBound], asked: asked, cited: nil, resumeTarget: resumeTarget, options: options)
    }

    /// `lines` of `row`, a slice of the file's lines, under the header naming the member and its whole range, paged like a member body; `cited` numbers the lines as Read does, marking that line.
    private func served(_ row: SymbolRow, lines: ArraySlice<String>, asked: String, cited: Int?, resumeTarget: String, options: DigestOptions) throws -> String {
        let memberLines = row.endLine - row.line + 1
        let target = try renderer.qualifiedTarget(of: row)
        let header = "\(row.path) \(asked), in \(target) — \(row.kind.rawValue) — \(row.rangeDescription) (\(memberLines) lines; digest \(target) for all of it)"
        let all = Array(lines)
        let firstLine = lines.startIndex + 1
        let cap = DigestCaps.bodyLineCap
        let preamble = try renderer.parseErrorBanner(touching: [row.path]) + renderer.guessedModuleBanner(touching: [row.path])
        if PastEndLine.applies(offset: options.offset, count: all.count) {
            return (preamble + [header, "", PastEndLine.text(offset: options.offset, count: all.count, noun: "body lines")]).joined(separator: "\n")
        }
        let offset = min(max(0, options.offset), all.count)
        var body = Array(all.dropFirst(offset).prefix(cap))
        if let cited {
            body = ReadNumbering.numbered(body, from: firstLine + offset, cited: cited)
        } else if offset > 0 {
            body.insert("(…\(offset) lines skipped)", at: 0)
        }
        let remaining = all.count - offset - min(cap, all.count - offset)
        if remaining > 0 {
            let resume = options.spelling.digest(resumeTarget, offset: offset + cap)
            body.append("… truncated: \(remaining) more lines — \(resume), or Read \(row.path) from line \(firstLine + offset + cap)")
        }
        return (preamble + [header, ""] + body).joined(separator: "\n")
    }
}
