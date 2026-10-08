cask "spotask" do
  version "0.2.6"

  on_arm do
    sha256 "8b9443c6f24b31152a7f87145ddf193de10721865bbfe04dab41003ffca20350"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "6c0d0fc5a190006c433396f6c1a12926124f1b21517952dce8e91b6e4d68cc26"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
