# Packing Monitor

Headless macOS packing monitor: capture a camera feed, continuously record packing video, recognize shipping labels/tracking numbers, and index each tracking number back to the relevant video time range.

## Architecture

```text
Camera (X-T2 / UVC / capture card)
        |
        v
PackingMonitor service (Swift)
  - AVFoundation camera discovery/capture
  - throttled JPEG diagnostics preview -> browser
  - VideoToolbox recording (next milestone)
  - Vision barcode/OCR (next milestone)
  - SQLite event/video index (next milestone)
        |
        +---- HTTP API ---- Web dashboard
```

The browser is a control/query surface only. Camera capture, recording and recognition stay native on macOS.

## Current milestone — P0

The first vertical slice now provides:

- Hummingbird-based local HTTP service
- macOS camera permission diagnostics
- AVFoundation video-device discovery
- camera capability summary (max resolution / FPS / format count)
- native live capture start/stop
- actual captured-frame resolution reporting
- low-overhead ~2 FPS JPEG browser preview
- minimal Web dashboard
- no-Dock `.app` development bundle packaging
- macOS CI build + bundle validation

Recording, SQLite indexing and shipping-label recognition are the next milestones after the real X-T2 input path is verified.

## Requirements

- macOS 14+
- Swift 6.1+
- A camera visible to AVFoundation (FUJIFILM X Webcam, USB/UVC camera, HDMI capture card, etc.)

Camera permission requires an app bundle containing `NSCameraUsageDescription`, so use the packaged development app below when testing capture. Plain `swift run PackingMonitor` is still useful for API/device-enumeration development, but intentionally refuses to request camera access when that bundle metadata is absent.

## Build and run the camera diagnostic app

```bash
git clone https://github.com/masakacj/packing-monitor.git
cd packing-monitor
bash scripts/build-app.sh debug
open .build/app/PackingMonitor.app
```

Then open:

```text
http://127.0.0.1:8787
```

In the dashboard:

1. Click **请求摄像头权限** and approve the macOS camera prompt.
2. Confirm the X-T2 / FUJIFILM device appears in **视频输入设备**.
3. Click **启动预览**.
4. Check **Actual frame** for the real resolution delivered to AVFoundation and confirm the browser preview shows the packing table clearly.

The service prefers a device whose AVFoundation metadata contains `FUJIFILM`, `FUJI`, or `X-T2`; otherwise it prefers an external/virtual camera, then falls back to the first video device.

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
- `POST /api/camera/authorize` — request camera permission from the packaged macOS host
- `GET /api/camera/capture-status` — current native capture/device/frame state
- `POST /api/camera/start` — start the preferred camera
- `POST /api/camera/stop` — stop capture
- `GET /api/camera/frame.jpg` — latest throttled diagnostics preview frame

## Roadmap

1. **P0 — Camera diagnostics**: verify X-T2 discovery, USB feed resolution/FPS and stability. **In progress.**
2. **P1 — Recorder**: native H.264 continuous recording, 5-minute segmentation, disk policy.
3. **P2 — Index database**: SQLite video segments and tracking events.
4. **P3 — Recognition**: Vision barcode first, OCR fallback, ROI and multi-frame stabilization.
5. **P4 — Search/playback**: tracking-number search, thumbnail, timestamp jump and clip export.
6. **P5 — Appliance mode**: LaunchAgent auto-start, recovery, LAN access and auth.

## Design rule

A tracking number points to a timestamp in continuous recording. We do **not** start/stop a new MP4 for every package. This preserves the packing activity that happened before the shipping label enters the camera view.
