/// A browser-side reference implementation of the renderer location contract.
///
/// A host may inject this script into a chapter loaded from an
/// `EpubRenderSession`, for example with a WebView's evaluate-JavaScript API.
/// The session never serves or runs it, and its Content Security Policy
/// blocks publication scripts. The script defines `window.readpub` with:
///
/// - `cfiFromPoint(node, offset)` and `cfiFromRange(range)`, which return
///   content-document CFI expressions without the `epubcfi()` wrapper;
/// - `selectionCfi()`, for the current selection, or null;
/// - `rangeFromCfi(expression)`, which returns a DOM `Range` or null;
/// - `firstVisibleCfi()`, for the first visible character;
/// - `scrollToCfi(expression)`, `progression()` and
///   `scrollToProgression(value)`, for scroll and paged reader flows.
///
/// Expressions use the same element and character-data counting, ID
/// assertions and canonical form as `DocumentText.cfiAt`, so they can be
/// passed to `ReadingServices.locatorForCfi` with the chapter link. The
/// script resolves ID assertions but leaves text assertions and other
/// corrections to the Dart services; pass it the CFIs they return.
const readerLocationScript = r'''
(() => {
  'use strict';
  if (window.readpub) return;
  const ELEMENT = 1;
  const isText = (node) => node.nodeType === 3 || node.nodeType === 4;
  const root = () => document.documentElement;
  const escape = (value) => value.replace(/[\^\[\](),;=]/g, '^$&');

  function elementIndex(node) {
    let index = 0;
    for (let sibling = node.parentNode.firstChild; sibling; sibling = sibling.nextSibling) {
      if (sibling.nodeType === ELEMENT) index += 2;
      if (sibling === node) break;
    }
    return index;
  }

  function steps(element) {
    const result = [];
    for (let node = element; node && node !== root(); node = node.parentNode) {
      result.unshift('/' + elementIndex(node) + (node.id ? '[' + escape(node.id) + ']' : ''));
    }
    return result;
  }

  // A DOM boundary point as CFI steps, a chunk step and a character offset.
  function point(node, offset) {
    let parent = node;
    let limit = offset;
    if (isText(node)) {
      parent = node.parentNode;
      limit = Array.prototype.indexOf.call(parent.childNodes, node);
    } else if (node.nodeType !== ELEMENT) {
      parent = node.parentNode;
      limit = Array.prototype.indexOf.call(parent.childNodes, node);
      offset = 0;
    }
    let chunk = 1;
    let length = 0;
    const children = parent.childNodes;
    for (let i = 0; i < limit && i < children.length; i++) {
      if (children[i].nodeType === ELEMENT) {
        chunk += 2;
        length = 0;
      } else if (isText(children[i])) {
        length += children[i].length;
      }
    }
    if (isText(node)) length += offset;
    return { steps: steps(parent).concat('/' + chunk), offset: length };
  }

  function cfiFromPoint(node, offset) {
    const value = point(node, offset);
    return value.steps.join('') + ':' + value.offset;
  }

  function cfiFromRange(range) {
    if (range.collapsed) return cfiFromPoint(range.startContainer, range.startOffset);
    const start = point(range.startContainer, range.startOffset);
    const end = point(range.endContainer, range.endOffset);
    let common = 0;
    while (common < start.steps.length && common < end.steps.length &&
        start.steps[common] === end.steps[common]) {
      common++;
    }
    if (common === 0) return null;
    return start.steps.slice(0, common).join('') +
      ',' + start.steps.slice(common).join('') + ':' + start.offset +
      ',' + end.steps.slice(common).join('') + ':' + end.offset;
  }

  function selectionCfi() {
    const selection = window.getSelection();
    return selection && selection.rangeCount ? cfiFromRange(selection.getRangeAt(0)) : null;
  }

  // Splits an expression at commas outside assertions.
  function split(expression) {
    const parts = [''];
    let depth = 0;
    for (let i = 0; i < expression.length; i++) {
      const c = expression[i];
      if (c === '^') {
        parts[parts.length - 1] += c + (expression[i + 1] || '');
        i++;
        continue;
      }
      if (c === '[') depth++;
      if (c === ']') depth--;
      if (c === ',' && depth === 0) parts.push('');
      else parts[parts.length - 1] += c;
    }
    return parts;
  }

  function parsePath(text) {
    const result = { steps: [], offset: null };
    let i = 0;
    while (i < text.length) {
      const c = text[i];
      if (c !== '/' && c !== ':') return c === '~' || c === '@' ? result : null;
      let j = i + 1;
      while (j < text.length && text[j] >= '0' && text[j] <= '9') j++;
      if (j === i + 1) return null;
      const value = Number(text.slice(i + 1, j));
      let id = null;
      if (text[j] === '[') {
        let k = j + 1;
        let raw = '';
        while (k < text.length && text[k] !== ']') {
          if (text[k] === '^') {
            raw += text[k + 1] || '';
            k += 2;
          } else if (text[k] === ',' || text[k] === ';') {
            break;
          } else {
            raw += text[k++];
          }
        }
        while (k < text.length && text[k] !== ']') k += text[k] === '^' ? 2 : 1;
        id = raw || null;
        j = k + 1;
      }
      if (c === ':') {
        result.offset = value;
        return result;
      }
      result.steps.push({ index: value, id });
      i = j;
    }
    return result;
  }

  function chunkPosition(parent, ordinal, offset) {
    const texts = [];
    let chunk = 0;
    let boundary = 0;
    const children = parent.childNodes;
    for (let i = 0; i < children.length; i++) {
      if (children[i].nodeType === ELEMENT) {
        if (chunk === ordinal) break;
        chunk++;
        boundary = i + 1;
      } else if (chunk === ordinal && isText(children[i])) {
        texts.push(children[i]);
      }
    }
    if (chunk < ordinal) return null;
    let remaining = offset;
    for (const text of texts) {
      if (remaining <= text.length) return { node: text, offset: remaining };
      remaining -= text.length;
    }
    if (texts.length) {
      const last = texts[texts.length - 1];
      return { node: last, offset: last.length };
    }
    return { node: parent, offset: boundary };
  }

  function resolve(path) {
    if (!path) return null;
    let node = root();
    for (let i = 0; i < path.steps.length; i++) {
      const { index, id } = path.steps[i];
      if (index % 2 === 1) return chunkPosition(node, (index - 1) / 2, path.offset || 0);
      const elements = node.children;
      if (index === 0) return { node, offset: 0 };
      if (index === 2 * (elements.length + 1)) return { node, offset: node.childNodes.length };
      let child = elements[index / 2 - 1];
      if (id && (!child || child.id !== id)) child = document.getElementById(id);
      if (!child) return null;
      node = child;
    }
    return { node, offset: 0 };
  }

  function rangeFromCfi(expression) {
    let text = String(expression);
    if (text.startsWith('epubcfi(') && text.endsWith(')')) text = text.slice(8, -1);
    if (text.includes('!')) return null;
    const parts = split(text);
    if (parts.length !== 1 && parts.length !== 3) return null;
    const start = resolve(parsePath(parts.length === 3 ? parts[0] + parts[1] : parts[0]));
    const end = parts.length === 3 ? resolve(parsePath(parts[0] + parts[2])) : start;
    if (!start || !end) return null;
    const range = document.createRange();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    return range;
  }

  const visible = (rect) => rect.width + rect.height > 0 && rect.bottom > 0 &&
    rect.right > 0 && rect.top < window.innerHeight && rect.left < window.innerWidth;

  function firstVisibleCfi() {
    const walker = document.createTreeWalker(document.body || root(), 4 | 8);
    const range = document.createRange();
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!/\S/.test(node.data)) continue;
      range.selectNodeContents(node);
      if (!Array.from(range.getClientRects()).some(visible)) continue;
      for (let i = 0; i < node.length; i++) {
        if (/\s/.test(node.data[i])) continue;
        range.setStart(node, i);
        range.setEnd(node, i + 1);
        if (Array.from(range.getClientRects()).some(visible)) return cfiFromPoint(node, i);
      }
    }
    return null;
  }

  function paged() {
    const body = document.body;
    if (!body) return false;
    const style = getComputedStyle(body);
    return style.columnWidth !== 'auto' && body.scrollWidth > body.clientWidth;
  }

  function scrollToCfi(expression) {
    const range = rangeFromCfi(expression);
    if (!range) return false;
    if (range.collapsed && isText(range.startContainer) &&
        range.startOffset < range.startContainer.length) {
      range.setEnd(range.startContainer, range.startOffset + 1);
    }
    let rect = range.getClientRects()[0];
    if (!rect) {
      const container = range.startContainer.nodeType === ELEMENT
        ? range.startContainer : range.startContainer.parentElement;
      rect = container.getBoundingClientRect();
    }
    if (paged()) {
      const body = document.body;
      const x = body.scrollLeft + rect.left;
      body.scrollLeft = Math.floor(x / window.innerWidth) * window.innerWidth;
    } else {
      window.scrollBy(0, rect.top);
    }
    return true;
  }

  function progression() {
    if (paged()) {
      const body = document.body;
      const max = body.scrollWidth - body.clientWidth;
      return max > 0 ? body.scrollLeft / max : 0;
    }
    const element = document.scrollingElement || root();
    const max = element.scrollHeight - element.clientHeight;
    return max > 0 ? element.scrollTop / max : 0;
  }

  function scrollToProgression(value) {
    const clamped = Math.min(1, Math.max(0, Number(value) || 0));
    if (paged()) {
      const body = document.body;
      const target = clamped * (body.scrollWidth - body.clientWidth);
      body.scrollLeft = Math.round(target / window.innerWidth) * window.innerWidth;
    } else {
      const element = document.scrollingElement || root();
      element.scrollTop = clamped * (element.scrollHeight - element.clientHeight);
    }
  }

  window.readpub = Object.freeze({
    version: 1,
    cfiFromPoint,
    cfiFromRange,
    selectionCfi,
    rangeFromCfi,
    firstVisibleCfi,
    scrollToCfi,
    progression,
    scrollToProgression,
  });
})();
''';
