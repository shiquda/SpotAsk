cask "spotask" do
  version "0.3.0"

  on_arm do
    sha256 "6a0f7c33f1eafa1d4251583b273d50f31685d836cdb0537637dfacee1ed8aff4"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "37bf643ceb00a2a7c4ca9a7c38beb3f9d8e9ab6024234831b6cb05262b5db295"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
