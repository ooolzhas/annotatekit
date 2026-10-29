# Homebrew formula for the `annotate` CLI. Lives in a tap repo (github.com/ooolzhas/homebrew-tap,
# file Formula/annotate.rb) so users can `brew install ooolzhas/tap/annotate`.
# On each release, copy the url and sha256 from the Release workflow's job summary.
class Annotate < Formula
  desc "Deliver AnnotateKit iOS annotation sessions to coding agents (MCP server, watcher, runner)"
  homepage "https://annotatekit.com"
  url "https://github.com/ooolzhas/annotatekit/releases/download/v0.3.0/annotate-0.3.0-macos-universal.tar.gz"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"
  license "MIT"

  depends_on :macos

  def install
    bin.install "annotate"
  end

  test do
    assert_match "annotate", shell_output("#{bin}/annotate help")
  end
end
