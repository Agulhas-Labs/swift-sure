//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The diagnostics in a search's or a command's output, located: each site's enclosing declaration and its numbered source line.
///
/// A log-triage search prints `…/Producer.swift:861:13: error: …`, and the reader's next move is always to ask which function line 861 is in. This answers it in the hook that sees the output, from a fresh parse of the file on disk, so it cannot be stale and never touches the index. A path printed on another machine is mapped to the repository file whose path ends the same way, and a site that maps to no file, or to more than one, is left out.
public struct DiagnosticSites {
    /// Sites named at most, in order of appearance.
    static var siteCap: Int {
        5
    }

    /// Sites shown with the lines around them, as `digest File.swift:LINE` shows a cited line; a later site shows its own line alone.
    ///
    /// The cited line alone, with the declaration's range beside it, sent readers to read the whole declaration raw (a 36-line `Read` where the window this replaces was 7 lines), which cost more than the turn the note saved.
    static var windowedSites: Int {
        2
    }

    /// Lines shown either side of a windowed site, inside its declaration.
    static var windowRadius: Int {
        3
    }

    /// The fewest trailing path components a foreign path and a repository file must share: the file name and one directory.
    static var sharedComponentFloor: Int {
        2
    }

    /// The one block locating the diagnostics in `response`, or `nil` where it holds none that resolve.
    ///
    /// Returns before any pattern or file work when `response` holds no `.swift:`. Relative paths resolve against `cwd`; `root` is the repository the paths map into. Stops starting sites once `deadline` passes.
    public static func note(forResponse response: String, cwd: String?, root: String, deadline: Date) -> String? {
        guard response.contains(".swift:") else { return nil }
        let sites = sites(in: response)
        guard !sites.isEmpty else { return nil }
        let rootURL = URL(fileURLWithPath: root)
        var listing: [String]?
        var lines: [String] = []
        let logs = runLogs(in: response)
        for site in sites {
            guard deadline.timeIntervalSinceNow > 0 else { break }
            guard let path = repositoryPath(of: site.path, cwd: cwd, root: rootURL, listing: &listing),
                  let located = locate(site, at: path, under: rootURL, windowed: lines.count < windowedSites, logs: logs)
            else {
                continue
            }
            lines.append(located)
        }
        guard !lines.isEmpty else { return nil }
        return (["\(ProductName.current.binary): the diagnostics above, located:"] + lines).joined(separator: "\n")
    }

