class AerospaceInvader < Formula
  desc "Workspace navigator and OSD for AeroSpace window manager"
  homepage "https://github.com/dungle-scrubs/aerospace-invader"
  url "https://github.com/dungle-scrubs/aerospace-invader/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "411eb582307f152021ff5a2c375b9d0180dc61e8ef73f5476e7f6ef0e0cb5a11"
  license "MIT"

  bottle do
    root_url "https://github.com/dungle-scrubs/aerospace-invader/releases/download/v0.2.1"
    sha256 cellar: :any_skip_relocation, arm64_sonoma: "75a5d364d845712bbc6ef11695110bd45a9b918322e532d447dff20096199edd"
  end

  depends_on :macos
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/aerospace-invader"
  end

  service do
    run [opt_bin/"aerospace-invader", "daemon"]
    keep_alive true
    log_path var/"log/aerospace-invader.log"
    error_log_path var/"log/aerospace-invader.err"
  end

  test do
    # Basic smoke test - binary should exit with usage info
    output = shell_output("#{bin}/aerospace-invader 2>&1", 0)
    assert_match "daemon", output
  end
end
