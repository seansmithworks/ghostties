# frozen_string_literal: true

cask "ghostties" do
  version "0.1.0-beta.22"
  sha256 "d98303637d6142af48e165627ca2afb312513610396ca56cda2e781efae780b0"

  # Ghostties has not cut a stable release yet — every tag so far, including
  # this one, is a GitHub prerelease. Tracking beta is a deliberate choice,
  # not a placeholder; see dist/ghostties/homebrew/README.md.
  url "https://github.com/SeanSmithWorks/ghostties/releases/download/v#{version}/Ghostties.dmg"
  name "Ghostties"
  desc "Terminal with a multi-agent workspace sidebar, built on Ghostty"
  homepage "https://ghostties.org/"

  # Every release published so far (including this one) is a GitHub
  # prerelease — there is no stable release to fall back to. The default
  # `github_latest`/`github_releases` behavior skips prereleases entirely,
  # which would make livecheck find nothing, so a custom block reads the
  # release list directly and keeps prereleases in scope.
  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+(?:-beta\.\d+)?)$/i)
    strategy :github_releases do |json, regex|
      json.filter_map { |release| release["tag_name"][regex, 1] }
    end
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Ghostties.app"

  uninstall quit: "com.seansmithdesign.ghostties"

  zap trash: [
    "~/Library/Application Support/Ghostties",
    "~/Library/Caches/com.seansmithdesign.ghostties",
    "~/Library/HTTPStorages/com.seansmithdesign.ghostties",
    "~/Library/HTTPStorages/com.seansmithdesign.ghostties.binarycookies",
    "~/Library/Preferences/com.seansmithdesign.ghostties.plist",
    "~/Library/Saved Application State/com.seansmithdesign.ghostties.savedState",
  ]
end
