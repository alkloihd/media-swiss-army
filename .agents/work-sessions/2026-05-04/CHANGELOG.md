# Changelog — 2026-05-04

## In Progress

- Cluster 5 adaptive Meta-marker registry completed locally on `feat/codex-cluster5-meta-marker-registry`: added bundled `MetaMarkers.json`, `MetaMarkerRegistry` actor, registry-backed video/still detection, Oakley Meta + device hints, false-positive guards, and review fixes for string-backed Ray-Ban and XMP `meta ai` / `meta wearable` markers. Local verification: focused registry tests passed 24/24, full `test_sim` passed 249 total / 248 passed / 1 documented skip, and `build_sim` succeeded. PR/CI/TestFlight steps remain.

- Cluster 0 hotfix implementation completed locally on `feat/codex-cluster0-hotfixes`: photo stitch scale-fit uses baked movie dimensions; compression Max bitrate is capped; writer settings now declare SDR BT.709 color metadata and clamp frame-rate/GOP hints; `-11841` encoder rejection retries once at a safer preset with the fallback surfaced in row UI. Bundle identity was normalized across the iOS target, test targets, and active TestFlight docs to `com.alkloihd.videocompressor`. Final PR/CI/manual TestFlight steps remain.
