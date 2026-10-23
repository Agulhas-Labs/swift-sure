//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Which declarations a range makes subjects of the access section, and which of those are never judged.
struct DiffAccessSubjectPinsTests {
    private typealias Fixtures = AccessPinFixtures

    private static func exclusion(of name: String, in subjects: [AccessSubject]) -> AccessExclusion? {
        subjects.first { $0.name == name }?.exclusion
    }

    @Test func aProtocolAddedWithItsRequirementsAndAnEnumWithItsCasesAreJudgedAsTheContainer() {
        let subjects = Fixtures.subjects(old: nil, new: "public protocol Shelf {\n    func restock()\n    associatedtype Item\n}\npublic enum Mode {\n    case fast\n}\n")

        #expect(Set(subjects.map(\.name)) == ["Shelf", "Mode"])
    }

    @Test func aRequirementOrCaseAddedToAnExistingTypeIsOutsideEveryCount() {
        let protocolSubjects = Fixtures.subjects(old: "public protocol Shelf {\n}\n", new: "public protocol Shelf {\n    func restock()\n}\n")
        let enumSubjects = Fixtures.subjects(old: "public enum Mode {\n    case fast\n}\n", new: "public enum Mode {\n    case fast\n    case slow\n}\n")

        #expect(protocolSubjects.isEmpty)
        #expect(enumSubjects.isEmpty)
    }

    @Test func aPublicMemberOfAnInternalTypeIsNotASubject() {
        let subjects = Fixtures.subjects(old: nil, new: "struct Depot {\n    public func run() {}\n}\n")

        #expect(subjects.isEmpty)
    }

    @Test func aPublicMemberOfAPublicTypeAddedWithItIsASubjectBesideIt() {
        let subjects = Fixtures.subjects(old: nil, new: "public struct Depot {\n    public func run() {}\n}\n")

        #expect(subjects.map(\.name) == ["Depot", "run()"])
        #expect(subjects.map(\.level) == [.publicLevel, .publicLevel])
    }

    @Test func aRangeThatPutsNothingAtTheJudgedLevelsHasNoSubjects() {
        #expect(Fixtures.subjects(old: nil, new: "func quiet() {}\nprivate struct Depot {}\nfileprivate func hush() {}\n").isEmpty)
        #expect(Fixtures.subjects(old: "public func restock() {}\n", new: "public func restock() { _ = 1 }\n").isEmpty)
    }

    @Test func aWidenedDeclarationIsASubjectMarkedWidenedAndAnAddedOneIsNot() {
        let widened = Fixtures.subjects(old: "func restock() {}\n", new: "public func restock() {}\n")
        let added = Fixtures.subjects(old: nil, new: "public func restock() {}\n")

        #expect(widened.map(\.widened) == [true])
        #expect(added.map(\.widened) == [false])
    }

    @Test func theCompilerReachedKindsAreExcludedAsReachedByTheCompilerNeverJudged() {
        let subjects = Fixtures.subjects(old: nil, new: """
        public struct Gizmo {
            public subscript(index: Int) -> Int { index }
            public static func + (lhs: Gizmo, rhs: Gizmo) -> Gizmo { lhs }
            public func callAsFunction() {}
        }
        @resultBuilder public struct Stack {
            public static func buildBlock(_ parts: Int...) -> Int { 0 }
        }
        @propertyWrapper public struct Boxed {
            public var wrappedValue: Int
        }
        """)

        let compiler = subjects.filter { $0.exclusion == .compiler }.map(\.name)

        #expect(compiler.count == 5)
        #expect(compiler.contains("callAsFunction()"))
        #expect(compiler.contains { $0.hasPrefix("buildBlock") })
        #expect(compiler.contains("wrappedValue"))
        #expect(subjects.contains { $0.kind == .subscriptKind && $0.exclusion == .compiler })
        #expect(subjects.contains { $0.name.hasPrefix("+") && $0.exclusion == .compiler })
        #expect(AccessExclusion.compiler.label(1) == "1 reached by the compiler, not by name")
    }

    @Test func aBuildMethodOutsideAResultBuilderAndAPlainMethodAreJudged() {
        let subjects = Fixtures.subjects(old: nil, new: "public struct Gizmo {\n    public func buildBlock() {}\n    public var wrappedValue: Int\n}\n")

        #expect(subjects.allSatisfy { $0.exclusion == nil })
    }

    @Test func actionsManagedPropertiesAndRequiredInitsAreNotJudged() {
        let subjects = Fixtures.subjects(old: nil, new: """
        public class Gizmo {
            @IBAction public func tap(_ sender: Any) {}
            @NSManaged public var title: String
            public required init() {}
            public func restock() {}
        }
        """)

        #expect(Self.exclusion(of: "tap(_:)", in: subjects) == .objc)
        #expect(Self.exclusion(of: "title", in: subjects) == .objc)
        #expect(subjects.first { $0.kind == .initializer }?.exclusion == .requiredInit)
        #expect(Self.exclusion(of: "restock()", in: subjects) == nil)
    }

    @Test func overridesOpenDeclarationsAndTheirKinOnTheHeadAloneAreNotJudged() {
        let subjects = Fixtures.subjects(old: nil, new: """
        public class Gizmo: Base {
            public override func reset() {}
            @objc public func ping() {}
            @inlinable public func fast() {}
            @_spi(Depot) public func inside() {}
            public dynamic func swap() {}
            @_cdecl("gizmo_go") public func go() {}
        }
        open class Widget {}
        """)

        #expect(Self.exclusion(of: "reset()", in: subjects) == .override)
        #expect(Self.exclusion(of: "ping()", in: subjects) == .objc)
        #expect(Self.exclusion(of: "fast()", in: subjects) == .inlinable)
        #expect(Self.exclusion(of: "inside()", in: subjects) == .spi)
        #expect(Self.exclusion(of: "swap()", in: subjects) == .dynamic)
        #expect(Self.exclusion(of: "go()", in: subjects) == .entryPoint)
        #expect(Self.exclusion(of: "Widget", in: subjects) == .open)
    }
}
