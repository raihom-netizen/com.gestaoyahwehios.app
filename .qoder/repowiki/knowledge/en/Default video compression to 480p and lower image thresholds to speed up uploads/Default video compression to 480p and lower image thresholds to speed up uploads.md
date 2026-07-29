---
kind: design
name: Default video compression to 480p and lower image thresholds to speed up uploads
source: session
category: adr
---

# Default video compression to 480p and lower image thresholds to speed up uploads

_Source: coding plans from commit period fd55706 → 45f1c25 — records intent at planning time; the implementation may lag or differ._

**Status:** accepted

## Context
Uploads across 7+ modules (events, notices, patrimony, members, financial, church logo, public registration) were bottlenecked by aggressive compression settings, causing slow perceived upload speeds on mobile networks.

## Decision drivers
- perceived upload speed
- mobile network variability
- CPU/battery cost of compression
- user experience over absolute quality

## Considered options
- **Lower defaults: 480p video, 70% JPEG/WebP quality, 1.5MB auto-compress threshold, higher concurrency** — pros: 2-3x faster uploads on typical connections; less CPU usage; more images skip compression entirely
- **Keep current high-quality defaults (720p, 85% WebP, 3MB threshold)** _(rejected)_ — pros: Best possible media quality; cons: Slow uploads frustrate users on 3G/4G; excessive CPU drain during compression

## Decision
Set default video transcode to 480p (threshold lowered to 20MB), reduce JPEG/WebP quality to 70%, lower `kAutoCompressImageThresholdBytes` from 3MB to 1.5MB, increase concurrent upload limits (chat: 4→6, feed: 4/6→6/8, patrimonio: 4→6), and add module-specific optimizations like 400px member profiles and PDF skip-compression.

## Consequences
Significantly faster upload completion times across all media-heavy modules. Some visual quality trade-off is accepted in exchange for responsiveness. Smaller profile photos and lighter videos reduce bandwidth and storage costs. Offline queue recovery remains via existing retry logic.