# Template for a Homebrew tap (a GitHub repo named homebrew-aix, file Formula/aix.rb).
# Replace OWNER and sha256 after tagging a release:
#   curl -sL https://github.com/OWNER/aix/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
class Aix < Formula
  desc "Turn plain-English requests into shell commands with Apple Intelligence"
  homepage "https://github.com/OWNER/aix"
  url "https://github.com/OWNER/aix/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"

  depends_on arch: :arm64

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/aix"
  end

  def caveats
    <<~EOS
      aix needs macOS 26 or later on Apple silicon with Apple Intelligence turned on
      (System Settings → Apple Intelligence & Siri).
    EOS
  end

  test do
    assert_match "aix", shell_output("#{bin}/aix --version")
  end
end
