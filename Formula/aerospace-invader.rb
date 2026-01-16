class AerospaceInvader < Formula
  desc "Workspace navigator and OSD for AeroSpace window manager"
  homepage "https://github.com/dungle-scrubs/aerospace-invader"
  url "https://github.com/dungle-scrubs/aerospace-invader/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "12c9f5f94378e672df34c34e38d35987287f81ee7512415378c10fe025038705"
  license "MIT"

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
