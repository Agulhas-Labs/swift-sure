# The tap formula for swift-sure. Generated from this template by Distribution/homebrew/build.sh, which
# fills in the version and the checksum of the release it is cutting — never edit those by hand.
#
# The URL is built from the artifact being released, not from a filename pattern: `make-dist.sh`
# stamps a public-commit or source-tree hash into the name it produces, so a pattern here would point at a file that is never
# uploaded under that name.
#
# The formula installs the binary, the agent rule and the docs, and stops there. The docs go into one
# directory with the layout the release bundle has, so the links between them resolve as they do there.
# Registering the MCP server and
# the hooks writes to ~/.claude, which is the user's own configuration and shared with tools this one
# does not own, so it stays an explicit command in the caveats rather than something a package
# manager does to you. `swift-sure install` is that explicit command: it finds Claude Code, Cursor and Codex
# and sets swift-sure up in the ones you accept.
class SwiftSure < Formula
  desc "Swift code index and truthful build/test runner for AI coding agents"
  homepage "https://github.com/Agulhas-Labs/swift-sure"
  url "@URL@"
  sha256 "@SHA256@"
  license "Apache-2.0"

  depends_on arch: :arm64
  depends_on macos: :ventura

  def install
    bin.install "swift-sure"
    pkgshare.install "SwiftSure.md", "INSTALL.md", "README.md", "CHANGELOG.md", "Docs",
                     "LICENSE.txt", "THIRD-PARTY-NOTICES.txt"
  end

  def caveats
    <<~EOS
      Installing this package does not write to ~/.claude, which is your own configuration. To set swift-sure
      up in Claude Code, Cursor and Codex (the server, and the hooks that make an agent reach for it):

        swift-sure install

      It finds each agent, asks once per agent, and says what it wrote; run without a terminal (by an
      agent, say) it asks nothing and installs nothing, so name the agent: `swift-sure install --agent claude`.
      Then, in a Swift repository, `swift-sure status` — the first query indexes it. On an upgrade a running Claude Code session's server
      re-execs into the new binary and the hooks apply at once; after a first install, and for the session primer, the
      tool list and the rule file, start a NEW one (restart Cursor; restart Codex and approve the trust prompt it shows).

      The docs (README.md, INSTALL.md, CHANGELOG.md and the full reference, Docs/Guide.md) are in
        #{opt_pkgshare}
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/swift-sure --version")
    # A repository is what it answers about, and refusing to answer outside one is the contract.
    assert_match "not inside a git repository", shell_output("#{bin}/swift-sure status 2>&1", 1).downcase
  end
end
