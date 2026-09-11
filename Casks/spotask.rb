cask "spotask" do
  version "0.2.3"

  on_arm do
    sha256 "f634e821c183a66cb57bf7fd19aea6fd772f6629ded69bc4f88e47f840c540d7"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-arm64.dmg"
  end
  on_intel do
    sha256 "006429e96f1124bf28b5b5b593fb8dd637aa2b418e3d98f6bf868b6a83397d91"

    url "https://github.com/shiquda/SpotAsk/releases/download/v#{version}/SpotAsk-#{version}-x86_64.dmg"
  end

  name "SpotAsk"
  desc "Ask an AI assistant from your menu bar"
  homepage "https://github.com/shiquda/SpotAsk"

  depends_on macos: :sequoia

  app "SpotAsk.app"
end
