import type MarkdownIt from 'markdown-it'
import type Token from 'markdown-it/lib/token.mjs'

/**
 * Turns ` ```mermaid ` fences into diagrams rendered in the browser.
 *
 * VitePress 1.6.4 has no diagram support, so the fence is emitted as a plain
 * element the client renderer picks up (`theme/mermaid.ts`); the `mermaid`
 * package is loaded there on demand, never during the build.
 *
 * Text after the language is the diagram's accessible name, which is what a
 * screen reader announces in place of the drawing:
 *
 *     ```mermaid Connection setup flow
 *     flowchart TD
 *       A --> B
 *     ```
 *
 * Keep the code inside the fence pure Mermaid: the label belongs in the info
 * string, and explanation belongs in the surrounding prose.
 *
 * Labels are drawn as SVG text, so HTML inside a fence (`<br/>`, `<b>`) would
 * show up literally. Node colors come from three shared classes — `entry`,
 * `decision`, `outcome` — whose palettes live in `theme/styles/diagrams.css`;
 * the fence only marks which node is which:
 *
 *     class A entry
 *     class B,C outcome
 */
export function mermaidFence(markdown: MarkdownIt): void {
  const defaultFence = markdown.renderer.rules.fence

  markdown.renderer.rules.fence = (tokens: Token[], index, options, environment, self) => {
    const token = tokens[index]
    const [language, ...labelParts] = token.info.trim().split(/\s+/)

    if (language !== 'mermaid') {
      return defaultFence
        ? defaultFence(tokens, index, options, environment, self)
        : self.renderToken(tokens, index, options)
    }

    const label = labelParts.join(' ') || 'Diagram'
    return `<div class="spotask-diagram" role="img" aria-label="${markdown.utils.escapeHtml(label)}">`
      + `<pre class="mermaid">${markdown.utils.escapeHtml(token.content.trim())}</pre>`
      + `</div>\n`
  }
}
