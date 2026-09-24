/// Draws decorations, such as highlights and underlines, over a chapter
/// prepared by an `EpubRenderSession`, layered on `readerLocationScript`.
///
/// Defines `window.readpubDecorations` with `apply(group, items)`, which
/// replaces the decorations of a group and returns a JSON string
/// `{"drawn": n, "missing": [ids]}`, and `clear()`. Each item is
/// `{id, cfi, style, color}`: a content-document range CFI, `"highlight"` or
/// `"underline"`, and `[red, green, blue, alpha]` with 0-255 channels and a
/// 0-1 alpha. Taps on a decoration post a `decorationActivated` event with
/// the group, id, tap point and the decoration's visible bounds in viewport
/// pixels to the `ReadpubReader` channel, and suppress the ordinary tap.
///
/// Decorations are drawn in a shadow tree appended to the root element,
/// outside the body, so the content's element structure and therefore its
/// CFIs are unchanged. They follow scrolling and are redrawn after the
/// layout changes.
const readerDecorationScript = r'''
(() => {
  'use strict';
  if (window.readpubDecorations || !window.readpub) return;
  const rp = window.readpub;
  const XHTML = 'http://www.w3.org/1999/xhtml';
  const post = (message) => {
    try {
      window.ReadpubReader.postMessage(JSON.stringify(message));
    } catch (_) {}
  };
  const body = () => document.body || document.documentElement;
  const important = (element, properties) => {
    for (const name in properties) element.style.setProperty(name, properties[name], 'important');
  };

  // Group name to its items, { id, range, style, color }, in paint order.
  const groups = new Map();
  // Drawn items in paint order, with rects relative to the layer.
  let drawn = [];
  let host = null;
  let layer = null;
  let fixed = false;

  const paged = () => getComputedStyle(body()).columnWidth !== 'auto';

  function dark() {
    for (const element of [body(), document.documentElement]) {
      const channels = (getComputedStyle(element).backgroundColor.match(/[\d.]+/g) || [])
        .map(Number);
      if (channels.length < 3 || channels[3] === 0) continue;
      return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2] < 128;
    }
    return false;
  }

  function ensureHost() {
    if (host && host.isConnected) return true;
    const root = document.documentElement;
    if (!root || root.namespaceURI !== XHTML) return false;
    host = document.createElementNS(XHTML, 'readpub-decorations');
    layer = document.createElementNS(XHTML, 'div');
    host.attachShadow({ mode: 'open' }).appendChild(layer);
    important(host, {
      display: 'block',
      margin: '0',
      padding: '0',
      border: '0',
      'pointer-events': 'none',
      'user-select': 'none',
      '-webkit-user-select': 'none',
      'z-index': '2147483647',
    });
    important(layer, { position: 'absolute', left: '0', top: '0', width: '0', height: '0' });
    root.appendChild(host);
    return true;
  }

  // Moves the layer with the content. Paged chapters scroll the body, so the
  // host is fixed to the viewport and the layer is translated on each scroll
  // event, which browsers dispatch before painting the scrolled frame;
  // scrolled chapters scroll the document, which moves an absolute host
  // natively.
  function sync() {
    if (!layer) return;
    const element = body();
    const own = element !== document.scrollingElement;
    const x = (own ? element.scrollLeft : 0) + (fixed ? window.scrollX : 0);
    const y = (own ? element.scrollTop : 0) + (fixed ? window.scrollY : 0);
    layer.style.setProperty('transform', 'translate(' + -x + 'px, ' + -y + 'px)', 'important');
  }

  function position() {
    fixed = paged();
    important(host, fixed
      ? { position: 'fixed', left: '0', top: '0', width: '100%', height: '100%', overflow: 'hidden' }
      : { position: 'absolute', left: '0', top: '0', width: '0', height: '0', overflow: 'visible' });
    // Multiplying keeps dark text crisp on light pages; on dark pages it
    // would hide the decoration, so it is composited normally.
    important(host, { 'mix-blend-mode': dark() ? 'normal' : 'multiply' });
    sync();
  }

  // The client rects of the text in a range, excluding element boxes, which
  // would cover margins between paragraphs.
  function textRects(range) {
    const rects = [];
    const add = (node, start, end) => {
      const part = document.createRange();
      part.setStart(node, start);
      part.setEnd(node, end);
      for (const rect of part.getClientRects()) {
        if (rect.width > 0.5 && rect.height > 0.5) rects.push(rect);
      }
    };
    const root = range.commonAncestorContainer;
    const text = (node) => node.nodeType === 3 || node.nodeType === 4;
    if (text(root)) {
      add(root, range.startOffset, range.endOffset);
      return rects;
    }
    const walker = document.createTreeWalker(root, 4 | 8);
    let node = null;
    const start = range.startContainer;
    if (text(start)) {
      node = start;
    } else {
      const child = start.childNodes[range.startOffset];
      if (child && text(child)) {
        node = child;
      } else {
        walker.currentNode = child || start;
        node = walker.nextNode();
      }
    }
    if (node) walker.currentNode = node;
    for (; node; node = walker.nextNode()) {
      if (range.comparePoint(node, 0) > 0) break;
      if (!range.intersectsNode(node)) continue;
      const from = node === range.startContainer ? range.startOffset : 0;
      const to = node === range.endContainer ? range.endOffset : node.length;
      if (to > from) add(node, from, to);
    }
    return rects;
  }

  function layout() {
    if (!groups.size) {
      if (host) host.remove();
      host = null;
      layer = null;
      drawn = [];
      return;
    }
    if (!ensureHost()) return;
    position();
    const origin = layer.getBoundingClientRect();
    const fragment = document.createDocumentFragment();
    drawn = [];
    for (const [group, items] of groups) {
      for (const item of items) {
        const rects = textRects(item.range).map((rect) => ({
          left: rect.left - origin.left,
          top: rect.top - origin.top,
          width: rect.width,
          height: rect.height,
        }));
        const element = document.createElementNS(XHTML, 'div');
        element.setAttribute('data-group', group);
        element.setAttribute('data-id', item.id);
        element.setAttribute('data-style', item.style);
        // Marks are opaque and the item is translucent, so overlapping marks
        // do not darken.
        important(element, { position: 'absolute', left: '0', top: '0', opacity: String(item.color[3]) });
        const color = 'rgb(' + item.color.slice(0, 3).join(', ') + ')';
        for (const rect of rects) {
          const underline = item.style === 'underline';
          const thickness = Math.max(1, Math.round(rect.height / 14));
          const mark = document.createElementNS(XHTML, 'div');
          important(mark, {
            position: 'absolute',
            margin: '0',
            padding: '0',
            border: '0',
            left: rect.left + 'px',
            top: (underline ? rect.top + rect.height - thickness : rect.top) + 'px',
            width: rect.width + 'px',
            height: (underline ? thickness : rect.height) + 'px',
            background: color,
          });
          element.appendChild(mark);
        }
        fragment.appendChild(element);
        drawn.push({ group, id: item.id, rects });
      }
    }
    layer.textContent = '';
    layer.appendChild(fragment);
  }

  function color(value) {
    const channels = Array.isArray(value) ? value.map(Number) : [];
    const channel = (index) => Math.max(0, Math.min(255, Math.round(channels[index] || 0)));
    const alpha = Number.isFinite(channels[3]) ? Math.max(0, Math.min(1, channels[3])) : 1;
    return [channel(0), channel(1), channel(2), alpha];
  }

  function apply(group, items) {
    const resolved = [];
    const missing = [];
    for (const item of Array.isArray(items) ? items : []) {
      let range = null;
      try {
        range = rp.rangeFromCfi(item.cfi);
      } catch (_) {}
      if (!range || range.collapsed) {
        missing.push(item.id);
        continue;
      }
      resolved.push({
        id: String(item.id),
        range,
        style: item.style === 'underline' ? 'underline' : 'highlight',
        color: color(item.color),
      });
    }
    if (resolved.length) groups.set(String(group), resolved);
    else groups.delete(String(group));
    layout();
    return { drawn: resolved.length, missing };
  }

  function clear() {
    groups.clear();
    layout();
    return true;
  }

  function hit(x, y) {
    if (!layer) return null;
    // A page turn dispatches its scroll event before the next frame; align
    // the layer now in case this click comes first.
    sync();
    const origin = layer.getBoundingClientRect();
    const px = x - origin.left;
    const py = y - origin.top;
    for (let i = drawn.length - 1; i >= 0; i--) {
      if (drawn[i].rects.some((rect) => px >= rect.left && px <= rect.left + rect.width &&
          py >= rect.top && py <= rect.top + rect.height)) {
        return drawn[i];
      }
    }
    return null;
  }

  // The union of an item's rects inside the viewport, in viewport pixels.
  function bounds(item) {
    const origin = layer.getBoundingClientRect();
    let box = null;
    for (const rect of item.rects) {
      const left = rect.left + origin.left;
      const top = rect.top + origin.top;
      const right = left + rect.width;
      const bottom = top + rect.height;
      if (right <= 0 || bottom <= 0 || left >= window.innerWidth || top >= window.innerHeight) {
        continue;
      }
      box = box
        ? {
          left: Math.min(box.left, left),
          top: Math.min(box.top, top),
          right: Math.max(box.right, right),
          bottom: Math.max(box.bottom, bottom),
        }
        : { left, top, right, bottom };
    }
    return box && { x: box.left, y: box.top, width: box.right - box.left, height: box.bottom - box.top };
  }

  const interactive = 'a[href], button, input, select, textarea, summary, audio, video, label';
  document.addEventListener('click', (event) => {
    if (event.defaultPrevented || !drawn.length) return;
    const target = event.target;
    if (target && target.closest && target.closest(interactive)) return;
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    const item = hit(event.clientX, event.clientY);
    if (!item) return;
    // The bridge ignores prevented clicks, so the tap does not turn pages.
    event.preventDefault();
    post({
      type: 'decorationActivated',
      group: item.group,
      id: item.id,
      x: event.clientX,
      y: event.clientY,
      rect: bounds(item),
    });
  }, true);

  let frame = 0;
  function schedule() {
    if (frame || !groups.size) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      layout();
    });
  }

  window.addEventListener('scroll', sync, { passive: true });
  body().addEventListener('scroll', sync, { passive: true });
  window.addEventListener('resize', schedule);
  // Images, media and web fonts that finish loading can move the text.
  document.addEventListener('load', schedule, true);
  if (document.fonts && document.fonts.addEventListener) {
    document.fonts.addEventListener('loadingdone', schedule);
  }
  if (window.ResizeObserver) {
    const observer = new ResizeObserver(schedule);
    observer.observe(document.documentElement);
    observer.observe(body());
  }

  const json = (fn) => (...args) => JSON.stringify(fn(...args));
  window.readpubDecorations = Object.freeze({ apply: json(apply), clear: json(clear) });
})();
''';
