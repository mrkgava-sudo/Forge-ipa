# Gift Rush iOS

Native SwiftUI catalogue of 152 Telegram gifts, local Lottie animations, detail screens and a 30-second catch-the-gift mini-game.

## Build via GitHub Actions
Open **Actions → Gift Rush iOS IPA → Run workflow**. The workflow downloads the public gift dataset, converts TGS files to local Lottie JSON, builds an unsigned iOS app on macOS and uploads `GiftRush-unsigned-IPA`.

The artifact is an **unsigned IPA**. Installing it on a physical iPhone requires signing with your own Apple Developer certificate and provisioning profile.

Gift asset source: https://github.com/denzyve/cdn-telegram-gifts
