# Packing Monitor

Headless macOS packing monitor: capture a camera feed, continuously record packing video, recognize shipping labels/tracking numbers, and index each tracking number back to the relevant video time range.

## Architecture

```text
Camera (X-T2 / UVC / capture card)
        |
        v
PackingMonitor service (Swift)
  - AVFoundation camera discovery/capture
  - VideoToolbox recording (next milestone)
  - Vision barcode/OCR (next milestone)
  - SQLite event/video index (next milestone)
        |
        +---- HTTP API ---- Web dashboard
```

The browser is a control/query surface only. Camera capture, recording and recognition stay native on macOS.

## Current milestone

The first vertical slice provides:

- Hummingbird-based local HTTP service
- Camera permission diagnostics
- AVFoundation video-device discovery
- Basic camera capability summary (max resolution / FPS / format count)
- Minimal Web dashboard
- Health/status APIs
- macOS CI build

Recording, SQLite indexing and label recognition are intentionally the next milestones after the X-T2 input path is verified.

## Requirements

- macOS 14+
- Swift 6.1+
- A camera visible to AVFoundation (FUJIFILM X Webcam, USB/UVC camera, HDMI capture card, etc.)

> Camera capture on macOS requires an app bundle containing `NSCameraUsageDescription`. During development the API can enumerate devices, but the production background service will be wrapped in a minimal no-Dock app/LaunchAgent before capture starts.

## Run in development

```bash
swift run PackingMonitor
```

Then open:

```text
http://127.0.0.1:8787
```

Environment variables:

```bash
PACKING_MONITOR_HOST=127.0.0.1
PACKING_MONITOR_PORT=8787
```

Keep the host on `127.0.0.1` during development. LAN access and authentication will be added together later.

## API

- `GET /api/health` — liveness
- `GET /api/status` — service/camera permission status
- `GET /api/cameras` — AVFoundation video inputs and capability summary
- `POST /api/camera/authorize` — request camera permission (effective once running from the packaged macOS host)

## Roadmap

1. **P0 — Camera diagnostics**: verify X-T2 discovery, USB feed resolution/FPS and stability.
2. **P1 — Recorder**: native H.264 continuous recording, 5-minute segmentation, disk policy.
3. **P2 — Index database**: SQLite video segments and tracking events.
4. **P3 — Recognition**: Vision barcode first, OCR fallback, ROI and multi-frame stabilization.
5. **P4 — Search/playback**: tracking-number search, thumbnail, timestamp jump and clip export.
6. **P5 — Appliance mode**: no-Dock app host, LaunchAgent auto-start, recovery, LAN access and auth.

## Design rule

A tracking number points to a timestamp in continuous recording. We do **not** start/stop a new MP4 for every package. This preserves the packing activity that happened before the shipping label enters the camera view.
