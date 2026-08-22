cask "spotask" do
  version "0.2.0"

  on_arm do
    sha256 "590a8d7614af1c2c9205762c18d5ae8b7054a3cd2a6b688ebcc05dc1b5b5741a"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "e8111a1ccd608eec033677a746cc4fb410da02759a7bb4420e482173bc06ddb2"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
