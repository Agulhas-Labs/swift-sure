//
// Copyright © Agulhas Labs
//

/// The receivers ruled out for a name's initializers, read when a scan first asks: those every initializer behind the name rules out.
struct RuledOutReceivers: Sendable {
    private var sources: [(ruling: InitReceiverRuling, type: String)]

    /// The receivers ruled out for an initializer declared in the type named `type`.
    init(ruling: InitReceiverRuling, type: String) {
        sources = [(ruling, type)]
    }

    /// Where `name` is ruled out for every initializer behind the name: everywhere only where every initializer rules it out everywhere, outside type declarations where some rule it out only there, and `nil` where any keeps it.
    func scope(of name: String) -> Scope? {
        var scope = Scope.everywhere
        for source in sources {
            let receivers = source.ruling.receivers(ruledOutForInitIn: source.type)
            if receivers.outsideTypeDeclarations.contains(name) {
                scope = .outsideTypeDeclarations
            } else if !receivers.everywhere.contains(name) {
                return nil
            }
        }
        return scope
    }

    /// The receivers both this and `other` rule out.
    func intersection(_ other: RuledOutReceivers) -> RuledOutReceivers {
        var merged = self
        merged.sources += other.sources
        return merged
    }
}

extension RuledOutReceivers {
    /// Where a ruled-out receiver is ruled out in a scanned file.
    enum Scope {
        /// At any use the file does not rebind.
        case everywhere
        /// At a use the file does not rebind outside every type, extension and protocol declaration of the file.
        case outsideTypeDeclarations
    }
}
