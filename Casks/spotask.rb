cask "spotask" do
  version "0.3.4"

  on_arm do
    sha256 "0812909845a960f82ab0e01e259707392f05af250af32a32cfb041a134b73253"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "23f4835bc6054032e9f8431fa2fd286cdbe4b1a1eeeee8c2fd6e2b9b9eedd7fc"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Menu bar AI quick-ask with one hotkey and your own API key"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
