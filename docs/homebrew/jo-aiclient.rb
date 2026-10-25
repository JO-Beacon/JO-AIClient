# Draft for homebrew/homebrew-cask. Do not submit until version and sha256
# match a Developer ID-signed, notarized GitHub release.
# Setup and submission notes: docs/macos-signing.md
cask "jo-aiclient" do
  version "0.1.17,17"
  sha256 "REPLACE_WITH_SHA256_OF_THE_SIGNED_DMG"

  url "https://github.com/JO-Beacon/JO-AIClient/releases/download/v#{version.csv.first}/JO-AIClient_macos_#{version.csv.first}%2B#{version.csv.second}.dmg"
  name "JO-AIClient"
  desc "Multi-platform, multi-provider LLM chat client"
  homepage "https://github.com/JO-Beacon/JO-AIClient"

  livecheck do
    url :url
    regex(/^JO-AIClient[._-]macos[._-]v?(\d+(?:\.\d+)+)\+(\d+)\.dmg$/i)
    strategy :github_latest do |json, regex|
      json["assets"]&.map do |asset|
        match = asset["name"]&.match(regex)
        next if match.blank?

        "#{match[1]},#{match[2]}"
      end
    end
  end

  depends_on macos: :monterey

  app "JO-AIClient.app"

  zap trash: [
    "~/Library/Application Support/JO-Beacon/JO-AIClient",
    "~/Library/Caches/io.github.jobeacon.joaiclient",
    "~/Library/Preferences/io.github.jobeacon.joaiclient.plist",
  ]
end
