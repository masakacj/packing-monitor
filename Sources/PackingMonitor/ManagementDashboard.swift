enum ManagementDashboard {
    static let html = #"""
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Packing Monitor · 存储与运单查询</title>
      <style>
        :root { color-scheme: dark; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
        * { box-sizing:border-box; }
        body { margin:0; background:#0b0c0f; color:#f5f5f7; }
        main { max-width:1120px; margin:0 auto; padding:24px 20px 60px; }
        header { display:flex; align-items:flex-start; justify-content:space-between; gap:16px; margin-bottom:20px; }
        h1 { margin:0; font-size:25px; }
        h2 { margin:0 0 12px; font-size:19px; }
        .muted { color:#9297a2; font-size:13px; }
        .card { background:#15171c; border:1px solid #252832; border-radius:12px; padding:14px; }
        .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:10px; }
        .label { color:#9297a2; font-size:11px; text-transform:uppercase; letter-spacing:.08em; }
        .value { margin-top:6px; font-size:17px; font-weight:650; word-break:break-word; }
        .ok { color:#62d38b; } .warn { color:#f7c65c; } .bad { color:#ff6b72; }
        section { margin-top:22px; }
        button,input,select,a.button { border:1px solid #343845; background:#20232b; color:#fff; border-radius:8px; }
        button,a.button { appearance:none; padding:9px 12px; cursor:pointer; text-decoration:none; display:inline-block; font-size:13px; }
        button:hover,a.button:hover { background:#292d37; }
        button.primary { background:#2f5feb; border-color:#4672ef; }
        input[type=text],select { width:100%; padding:9px 10px; font-size:14px; }
        input[type=checkbox] { width:auto; }
        .actions { display:flex; gap:8px; flex-wrap:wrap; }
        .path-row { display:grid; grid-template-columns:minmax(0,1fr) auto; gap:8px; align-items:end; }
        .settings-row { display:grid; grid-template-columns:minmax(0,1fr) 170px; gap:10px; align-items:end; margin-top:10px; }
        .check-row { display:flex; gap:8px; align-items:center; margin-top:10px; }
        .volume-list { display:flex; gap:7px; flex-wrap:wrap; margin-top:10px; }
        .volume-chip { padding:6px 9px; border-radius:999px; background:#20232b; border:1px solid #343845; color:#cbd0dc; cursor:pointer; font-size:12px; }
        .status-detail { margin-top:10px; line-height:1.65; word-break:break-all; }
        .search-row { display:grid; grid-template-columns:minmax(0,1fr) auto auto; gap:8px; }
        table { width:100%; border-collapse:collapse; background:#15171c; border:1px solid #252832; border-radius:12px; overflow:hidden; }
        th,td { padding:10px 12px; border-bottom:1px solid #252832; text-align:left; vertical-align:top; }
        th { color:#9297a2; font-size:11px; font-weight:600; }
        td { font-size:13px; }
        tr:last-child td { border-bottom:0; }
        .empty { padding:24px; text-align:center; color:#9297a2; }
        .pill { display:inline-block; padding:2px 6px; border-radius:999px; background:#252832; font-size:11px; color:#cbd0dc; }
        .path { max-width:300px; word-break:break-all; color:#aeb5c2; }
        .query-summary { margin:9px 0 0; }
        @media(max-width:760px){ .path-row,.settings-row,.search-row{grid-template-columns:1fr;} .table-wrap{overflow-x:auto;} table{min-width:850px;} }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div>
            <h1>存储与运单查询</h1>
            <div class="muted">选择 NAS 保存位置，按运单号查询对应打包录像和时间点</div>
          </div>
          <div class="actions">
            <a class="button" href="/">返回实时监控</a>
            <button id="refresh">刷新</button>
          </div>
        </header>

        <div class="grid">
          <div class="card"><div class="label">NAS</div><div id="nas-state" class="value">—</div></div>
          <div class="card"><div class="label">Recording</div><div id="recording-state" class="value">—</div></div>
          <div class="card"><div class="label">Current file</div><div id="current-file" class="value" style="font-size:13px">—</div></div>
          <div class="card"><div class="label">Recent waybills</div><div id="recent-count" class="value">—</div></div>
        </div>

        <section>
          <h2>保存位置</h2>
          <div class="card">
            <div class="path-row">
              <div>
                <div class="label">保存目录</div>
                <input id="storage-path" type="text" placeholder="/Volumes/NAS/PackingMonitor">
              </div>
              <button id="choose-folder" class="primary">选择保存位置</button>
            </div>
            <div class="muted" style="margin-top:7px">只允许选择 /Volumes 下已挂载的 NAS / 外接存储；录像和索引都直接写入该位置，不落 Mac 本地硬盘。</div>
            <div id="volume-list" class="volume-list"></div>

            <div class="settings-row">
              <div>
                <div class="label">录像分段</div>
                <select id="segment-minutes">
                  <option value="2">2 分钟</option>
                  <option value="5">5 分钟</option>
                  <option value="10">10 分钟</option>
                  <option value="15">15 分钟</option>
                </select>
              </div>
              <div class="actions">
                <button id="save-storage">保存并测试</button>
              </div>
            </div>
            <div class="check-row">
              <input id="recording-enabled" type="checkbox" checked>
              <label for="recording-enabled">开始监控时自动录制到所选目录</label>
            </div>
            <div id="storage-detail" class="muted status-detail">—</div>
          </div>
        </section>

        <section>
          <h2>运单查询</h2>
          <div class="card">
            <div class="search-row">
              <input id="tracking-query" type="text" placeholder="输入快递单号 / 面单条码，例如 773001014267887">
              <button id="search" class="primary">查询</button>
              <button id="recent">最近记录</button>
            </div>
            <div id="query-summary" class="muted query-summary">默认显示最近识别记录</div>
          </div>
          <div class="table-wrap" style="margin-top:10px">
            <table>
              <thead>
                <tr><th>运单号</th><th>识别时间</th><th>识别方式</th><th>录像时间点</th><th>NAS 文件</th><th>操作</th></tr>
              </thead>
              <tbody id="event-body"><tr><td colspan="6" class="empty">正在读取…</td></tr></tbody>
            </table>
          </div>
        </section>
      </main>
      <script>
        const $ = id => document.getElementById(id);
        const escapeHtml = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
        const basename = path => path ? path.split('/').filter(Boolean).pop() : '—';
        const fmtTime = value => value ? new Date(value).toLocaleString() : '—';
        const fmtOffset = seconds => {
          if (seconds == null || Number.isNaN(Number(seconds))) return '—';
          const n = Math.max(0, Math.round(Number(seconds)));
          const h = Math.floor(n/3600), m = Math.floor((n%3600)/60), s = n%60;
          return h ? `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}` : `${m}:${String(s).padStart(2,'0')}`;
        };

        function renderStorage(storage, recording) {
          const ready = !!(storage.available && storage.writable);
          $('nas-state').textContent = ready ? 'Ready' : (storage.configured ? 'Offline' : '未配置');
          $('nas-state').className = `value ${ready ? 'ok' : 'warn'}`;
          $('recording-state').textContent = recording.recording ? `REC ${fmtOffset(recording.segmentDurationSeconds)}` : (storage.recordingEnabled ? 'Standby' : 'Disabled');
          $('recording-state').className = `value ${recording.recording ? 'ok' : ''}`;
          $('current-file').textContent = recording.currentPath ? basename(recording.currentPath) : '—';
          if (document.activeElement !== $('storage-path')) $('storage-path').value = storage.rootPath || '';
          $('segment-minutes').value = String(storage.segmentMinutes || 5);
          $('recording-enabled').checked = !!storage.recordingEnabled;

          const volumes = storage.mountedVolumes || [];
          $('volume-list').innerHTML = volumes.length
            ? volumes.map(v => `<button class="volume-chip" data-volume="${escapeHtml(v)}">${escapeHtml(v)}</button>`).join('')
            : '<span class="muted">当前没有检测到 /Volumes 下的挂载目录</span>';
          document.querySelectorAll('[data-volume]').forEach(button => {
            button.onclick = () => { $('storage-path').value = `${button.dataset.volume}/PackingMonitor`; };
          });

          const lines = [];
          if (storage.rootPath) lines.push(`路径：${storage.rootPath}`);
          lines.push(`状态：${storage.available ? '已挂载' : '不可用'} / ${storage.writable ? '可写' : '不可写'}`);
          if (storage.error) lines.push(`提示：${storage.error}`);
          if (recording.lastError) lines.push(`录像错误：${recording.lastError}`);
          $('storage-detail').innerHTML = lines.map(escapeHtml).join('<br>');
        }

        function renderEvents(events, summary) {
          $('recent-count').textContent = String(events.length);
          $('query-summary').textContent = summary;
          const body = $('event-body');
          if (!events.length) {
            body.innerHTML = '<tr><td colspan="6" class="empty">没有找到对应运单记录</td></tr>';
            return;
          }
          body.innerHTML = events.map(event => `
            <tr>
              <td><strong>${escapeHtml(event.trackingNumber)}</strong><br><button style="margin-top:5px;padding:4px 7px" onclick="copyText('${escapeHtml(event.trackingNumber)}')">复制单号</button></td>
              <td>${escapeHtml(fmtTime(event.detectedAt))}</td>
              <td><span class="pill">${escapeHtml(event.source)}</span>${event.symbology ? '<br><span class="muted">' + escapeHtml(event.symbology) + '</span>' : ''}</td>
              <td><strong>${escapeHtml(fmtOffset(event.offsetSeconds))}</strong></td>
              <td class="path" title="${escapeHtml(event.videoPath || '')}">${escapeHtml(basename(event.videoPath))}</td>
              <td><div class="actions">
                ${event.videoPath ? `<button onclick="openEvent('${event.id}')">打开录像</button><button onclick="revealEvent('${event.id}')">定位文件</button><button onclick="copyText('${escapeHtml(event.videoPath)}')">复制路径</button>` : '<span class="muted">无录像</span>'}
              </div></td>
            </tr>`).join('');
        }

        async function refreshStorage() {
          const [storageRes, recordingRes] = await Promise.all([fetch('/api/storage/status'), fetch('/api/recording/status')]);
          renderStorage(await storageRes.json(), await recordingRes.json());
        }

        async function chooseFolder() {
          const button = $('choose-folder');
          button.disabled = true;
          button.textContent = '等待选择…';
          try {
            const res = await fetch('/api/storage/choose', { method:'POST' });
            const data = await res.json();
            if (data.ok && data.path) {
              $('storage-path').value = data.path;
            } else if (data.error && data.error !== '已取消选择') {
              alert(data.error);
            }
          } finally {
            button.disabled = false;
            button.textContent = '选择保存位置';
          }
        }

        async function saveStorage() {
          const rootPath = $('storage-path').value.trim();
          const enabled = $('recording-enabled').checked ? '1' : '0';
          const minutes = $('segment-minutes').value;
          const url = `/api/storage/config?rootPath=${encodeURIComponent(rootPath)}&recordingEnabled=${enabled}&segmentMinutes=${encodeURIComponent(minutes)}`;
          const res = await fetch(url, { method:'POST' });
          const data = await res.json();
          if (!data.ok) alert(data.error || '保存失败');
          await refreshStorage();
        }

        async function loadRecent() {
          const res = await fetch('/api/events/recent');
          const data = await res.json();
          renderEvents(data.results || [], `最近 ${data.results?.length || 0} 条识别记录`);
        }

        async function searchWaybill() {
          const q = $('tracking-query').value.trim();
          if (!q) { await loadRecent(); return; }
          const res = await fetch(`/api/events/search?q=${encodeURIComponent(q)}`);
          const data = await res.json();
          renderEvents(data.results || [], `“${q}” 找到 ${data.results?.length || 0} 条记录`);
        }

        async function revealEvent(id) {
          const res = await fetch(`/api/events/reveal?id=${encodeURIComponent(id)}`, { method:'POST' });
          const data = await res.json();
          if (!data.ok) alert(data.error || '无法定位录像');
        }
        async function openEvent(id) {
          const res = await fetch(`/api/events/open?id=${encodeURIComponent(id)}`, { method:'POST' });
          const data = await res.json();
          if (!data.ok) alert(data.error || '无法打开录像');
        }
        async function copyText(value) {
          if (!value) return;
          try { await navigator.clipboard.writeText(value); }
          catch (_) {
            const area = document.createElement('textarea');
            area.value = value; document.body.appendChild(area); area.select(); document.execCommand('copy'); area.remove();
          }
        }
        window.revealEvent = revealEvent;
        window.openEvent = openEvent;
        window.copyText = copyText;

        $('refresh').onclick = () => { refreshStorage(); loadRecent(); };
        $('choose-folder').onclick = chooseFolder;
        $('save-storage').onclick = saveStorage;
        $('search').onclick = searchWaybill;
        $('recent').onclick = loadRecent;
        $('tracking-query').addEventListener('keydown', e => { if (e.key === 'Enter') searchWaybill(); });

        refreshStorage();
        loadRecent();
        setInterval(refreshStorage, 3000);
      </script>
    </body>
    </html>
    """#
}
