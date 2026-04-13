cask "micmixer" do
  version "1.0.0"
  sha256 "695f0165683b10c0401a112c3fef46248b43cea9b0567b15d5673a4da7a5c510"

  url "https://github.com/amenocturne/mic-mixer/releases/download/v#{version}/MicMixer.app.zip"
  name "MicMixer"
  desc "Menu bar app that mixes system audio + microphone into a virtual device"
  homepage "https://github.com/amenocturne/mic-mixer"

  depends_on macos: ">= :sequoia"

  app "MicMixer.app"

  zap trash: [
    "~/Library/Preferences/com.amenocturne.micmixer.plist",
  ]
end
