# Forge IPA

Local iOS IPA / Unity IL2CPP package inspector.

## Current scope
- Import an IPA from Files.
- Enforce a 4 GiB input-file limit.
- Extract archive entries locally using ZIPFoundation.
- Detect common Unity markers and `global-metadata.dat`.
- Validate the IL2CPP metadata sanity value and report metadata version plus known header section offsets/counts.
- Export a JSON report.

## Accuracy and safety
Reported offsets are offsets inside the metadata file, not runtime memory addresses or guaranteed method offsets. Runtime addresses depend on the exact binary, architecture, load address and build. This project does not bypass DRM, anti-cheat, app sandboxing or signing protections.

## Build
GitHub Actions builds an unsigned iOS app and packages it as an unsigned IPA artifact. To install on a device, sign it with a certificate/profile using your own trusted signing workflow.

The Xcode project is generated from `project.yml` using XcodeGen.


## Interface update
The current interface branch adopts the native visual language used by Signet: adaptive iOS grouped surfaces, restrained system-blue accents, translucent panels, compact typography, and a four-section bottom navigation. IPA selection uses the UIKit document picker with copy-on-import so the selected file is staged in the app container before analysis.

The current report is still an intermediate metadata-header inspection. Full IL2CPP type/method reconstruction and real `dump.cs` generation are not implemented yet.
