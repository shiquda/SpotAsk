/**
 * Renders ` ```mermaid ` fences in the browser.
 *
 * The diagrams are emitted as `pre.mermaid` by `../mermaidFence.ts` during the
 * build, and this module draws them once the page is in the DOM. The `mermaid`
 * package is imported on demand, so pages without a diagram never download it.
 *
 * Two Mermaid behaviors shape this module:
 * - It stamps `data-processed` on a diagram *before* drawing it and fetches
 *   diagram code lazily, so that attribute cannot be used to tell a finished
 *   drawing from a blank one. This module records its own result instead.
 * - It writes the drawing asynchronously, and the page mutates while it does,
 *   so render passes are serialized and cannot restore a diagram mid-draw.
 *
 * Diagrams are re-drawn when the color scheme changes, because Mermaid bakes
 * its colors into the SVG rather than inheriting them from CSS.
 */

import type { Mermaid } from 'mermaid'

const DIAGRAM_SELECTOR = 'pre.mermaid'
/** Theme a diagram was last *drawn* with; Mermaid's own marker means nothing. */
const DRAWN_ATTRIBUTE = 'data-mermaid-drawn'
/** Theme whose attempt failed, so a broken diagram is not retried forever. */
const FAILED_ATTRIBUTE = 'data-mermaid-failed'
/** Set on the failed element to reveal the fence and its reason. */
const ERROR_ATTRIBUTE = 'data-mermaid-error'
/** A cold visit downloads Mermaid and the diagram code; give that time. */
const RENDER_TIMEOUT_MS = 15000

/** Mermaid's source for each diagram, so a re-render can start from scratch. */
const sources = new WeakMap<Element, string>()

export function installMermaidDiagrams(): void {
  if (import.meta.env.SSR) return

  let mermaid: Mermaid | null = null
  let loading: Promise<void> | null = null
  let scheduled = false
  /** Serializes render passes; Mermaid's own DOM writes trigger the observer. */
  let passes: Promise<void> = Promise.resolve()

  const load = async (): Promise<Mermaid> => {
    loading ??= import('mermaid').then((module) => {
      mermaid = module.default
    })
    await loading
    return mermaid!
  }

  const theme = (): string => (document.documentElement.classList.contains('dark') ? 'dark' : 'default')

  /** Redraws one diagram, resolving to the failure message, if any. */
  const draw = async (instance: Mermaid, node: HTMLElement, current: string): Promise<string | null> => {
    // Mermaid replaces its source with the drawing, so keep the source the
    // first time a diagram is seen and restore it before every render.
    const source = sources.get(node) ?? node.textContent ?? ''
    sources.set(node, source)
    node.textContent = source
    node.removeAttribute('data-processed')
    node.removeAttribute(ERROR_ATTRIBUTE)
    node.setAttribute(FAILED_ATTRIBUTE, current)

    let timer: number | undefined
    const timeout = new Promise<never>((_, reject) => {
      timer = window.setTimeout(() => reject(new Error('Mermaid did not finish drawing')), RENDER_TIMEOUT_MS)
    })

    try {
      instance.initialize({ startOnLoad: false, securityLevel: 'strict', theme: current })
      await Promise.race([instance.run({ nodes: [node] }), timeout])
      // Mermaid skips an element it already marked, and leaves an empty <svg>
      // behind when it fails, so trust a drawing only when it is really there.
      if (!node.querySelector('svg g')) throw new Error('Mermaid produced no drawing')
      node.removeAttribute(FAILED_ATTRIBUTE)
      node.setAttribute(DRAWN_ATTRIBUTE, current)
      return null
    } catch (error) {
      return error instanceof Error ? error.message : String(error)
    } finally {
      clearTimeout(timer)
    }
  }

  const render = async (): Promise<void> => {
    const nodes = Array.from(document.querySelectorAll<HTMLElement>(DIAGRAM_SELECTOR))
    const pending = nodes.filter(
      (node) =>
        node.getAttribute(DRAWN_ATTRIBUTE) !== theme() && node.getAttribute(FAILED_ATTRIBUTE) !== theme()
    )
    if (pending.length === 0) return

    let instance: Mermaid
    try {
      instance = await load()
    } catch (error) {
      // A chunk that never arrives must not leave a blank space behind: show
      // the fence and keep the reason. The next color scheme change retries.
      const message = error instanceof Error ? error.message : String(error)
      loading = null
      for (const node of pending) {
        node.setAttribute(FAILED_ATTRIBUTE, theme())
        node.setAttribute(ERROR_ATTRIBUTE, message)
      }
      console.error('[spotask-docs] Mermaid could not be loaded', message)
      return
    }

    for (const node of pending) {
      const message = await draw(instance, node, theme())
      if (message) {
        // Reveal the fence rather than leaving a blank space, and keep the
        // reason where a reader can see it: an undrawable diagram is a bug.
        node.setAttribute(ERROR_ATTRIBUTE, message)
        console.error('[spotask-docs] Mermaid diagram failed to render', message, node)
      }
    }
  }

  const schedule = (): void => {
    if (scheduled) return
    scheduled = true
    // VitePress swaps page content on navigation, so wait for the DOM to settle
    // and for Mermaid's own writes before deciding whether anything is pending.
    requestAnimationFrame(() => {
      scheduled = false
      passes = passes.then(render).catch((error) => {
        console.error('[spotask-docs] Mermaid diagram pass failed', error)
      })
    })
  }

  schedule()

  new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true })
  new MutationObserver(schedule).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['class']
  })
}
