cask "notchflow" do
  version :latest
  sha256 :no_check

  url "https://github.com/Tymcio/notchflow/releases/latest/download/NotchFlow.dmg"
  name "NotchFlow"
  desc "Coding agents, music, files and timers in an island at the top of the screen"
  homepage "https://notchflow.eu/"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "NotchFlow.app"

  uninstall quit: "eu.notchflow.app"

  zap trash: [
    "~/Library/Application Support/NotchFlow",
    "~/Library/Caches/eu.notchflow.app",
    "~/Library/Caches/eu.notchflow.app.sparkle",
    "~/Library/HTTPStorages/eu.notchflow.app",
    "~/Library/Preferences/eu.notchflow.app.plist",
  ]
end
