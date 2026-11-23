# Forge IPA

Local iOS IPA / Unity IL2CPP package inspector.

## Current scope
- Import a Unity IPA from Files using the native iOS document picker; copy the selected IPA into the app container.
- Analyze locally on-device, with a 4 GiB input-file limit.
- Extract only global-metadata.dat and the native Unity executable instead of unpacking every game asset.
- Parse IL2CPP metadata versions 27, 28, 29 and 31.
- Reconstruct namespaces, classes, structs, enums, inheritance, fields, methods, properties and events.
- Inspect the matching Mach-O image and attempt to resolve native IL2CPP registration data.
- When registration data is found, resolve field offsets, available field/method types and method RVAs.
- Export the reconstructed dump.cs and a JSON analysis report.

## Build
GitHub Actions builds an unsigned iOS app and packages it as an unsigned IPA artifact. To install on a device, sign it with a certificate/profile using your own trusted signing workflow.

The Xcode project is generated from `project.yml` using XcodeGen.


## Interface update
The current interface branch adopts the native visual language used by Signet: adaptive iOS grouped surfaces, restrained system-blue accents, translucent panels, compact typography, and a four-section bottom navigation. IPA selection uses the UIKit document picker with copy-on-import so the selected file is staged in the app container before analysis.

The current report is still an intermediate metadata-header inspection. Full IL2CPP type/method reconstruction and real `dump.cs` generation are not implemented yet.
