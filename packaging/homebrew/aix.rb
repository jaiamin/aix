# Formula for the jaiamin/homebrew-aix tap (Formula/aix.rb there).
# On release: upload `make dist` output to the GitHub release, then update version and sha256.
class Aix < Formula
  desc "Turn plain English into shell commands with Apple Intelligence"
  homepage "https://github.com/jaiamin/aix"
  url "https://github.com/jaiamin/aix/releases/download/v0.1.0/aix-0.1.0-arm64-macos.tar.gz"
  sha256 "4fe9cae9350b2678e777a7b37a3a3b751e3a2cf603953e5523af40419ab0ceab"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  def install
    bin.install "aix"
  end

  def caveats
    <<~EOS
      aix uses Apple Intelligence. Turn it on in
      System Settings → Apple Intelligence & Siri.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/aix --version")
  end
end
