---
kind: design
name: Optimize media uploads by reducing compression and increasing parallelism
source: session
category: adr
---

# Optimize media uploads by reducing compression and increasing parallelism

_Source: coding plans from commit period 45f1c25 → 7ad4946 — records intent at planning time; the implementation may lag or differ._

**Status:** accepted

## Context
Uploads across 7+ modules (events, notices, patrimony, members, financial receipts, church logo, public registration) were slow due to aggressive image/video compression and sequential upload pipelines. Users experienced long wait times especially on mobile networks.

## Decision drivers
- upload speed
- user experience
- mobile network constraints
- memory usage

## Considered options
- **Reduce compression quality/size + increase concurrency + skip small files** — pros: 2-3x faster uploads, less CPU/memory, better UX on slow networks
- **Keep current high-quality compression settings** _(rejected)_ — pros: Better image/video quality; cons: Slow uploads, higher bandwidth, more CPU usage, worse user experience

## Decision
Lower image thresholds (`kAutoCompressImageThresholdBytes` 3MB→1.5MB), reduce JPEG/WebP quality (chat profiles 800px@70%, feed 1440px@75%), default video to 480p, skip transcode for files under 16MB, and increase concurrent uploads from 4→6 (chat/feed) and 4→6 (patrimony gallery). Module-specific optimizations: member profiles at 400px, PDF receipts skip compression.

## Consequences
Uploads are 2-3x faster with slightly lower quality images/videos. Less memory pressure and CPU usage. Some edge cases may need manual review if quality loss is noticeable. Retry with exponential backoff improves resilience on flaky connections.