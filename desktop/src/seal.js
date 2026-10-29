import { reserveLanguageSpace } from './language-layout.js';
const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const basename = (s) => s?.split('/').pop() || '';
const defaults = { force: true, deep: true, preserveMetadata: true, hardenedRuntime: false, timestamp: false, removeQuarantine: true, entitlements: null };
export function initSeal({ t, page, getPreferences, setLanguage }) {
  const api = window.seal;
  let previewGeneration = 0;
  const state = { target: null, report: null, identities: [{ id: '-', name: 'Ad-hoc', adHoc: true }], identity: '-', options: { ...defaults }, queue: [], busy: false, stop: false, processing: false, processed: 0, total: 0, logs: [], recursive: false, identityMenu: null, error: '' };
  const text = (zh, en) => esc(t(zh, en));
  const status = (value) => ({ signed: t('签名有效', 'VALID SIGNATURE'), adhoc: t('Ad-hoc 有效', 'VALID AD-HOC'), unsigned: t('未签名', 'UNSIGNED'), invalid: t('签名无效', 'INVALID'), unsupported: t('不适用', 'NOT APPLICABLE') })[value] || t('尚未检查', 'NOT INSPECTED');
  const phase = (value) => ({ pending: t('待检查', 'PENDING'), inspecting: t('检查中', 'INSPECTING'), ready: t('待签名', 'READY'), signing: t('签名中', 'SIGNING'), signed: t('已完成', 'COMPLETE'), failed: t('失败', 'FAILED'), skipped: t('已跳过', 'SKIPPED') })[value];
  const kind = (value) => ({ app: 'App Bundle', plugin: t('音频插件', 'Audio plugin'), bundle: 'Code Bundle', binary: 'Mach-O', file: t('文件', 'File'), folder: t('文件夹', 'Folder') })[value];
  const bytes = (n) => n == null ? t('目录', 'Directory') : new Intl.NumberFormat(getPreferences().language, { style: 'unit', unit: n < 1024 ? 'byte' : n < 1048576 ? 'kilobyte' : 'megabyte', maximumFractionDigits: 1 }).format(n < 1024 ? n : n < 1048576 ? n / 1024 : n / 1048576);
  const button = (action, zh, en, attr = '') => `<button data-action="${action}" ${attr}>${text(zh, en)}</button>`;
  const badge = (value) => `<span class="signature-badge ${esc(value)}">${esc(status(value))}</span>`;
  function toast(zh, en, error = false) {
    const box = $('#toast'); box.hidden = false; box.textContent = t(zh, en); box.classList.toggle('error', error);
    clearTimeout(toast.timer); toast.timer = setTimeout(() => { box.hidden = true; }, 3200);
  }
  function log(message, level = 'info', command = '') {
    state.logs.push({ time: new Date().toISOString(), message, level, command });
    state.logs = state.logs.slice(-100); renderLog();
  }
  function fail(error) {
    state.error = error.message || String(error);
    log(state.error, 'error'); showError();
  }
  function showError() {
    const box = $('#error'); box.hidden = !state.error;
    box.replaceChildren();
    if (state.error) {
      const copy = document.createElement('span'); copy.textContent = state.error;
      const close = document.createElement('button'); close.textContent = '×'; close.setAttribute('aria-label', t('关闭错误', 'Dismiss error'));
      close.onclick = () => { state.error = ''; showError(); };
      box.append(copy, close);
    }
  }
  async function work(fn) {
    if (state.busy) return;
    state.busy = true; state.error = ''; render(); showError();
    try { await fn(); } catch (error) { fail(error); }
    finally { state.busy = false; render(); }
  }
  function applyReport(report) {
    state.report = report; state.target = report.target;
    if (report.xattrError) log(report.xattrError, 'warning');
    if (report.warning) { state.error = report.warning; showError(); log(report.warning, 'warning'); }
    const queued = state.queue.find((item) => item.target.path === report.target.path);
    if (queued) { queued.report = report; queued.target = report.target; }
  }
  async function inspect(target) {
    applyReport(await api.inspect(target.path));
    log(`${t('检查完成', 'Inspected')}: ${target.name}`);
  }
  function optionsHTML(scope) {
    const identity = state.identities.find((id) => id.id === state.identity) || state.identities[0];
    const opts = [
      ['deep', '深度签名', 'Deep signing', '重签包内的嵌套代码', 'Re-sign nested code inside bundles'],
      ['preserveMetadata', '保留元数据', 'Preserve metadata', '保留 entitlements、flags 和 runtime', 'Keep entitlements, flags and runtime'],
      ['hardenedRuntime', 'Hardened Runtime', 'Hardened Runtime', '启用运行时保护', 'Enable runtime protections'],
      ['timestamp', '时间戳', 'Timestamp', '证书签名时连接 Apple 时间戳服务', 'Use Apple’s timestamp service for certificate signing'],
      ['removeQuarantine', '移除隔离标记', 'Remove quarantine', '签名后清理包内的 quarantine 属性', 'Clear quarantine recursively after signing'],
    ];
    return `<div class="panel-title"><h2>${text('签名配置', 'SIGNING CONFIGURATION')}</h2><span class="micro">${scope === 'batch' ? text('应用于整个队列', 'SHARED BY THE QUEUE') : 'CODESIGN'}</span></div>
      <div class="identity-control"><label>${text('签名身份', 'SIGNING IDENTITY')}</label><button class="identity-button" data-action="identity-menu" data-scope="${scope}" aria-expanded="${state.identityMenu === scope}" ${state.busy ? 'disabled' : ''}>${esc(identity.adHoc ? t('Ad-hoc · 本机临时签名', 'Ad-hoc · local signature') : identity.name)} <span>⌄</span></button>
      ${state.identityMenu === scope ? `<div class="identity-list" role="group" aria-label="${text('签名身份', 'Signing identity')}">${state.identities.map((id) => `<button data-action="choose-identity" data-identity="${esc(id.id)}" aria-pressed="${state.identity === id.id}">${esc(id.adHoc ? t('Ad-hoc · 本机临时签名', 'Ad-hoc · local signature') : id.name)}</button>`).join('')}</div>` : ''}
      ${button('refresh-identities', '刷新证书列表 ↻', 'REFRESH IDENTITIES ↻', `class="text-button" ${state.busy ? 'disabled' : ''}`)}</div>
      <div class="option-list">${opts.map(([key, zh, en, hintZh, hintEn]) => `<div class="option-row"><div><span>${text(zh, en)}</span><small>${text(hintZh, hintEn)}</small></div><button class="switch" role="switch" data-action="option" data-option="${key}" aria-label="${text(zh, en)}" aria-checked="${state.options[key]}" ${state.busy || key === 'timestamp' && identity.adHoc ? 'disabled' : ''}>${state.options[key] ? 'ON' : 'OFF'}</button></div>`).join('')}</div>
      <div class="entitlements-row"><span>ENTITLEMENTS</span><p title="${esc(state.options.entitlements || '')}">${esc(state.options.entitlements ? basename(state.options.entitlements) : t('使用现有权限配置', 'Use existing entitlements'))}</p><div class="actions">${button('entitlements', '选择文件', 'CHOOSE FILE', state.busy ? 'disabled' : '')}${state.options.entitlements ? button('clear-entitlements', '移除', 'REMOVE', state.busy ? 'disabled' : '') : ''}</div></div>`;
  }
  const info = (label, value) => `<div class="info-row"><dt>${esc(label)}</dt><dd>${esc(value || '—')}</dd></div>`;
  function renderSingle() {
    $('#drop-zone').hidden = !!state.target;
    $('#empty-support').hidden = !!state.target;
    const root = $('#single-result'); root.hidden = !state.target;
    if (!state.target) { root.innerHTML = ''; return; }
    const target = state.target, sig = state.report?.signature;
    root.innerHTML = `<div class="file-header"><div class="file-monogram" aria-hidden="true">${target.kind === 'plugin' ? 'AU' : target.kind === 'app' ? 'APP' : target.kind === 'binary' ? 'BIN' : 'FILE'}</div><div class="file-meta"><h2>${esc(target.name)}</h2><p class="file-path" title="${esc(target.path)}">${esc(target.path)}</p><div class="file-facts"><span>${esc(kind(target.kind))}</span><span>${esc(bytes(target.size))}</span><span>${esc(target.writable ? t('可写', 'WRITABLE') : t('只读', 'READ ONLY'))}</span></div></div><div class="file-header-actions">${button('open', '更换文件 ↗', 'CHANGE FILE ↗', state.busy ? 'disabled' : '')}${button('sign', '重新签名 ↗', 'RE-SIGN ↗', `class="primary" ${state.busy || !sig || !target.canSign ? 'disabled' : ''}`)}</div></div>
      <div class="inspection-grid"><div><article class="panel signature-panel"><div class="panel-title"><h2>${text('签名状态', 'SIGNATURE')}</h2>${badge(sig?.status)}</div>
      ${!sig ? `<p class="loading-line"><span class="spinner"></span>${text('正在读取签名与扩展属性…', 'Reading signature and extended attributes…')}</p>` : `<div class="verification-result ${sig.verified ? 'pass' : ''}"><span>${sig.verified ? '✓' : '↗'}</span><div><strong>${esc(status(sig.status))}</strong><p>${esc(sig.status === 'unsupported' ? t('普通文件夹支持扩展属性操作。', 'Use the attributes workspace for ordinary folders.') : sig.verified ? t('codesign 严格校验通过', 'Passed strict codesign verification') : t('可以查看详细输出，或重新签名。', 'Review the output or apply a new signature.'))}</p></div></div>
      <dl>${info('Identifier', sig.identifier)}${info('Team ID', sig.teamID)}${info('CDHash', sig.cdhash)}${info('Format', sig.format)}${info('Flags', sig.flags.join(', '))}${info('Timestamp', sig.timestamp)}</dl>
      <div class="authority"><span class="micro">${text('证书链', 'AUTHORITY CHAIN')}</span><p>${esc(sig.authorities.length ? sig.authorities.join(' → ') : sig.status === 'adhoc' ? t('Ad-hoc · 无证书链', 'Ad-hoc · no certificate chain') : t('没有证书链', 'No certificate chain'))}</p></div>
      <div class="gatekeeper"><span class="micro">GATEKEEPER</span><p>${esc(sig.gatekeeper.status === 'accepted' ? t('通过评估', 'Assessment accepted') : sig.gatekeeper.status === 'rejected' ? t('未通过评估', 'Assessment rejected') : t('仅对带签名的 App 评估', 'Assessed for signed app bundles only'))}</p>${sig.gatekeeper.output ? `<details><summary>${text('评估输出', 'ASSESSMENT OUTPUT')}</summary><pre>${esc(sig.gatekeeper.output)}</pre></details>` : ''}</div>
      <details><summary>${text('签名与校验原始输出', 'RAW SIGNATURE & VERIFICATION')}</summary><pre>${esc(sig.raw)}\n${esc(sig.verificationOutput)}</pre></details>
      ${sig.entitlements ? `<details><summary>ENTITLEMENTS</summary><pre>${esc(sig.entitlements)}</pre></details>` : ''}`}
      <div class="actions">${button('refresh', '重新检查 ↻', 'RE-INSPECT ↻', state.busy ? 'disabled' : '')}${button('copy-report', '复制报告', 'COPY REPORT', !sig ? 'disabled' : '')}${button('reveal', 'Finder 定位', 'REVEAL', '')}</div></article>
      <div class="panel attributes-link"><div><h2>${text('扩展属性', 'EXTENDED ATTRIBUTES')}</h2><p>${esc(state.report?.xattrs.length ?? 0)} ${text('项属性', 'attributes')} ${state.report?.xattrs.some((item) => item.quarantine) ? '· QUARANTINE' : ''}</p></div>${button('goto-attributes', '查看 ↗', 'VIEW ↗')}</div></div>
      <article class="panel signing-panel">${optionsHTML('single')}<div class="sign-action">${button('sign', '重新签名 ↗', 'RE-SIGN ↗', `class="primary wide" ${state.busy || !sig || !target.canSign ? 'disabled' : ''}`)}<p>${text('完成后自动校验签名。', 'The signature is verified after signing.')}</p></div><details><summary>${text('命令预览', 'COMMAND PREVIEW')}</summary><pre id="command-preview"></pre></details></article></div>`;
    if (api && sig) {
      const ticket = target.path, generation = ++previewGeneration;
      api.preview?.(ticket, state.identity, { ...state.options }, sig.exists).then((command) => { if (previewGeneration === generation && state.target?.path === ticket && $('#command-preview')) $('#command-preview').textContent = command; }).catch(() => {});
    }
  }
  function renderBatch() {
    const counts = Object.fromEntries(['signed', 'failed', 'skipped'].map((value) => [value, state.queue.filter((item) => item.state === value).length]));
    $('#batch-progress').innerHTML = `<span>${state.queue.length} ${text('项', 'FILES')}</span><span class="pass">${counts.signed} ${text('成功', 'COMPLETE')}</span><span class="failure">${counts.failed} ${text('失败', 'FAILED')}</span><span>${counts.skipped} ${text('跳过', 'SKIPPED')}</span>${state.processing ? `<strong><span class="spinner"></span>${state.processed} / ${state.total}${state.stop ? ` · ${text('等待当前项完成', 'STOPPING AFTER CURRENT FILE')}` : ''}</strong>` : ''}`;
    $('#batch-list').innerHTML = state.queue.length ? state.queue.map((item, index) => `<article class="queue-row ${esc(item.state)}"><span class="queue-index">${String(index + 1).padStart(2, '0')}</span><div class="queue-file"><strong title="${esc(item.target.path)}">${esc(item.target.name)}</strong><p class="file-path">${esc(item.target.path)}</p><small>${esc(kind(item.target.kind))} · ${esc(bytes(item.target.size))}</small>${item.message ? `<p class="queue-message">${esc(item.message)}</p>` : ''}</div><div class="queue-state"><span class="phase">${esc(phase(item.state))}</span>${item.report ? badge(item.report.signature.status) : ''}</div><div class="queue-actions">${button('item-sign', '重签', 'SIGN', `data-path="${esc(item.target.path)}" ${state.busy || !item.target.canSign ? 'disabled' : ''}`)}${button('item-open', '查看', 'OPEN', `data-path="${esc(item.target.path)}" ${state.busy ? 'disabled' : ''}`)}${button('item-reveal', '定位', 'REVEAL', `data-path="${esc(item.target.path)}"`)}${button('item-remove', '移出', 'REMOVE', `data-path="${esc(item.target.path)}" ${state.busy ? 'disabled' : ''}`)}</div></article>`).join('') : `<div class="empty-state"><span class="empty-mark">[ + ]</span><h2>${text('队列为空', 'THE QUEUE IS EMPTY')}</h2><p>${text('拖入多个文件，或点击「添加文件」。', 'Drop multiple files here or choose Add files.')}</p></div>`;
    $('#batch-options').innerHTML = optionsHTML('batch');
    $('#batch-sign').disabled = state.busy || !state.queue.some((item) => item.target.canSign);
    $('#batch-inspect').disabled = state.busy || !state.queue.length;
    for (const id of ['batch-add', 'batch-clear', 'batch-clear-done']) $(`#${id}`).disabled = state.busy;
    $('#batch-stop').hidden = !state.processing; $('#batch-stop').disabled = state.stop;
  }
  function renderAttributes() {
    const root = $('#attributes-content');
    if (!state.target) { root.innerHTML = `<div class="empty-state"><h2>${text('先选择一个文件', 'CHOOSE A FILE FIRST')}</h2><p>${text('App、插件、普通文件和文件夹均可检查扩展属性。', 'Inspect extended attributes on apps, plugins, files and folders.')}</p>${button('open', '打开文件 ↗', 'OPEN FILE ↗', 'class="primary"')}</div>`; return; }
    const attrs = state.report?.xattrs || [];
    root.innerHTML = `<div class="target-strip"><div><strong>${esc(state.target.name)}</strong><p class="file-path">${esc(state.target.path)}</p></div>${button('open', '更换文件', 'CHANGE FILE', state.busy ? 'disabled' : '')}</div>
      <div class="attributes-toolbar"><div class="recursive-choice"><span>${text('包含嵌套文件', 'INCLUDE NESTED FILES')}</span><button class="switch" role="switch" data-action="recursive" aria-label="${text('包含嵌套文件', 'Include nested files')}" aria-checked="${state.recursive}" ${state.busy ? 'disabled' : ''}>${state.recursive ? 'ON' : 'OFF'}</button></div><div class="actions">${button('refresh', '刷新 ↻', 'REFRESH ↻', state.busy ? 'disabled' : '')}${button('remove-quarantine', '移除隔离标记', 'REMOVE QUARANTINE', `${state.busy ? 'disabled' : ''}`)}${button('clear-xattrs', '清除全部属性', 'CLEAR ALL ATTRIBUTES', `class="danger" ${state.busy || !state.report ? 'disabled' : ''}`)}</div></div>
      <p class="attribute-scope">${text('列表显示顶层属性。开启递归后，删除操作也会作用于包内文件。', 'The list shows top-level attributes. Recursive removal also applies inside the bundle.')}</p>
      ${state.report?.xattrError ? `<p class="inline-error">${esc(state.report.xattrError)}</p>` : ''}
      ${attrs.length ? attrs.map((item) => `<article class="xattr-row"><div class="xattr-heading"><div><strong>${esc(item.name)}</strong><span class="micro">${esc(bytes(item.size))}${item.truncated ? ' · TRUNCATED' : ''}</span></div>${button('remove-xattr', '移除', 'REMOVE', `class="danger" data-name="${esc(item.name)}" ${state.busy ? 'disabled' : ''}`)}</div><p>${esc(item.summary || t('空值', 'Empty value'))}</p>${item.quarantine ? `<dl>${info(t('下载代理', 'Download agent'), item.quarantine.agent)}${info(t('下载时间', 'Downloaded'), item.quarantine.date ? new Date(item.quarantine.date).toLocaleString(getPreferences().language) : '')}${info(t('来源', 'Origin'), item.quarantine.origin)}${info(t('标志', 'Flags'), item.quarantine.flags)}</dl>` : ''}<details><summary>${text('详细值与十六进制', 'DETAILS & HEX')}</summary><pre>${esc(item.details.join('\n'))}\n\nHEX: ${esc(item.hex)}</pre></details>${button('copy-xattr', '复制属性', 'COPY ATTRIBUTE', `class="text-button" data-name="${esc(item.name)}"`)}</article>`).join('') : `<div class="empty-state"><h2>${text(state.busy ? '正在读取…' : '没有扩展属性', state.busy ? 'READING…' : 'NO EXTENDED ATTRIBUTES')}</h2><p>${text('属性操作使用当前用户权限。', 'Attribute operations use your current user permissions.')}</p></div>`}`;
  }
  function renderLog() {
    const list = $('#activity-list');
    list.innerHTML = [...state.logs].reverse().map((entry) => `<article class="log-entry ${esc(entry.level)}"><time>${esc(new Date(entry.time).toLocaleTimeString(getPreferences().language, { hour12: false }))}</time><div><p>${esc(entry.message)}</p>${entry.command ? `<pre>${esc(entry.command)}</pre>` : ''}</div></article>`).join('');
  }
  function render() {
    renderSingle(); renderBatch(); renderAttributes(); renderLog();
    $('#sidebar-target').textContent = state.target?.name || t('尚未选择文件', 'NO FILE SELECTED');
    $('#footer-status').textContent = state.busy ? t('处理中…', 'WORKING…') : t('就绪', 'READY');
    $('#drop-zone').setAttribute('aria-disabled', String(state.busy));
    $('#open-target').disabled = state.busy;
    $('[data-page="batch"] small').textContent = `${state.queue.length} ${t('项文件', 'FILES IN QUEUE')}`;
    reserveLanguageSpace();
  }
  async function select(target) {
    page('overview');
    await work(async () => { state.target = target; state.report = null; render(); await inspect(target); });
  }
  async function accept(targets, forceBatch = false) {
    if (!targets?.length || state.busy) return;
    if (targets.length === 1 && !forceBatch) return select(targets[0]);
    for (const target of targets) if (!state.queue.some((item) => item.target.path === target.path)) state.queue.push({ target, state: 'pending', report: null, message: '' });
    page('batch'); render();
    await runQueue(false, state.queue.filter((item) => item.state === 'pending'));
  }
  async function open(forceBatch = false) { if (!api || state.busy) return; try { await accept(await api.chooseTargets(), forceBatch || $('#site').dataset.view === 'batch'); } catch (error) { fail(error); } }
  async function refresh() { if (state.target) await work(() => inspect(state.target)); }
  async function sign() {
    if (!state.target?.canSign) return;
    await work(async () => {
      const name = state.target.name;
      log(`${t('开始签名', 'Signing')}: ${name}`);
      applyReport(await api.sign(state.target.path, state.identity, { ...state.options }));
      log(`${t('签名及校验完成', 'Signed and verified')}: ${name}`, 'success');
      toast('签名及校验完成', 'Signed and verified');
    });
  }
  async function runQueue(signing, items = state.queue) {
    if (state.busy || !items.length) return;
    const snapshot = [...items], identity = state.identity, options = { ...state.options };
    await work(async () => {
      state.processing = true; state.stop = false; state.processed = 0; state.total = snapshot.length;
      try {
        for (const item of snapshot) {
          if (state.stop) break;
          item.state = signing ? 'signing' : 'inspecting'; item.message = ''; render();
          try {
            if (signing && !item.target.canSign) { item.state = 'skipped'; continue; }
            item.report = signing ? await api.sign(item.target.path, identity, options) : await api.inspect(item.target.path);
            item.target = item.report.target;
            item.state = !item.target.canSign ? 'skipped' : signing ? 'signed' : 'ready';
            if (item.report.warning) { item.message = item.report.warning; log(item.report.warning, 'warning'); }
            if (state.target?.path === item.target.path) applyReport(item.report);
            log(`${signing ? t('签名完成', 'Signed') : t('检查完成', 'Inspected')}: ${item.target.name}`, signing ? 'success' : 'info');
          } catch (error) { item.state = 'failed'; item.message = error.message; log(`${item.target.name}: ${error.message}`, 'error'); }
          finally { state.processed++; render(); }
        }
        log(state.stop ? t('批量操作已停止', 'Batch stopped') : t('批量操作完成', 'Batch complete'), snapshot.some((item) => item.state === 'failed') ? 'warning' : 'success');
        toast(state.stop ? '批量操作已停止' : '批量操作完成，请查看每项结果', state.stop ? 'Batch stopped' : 'Batch complete. Review the per-file results.');
      } finally { state.processing = false; state.stop = false; }
    });
  }
  async function attributes(action, name) {
    if (!state.target) return;
    await work(async () => {
      const report = action === 'clear-xattrs' ? await api.clearXattrs(state.target.path, state.recursive) : await api.removeXattr(state.target.path, name, state.recursive);
      if (report) { applyReport(report); log(t('扩展属性已更新', 'Extended attributes updated'), 'success'); toast('扩展属性已更新', 'Extended attributes updated'); }
    });
  }
  const reportText = () => JSON.stringify(state.report, null, 2);
  async function copy(value) { try { await api.copy(value); toast('已复制', 'Copied'); } catch (error) { fail(error); } }
  document.addEventListener('click', async (event) => {
    const control = event.target.closest('[data-action]'); if (!control || control.disabled) return;
    const action = control.dataset.action, item = state.queue.find((entry) => entry.target.path === control.dataset.path);
    try {
      if (action === 'open') await open();
      else if (action === 'refresh') await refresh();
      else if (action === 'sign') await sign();
      else if (action === 'goto-attributes') page('attributes');
      else if (action === 'reveal') await api.reveal(state.target.path);
      else if (action === 'copy-report') await copy(reportText());
      else if (action === 'identity-menu' && !state.busy) { state.identityMenu = state.identityMenu === control.dataset.scope ? null : control.dataset.scope; render(); }
      else if (action === 'choose-identity' && !state.busy) { state.identity = control.dataset.identity; state.identityMenu = null; render(); }
      else if (action === 'option' && !state.busy) { state.options[control.dataset.option] = !state.options[control.dataset.option]; render(); }
      else if (action === 'refresh-identities') await work(async () => { const result = await api.identities(); state.identities = result.identities; if (result.error) throw new Error(result.error); toast('证书列表已刷新', 'Identities refreshed'); });
      else if (action === 'entitlements') { if (!state.busy) { const value = await api.chooseEntitlements(); if (value) state.options.entitlements = value; render(); } }
      else if (action === 'clear-entitlements' && !state.busy) { state.options.entitlements = null; render(); }
      else if (action === 'recursive' && !state.busy) { state.recursive = !state.recursive; render(); }
      else if (action === 'remove-xattr') await attributes(action, control.dataset.name);
      else if (action === 'remove-quarantine') await attributes(action, 'com.apple.quarantine');
      else if (action === 'clear-xattrs') await attributes(action);
      else if (action === 'copy-xattr') await copy(JSON.stringify(state.report.xattrs.find((entry) => entry.name === control.dataset.name), null, 2));
      else if (action === 'item-open' && item) await select(item.target);
      else if (action === 'item-sign' && item) await runQueue(true, [item]);
      else if (action === 'item-reveal' && item) await api.reveal(item.target.path);
      else if (action === 'item-remove' && !state.busy) { state.queue = state.queue.filter((entry) => entry !== item); render(); }
    } catch (error) { fail(error); }
  });
  $('#open-target').onclick = (event) => { event.stopPropagation(); open(); };
  $('#drop-zone').onclick = () => open();
  $('#drop-zone').onkeydown = (event) => { if (['Enter', ' '].includes(event.key)) { event.preventDefault(); open(); } };
  $('#batch-add').onclick = () => open(true);
  $('#batch-inspect').onclick = () => runQueue(false);
  $('#batch-sign').onclick = () => runQueue(true);
  $('#batch-stop').onclick = () => { state.stop = true; render(); };
  $('#batch-clear').onclick = () => { if (!state.busy) { state.queue = []; render(); } };
  $('#batch-clear-done').onclick = () => { if (!state.busy) { state.queue = state.queue.filter((item) => !['signed', 'failed', 'skipped'].includes(item.state)); render(); } };
  $('#copy-log').onclick = () => copy(state.logs.map((entry) => `[${entry.time}] ${entry.message}${entry.command ? '\n' + entry.command : ''}`).join('\n\n'));
  $('#clear-log').onclick = () => { state.logs = []; renderLog(); };
  document.addEventListener('dragover', (event) => { if ([...event.dataTransfer.types].includes('Files')) { event.preventDefault(); $('#site').classList.add('drag-over'); } });
  document.addEventListener('dragleave', (event) => { if (!event.relatedTarget) $('#site').classList.remove('drag-over'); });
  document.addEventListener('drop', async (event) => {
    event.preventDefault(); $('#site').classList.remove('drag-over'); if (state.busy || !api) return;
    try { await accept(await api.acceptFiles([...event.dataTransfer.files]), $('#site').dataset.view === 'batch'); } catch (error) { fail(error); }
  });
  $$('[data-preset]').forEach((b) => b.onclick = async () => { try { await api.resize(b.dataset.preset); localStorage.setItem('seal-window', b.dataset.preset); syncPreset(); } catch (error) { fail(error); } });
  function syncPreset() { $$('[data-preset]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.preset === (localStorage.getItem('seal-window') || 'standard')))); }
  document.addEventListener('languagechange', () => { render(); showError(); });
  api?.onCommand((command) => log(t('执行命令', 'Command executed'), 'command', command));
  api?.onOpen((targets) => { if (!state.busy) accept(targets); else { log(t('当前操作完成后，请重新打开文件。', 'Reopen the file after the current operation finishes.'), 'warning'); } });
  api?.onMenu((action) => {
    if (action === 'settings') { if ($('#welcome').hidden) $('#system-open').click(); }
    else if (action === 'open') open();
    else if (action === 'refresh') $('#site').dataset.view === 'batch' ? runQueue(false) : refresh();
    else if (action === 'sign') $('#site').dataset.view === 'batch' ? runQueue(true) : sign();
  });
  async function initialize() {
    if (!api) { log(t('请从 Seal.app 打开以操作本机文件。', 'Open Seal.app to work with local files.'), 'warning'); return; }
    try {
      const initial = await api.initialState();
      if (!localStorage.getItem('seal-migrated')) {
        if (initial.migrated.language) setLanguage(initial.migrated.language);
        if (['compact', 'standard', 'large'].includes(initial.migrated.preset)) localStorage.setItem('seal-window', initial.migrated.preset);
        localStorage.setItem('seal-migrated', 'true');
      }
      await api.resize(localStorage.getItem('seal-window') || 'standard');
      const identities = await api.identities(); state.identities = identities.identities;
      // Local signing remains the safe, certificate-independent default.
      if (identities.error) log(identities.error, 'warning');
      log(t('Seal 已就绪', 'Seal is ready')); render(); syncPreset();
      if (initial.targets.length) await accept(initial.targets);
    } catch (error) { fail(error); }
  }
  render(); syncPreset(); initialize();
  return { state };
}