    /// The log path each `raw:` line of `response` names, with where in `response` the line starts.
    private static func runLogs(in response: String) -> [(offset: Int, path: String)] {
        guard let pattern = try? NSRegularExpression(pattern: #"^raw: .*? · (.+?\.log)(?: \(|$)"#, options: .anchorsMatchLines) else { return [] }
        let text = response as NSString
        return pattern.matches(in: response, range: NSRange(location: 0, length: text.length)).map {
            (offset: $0.range.location, path: text.substring(with: $0.range(at: 1)))
        }
    }

    /// The line saying the file at `path` changed after the run whose log is the first `raw:` line after `site`, or `nil` where there is no such log or the file is not newer than it.
    private static func changedNote(site: Site, path: String, under root: URL, logs: [(offset: Int, path: String)]) -> String? {
        guard let log = logs.first(where: { $0.offset > site.offset }),
              let logged = (try? FileManager.default.attributesOfItem(atPath: log.path.hasPrefix("/") ? log.path : root.appendingPathComponent(log.path).path))?[.modificationDate] as? Date,
              let changed = FileChangeStat.of(path: root.appendingPathComponent(path).path)?.changed,
              changed > logged.timeIntervalSince1970
        else {
            return nil
        }
        return "  \((path as NSString).lastPathComponent) changed after this diagnostic; the lines below are the file as it is now"
    }

    /// The distinct file-and-line sites `response` prints as an error or a warning, first ``siteCap`` in order of appearance.
    static func sites(in response: String) -> [Site] {
        guard let pattern = try? NSRegularExpression(pattern: #"([^\s:'"()]+\.swift):(\d+):\d+: (?:error|warning):"#) else { return [] }
        let text = response as NSString
        var found: [Site] = []
        pattern.enumerateMatches(in: response, range: NSRange(location: 0, length: text.length)) { match, _, stop in
            guard let match, let line = Int(text.substring(with: match.range(at: 2))), line > 0 else { return }
            let site = Site(path: text.substring(with: match.range(at: 1)), line: line, offset: match.range.location)
            // A site printed again keeps its place in the order but takes the later offset, so it pairs with the log of the run that printed it last.
            if let seen = found.firstIndex(of: site) {
                found[seen] = site
            } else {
                found.append(site)
            }
            if found.count == siteCap {
                stop.pointee = true
            }
        }
        return found
    }

    /// The repository-relative path `printed` names, or `nil` where it names no one file here.
    ///
    /// A path that resolves to a file inside the repository is that file; otherwise (including a relative path that names no file under the working directory) it is matched by its trailing components against the files git lists, and the longest match wins unless two files tie. A path outside the repository that resolves to a file on this machine, such as another checkout of the same repository, is none of this repository's files, and its line numbers are not read against one.
    private static func repositoryPath(of printed: String, cwd: String?, root: URL, listing: inout [String]?) -> String? {
        let absolute = printed.hasPrefix("/") ? printed : URL(fileURLWithPath: cwd ?? root.path).appendingPathComponent(printed).path
        let prefix = CanonicalPath.of(root.path) + "/"
        let canonical = CanonicalPath.of(absolute)
        if canonical.hasPrefix(prefix), FileManager.default.fileExists(atPath: canonical) {
            return String(canonical.dropFirst(prefix.count))
        }
        if FileManager.default.fileExists(atPath: canonical) {
            return nil
        }
        if listing == nil {
            listing = (try? GitContext(repoRoot: root).visibleSwiftFiles()) ?? []
        }
        let printedParts = printed.split(separator: "/")
        var best: (path: String, shared: Int)?
        var tied = false
        for candidate in listing ?? [] {
            let shared = sharedTail(printedParts, candidate.split(separator: "/"))
            guard shared >= sharedComponentFloor else { continue }
            if let current = best, shared == current.shared {
                tied = true
            } else if shared > (best?.shared ?? 0) {
                best = (candidate, shared)
                tied = false
            }
        }
        return tied ? nil : best?.path
    }

    /// How many trailing components `left` and `right` share.
    private static func sharedTail(_ left: [Substring], _ right: [Substring]) -> Int {
        var count = 0
        while count < left.count, count < right.count, left[left.count - 1 - count] == right[right.count - 1 - count] {
            count += 1
        }
        return count
    }

    /// The lines locating `site` in the repository file `path` — its heading, a line saying so where the file changed after the run that printed the diagnostic, then the cited line marked `>` among up to ``windowRadius`` lines either side inside its declaration where `windowed`, or alone — or `nil` where the file is unreadable, the line is past its end or no declaration holds it.
    private static func locate(_ site: Site, at path: String, under root: URL, windowed: Bool, logs: [(offset: Int, path: String)]) -> String? {
        let url = root.appendingPathComponent(path)
        guard let data = FileManager.default.contents(atPath: url.path), let text = String(data: data, encoding: .utf8) else { return nil }
        let source = text.components(separatedBy: "\n")
        guard site.line <= source.count,
              let parsed = FileParser.parse(absoluteURL: url, repoRelativePath: path),
              let declaration = RunFailureSites.Declaration(enclosing: site.line, in: parsed)
        else {
            return nil
        }
        let range = declaration.startLine == declaration.endLine ? "\(declaration.startLine)" : "\(declaration.startLine)-\(declaration.endLine)"
        let shown = windowed
            ? max(declaration.startLine, site.line - windowRadius) ... min(declaration.endLine, source.count, site.line + windowRadius)
            : site.line ... site.line
        let width = String(shown.upperBound).count
        let rows = shown.map { number in
            let code = source[number - 1].replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            let label = String(repeating: " ", count: width - String(number).count) + String(number)
            return "  \(number == site.line ? ">" : " ") \(label)| \(code)"
        }
        let heading = "  \(path):\(site.line) — in \(declaration.name) :\(range)"
        let changed = changedNote(site: site, path: path, under: root, logs: logs)
        return ([heading] + (changed.map { [$0] } ?? []) + rows).joined(separator: "\n")
    }
}

extension DiagnosticSites {
    /// One printed diagnostic location.
    struct Site: Equatable {
        let path: String
        let line: Int
        /// Where in the response the diagnostic starts; not part of a site's identity.
        let offset: Int

        static func == (left: Site, right: Site) -> Bool {
            left.path == right.path && left.line == right.line
        }
    }
}
