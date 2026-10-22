cask "spotask" do
  version "0.3.2"

  on_arm do
    sha256 "90eb1962eb7481f8db0c845403ffdd29969e69e598d0a1b1fca12c6af6cb5fb1"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "d2ecb4c7fa7e0e6902bbd54eef736b4d125139a9d2dc7a492343190326ba3756"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "One hotkey to ask any AI from the Mac menu bar"
  homepage "https://shiquda.github.io/SpotAsk/"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
