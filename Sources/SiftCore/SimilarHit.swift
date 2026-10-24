//
// Copyright © Agulhas Labs
//

/// One declaration the reuse nudge ranked, with the evidence that earned its place.
///
/// The shared callees travel with the score rather than being recomputed for display: a ranked list whose reasons were derived separately is a list that can disagree with itself, and the reasons are the whole point — a number alone gives a reader nothing to check.
public struct SimilarHit: Sendable {
    public let fingerprint: DeclarationFingerprint
    /// All three terms together — what the list is ordered and labelled by.
    public let score: Double
    /// The rarity-weighted callee overlap alone, which is what `SimilarityScore.calleeFloor` gates on.
    ///
    /// Carried rather than recomputed, so the number that admitted a hit is the number that scored it.
    public let calleeOverlap: Double
    /// The summed rarity weight of every shared callee, in units of a callee only one declaration names (`CalleeRarity.singleWeight`).
    ///
    /// The absolute amount the overlap fraction hides: two bodies sharing only `contains` reach 1.00 overlap on one common name, and weigh well under one unit.
    public let sharedEvidence: Double

    public init(fingerprint: DeclarationFingerprint, score: Double, calleeOverlap: Double, sharedEvidence: Double = 0) {
        self.fingerprint = fingerprint
        self.score = score
        self.calleeOverlap = calleeOverlap
        self.sharedEvidence = sharedEvidence
    }
}
