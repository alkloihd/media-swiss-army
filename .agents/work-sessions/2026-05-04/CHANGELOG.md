# Changelog — 2026-05-04

## In Progress

- Cluster 0 hotfix implementation completed locally on `feat/codex-cluster0-hotfixes`: photo stitch scale-fit uses baked movie dimensions; compression Max bitrate is capped; writer settings now declare SDR BT.709 color metadata and clamp frame-rate/GOP hints; `-11841` encoder rejection retries once at a safer preset with the fallback surfaced in row UI. Bundle identity was normalized across the iOS target, test targets, and active TestFlight docs to `com.alkloihd.videocompressor`. Final PR/CI/manual TestFlight steps remain.
