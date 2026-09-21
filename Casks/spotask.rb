cask "spotask" do
  version "0.2.5"

  on_arm do
    sha256 "d1bb3fd94f61c464b8c5deac1e269965c5ae22faa67f5071ac4e582dbcda805e"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "17301cad8f8da80c224591c2419ac02341d8ab781d5cf15d07bbf111072b8e2e"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
