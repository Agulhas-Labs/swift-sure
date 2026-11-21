//
// Copyright © Agulhas Labs
//

import Foundation

/// The function a line sits in and the types around it, read from a parse of the file as it is now.
///
/// Held in memory for the one call: nothing is written to the store and no tree outlives the parse.
struct FreshFailureScope {
    /// The enclosing function's name and the container names around it for `line` in `file`; `nil` where the line sits in no function.
    static func of(line: Int, in file: ParsedFile) -> (function: String, owners: [String])? {
        var chosen: (index: Int, span: Int)?
        for (index, symbol) in file.symbols.enumerated() where symbol.line <= line && line <= symbol.endLine {
            let span = symbol.endLine - symbol.line
            if let chosen, chosen.span < span {
                continue
            }
            chosen = (index, span)
        }
        guard let chosen else {
            return nil
        }
        var chain: [ParsedSymbol] = []
        var cursor: Int? = chosen.index
        while let index = cursor {
            chain.append(file.symbols[index])
            cursor = file.symbols[index].parentIndex
        }
        chain.reverse()
        guard let function = chain.last(where: { $0.kind == .function }) else {
            return nil
        }
        return (function.name, chain.filter(\.kind.isContainer).map(\.name))
    }
}
