enum Dashboard {
    static let html = #"""
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Packing Monitor</title>
      <style>
        :root { color-scheme: dark; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
        * { box-sizing: border-box; }
        body { margin: 0; background: #0b0c0f; color: #f5f5f7; }
        main { max-width: 1100px; margin: 0 auto; padding: 28px 22px 60px; }
        header { display:flex; align-items:center; justify-content:space-between; gap:16px; margin-bottom:24px; }
        h1 { margin:0; font-size:26px; } h2 { margin-bottom:12px; }
        .muted { color:#9297a2; }
        .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(210px,1fr)); gap:12px; margin-bottom:22px; }
        .card { background:#15171c; border:1px solid #252832; border-radius:14px; padding:16px; }
        .label { color:#9297a2; font-size:12px; text-transform:uppercase; letter-spacing:.08em; }
        .value { margin-top:7px; font-size:18px; font-weight:650; word-break:break-word; }
        .ok { color:#62d38b; } .warn { color:#f7c65c; } .bad { color:#ff6b72; }
        button { appearance:none; border:1px solid #343845; background:#20232b; color:#fff; border-radius:9px; padding:9px 12px; cursor:pointer; }
        button:hover { background:#292d37; }
        section { margin-top:24px; }
        .preview-layout { display:grid; grid-template-columns:minmax(0, 2fr) minmax(240px, 1fr); gap:14px; }
        .preview-box { min-height:320px; border:1px solid #252832; border-radius:14px; background:#050608; display:flex; align-items:center; justify-content:center; overflow:hidden; }
        .preview-box img { display:none; width:100%; height:auto; max-height:620px; object-fit:contain; }
        .preview-placeholder { color:#737985; text-align:center; padding:24px; }
        .capture-meta { display:grid; gap:12px; align-content:start; }
        table { width:100%; border-collapse:collapse; overflow:hidden; background:#15171c; border:1px solid #252832; border-radius:14px; }
        th,td { padding:12px 14px; border-bottom:1px solid #252832; text-align:left; vertical-align:top; }
        th { color:#9297a2; font-size:12px; font-weight:600; }
        td { font-size:14px; }
        tr:last-child td { border-bottom:0; }
        code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; color:#cbd3ff; }
        .empty { padding:28px; text-align:center; color:#9297a2; }
        .actions { display:flex; gap:8px; flex-wrap:wrap; }
        @media(max-width:760px){ .preview-layout{grid-template-columns:1fr;} .table-wrap{overflow-x:auto;} table{min-width:760px;} }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div>
            <h1>Packing Monitor</h1>
            <div class="muted">P0 · Camera capture diagnostics</div>
          </div>
          <div class="actions">
            <button id="authorize">请求摄像头权限</button>
            <button id="refresh">刷新</button>
          </div>
        </header>

        <div class="grid">
          <div class="card"><div class="label">Service</div><div class="value" id="service">—</div></div>
          <div class="card"><div class="label">Camera permission</div><div class="value" id="permission">—</div></div>
          <div class="card"><div class="label">Cameras</div><div class="value" id="camera-count">—</div></div>
          <div class="card"><div class="label">Uptime</div><div class="value" id="uptime">—</div></div>
        </div>

        <section>
          <h2>实时预览</h2>
          <div class="preview-layout">
            <div class="preview-box">
              <img id="preview" alt="Camera preview">
              <div id="preview-placeholder" class="preview-placeholder">授权摄像头后点击“启动预览”</div>
            </div>
            <div class="capture-meta">
              <div class="card"><div class="label">Capture</div><div class="value" id="capture-state">Stopped</div></div>
              <div class="card"><div class="label">Device</div><div class="value" id="capture-device">—</div></div>
              <div class="card"><div class="label">Actual frame</div><div class="value" id="capture-size">—</div></div>
              <div class="actions">
                <button id="start-capture">启动预览</button>
                <button id="stop-capture">停止</button>
              </div>
              <div class="muted">网页只拉取约 2 FPS JPEG 诊断预览；后续录像不会经过浏览器。</div>
            </div>
          </div>
        </section>

        <section>
          <h2>视频输入设备</h2>
          <div class="table-wrap">
            <table>
              <thead><tr><th>设备</th><th>厂商 / Model</th><th>类型</th><th>最大画面</th><th>最大 FPS</th><th>Formats</th></tr></thead>
              <tbody id="camera-body"><tr><td colspan="6" class="empty">正在读取…</td></tr></tbody>
            </table>
          </div>
        </section>
      </main>
      <script>
        const $ = (id) => document.getElementById(id);
        let captureRunning = false;
        const permissionClass = (v) => v === 'authorized' ? 'ok' : (v === 'denied' || v === 'restricted' ? 'bad' : 'warn');
        const fmtUptime = (s) => {
          s = Math.max(0, Math.floor(s || 0));
          const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
          return `${h}h ${m}m ${sec}s`;
        };
        const escapeHtml = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));

        function renderCapture(capture) {
          captureRunning = !!capture.running;
          $('capture-state').textContent = captureRunning ? 'Running' : 'Stopped';
          $('capture-state').className = `value ${captureRunning ? 'ok' : ''}`;
          $('capture-device').textContent = capture.deviceName || '—';
          $('capture-size').textContent = capture.capturedWidth && capture.capturedHeight
            ? `${capture.capturedWidth} × ${capture.capturedHeight}` : '等待首帧…';
          if (!captureRunning) {
            $('preview').style.display = 'none';
            $('preview-placeholder').style.display = 'block';
          }
        }

        function refreshPreview() {
          if (!captureRunning) return;
          const img = $('preview');
          img.onload = () => {
            img.style.display = 'block';
            $('preview-placeholder').style.display = 'none';
          };
          img.src = `/api/camera/frame.jpg?t=${Date.now()}`;
        }

        async function refresh() {
          try {
            const [statusRes, camerasRes, captureRes] = await Promise.all([
              fetch('/api/status'), fetch('/api/cameras'), fetch('/api/camera/capture-status')
            ]);
            const status = await statusRes.json();
            const data = await camerasRes.json();
            const capture = await captureRes.json();
            $('service').textContent = `${status.service} ${status.version}`;
            $('permission').textContent = status.cameraPermission;
            $('permission').className = `value ${permissionClass(status.cameraPermission)}`;
            $('camera-count').textContent = status.cameraCount;
            $('uptime').textContent = fmtUptime(status.uptimeSeconds);
            renderCapture(capture);

            const body = $('camera-body');
            if (!data.cameras.length) {
              body.innerHTML = '<tr><td colspan="6" class="empty">未发现 AVFoundation 视频设备</td></tr>';
              return;
            }
            body.innerHTML = data.cameras.map(c => `
              <tr>
                <td><strong>${escapeHtml(c.name)}</strong><br><code>${escapeHtml(c.id)}</code></td>
                <td>${escapeHtml(c.manufacturer)}<br><span class="muted">${escapeHtml(c.modelID)}</span></td>
                <td><code>${escapeHtml(c.deviceType)}</code></td>
                <td>${c.maxWidth || 0} × ${c.maxHeight || 0}</td>
                <td>${Number(c.maxFPS || 0).toFixed(2)}</td>
                <td>${c.formatCount}</td>
              </tr>`).join('');
          } catch (error) {
            $('service').textContent = 'API error';
            console.error(error);
          }
        }

        async function captureAction(path) {
          const res = await fetch(path, { method: 'POST' });
          const data = await res.json();
          renderCapture(data.capture);
          if (!data.ok) alert(data.error || '操作失败');
          await refresh();
        }

        $('refresh').addEventListener('click', refresh);
        $('authorize').addEventListener('click', async () => {
          const res = await fetch('/api/camera/authorize', { method: 'POST' });
          const data = await res.json();
          alert(data.granted ? '摄像头权限已授权' : `摄像头权限未授权：${data.status}`);
          await refresh();
        });
        $('start-capture').addEventListener('click', () => captureAction('/api/camera/start'));
        $('stop-capture').addEventListener('click', () => captureAction('/api/camera/stop'));
        refresh();
        setInterval(refresh, 5000);
        setInterval(refreshPreview, 500);
      </script>
    </body>
    </html>
    """#
}
