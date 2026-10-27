import { mathjax } from '@mathjax/src/mjs/mathjax.js';
import { liteAdaptor } from '@mathjax/src/mjs/adaptors/liteAdaptor.js';
import { RegisterHTMLHandler } from '@mathjax/src/mjs/handlers/html.js';
import { TeX } from '@mathjax/src/mjs/input/tex.js';
import { SVG } from '@mathjax/src/mjs/output/svg.js';
import { MathJaxNewcmFont } from '@mathjax/mathjax-newcm-font/mjs/svg.js';

// TeX extension packages
import '@mathjax/src/mjs/input/tex/ams/AmsConfiguration.js';
import '@mathjax/src/mjs/input/tex/boldsymbol/BoldsymbolConfiguration.js';

// Pre-bundled New Computer Modern math font dynamic chunks for offline rendering
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/double-struck.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/fraktur.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/calligraphic.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/script.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/math.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/arrows.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/marrows.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/symbols.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/symbols-b-i.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/variants.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/shapes.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/mshapes.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/accents.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/accents-b-i.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/sans-serif.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/sans-serif-b.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/sans-serif-i.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/sans-serif-bi.js';
import '@mathjax/mathjax-newcm-font/mjs/svg/dynamic/monospace.js';

// Disable runtime network / async dynamic font loading in offline JavaScriptCore
mathjax.asyncIsSynchronous = false;
mathjax.asyncLoad = function (file) {
  throw new Error('Offline font load unavailable: ' + file);
};

// Initialize DOM adapter and HTML handler
const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);

// Initialize TeX input with safety limits and selected packages (base + ams + boldsymbol)
const texInput = new TeX({
  packages: ['base', 'ams', 'boldsymbol'],
  maxBuffer: 16 * 1024,
  maxMacros: 1000,
  maxTemplateSubtitutions: 1000
});

// Explicit font instance with standalone path output and inline linebreaks disabled
// (Disable inline linebreaks so MathJax does not split inline formulas into multiple SVG chunks at operators)
const font = new MathJaxNewcmFont();
const svgOutput = new SVG({
  fontData: font,
  fontCache: 'none',
  linebreaks: { inline: false }
});

// Statically apply all pre-loaded dynamic math font chunks to the SVG font instance
const preloadedDynamics = [
  'double-struck',
  'fraktur',
  'calligraphic',
  'script',
  'math',
  'arrows',
  'marrows',
  'symbols',
  'symbols-b-i',
  'variants',
  'shapes',
  'mshapes',
  'accents',
  'accents-b-i',
  'sans-serif',
  'sans-serif-b',
  'sans-serif-i',
  'sans-serif-bi',
  'monospace'
];

for (const name of preloadedDynamics) {
  const dynamic = MathJaxNewcmFont.dynamicFiles[name];
  if (dynamic && typeof dynamic.setup === 'function') {
    dynamic.setup(font);
  }
}

// Create isolated MathJax document
const htmlDoc = mathjax.document('', {
  InputJax: texInput,
  OutputJax: svgOutput
});

/**
 * Recursively search the lite DOM tree for a MathJax error node (<g data-mml-node="merror">).
 */
function findError(node) {
  if (!node || !node.attributes) return null;
  const mml = node.attributes['data-mml-node'];
  if (mml === 'merror') {
    return node.attributes['data-mjx-error'] || adaptor.textContent(node) || 'LaTeX syntax error';
  }
  if (Array.isArray(node.children)) {
    for (let i = 0; i < node.children.length; i++) {
      const err = findError(node.children[i]);
      if (err) return err;
    }
  }
  return null;
}

/**
 * Public global entry point called from Swift bridge.
 * Returns JSON string { svg, widthEm, heightEm, descentEm, error }.
 *
 * @param {string} tex - LaTeX math expression
 * @param {boolean} display - true for block display ($$), false for inline ($)
 * @returns {string} JSON string representation of rendering result
 */
export function renderMath(tex, display) {
  if (typeof tex !== 'string') {
    return JSON.stringify({
      svg: null,
      widthEm: null,
      heightEm: null,
      descentEm: null,
      error: 'Invalid formula: tex must be a string'
    });
  }

  if (tex.length > 16384) {
    return JSON.stringify({
      svg: null,
      widthEm: null,
      heightEm: null,
      descentEm: null,
      error: 'Formula exceeds maximum length of 16384 characters'
    });
  }

  try {
    if (typeof texInput.reset === 'function') {
      texInput.reset();
    }
    if (typeof svgOutput.reset === 'function') {
      svgOutput.reset();
    }

    const isDisplay = Boolean(display);
    const container = htmlDoc.convert(tex, { display: isDisplay });

    // Check for MathJax syntax errors in the generated node tree
    const errorMsg = findError(container);
    if (errorMsg) {
      return JSON.stringify({
        svg: null,
        widthEm: null,
        heightEm: null,
        descentEm: null,
        error: errorMsg
      });
    }

    const svgs = adaptor.tags(container, 'svg');
    if (!svgs || svgs.length === 0) {
      return JSON.stringify({
        svg: null,
        widthEm: null,
        heightEm: null,
        descentEm: null,
        error: 'No SVG element generated'
      });
    }

    const svg = svgs[0];
    const viewBox = adaptor.getAttribute(svg, 'viewBox');
    if (!viewBox) {
      return JSON.stringify({
        svg: null,
        widthEm: null,
        heightEm: null,
        descentEm: null,
        error: 'Missing SVG viewBox attribute'
      });
    }

    const parts = viewBox.trim().split(/\s+/).map(Number);
    if (parts.length !== 4 || parts.some((n) => isNaN(n))) {
      return JSON.stringify({
        svg: null,
        widthEm: null,
        heightEm: null,
        descentEm: null,
        error: 'Invalid SVG viewBox format: ' + viewBox
      });
    }

    const [minX, minY, vbW, vbH] = parts;
    if (vbW <= 0 || vbH <= 0) {
      return JSON.stringify({
        svg: null,
        widthEm: null,
        heightEm: null,
        descentEm: null,
        error: 'Invalid formula dimensions in viewBox'
      });
    }

    // Normalize SVG width and height to numeric SVG units matching viewBox (not browser CSS ex/em)
    adaptor.setAttribute(svg, 'width', String(vbW));
    adaptor.setAttribute(svg, 'height', String(vbH));

    // Ensure explicit currentColor black on SVG root and main group for standalone native rendering
    adaptor.setAttribute(svg, 'color', 'black');
    adaptor.setAttribute(svg, 'style', 'color: black;');

    const g = adaptor.tags(svg, 'g')[0];
    if (g) {
      adaptor.setAttribute(g, 'color', 'black');
    }

    // Compute dimensions in em (1000 units = 1 em)
    const widthEm = Math.round((vbW / 1000) * 10000) / 10000;
    const heightEm = Math.round((vbH / 1000) * 10000) / 10000;
    const descentEm = Math.round(((vbH + minY) / 1000) * 10000) / 10000;

    // SwiftDraw consumes XML, not HTML. Escape '<' in MathJax's data-latex
    // attributes without changing the original TeX or the drawn geometry.
    const svgXml = adaptor.serializeXML(svg);

    return JSON.stringify({
      svg: svgXml,
      widthEm,
      heightEm,
      descentEm,
      error: null
    });
  } catch (err) {
    return JSON.stringify({
      svg: null,
      widthEm: null,
      heightEm: null,
      descentEm: null,
      error: err && err.message ? err.message : String(err)
    });
  }
}

// Expose renderMath on global object for JSContext invocation
globalThis.renderMath = renderMath;
