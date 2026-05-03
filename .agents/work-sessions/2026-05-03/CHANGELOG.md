# Changelog — 2026-05-03

## [Unreleased]

### Added

- 2026-05-03 [subagent:sonnet] Audio Background Mode opt-in for unlimited background encodes (Phase 3 commit 2). New `AudioBackgroundKeeper` service (refcounted AVAudioSession + silent m4a loop); `INFOPLIST_KEY_UIBackgroundModes = audio` in pbxproj; keeper wired into `VideoLibrary.runJob` and `StitchProject.runExport`; Settings tab toggle with footer explainer; 4-tab ContentView with gearshape icon.
