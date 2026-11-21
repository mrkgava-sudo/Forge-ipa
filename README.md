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
