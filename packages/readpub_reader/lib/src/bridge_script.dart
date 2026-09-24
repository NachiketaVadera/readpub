/// The name of the JavaScript channel the bridge posts events to.
const readerChannelName = 'ReadpubReader';

/// Page-turning, relocation and input events for a chapter prepared by an
/// `EpubRenderSession`, layered on `readerLocationScript`.
///
/// Defines `window.readpubReader` with `state()`, `nextPage()`,
/// `previousPage()`, `goToEnd()` and `restore(target)`, all returning JSON
/// strings, and posts `relocated`, `selection`, `tap`, `swipe` and `key`
/// events to the [readerChannelName] channel as JSON.
const readerBridgeScript = r'''
(() => {
  'use strict';
  if (window.readpubReader || !window.readpub) return;
  const rp = window.readpub;
  const post = (message) => {
    try {
      window.ReadpubReader.postMessage(JSON.stringify(message));
    } catch (_) {}
  };
  const body = () => document.body || document.documentElement;
  const scroller = () => document.scrollingElement || document.documentElement;
  const width = () => window.innerWidth;
  const rtl = () => getComputedStyle(body()).direction === 'rtl';
  const paged = () => getComputedStyle(body()).columnWidth !== 'auto';

  function pageCount() {
    return paged() ? Math.max(1, Math.round(body().scrollWidth / width())) : 1;
  }

  function page() {
    if (!paged()) return 0;
    return Math.min(pageCount() - 1, Math.round(Math.abs(body().scrollLeft) / width()));
  }

  function goToPage(index) {
    const target = Math.max(0, Math.min(pageCount() - 1, index));
    body().scrollLeft = (rtl() ? -1 : 1) * target * width();
  }

  function state() {
    return {
      cfi: rp.firstVisibleCfi(),
      progression: rp.progression(),
      page: page(),
      pageCount: pageCount(),
      paged: paged(),
      rtl: rtl(),
    };
  }

  let anchor = null;
  let relocation = null;
  function relocated() {
    clearTimeout(relocation);
    relocation = setTimeout(() => {
      const current = state();
      anchor = current.cfi;
      post(Object.assign({ type: 'relocated' }, current));
    }, 120);
  }

  function nextPage() {
    if (paged()) {
      if (page() + 1 >= pageCount()) return false;
      goToPage(page() + 1);
    } else {
      const element = scroller();
      const max = element.scrollHeight - element.clientHeight;
      if (element.scrollTop >= max - 1) return false;
      element.scrollTop = Math.min(max, element.scrollTop + element.clientHeight * 0.9);
    }
    relocated();
    return true;
  }

  function previousPage() {
    if (paged()) {
      if (page() === 0) return false;
      goToPage(page() - 1);
    } else {
      const element = scroller();
      if (element.scrollTop <= 1) return false;
      element.scrollTop = Math.max(0, element.scrollTop - element.clientHeight * 0.9);
    }
    relocated();
    return true;
  }

  function goToEnd() {
    if (paged()) goToPage(pageCount() - 1);
    else scroller().scrollTop = scroller().scrollHeight;
    relocated();
    return true;
  }

  // Positions the chapter at a CFI, a progression or its end.
  function restore(target) {
    let placed = false;
    if (target.end) placed = goToEnd();
    if (!placed && target.cfi) placed = rp.scrollToCfi(target.cfi);
    if (!placed && typeof target.progression === 'number') {
      rp.scrollToProgression(target.progression);
      placed = true;
    }
    const current = state();
    anchor = current.cfi;
    return current;
  }

  // Paged chapters turn pages under program control rather than scrolling
  // freely, so pages stay aligned to columns.
  if (paged()) body().style.overflowX = 'hidden';

  body().addEventListener('scroll', relocated, { passive: true });
  window.addEventListener('scroll', relocated, { passive: true });

  let resize = null;
  window.addEventListener('resize', () => {
    clearTimeout(resize);
    resize = setTimeout(() => {
      if (anchor) rp.scrollToCfi(anchor);
      relocated();
    }, 150);
  });

  let selection = null;
  document.addEventListener('selectionchange', () => {
    clearTimeout(selection);
    selection = setTimeout(() => {
      const current = window.getSelection();
      const text = current ? current.toString() : '';
      post({ type: 'selection', cfi: text ? rp.selectionCfi() : null, text });
    }, 200);
  });

  const interactive = 'a[href], button, input, select, textarea, summary, audio, video, label';
  document.addEventListener('click', (event) => {
    if (event.defaultPrevented) return;
    const target = event.target;
    if (target && target.closest && target.closest(interactive)) return;
    const current = window.getSelection();
    if (current && !current.isCollapsed) return;
    post({ type: 'tap', x: event.clientX / width(), y: event.clientY / window.innerHeight });
  });

  let touch = null;
  document.addEventListener('touchstart', (event) => {
    touch = event.touches.length === 1
      ? { x: event.touches[0].clientX, y: event.touches[0].clientY }
      : null;
  }, { passive: true });
  document.addEventListener('touchend', (event) => {
    if (!touch || !paged()) return;
    const end = event.changedTouches[0];
    const dx = end.clientX - touch.x;
    const dy = end.clientY - touch.y;
    touch = null;
    const current = window.getSelection();
    if (Math.abs(dx) > 40 && Math.abs(dx) > 1.5 * Math.abs(dy) &&
        (!current || current.isCollapsed)) {
      post({ type: 'swipe', direction: dx < 0 ? 'left' : 'right' });
    }
  }, { passive: true });

  document.addEventListener('keydown', (event) => {
    if (['ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown', ' '].includes(event.key)) {
      event.preventDefault();
      post({ type: 'key', key: event.key });
    }
  });

  const json = (fn) => (...args) => JSON.stringify(fn(...args));
  window.readpubReader = Object.freeze({
    state: json(state),
    nextPage: json(nextPage),
    previousPage: json(previousPage),
    goToEnd: json(goToEnd),
    restore: json(restore),
  });
})();
''';
