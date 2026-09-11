cask "spotask" do
  version "0.2.2"

  on_arm do
    sha256 "7694809d875e2ccd7987f3b62de4ba3dd463b604d97941e92774b580f1ad2987"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "09dea9072b4f8500560783ae916c7076fd346f3ce27c0d286778235e1bc58dd9"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
