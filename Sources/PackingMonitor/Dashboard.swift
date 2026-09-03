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
        body { margin:0; background:#0b0c0f; color:#f5f5f7; }
        main { max-width:1180px; margin:0 auto; padding:24px 20px 60px; }
        header { display:flex; align-items:center; justify-content:space-between; gap:16px; margin-bottom:20px; }
        h1 { margin:0; font-size:26px; } h2 { margin:0 0 12px; font-size:19px; }
        .muted { color:#9297a2; font-size:13px; }
        .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:10px; margin-bottom:18px; }
        .card { background:#15171c; border:1px solid #252832; border-radius:12px; padding:14px; }
        .label { color:#9297a2; font-size:11px; text-transform:uppercase; letter-spacing:.08em; }
        .value { margin-top:6px; font-size:17px; font-weight:650; word-break:break-word; }
        .ok { color:#62d38b; } .warn { color:#f7c65c; } .bad { color:#ff6b72; }
        button, select, input { border:1px solid #343845; background:#20232b; color:#fff; border-radius:8px; }
        button { appearance:none; padding:9px 12px; cursor:pointer; }
        button:hover { background:#292d37; }
        button.primary { background:#2f5feb; border-color:#4672ef; }
        button.danger { background:#402024; border-color:#633139; }
        select, input[type=text], input[type=number] { width:100%; padding:9px 10px; font-size:14px; }
        input[type=checkbox] { width:auto; }
        section { margin-top:22px; }
        .preview-layout { display:grid; grid-template-columns:minmax(0, 2fr) minmax(275px, 1fr); gap:12px; }
        .preview-box { min-height:360px; border:1px solid #252832; border-radius:12px; background:#050608; display:flex; align-items:center; justify-content:center; overflow:hidden; position:relative; }
        .preview-box img { display:none; width:100%; height:auto; max-height:660px; object-fit:contain; }
        .preview-placeholder { color:#737985; text-align:center; padding:24px; }
        .recognition-overlay { display:none; position:absolute; border:3px solid #62d38b; border-radius:4px; box-shadow:0 0 0 1px rgba(0,0,0,.55); pointer-events:none; }
        .recognition-tag { display:none; position:absolute; background:rgba(0,0,0,.78); border:1px solid #62d38b; color:#fff; padding:5px 7px; border-radius:6px; font:12px ui-monospace,SFMono-Regular,Menlo,monospace; pointer-events:none; }
        .capture-meta { display:grid; gap:10px; align-content:start; }
        .actions { display:flex; gap:8px; flex-wrap:wrap; }
        .form-grid { display:grid; grid-template-columns:minmax(0,2fr) minmax(140px,.6fr); gap:10px; align-items:end; }
        .check-row { display:flex; gap:8px; align-items:center; padding-top:8px; }
        .storage-state { margin-top:10px; line-height:1.6; }
        table { width:100%; border-collapse:collapse; background:#15171c; border:1px solid #252832; border-radius:12px; overflow:hidden; }
        th,td { padding:10px 12px; border-bottom:1px solid #252832; text-align:left; vertical-align:top; }
        th { color:#9297a2; font-size:11px; font-weight:600; }
        td { font-size:13px; }
        tr:last-child td { border-bottom:0; }
        code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; color:#cbd3ff; }
        .empty { padding:24px; text-align:center; color:#9297a2; }
        .search-row { display:grid; grid-template-columns:1fr auto; gap:8px; }
        .path { max-width:360px; word-break:break-all; color:#aeb5c2; }
        .pill { display:inline-block; padding:2px 6px; border-radius:999px; background:#252832; font-size:11px; color:#cbd0dc; }
        @media(max-width:780px){ .preview-layout,.form-grid{grid-template-columns:1fr;} .table-wrap{overflow-x:auto;} table{min-width:780px;} }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div>
            <h1>Packing Monitor</h1>
            <div class="muted">面单识别 · 视频定位 · NAS 录像</div>
          </div>
          <div class="actions">
            <button id="authorize">摄像头权限</button>
            <button id="refresh">刷新</button>
          </div>
        </header>

        <div class="grid">
          <div class="card"><div class="label">Service</div><div class="value" id="service">—</div></div>
          <div class="card"><div class="label">Camera</div><div class="value" id="permission">—</div></div>
          <div class="card"><div class="label">NAS</div><div class="value" id="nas-state">—</div></div>
          <div class="card"><div class="label">Recording</div><div class="value" id="recording-state">—</div></div>
          <div class="card"><div class="label">Last tracking</div><div class="value" id="last-tracking">—</div></div>
        </div>

        <section>
          <h2>实时监控</h2>
          <div class="preview-layout">
            <div class="preview-box" id="preview-box">
              <img id="preview" alt="Camera preview">
              <div id="preview-placeholder" class="preview-placeholder">选择 HDMI / USB 采集卡并点击“开始监控”</div>
              <div id="recognition-overlay" class="recognition-overlay"></div>
              <div id="recognition-tag" class="recognition-tag"></div>
            </div>
            <div class="capture-meta">
              <div class="card">
                <div class="label">Video source</div>
                <select id="camera-select"><option value="">正在读取视频设备…</option></select>
                <div class="muted" id="camera-select-detail" style="margin-top:7px">—</div>
              </div>
              <div class="card"><div class="label">Capture</div><div class="value" id="capture-state">Stopped</div></div>
              <div class="card"><div class="label">Actual frame</div><div class="value" id="capture-size">—</div></div>
              <div class="card">
                <div class="label">Recognition</div>
                <div class="value" id="recognition-state">等待面单</div>
                <div class="muted" id="recognition-detail" style="margin-top:6px">条码优先，OCR 兜底</div>
              </div>
              <div class="actions">
                <button id="start-capture" class="primary">开始监控</button>
                <button id="stop-capture" class="danger">停止</button>
              </div>
              <div class="muted">网页预览约 8 FPS；识别和录像均在 Mac 原生采集链路完成，不经过浏览器。</div>
            </div>
          </div>
        </section>

        <section>
          <h2>NAS 存储</h2>
          <div class="card">
            <div class="form-grid">
              <div>
                <div class="label">NAS root path</div>
                <input id="storage-path" type="text" list="volume-list" placeholder="/Volumes/NAS/PackingMonitor">
                <datalist id="volume-list"></datalist>
              </div>
              <div>
                <div class="label">Segment minutes</div>
                <select id="segment-minutes">
                  <option value="2">2 分钟</option>
                  <option value="5">5 分钟</option>
                  <option value="10">10 分钟</option>
                  <option value="15">15 分钟</option>
                </select>
              </div>
            </div>
            <div class="check-row">
              <input id="recording-enabled" type="checkbox" checked>
              <label for="recording-enabled">开始监控时直接录到 NAS，不在 Mac 本地保存视频</label>
            </div>
            <div class="actions" style="margin-top:10px">
              <button id="save-storage">保存并测试 NAS</button>
            </div>
            <div id="storage-detail" class="muted storage-state">—</div>
          </div>
        </section>

        <section>
          <h2>面单查询 / 视频定位</h2>
          <div class="search-row">
            <input id="tracking-query" type="text" placeholder="输入快递单号 / 面单条码">
            <button id="search-tracking" class="primary">查询</button>
          </div>
          <div class="table-wrap" style="margin-top:10px">
            <table>
              <thead><tr><th>面单号</th><th>识别时间</th><th>方式</th><th>录像定位</th><th>NAS 文件</th><th></th></tr></thead>
              <tbody id="event-body"><tr><td colspan="6" class="empty">正在读取最近识别记录…</td></tr></tbody>
            </table>
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
        let previewBusy = false;
        let selectedCameraID = null;
        let camerasCache = [];
        let lastRecognitionKey = null;

        const escapeHtml = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
        const fmtTime = (value) => value ? new Date(value).toLocaleString() : '—';
        const fmtOffset = (seconds) => {
          if (seconds == null || Number.isNaN(Number(seconds))) return '—';
          const total = Math.max(0, Math.round(Number(seconds)));
          const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
          return h ? `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}` : `${m}:${String(s).padStart(2,'0')}`;
        };
        const basename = (path) => path ? path.split('/').filter(Boolean).pop() : '—';

        function defaultCameraID(cameras) {
          if (!cameras.length) return null;
          const score = (c) => {
            const text = `${c.name || ''} ${c.manufacturer || ''} ${c.modelID || ''}`.toLowerCase();
            let value = 0;
            if (text.includes('capture') || text.includes('uvc') || text.includes('hdmi') || text.includes('usb3') || text.includes('usb 3')) value += 100;
            if (String(c.position) === 'unspecified') value += 20;
            if (text.includes('x webcam')) value -= 100;
            if (text.includes('facetime')) value -= 30;
            value += Math.min(20, ((c.maxWidth || 0) * (c.maxHeight || 0)) / 1000000);
            return value;
          };
          return [...cameras].sort((a,b) => score(b) - score(a))[0].id;
        }

        function updateCameraDetail() {
          const camera = camerasCache.find(c => c.id === selectedCameraID);
          $('camera-select-detail').textContent = camera
            ? `${camera.maxWidth || 0} × ${camera.maxHeight || 0} · max ${Number(camera.maxFPS || 0).toFixed(0)} FPS`
            : '—';
        }

        function renderCameraSelector(cameras, status, capture) {
          camerasCache = cameras;
          const available = new Set(cameras.map(c => c.id));
          if (!selectedCameraID || !available.has(selectedCameraID)) {
            selectedCameraID = status.preferredCameraID && available.has(status.preferredCameraID)
              ? status.preferredCameraID
              : (capture.deviceID && available.has(capture.deviceID) ? capture.deviceID : defaultCameraID(cameras));
          }
          const select = $('camera-select');
          if (!cameras.length) {
            select.innerHTML = '<option value="">未发现视频设备</option>';
            select.disabled = true;
            return;
          }
          select.disabled = false;
          select.innerHTML = cameras.map(c => `<option value="${escapeHtml(c.id)}">${escapeHtml(c.name)} · ${c.maxWidth || 0}×${c.maxHeight || 0}</option>`).join('');
          if (selectedCameraID) select.value = selectedCameraID;
          updateCameraDetail();
        }

        function renderCapture(capture) {
          captureRunning = !!capture.running;
          $('capture-state').textContent = captureRunning ? (capture.deviceName || 'Running') : 'Stopped';
          $('capture-state').className = `value ${captureRunning ? 'ok' : ''}`;
          $('capture-size').textContent = capture.capturedWidth && capture.capturedHeight
            ? `${capture.capturedWidth} × ${capture.capturedHeight}` : (captureRunning ? '等待首帧…' : '—');
          if (!captureRunning) {
            $('preview').style.display = 'none';
            $('preview-placeholder').style.display = 'block';
            $('recognition-overlay').style.display = 'none';
            $('recognition-tag').style.display = 'none';
          }
        }

        function renderRecognition(recognition) {
          const hit = recognition.lastHit;
          $('last-tracking').textContent = hit ? hit.trackingNumber : '—';
          $('recognition-state').textContent = hit ? hit.trackingNumber : '等待面单';
          $('recognition-state').className = `value ${hit ? 'ok' : ''}`;
          $('recognition-detail').textContent = hit
            ? `${hit.source.toUpperCase()}${hit.symbology ? ' · ' + hit.symbology : ''} · ${(Number(hit.confidence || 0) * 100).toFixed(0)}% · ${fmtTime(hit.detectedAt)} · 本次 ${recognition.totalConfirmed} 个`
            : (recognition.lastError || '条码优先，OCR 兜底');

          if (!hit || !captureRunning) return;
          const key = `${hit.trackingNumber}-${hit.detectedAt}`;
          if (key === lastRecognitionKey) return;
          lastRecognitionKey = key;

          const b = hit.boundingBox;
          const overlay = $('recognition-overlay');
          const tag = $('recognition-tag');
          const left = Math.max(0, Math.min(100, Number(b.x) * 100));
          const top = Math.max(0, Math.min(100, (1 - Number(b.y) - Number(b.height)) * 100));
          const width = Math.max(1, Math.min(100 - left, Number(b.width) * 100));
          const height = Math.max(1, Math.min(100 - top, Number(b.height) * 100));
          Object.assign(overlay.style, { display:'block', left:`${left}%`, top:`${top}%`, width:`${width}%`, height:`${height}%` });
          tag.textContent = hit.trackingNumber;
          Object.assign(tag.style, { display:'block', left:`${left}%`, top:`${Math.max(0, top - 7)}%` });
          setTimeout(() => {
            if (lastRecognitionKey === key) {
              overlay.style.display = 'none';
              tag.style.display = 'none';
            }
          }, 6000);
        }

        function renderStorage(storage, recording) {
          $('nas-state').textContent = storage.available && storage.writable ? 'Ready' : (storage.configured ? 'Offline' : '未配置');
          $('nas-state').className = `value ${storage.available && storage.writable ? 'ok' : 'warn'}`;
          $('recording-state').textContent = recording.recording ? `REC ${fmtOffset(recording.segmentDurationSeconds)}` : (storage.recordingEnabled ? 'Standby' : 'Disabled');
          $('recording-state').className = `value ${recording.recording ? 'ok' : ''}`;

          if (document.activeElement !== $('storage-path')) $('storage-path').value = storage.rootPath || '';
          $('recording-enabled').checked = !!storage.recordingEnabled;
          $('segment-minutes').value = String(storage.segmentMinutes || 5);
          $('volume-list').innerHTML = (storage.mountedVolumes || []).map(v => `<option value="${escapeHtml(v + '/PackingMonitor')}"></option>`).join('');

          const lines = [];
          if (storage.rootPath) lines.push(`路径：${storage.rootPath}`);
          lines.push(`状态：${storage.available ? '已挂载' : '不可用'} / ${storage.writable ? '可写' : '不可写'}`);
          if (recording.currentPath) lines.push(`当前录像：${recording.currentPath}`);
          if (storage.error) lines.push(`提示：${storage.error}`);
          if (recording.lastError) lines.push(`录像错误：${recording.lastError}`);
          $('storage-detail').innerHTML = lines.map(escapeHtml).join('<br>');
        }

        function renderEvents(events) {
          const body = $('event-body');
          if (!events.length) {
            body.innerHTML = '<tr><td colspan="6" class="empty">暂无匹配记录</td></tr>';
            return;
          }
          body.innerHTML = events.map(event => `
            <tr>
              <td><strong>${escapeHtml(event.trackingNumber)}</strong><br><span class="muted">${escapeHtml(event.rawValue || '')}</span></td>
              <td>${escapeHtml(fmtTime(event.detectedAt))}</td>
              <td><span class="pill">${escapeHtml(event.source)}</span>${event.symbology ? '<br><span class="muted">' + escapeHtml(event.symbology) + '</span>' : ''}</td>
              <td><strong>${escapeHtml(fmtOffset(event.offsetSeconds))}</strong></td>
              <td class="path" title="${escapeHtml(event.videoPath || '')}">${escapeHtml(basename(event.videoPath))}</td>
              <td>${event.videoPath ? `<button onclick="revealEvent('${event.id}')">定位文件</button>` : '<span class="muted">无录像</span>'}</td>
            </tr>`).join('');
        }

        function refreshPreview() {
          if (!captureRunning || previewBusy) return;
          previewBusy = true;
          const img = $('preview');
          img.onload = () => {
            previewBusy = false;
            img.style.display = 'block';
            $('preview-placeholder').style.display = 'none';
          };
          img.onerror = () => {
            previewBusy = false;
            img.style.display = 'none';
            $('preview-placeholder').style.display = 'block';
            $('preview-placeholder').textContent = '正在等待视频帧…';
          };
          img.src = `/api/camera/frame.jpg?t=${Date.now()}`;
        }

        async function refresh() {
          try {
            const [statusRes, camerasRes, captureRes, recognitionRes, storageRes, recordingRes] = await Promise.all([
              fetch('/api/status'), fetch('/api/cameras'), fetch('/api/camera/capture-status'),
              fetch('/api/recognition/status'), fetch('/api/storage/status'), fetch('/api/recording/status')
            ]);
            const status = await statusRes.json();
            const cameras = await camerasRes.json();
            const capture = await captureRes.json();
            const recognition = await recognitionRes.json();
            const storage = await storageRes.json();
            const recording = await recordingRes.json();

            $('service').textContent = `${status.service} ${status.version}`;
            $('permission').textContent = status.cameraPermission;
            $('permission').className = `value ${status.cameraPermission === 'authorized' ? 'ok' : 'warn'}`;
            renderCapture(capture);
            renderCameraSelector(cameras.cameras, status, capture);
            renderRecognition(recognition);
            renderStorage(storage, recording);

            const cameraBody = $('camera-body');
            if (!cameras.cameras.length) {
              cameraBody.innerHTML = '<tr><td colspan="6" class="empty">未发现 AVFoundation 视频设备</td></tr>';
            } else {
              cameraBody.innerHTML = cameras.cameras.map(c => `
                <tr>
                  <td><strong>${escapeHtml(c.name)}</strong><br><code>${escapeHtml(c.id)}</code></td>
                  <td>${escapeHtml(c.manufacturer)}<br><span class="muted">${escapeHtml(c.modelID)}</span></td>
                  <td><code>${escapeHtml(c.deviceType)}</code></td>
                  <td>${c.maxWidth || 0} × ${c.maxHeight || 0}</td>
                  <td>${Number(c.maxFPS || 0).toFixed(2)}</td>
                  <td>${c.formatCount}</td>
                </tr>`).join('');
            }
          } catch (error) {
            $('service').textContent = 'API error';
            console.error(error);
          }
        }

        async function loadRecentEvents() {
          try {
            const res = await fetch('/api/events/recent');
            const data = await res.json();
            renderEvents(data.results || []);
          } catch (error) { console.error(error); }
        }

        async function searchTracking() {
          const q = $('tracking-query').value.trim();
          if (!q) { await loadRecentEvents(); return; }
          const res = await fetch(`/api/events/search?q=${encodeURIComponent(q)}`);
          const data = await res.json();
          renderEvents(data.results || []);
        }

        async function captureAction(path) {
          const res = await fetch(path, { method:'POST' });
          const data = await res.json();
          if (!data.ok) alert(data.error || '操作失败');
          renderCapture(data.capture);
          await refresh();
          refreshPreview();
        }

        async function saveStorage() {
          const path = $('storage-path').value.trim();
          const enabled = $('recording-enabled').checked ? '1' : '0';
          const minutes = $('segment-minutes').value;
          const url = `/api/storage/config?rootPath=${encodeURIComponent(path)}&recordingEnabled=${enabled}&segmentMinutes=${encodeURIComponent(minutes)}`;
          const res = await fetch(url, { method:'POST' });
          const data = await res.json();
          if (!data.ok) alert(data.error || 'NAS 配置失败');
          await refresh();
        }

        async function revealEvent(id) {
          const res = await fetch(`/api/events/reveal?id=${encodeURIComponent(id)}`, { method:'POST' });
          const data = await res.json();
          if (!data.ok) alert(data.error || '无法定位录像文件');
        }
        window.revealEvent = revealEvent;

        $('refresh').addEventListener('click', () => { refresh(); loadRecentEvents(); });
        $('camera-select').addEventListener('change', (event) => { selectedCameraID = event.target.value || null; updateCameraDetail(); });
        $('authorize').addEventListener('click', async () => {
          const res = await fetch('/api/camera/authorize', { method:'POST' });
          const data = await res.json();
          alert(data.granted ? '摄像头权限已授权' : `摄像头权限未授权：${data.status}`);
          await refresh();
        });
        $('start-capture').addEventListener('click', () => {
          if (!selectedCameraID) { alert('请先选择视频源'); return; }
          captureAction(`/api/camera/start?deviceID=${encodeURIComponent(selectedCameraID)}`);
        });
        $('stop-capture').addEventListener('click', () => captureAction('/api/camera/stop'));
        $('save-storage').addEventListener('click', saveStorage);
        $('search-tracking').addEventListener('click', searchTracking);
        $('tracking-query').addEventListener('keydown', (event) => { if (event.key === 'Enter') searchTracking(); });

        refresh();
        loadRecentEvents();
        setInterval(refresh, 2000);
        setInterval(refreshPreview, 125);
        setInterval(loadRecentEvents, 10000);
      </script>
    </body>
    </html>
    """#
}
