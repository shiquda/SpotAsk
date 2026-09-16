cask "spotask" do
  version "0.2.4"

  on_arm do
    sha256 "3633a767b198d40b82e2eb8c8366a2fe991580b447cacb15cd7f5ab68602d623"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "4b74fbe1d5961385ecba747b1850155aa3e5d040200ff2290630025c2ad49e3d"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
