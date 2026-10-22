/* SpotAsk session document renderer.
   Pinned engines: markdown-it 14.1.0, markdown-it-texmath 1.0.0, KaTeX 0.16.25.
   Math is recognized before emphasis/escape. Code spans and fences win because
   their opener is consumed before the delimiter inside them is visited. */
(function (root) {
  "use strict";

  const MATH_OPTIONS = {
    throwOnError: false,
    trust: false,
    strict: "ignore",
    output: "htmlAndMathml",
  };

  let mathParser = null;
  let textParser = null;

  function engine(name) {
    if (root[name]) return root[name];
    throw new Error("Missing " + name);
  }

  function escapedDelimiter(state, silent) {
    const src = state.src;
    const pos = state.pos;
    if (src.charCodeAt(pos) !== 0x5c || src.charCodeAt(pos + 1) !== 0x5c) return false;
    const third = src[pos + 2];
    if (third !== "(" && third !== ")" && third !== "[" && third !== "]" && third !== "$") return false;
    if (!silent) state.pending += src.slice(pos, pos + 3);
    state.pos += 3;
    return true;
  }

  function parser(renderMath) {
    if (renderMath && mathParser) return mathParser;
    if (!renderMath && textParser) return textParser;
    const markdownit = engine("markdownit");
    const created = markdownit({
      html: false,
      linkify: false,
      typographer: false,
      breaks: false,
    });
    created.inline.ruler.before("escape", "escaped_math", escapedDelimiter);
    if (renderMath) {
      const texmathPlugin = engine("texmath");
      if (texmathPlugin.rules && texmathPlugin.rules.brackets && texmathPlugin.rules.brackets.inline) {
        const hasBracketDisplay = texmathPlugin.rules.brackets.inline.some(function (r) {
          return r.tag === "\\[";
        });
        if (!hasBracketDisplay) {
          texmathPlugin.rules.brackets.inline.push({
            name: "math_block_inline",
            rex: /\\\[([\s\S]+?)\\\]/gy,
            tmpl: "<section><eqn>$1</eqn></section>",
            tag: "\\[",
          });
        }
      }
      texmathPlugin(created, {
        engine: engine("katex"),
        delimiters: ["dollars", "brackets"],
        katexOptions: MATH_OPTIONS,
      });
    }
    created.renderer.rules.image = function (tokens, idx) {
      return '<span class="md-image">' + escapeText(tokens[idx].content || "") + "</span>";
    };
     created.renderer.rules.fence = function (tokens, idx) {
       const token = tokens[idx];
       const info = escapeText((token.info || "").trim().split(/\s+/)[0] || label("codeLanguage"));
       const code = escapeText(token.content || "");
       return (
         '<div class="code-block"><div class="code-bar"><span class="code-lang">' +
         info +
         '</span><button type="button" class="icon-button" data-action="copy-code"></button></div><pre><code>' +
         code +
         "</code></pre></div>"
       );
     };
    const defaultLink = created.renderer.rules.link_open || function (tokens, idx, options, env, self) {
      return self.renderToken(tokens, idx, options);
    };
    created.renderer.rules.link_open = function (tokens, idx, options, env, self) {
      const href = tokens[idx].attrGet("href") || "";
      if (!isOpenableLink(href)) tokens[idx].attrSet("href", "");
      tokens[idx].attrSet("rel", "noreferrer noopener");
      return defaultLink(tokens, idx, options, env, self);
    };
    if (renderMath) mathParser = created;
    else textParser = created;
    return created;
  }

  function isOpenableLink(href) {
    return /^https?:\/\//i.test(href) || /^mailto:/i.test(href);
  }

  function escapeText(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function sanitize(html) {
    return String(html)
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/\son[a-z]+\s*=\s*(['"]).*?\1/gi, "")
      .replace(/\s(href|src)\s*=\s*(['"])\s*javascript:[^'"]*\2/gi, " $1=$2");
  }

  function renderMarkdown(source, renderMath) {
    return sanitize(parser(!!renderMath).render(String(source || "")));
  }

  function openingFence(trimmed) {
    const match = /^(`{3,}|~{3,})/.exec(trimmed);
    if (!match) return null;
    const marker = match[1];
    const rest = trimmed.slice(marker.length);
    const closeAt = rest.lastIndexOf(marker);
    return { marker: marker, closes: closeAt > 0 && rest.slice(closeAt) === marker };
  }

  function isFenceClose(trimmed, marker) {
    return trimmed === marker || (trimmed.startsWith(marker) && trimmed.slice(marker.length).trim() === "");
  }

  function stableEnd(source) {
    const lines = String(source || "").split("\n");
    let offset = 0;
    let fence = null;
    let math = null;
    let lastClosed = 0;
    let inBlock = false;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const hasNewline = i < lines.length - 1;
      const end = offset + line.length + (hasNewline ? 1 : 0);
      const trimmed = line.trim();
      if (fence) {
        if (isFenceClose(trimmed, fence)) {
          fence = null;
          lastClosed = end;
        }
        offset = end;
        continue;
      }
      if (math) {
        if ((math === "$$" && trimmed === "$$") || (math === "\\[" && trimmed.indexOf("\\]") !== -1)) {
          math = null;
          lastClosed = end;
        }
        offset = end;
        continue;
      }
      const fenceOpen = openingFence(trimmed);
      if (fenceOpen) {
        if (fenceOpen.closes) lastClosed = end;
        else fence = fenceOpen.marker;
        inBlock = false;
        offset = end;
        continue;
      }
      if (trimmed === "$$") {
        math = "$$";
        inBlock = false;
        offset = end;
        continue;
      }
      if (trimmed.indexOf("\\[") === 0 && trimmed.indexOf("\\]") === -1) {
        math = "\\[";
        inBlock = false;
        offset = end;
        continue;
      }
      if (trimmed === "") {
        if (inBlock) lastClosed = end;
        inBlock = false;
      } else {
        inBlock = true;
      }
      offset = end;
    }
    return lastClosed;
  }

  function tailNeedsRaw(tail) {
    const text = String(tail || "");
    let fence = null;
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (fence) {
        if (isFenceClose(trimmed, fence)) fence = null;
        continue;
      }
      const fenceOpen = openingFence(trimmed);
      if (fenceOpen && !fenceOpen.closes) fence = fenceOpen.marker;
    }
    if (fence) return true;
    const blockDollars = text.match(/(^|\n)\s*\$\$/g);
    if (blockDollars && blockDollars.length % 2 === 1) return true;
    const blockOpen = text.match(/\\\[/g);
    const blockClose = text.match(/\\\]/g);
    if ((blockOpen ? blockOpen.length : 0) > (blockClose ? blockClose.length : 0)) return true;
    const inlineOpen = text.match(/\\\(/g);
    const inlineClose = text.match(/\\\)/g);
    if ((inlineOpen ? inlineOpen.length : 0) > (inlineClose ? inlineClose.length : 0)) return true;
    return false;
  }

  function streamingBody(source, renderMath, complete) {
    const text = String(source || "");
    if (complete) {
      return { mode: "complete", html: renderMarkdown(text, renderMath), stableKey: text, tailText: "" };
    }
    const end = stableEnd(text);
    const stable = text.slice(0, end);
    const tail = text.slice(end);
    const raw = tailNeedsRaw(tail);
    return {
      mode: "streaming",
      stableHTML: stable ? renderMarkdown(stable, renderMath) : "",
      tailHTML: !raw && tail ? renderMarkdown(tail, renderMath) : "",
      tailText: raw ? tail : "",
      stableKey: stable,
    };
  }

  function nodeToText(node) {
    if (!node) return "";
    if (node.nodeType === 3) return node.nodeValue || "";
    if (node.nodeType !== 1) {
      return Array.prototype.map.call(node.childNodes || [], nodeToText).join("");
    }
    if (node.classList && node.classList.contains("katex-html")) return "";
    if (node.classList && node.classList.contains("katex")) {
      const annotation = node.querySelector("annotation");
      if (annotation && annotation.textContent) return annotation.textContent;
    }
    if (node.tagName === "BR") return "\n";
    const inner = Array.prototype.map.call(node.childNodes, nodeToText).join("");
    if (node.tagName === "LI") return "- " + inner.replace(/\n+$/g, "") + "\n";
    if (/^(P|DIV|PRE|H1|H2|H3|H4|TR|SECTION|BLOCKQUOTE|ARTICLE)$/.test(node.tagName)) {
      return inner.replace(/\n+$/g, "") + "\n";
    }
    return inner;
  }

  const page = {
    generation: "",
    labels: {},
    hints: {},
    followsLatest: true,
    programmatic: false,
    userActive: false,
    idleTimer: 0,
  };

  function post(payload) {
    payload.generation = page.generation;
    const handler = root.webkit && root.webkit.messageHandlers && root.webkit.messageHandlers.sessionDocument;
    if (handler) handler.postMessage(payload);
  }

  function label(key) {
    return page.labels[key] || "";
  }

   function icon(name, className, weight, size, frame) {
     const box = frame || size || 10;
     const src =
       "spotask-doc://symbol/" +
       (weight || "regular") +
       "/" +
       (size || 0) +
       "/" +
       box +
       "/" +
       encodeURIComponent(name);
     return '<i class="' + (className || "icon") + " frame-" + box + '" style="-webkit-mask-image:url(\'' + src + '\');mask-image:url(\'' + src + '\')"></i>';
   }

  function keycaps(raw) {
    if (!raw) return "";
    const parts = String(raw).split("|");
    let html = '<span class="keycaps">';
    for (let i = 0; i < parts.length; i++) {
      if (!parts[i]) continue;
      html += '<kbd class="keycap">' + escapeText(parts[i]) + "</kbd>";
    }
    return html + "</span>";
  }

  function toolbarButton(action, symbol, labelText, options) {
    const hintKey = options && options.hintKey;
    const showHint = !!(options && options.showHint && hintKey && page.hints[hintKey]);
    const full = showHint && page.hints[hintKey + "Full"] ? page.hints[hintKey + "Full"] : "";
    const title = full ? labelText + " (" + full + ")" : labelText;
    const aria = (options && options.aria) || labelText;
    const weight = (options && options.weight) || "regular";
    const pointSize = (options && options.size) || 10;
    const extraClass = options && options.className ? " " + options.className : "";
    return (
      '<button type="button" class="toolbar-button' +
      extraClass +
      '" data-action="' +
      action +
      '" aria-label="' +
      escapeText(aria) +
      '" title="' +
      escapeText(title) +
      '">' +
       icon(symbol, "icon", weight, pointSize, (options && options.frame) || 24) +
      (showHint ? keycaps(page.hints[hintKey]) : "") +
      "</button>"
    );
  }

  function copyButton(message, role) {
    const copied = !!message.copied;
    const isUser = role === "user";
    const labelText = copied ? label("copied") : label(isUser ? "copyQuestion" : "copyCompleteAnswer");
    const aria = copied ? label(isUser ? "questionCopied" : "copyAnswer") : labelText;
    return toolbarButton("copy-message", copied ? "checkmark" : "doc.on.doc", labelText, {
      aria: aria,
      hintKey: "copy",
      showHint: !copied && role === "assistant" && !!message.isLatest,
      className: copied ? "copied" : "",
    });
  }

  function fillCopyButtons(rootNode) {
    const buttons = rootNode.querySelectorAll('[data-action="copy-code"]');
    for (let i = 0; i < buttons.length; i++) {
      buttons[i].setAttribute("aria-label", label("copy"));
       buttons[i].innerHTML = icon("doc.on.doc", "icon", "regular", 0, 20);
    }
  }

   function renderBody(message, renderMath) {
     if (message.role === "user") {
       return { mode: "text", text: message.collapsed ? message.preview || "" : message.content || "" };
     }
     if (message.collapsed) return { mode: "text", text: message.preview || "" };
     return streamingBody(message.content || "", renderMath, message.state !== "streaming");
   }
 
   function articleHTML(message) {
     const role = message.role === "user" ? "user" : "assistant";
     const parts = ['<article class="message ' + role + '" data-id="' + escapeText(message.id) + '">'];
     if (role === "assistant") {
       const dark = document.documentElement.dataset.theme === "dark" ? "?dark=true" : "";
       parts.push('<header class="identity">');
       if (message.iconSlug) {
         parts.push(
           '<span class="provider-mark brand"><img class="provider-icon" alt="" src="spotask-doc://icon/' +
             encodeURIComponent(message.iconSlug) +
             dark +
             '"></span>'
         );
       } else {
         parts.push('<span class="provider-mark fallback">' + icon("brain.head.profile", "icon", "semibold", 9.9, 18) + "</span>");
       }
       parts.push('<span class="identity-name">' + escapeText(message.title || "") + "</span>");
       if (message.canRetryWithModel) {
         parts.push(
           toolbarButton("show-model-menu", "arrow.triangle.2.circlepath", label("retryWithModel"), {
             className: "model-retry",
             weight: "semibold",
             size: 10,
             frame: 22,
           })
         );
       }
       parts.push("</header>");
     } else {
       parts.push('<header class="identity">');
       parts.push('<span class="user-avatar">' + icon("person.fill", "icon", "semibold", 9, 18) + "</span>");
       parts.push('<span class="identity-name">' + escapeText(message.title || "") + "</span>");
       if (message.presetText) {
         parts.push(
           '<span class="preset">' +
             icon(message.presetSymbol || "sparkles", "icon", "regular", 11, 14) +
             "<span>" +
             escapeText(message.presetText) +
             "</span></span>"
         );
       }
       parts.push("</header>");
     }
     if (message.reasoning) {
       const expanded = !!message.reasoningExpanded;
       parts.push('<section class="reasoning"><button type="button" class="reasoning-toggle" data-action="toggle-reasoning" aria-expanded="' + (expanded ? "true" : "false") + '" title="' + escapeText(expanded ? label("reasoningCollapse") : label("reasoningExpand")) + '">');
       parts.push(icon(expanded ? "chevron.down" : "chevron.right", "icon", "medium", 11, 14));
       parts.push("<span>" + escapeText(message.reasoningTitle || "") + "</span></button>");
       if (expanded) parts.push('<pre class="reasoning-body">' + escapeText(message.reasoning) + "</pre>");
       parts.push("</section>");
     }
     if (message.attachments && message.attachments.length) {
       parts.push('<div class="attachments">');
       for (let i = 0; i < message.attachments.length; i++) {
         const item = message.attachments[i];
         parts.push('<span class="attachment" title="' + escapeText(item.filename) + '">');
         if (item.isImage) {
           parts.push('<img alt="" src="spotask-doc://attachment/' + encodeURIComponent(item.id) + '">');
         } else if (item.symbol) {
           parts.push('<span class="attachment-symbol">' + icon(item.symbol, "icon", "regular", 9, 18) + "</span>");
         }
         parts.push("<span>" + escapeText(item.filename) + "</span></span>");
       }
       parts.push("</div>");
     }
     if (role === "assistant" && message.state === "streaming" && !message.content) {
       parts.push('<div class="generating"><span class="spinner"></span><span>' + escapeText(label("generating")) + "</span></div>");
     } else {
       parts.push('<div class="body"></div>');
     }
     if (message.canToggleExpand) {
       const expandLabel = message.collapsed
         ? label(role === "user" ? "showFullQuestion" : "expandAnswer")
         : label(role === "user" ? "collapseQuestion" : "collapseAnswer");
       parts.push(
         '<button type="button" class="expand-button" data-action="toggle-expand" aria-label="' +
           escapeText(expandLabel) +
           '" title="' +
           escapeText(expandLabel) +
           '">' +
           icon(message.collapsed ? "chevron.down" : "chevron.up", "icon", "medium", 11, 14) +
           "<span>" +
           escapeText(expandLabel) +
           "</span></button>"
       );
     }
     if (message.errorText) {
       const retryTitle = page.hints.regenerateFull ? label("retry") + " (" + page.hints.regenerateFull + ")" : label("retry");
       parts.push('<div class="error-row"><span class="error-text">' + escapeText(message.errorText) + "</span>");
       if (message.canRetry) {
         parts.push(
           '<button type="button" class="retry-text" data-action="retry" aria-label="' +
             escapeText(label("retryFailed")) +
             '" title="' +
             escapeText(retryTitle) +
             '"><span>' +
             escapeText(label("retry")) +
             "</span>" +
             keycaps(page.hints.regenerate) +
             "</button>"
         );
       }
       parts.push("</div>");
     }
     if (message.cancelledText) parts.push('<div class="cancelled-text">' + escapeText(message.cancelledText) + "</div>");
     parts.push('<div class="actions">');
     if (message.canCopy) parts.push(copyButton(message, role));
     if (message.canRetryUser) {
       parts.push(
         toolbarButton("retry-user", "arrow.clockwise", label("retry"), {
           hintKey: "regenerate",
           showHint: true,
           aria: label("retryFailed"),
         })
       );
     }
     if (message.canInsert) parts.push(toolbarButton("insert-selection", "arrow.down.doc", label("insertSelection")));
     if (message.canRegenerate) {
       parts.push(
         toolbarButton("regenerate", "arrow.clockwise", label("regenerate"), {
           hintKey: "regenerate",
           showHint: true,
         })
       );
     }
     if (role === "assistant" && message.metadata) {
       parts.push('<span class="metadata" title="' + escapeText(message.metadata) + '">' + escapeText(message.metadata) + "</span>");
     }
     parts.push("</div></article>");
     return parts.join("");
   }

  function updateBody(article, message, renderMath) {
    const body = article.querySelector(".body");
    if (!body) return;
    const rendered = renderBody(message, renderMath);
    if (rendered.mode === "text") {
      body.textContent = rendered.text;
      body.classList.add("plain");
      article.dataset.stable = "";
      return;
    }
    body.classList.remove("plain");
    if (rendered.mode === "complete") {
      body.innerHTML = rendered.html;
      fillCopyButtons(body);
      article.dataset.stable = rendered.stableKey;
      return;
    }
    let stable = body.querySelector(":scope > .stable");
    let tail = body.querySelector(":scope > .tail");
    if (!stable || !tail) {
      body.innerHTML = '<div class="stable"></div><div class="tail"></div>';
      stable = body.querySelector(".stable");
      tail = body.querySelector(".tail");
    }
    if (article.dataset.stable !== rendered.stableKey) {
      stable.innerHTML = rendered.stableHTML;
      fillCopyButtons(stable);
      article.dataset.stable = rendered.stableKey;
    }
    if (rendered.tailText) {
      tail.textContent = rendered.tailText;
      tail.classList.add("raw");
    } else {
      tail.innerHTML = rendered.tailHTML;
      tail.classList.remove("raw");
      fillCopyButtons(tail);
    }
  }

  function applyMessage(existing, message, renderMath) {
    const host = document.getElementById("messages");
    const wrapper = document.createElement("div");
    wrapper.innerHTML = articleHTML(message);
    const article = wrapper.firstChild;
     if (existing) {
       article.dataset.stable = existing.dataset.stable || "";
       const previousBody = existing.querySelector(".body");
       const nextBody = article.querySelector(".body");
       if (previousBody && nextBody && message.state === "streaming" && !message.collapsed) {
         nextBody.innerHTML = previousBody.innerHTML;
       }
       existing.replaceWith(article);
     } else {
       host.appendChild(article);
     }
     updateBody(article, message, renderMath);
   }

  function scrollToBottom() {
    const scroller = document.getElementById("scroller");
    if (!scroller) return;
    page.programmatic = true;
    scroller.scrollTop = scroller.scrollHeight;
    page.programmatic = false;
  }

  function apply(snapshot) {
    if (!snapshot || !document.getElementById("messages")) return false;
    page.generation = String(snapshot.generation || "");
    page.labels = snapshot.labels || {};
    page.hints = snapshot.hints || {};
    page.followsLatest = !!snapshot.followsLatest;
    document.documentElement.dataset.theme = snapshot.theme === "dark" ? "dark" : "light";
    document.documentElement.dataset.style = snapshot.messageStyle === "im" ? "im" : "standard";
    document.documentElement.dataset.reduceMotion = snapshot.reduceMotion ? "true" : "false";
    document.documentElement.style.setProperty("--text-size", (snapshot.fontSizePx || 14.5) + "px");
    const host = document.getElementById("messages");
    const previous = new Map();
    host.querySelectorAll("article").forEach(function (article) {
      previous.set(article.dataset.id, article);
    });
    const seen = new Set();
    const messages = snapshot.messages || [];
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i];
      seen.add(message.id);
      applyMessage(previous.get(message.id) || null, message, !!snapshot.renderMath);
    }
    previous.forEach(function (article, id) {
      if (!seen.has(id)) article.remove();
    });
    if (page.followsLatest) scrollToBottom();
    return true;
  }

  function patch(body) {
    if (!body || String(body.generation || "") !== page.generation) return false;
    const id = String(body.id || "").replace(/"/g, "");
    const article = document.querySelector('article[data-id="' + id + '"]');
    if (!article) return false;
    updateBody(article, {
      id: body.id,
      role: "assistant",
      content: body.content || "",
      state: body.state || "streaming",
      collapsed: !!body.collapsed,
      preview: body.preview || "",
    }, body.renderMath !== false);
    if (body.reasoningTitle) {
      const title = article.querySelector(".reasoning-toggle span");
      if (title) title.textContent = body.reasoningTitle;
    }
    if (page.followsLatest) scrollToBottom();
    return true;
  }

  function nearBottom(scroller) {
    return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight <= 12;
  }

  function postScroll(phase) {
    const scroller = document.getElementById("scroller");
    if (!scroller) return;
    post({ type: "scroll", phase: phase, nearBottom: nearBottom(scroller) });
  }

  function installPage() {
    const scroller = document.getElementById("scroller");
    const messages = document.getElementById("messages");
    if (!scroller || !messages) return;
    messages.addEventListener("click", function (event) {
      const control = event.target.closest("[data-action]");
      if (control) {
        event.preventDefault();
        const article = control.closest("article");
        const messageID = article ? article.dataset.id : "";
        if (control.dataset.action === "copy-code") {
          const code = control.closest(".code-block");
          const text = code ? code.querySelector("code").textContent : "";
          post({ type: "copy-code", messageID: messageID, code: text });
          return;
        }
         if (control.dataset.action === "show-model-menu") {
          const rect = control.getBoundingClientRect();
          post({
            type: control.dataset.action,
            messageID: messageID,
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
          });
          return;
        }
        post({ type: control.dataset.action, messageID: messageID });
        return;
      }
      const link = event.target.closest("a");
      if (link) {
        event.preventDefault();
        post({ type: "open-link", url: link.getAttribute("href") || "" });
      }
    });
    scroller.addEventListener("wheel", function () {
      page.userActive = true;
      postScroll("userInteracting");
      window.clearTimeout(page.idleTimer);
      page.idleTimer = window.setTimeout(function () {
        page.userActive = false;
        postScroll("idle");
      }, 140);
    }, { passive: true });
    scroller.addEventListener("pointerdown", function () {
      page.userActive = true;
      postScroll("userInteracting");
    });
    scroller.addEventListener("scroll", function () {
      if (page.programmatic) return;
      postScroll(page.userActive ? "userInteracting" : "idle");
    });
    document.addEventListener("copy", function (event) {
      const selection = window.getSelection();
      if (!selection || selection.isCollapsed || !selection.rangeCount) return;
      if (!scroller.contains(selection.anchorNode)) return;
      const text = nodeToText(selection.getRangeAt(0).cloneContents()).replace(/\n{3,}/g, "\n\n").trim();
      if (!text) return;
      event.preventDefault();
      event.clipboardData.setData("text/plain", text);
    });
    root.SessionDocumentScrollToBottom = scrollToBottom;
  }

  const api = {
    renderMarkdown: renderMarkdown,
    stableEnd: stableEnd,
    tailNeedsRaw: tailNeedsRaw,
    streamingBody: streamingBody,
    nodeToText: nodeToText,
    isOpenableLink: isOpenableLink,
    apply: apply,
    patch: patch,
    install: installPage,
  };
  root.SessionDocument = api;
  if (typeof module === "object" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
