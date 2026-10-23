//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Covers recognising this tool's status-line command, the one test the removal of an older install's status line goes by.
struct StatuslineRegistrationTests {
    @Test
    func ourCommandIsRecognisedAtAnyPathAndOthersAreNot() {
        #expect(StatuslineRegistration.isOurs("/anywhere/swift-sure statusline"))
        #expect(StatuslineRegistration.isOurs("~/.claude/statusline.sh") == false)
        #expect(StatuslineRegistration.isOurs("/anywhere/swift-sure session-start") == false)
        #expect(StatuslineRegistration.isOurs(nil) == false)
    }

    /// An earlier release registered its status line under the name it shipped as, and a re-run must still find it.
    @Test
    func anEarlierReleasesCommandIsRecognisedAndAnotherToolsIsNot() {
        #expect(StatuslineRegistration.isOurs("/opt/old/bin/sift statusline"))
        #expect(StatuslineRegistration.isOurs("sift statusline"))
        #expect(StatuslineRegistration.isOurs("/opt/old/bin/sift session-start") == false)
        #expect(StatuslineRegistration.isOurs("/opt/old/bin/sifter statusline") == false)
    }
}
