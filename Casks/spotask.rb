cask "spotask" do
  version "0.2.7"

  on_arm do
    sha256 "b49c5a94c640486b769d5b8929575fdee5f9e45cda973edb207b2eb6fd989a9a"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "82d1a83666edb062dfba8d2f92401fb4c6fa315fe24d745ed1c68766fe8f1cce"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
