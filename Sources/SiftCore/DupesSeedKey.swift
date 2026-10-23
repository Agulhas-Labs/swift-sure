//
// Copyright © Agulhas Labs
//

/// One declaration named by its path and the line it starts on, the identity `DeclarationFingerprint.isSameDeclaration(as:)` compares by.
public struct DupesSeedKey: Sendable, Hashable {
    public let path: String
    public let line: Int

    public init(path: String, line: Int) {
        self.path = path
        self.line = line
    }

    init(_ fingerprint: DeclarationFingerprint) {
        self.init(path: fingerprint.declaration.path, line: fingerprint.declaration.line)
    }
}
