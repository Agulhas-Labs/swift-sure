//
// Copyright © Agulhas Labs
//

/// How the command in front of a shell window numbers the lines it prints.
public enum WindowNumbering: Equatable, Sendable {
    /// Nothing is numbered.
    case none
    /// `cat -n`: `%6d`, a tab, the line; `first` is the number on the first printed line.
    case catN(first: Int)
    /// `nl` (`numbersBlank` false: a blank line prints six spaces and a tab, unnumbered, and the count stays) or `nl -ba` (true).
    case numberLines(first: Int, numbersBlank: Bool)
    /// `awk '{print NR+k<sep>$0}'`: the number, the separator, the line, and always a newline.
    case awk(first: Int, separator: String)
}
