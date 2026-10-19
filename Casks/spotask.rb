cask "spotask" do
  version "0.3.1"

  on_arm do
    sha256 "17defba5b4806ebce3f65f5054fd3bbb67b6491286ab3b4341853138dab45be7"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "68082fb8a4c6c5c7a577ca202253605d4965796f36ade23652377c56751ce3ed"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
