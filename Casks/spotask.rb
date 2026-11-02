cask "spotask" do
  version "0.3.3"

  on_arm do
    sha256 "bfb93a29fb93104c205fae330fac71146718ae96de05d26915e45c22b23a2a5e"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "00aab78ec7542d1c4bce5ad68b98f1a807d523c702d84fe48cc302bd3d58d3c3"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
