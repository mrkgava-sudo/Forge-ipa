# Forge IPA

Local iOS IPA inspector for Unity IL2CPP and Unreal Engine 4 packages.

## Current scope
- Import a Unity IPA from Files using the native iOS document picker; copy the selected IPA into the app container.
- Analyze locally on-device, with a 4 GiB input-file limit.
- Extract only global-metadata.dat and the native Unity executable instead of unpacking every game asset.
- Parse IL2CPP metadata versions 27, 28, 29 and 31.
- Reconstruct namespaces, classes, structs, enums, inheritance, fields, methods, properties and events.
- Inspect the matching Mach-O image and attempt to resolve native IL2CPP registration data.
- When registration data is found, resolve field offsets, available field/method types and method RVAs.
- Export the reconstructed dump.cs (Unity path) and a JSON analysis report.

## Build
GitHub Actions builds an unsigned iOS app and packages it as an unsigned IPA artifact. To install on a device, sign it with a certificate/profile using your own trusted signing workflow.

The Xcode project is generated from `project.yml` using XcodeGen.


## Interface update
The current interface branch adopts the native visual language used by Signet: adaptive iOS grouped surfaces, restrained system-blue accents, translucent panels, compact typography, and a four-section bottom navigation. IPA selection uses the UIKit document picker with copy-on-import so the selected file is staged in the app container before analysis.

The current report is still an intermediate metadata-header inspection. Full IL2CPP type/method reconstruction and real `dump.cs` generation are not implemented yet.

## Unreal Engine 4 static analysis
- Detect and extract the main iOS app executable from the IPA, then inspect its ARM64 Mach-O image.
- Search the executable for known Unreal object/reflection/name-system marker strings.
- Inventory common cooked resource extensions such as .pak, .ucas, .utoc, .uasset and .uexp.
- Export a UE4 static-analysis text report with Mach-O section information and exact file offsets for found strings.

This UE4 path is static inspection only. String file offsets are not runtime addresses or UObject property offsets. A full live UObject dump (GWorld, GNames, GUObjectArray, class/property offsets and function addresses) is not claimed; it requires validated engine-version-specific runtime structure recovery and cannot be safely inferred from string matches.
