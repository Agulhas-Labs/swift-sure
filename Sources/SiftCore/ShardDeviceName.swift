//
// Copyright © Agulhas Labs
//

/// The name every simulator a sharded run creates carries — `swift-sure-<prefix>-<runid>-<k>`.
///
/// **The name is what makes an orphan findable with no record of it at all.** A run whose ledger was lost, or that died between `simctl create` returning and the udid reaching the ledger, leaves a device this tool has no record of; the name in `simctl`'s own listing is then the only thing that says which run made it, and the listing carries the udid beside it. So the name finds candidates and the udid does the deleting.
///
/// **Parsing is strict, and strictness is the safety property.** `swift-sure-<prefix>-<runid>-0-copy` is a device somebody duplicated by hand and a device this tool must never delete, and so is any name a person wrote that merely starts the same way: anything that is not exactly the four components in exactly this shape parses to `nil` and is never looked at again.
public struct ShardDeviceName: Equatable, Sendable {
    /// The six hex characters of the checkout that created the device.
    public let prefix: String
    /// The eight hex characters of the run that created it.
    public let runID: String
    /// Which shard of that run it was created for, from zero.
    public let index: Int

    public init(prefix: String, runID: String, index: Int) {
        self.prefix = prefix
        self.runID = runID
        self.index = index
    }
}

public extension ShardDeviceName {
    /// The name as `simctl` is given it.
    var text: String {
        "\(Self.marker)-\(prefix)-\(runID)-\(index)"
    }

    /// The name a device in `simctl`'s listing carries, or `nil` where that name was not written by this tool.
    ///
    /// Every component is checked: the marker, six lowercase hex, eight lowercase hex, and an index spelled the one way this tool spells it — so `-00` and `-0-copy` are both somebody else's names.
    init?(parsing text: String) {
        guard let tail = Self.markers.lazy.compactMap({ marker in text.hasPrefix(marker + "-") ? String(text.dropFirst(marker.count + 1)) : nil }).first else {
            return nil
        }
        let components = tail.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 3 else {
            return nil
        }
        guard Self.isHexadecimal(components[0], count: Self.prefixLength), Self.isHexadecimal(components[1], count: Self.runIDLength) else {
            return nil
        }
        guard let index = Int(components[2]), index >= 0, String(index) == components[2] else {
            return nil
        }
        self.init(prefix: components[0], runID: components[1], index: index)
    }

    /// The word every one of this tool's device names opens with.
    static var marker: String {
        ProductName.current.binary
    }

    /// Every word a device name may open with: the current one, then the previous release's, whose dead runs left devices behind.
    static var markers: [String] {
        ProductName.recognised.map(\.binary)
    }

    /// How many hex characters a checkout's prefix carries.
    static var prefixLength: Int {
        6
    }

    /// How many hex characters a run's identifier carries.
    static var runIDLength: Int {
        8
    }

    /// Whether `text` is exactly `count` lowercase hex characters — the spelling both identifiers are minted in.
    static func isHexadecimal(_ text: String, count: Int) -> Bool {
        text.count == count && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
