//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The leases `swift-sure test` holds on the devices it creates, in the store every Fieldwork tool reads, so that nothing walking "any unleased device" takes a shard's device mid-run.
///
/// **A lease is taken the moment a device is created and given up once it is deleted.** A delete that failed keeps its lease, since a half-deleted device is no device for anybody else to take.
///
/// **Nothing renews a lease.** The holder is this process, and a holder that has exited ends its lease as surely as an expiry does: a lapsed lease on a created device is never taken over, only deleted. The term is long enough to outlast any run, so a run never has to come back for it.
///
/// **The token is the device's own**, so whichever actor deletes the device — the run, its watcher or a later run's sweep — gives up the lease without having to have been told it.
public struct ShardLeases: Sendable {
    /// The store the leases are written to.
    public let store: LeaseStore
    /// The process every lease taken here names as its holder.
    let holderPID: Int32
    private let now: @Sendable () -> Date

    public init(
        directory: URL,
        holderPID: Int32 = getpid(),
        isAlive: @escaping @Sendable (Int32) -> Bool = HolderProcess.isAlive,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        store = LeaseStore(directory: directory, isAlive: isAlive)
        self.holderPID = holderPID
        self.now = now
    }
}

public extension ShardLeases {
    /// The machine's lease store: `.simwalk/leases` under the account's home, which is where every tool that walks devices reads it whatever `HOME` says.
    static var sharedDirectory: URL {
        AgentPaths.accountHome.appendingPathComponent(".simwalk/leases", isDirectory: true)
    }

    /// The leases a real run takes, in the machine's shared store.
    static var shared: ShardLeases {
        ShardLeases(directory: sharedDirectory)
    }

    /// The directory the leases are written to.
    var directory: URL {
        store.directory
    }
}

extension ShardLeases {
    /// How long a lease is taken for: longer than any run, since nothing renews it and the holder's exit ends it first.
    static var term: TimeInterval {
        6 * 60 * 60
    }

    /// The token a lease on `udid` carries, which every actor that deletes the device can name.
    static func token(for udid: String) -> String {
        "\(ProductName.current.binary)-test-\(udid)"
    }

    /// Takes the lease on a device this run has just created, and answers why it could not, or `nil` where it did.
    ///
    /// A device that is already leased cannot be one this run just created, so a lease somebody else holds on it is answered as a failure like any other.
    func take(udid: String) -> String? {
        do {
            _ = try store.acquire(udid: udid, ttl: Self.term, holderPID: holderPID, now: now(), createdDevice: true, token: Self.token(for: udid))
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// Gives up the lease on a device whose delete went through, or found it already gone; a device still there keeps its lease.
    ///
    /// Only a lease carrying this tool's token for the device is removed, and one that is not in the store is not looked for under the store's lock.
    func release(after deletion: ShardDevices.Deletion) {
        guard deletion.failure == nil else {
            return
        }
        let token = Self.token(for: deletion.udid)
        guard (try? store.lease(onDevice: deletion.udid))??.token == token else {
            return
        }
        _ = try? store.remove(udid: deletion.udid, token: token)
    }

    /// What keeps a lease on a device from being the run's own: a live process, or a lease file nobody can read.
    enum Holding: Equatable {
        case process(Int32)
        case unreadable
    }

    /// Who other than this run keeps `udid` leased, or `nil` where nobody does.
    ///
    /// A lease carrying this tool's token for the device is never foreign: only the run that created the device holds it, and a sweep has already proved that run dead, whatever process now has its pid. A lease file that cannot be read is held, as the store treats it, since what cannot be read cannot be judged free.
    func foreignHolding(of udid: String) -> Holding? {
        let lease: DeviceLease?
        do {
            lease = try store.lease(onDevice: udid)
        } catch {
            return .unreadable
        }
        guard let lease, lease.token != Self.token(for: udid), lease.holderPID != holderPID, store.isHeld(lease, now: now()) else {
            return nil
        }
        return .process(lease.holderPID)
    }
}
