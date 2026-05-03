# Changelog — 2026-05-03

## [Unreleased]

### Added

- 2026-05-03 [solo/sonnet] iMovie-style horizontal drag-anywhere timeline + live trim preview with auto-play (Phase 3 commit 6, 496e57f). StitchTimelineView: horizontal ScrollView + HStack with .draggable/.dropDestination using ClipID typed Transferable wrapper. TrimEditorView: VideoPlayer + custom DualThumbSlider with correct drag-origin capture; auto-plays 2 s before trim-end on handle release. ClipEditorSheet: live-apply edits via project.updateEdits, Cancel reverts to on-appear snapshot. Also fixes pre-existing build blockers (kCGImagePropertyXMPData iOS, SettingsTabView Section initializer, 6 untracked files staged).
- 2026-05-03 [subagent:sonnet] Audio Background Mode opt-in for unlimited background encodes (Phase 3 commit 2). New `AudioBackgroundKeeper` service (refcounted AVAudioSession + silent m4a loop); `INFOPLIST_KEY_UIBackgroundModes = audio` in pbxproj; keeper wired into `VideoLibrary.runJob` and `StitchProject.runExport`; Settings tab toggle with footer explainer; 4-tab ContentView with gearshape icon.
