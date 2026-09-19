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
 *   so each attempt draws on a detached node and only replaces the live diagram
 *   when that attempt is still current. A timed-out `run()` cannot overwrite a
 *   later result, and a node that leaves the document is skipped.
 * - `run()` is serialized with a gate that this module releases when it
 *   abandons the wait. Mermaid itself may never settle; holding the next
 *   drawing on that promise would leave every later page unable to draw.
 *
 * Diagrams are re-drawn when the color scheme changes, because Mermaid bakes
 * its colors into the SVG rather than inheriting them from CSS.
 */

import type { Mermaid } from 'mermaid'

const DIAGRAM_SELECTOR = '.spotask-diagram > pre.mermaid'
const WRAPPER_SELECTOR = '.spotask-diagram'
const ERROR_TEXT_CLASS = 'spotask-diagram-error'
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
/** Monotonic attempt id per node; a timed-out run must not commit later. */
const attempts = new WeakMap<Element, number>()

function errorMessage(error: unknown): string {
  if (typeof error === 'string' && error.trim()) return error
  if (error instanceof Error && error.message?.trim()) return error.message
  if (typeof error === 'object' && error) {
    const record = error as { message?: unknown; str?: unknown }
    if (typeof record.message === 'string' && record.message.trim()) return record.message
    if (typeof record.str === 'string' && record.str.trim()) return record.str
  }
  return 'Mermaid could not draw this diagram'
}

export function installMermaidDiagrams(): void {
  if (import.meta.env.SSR) return

  let mermaid: Mermaid | null = null
  let loading: Promise<void> | null = null
  let scheduled = false
  /** Serializes render passes so we never inspect the DOM mid-commit. */
  let passes: Promise<void> = Promise.resolve()
  /**
   * Bumped when the color scheme changes. In-flight draws compare against the
   * epoch they started with and abandon the commit if it moved.
   */
  let epoch = 0
  /**
   * Turns of `mermaid.run`. Released when this module abandons a wait, not
   * when Mermaid's own promise settles, so a hung `run()` cannot pin the queue.
   */
  let mermaidGate: Promise<void> = Promise.resolve()

  const load = async (): Promise<Mermaid> => {
    loading ??= import('mermaid').then((module) => {
      mermaid = module.default
    })
    await loading
    return mermaid!
  }

  const theme = (): string => (document.documentElement.classList.contains('dark') ? 'dark' : 'default')

  const wrapperOf = (node: HTMLElement): HTMLElement | null => node.closest(WRAPPER_SELECTOR)

  const clearErrorText = (wrap: HTMLElement | null): void => {
    wrap?.querySelector(`.${ERROR_TEXT_CLASS}`)?.remove()
  }

  const showErrorText = (wrap: HTMLElement | null, message: string): void => {
    if (!wrap) return
    let errorText = wrap.querySelector<HTMLElement>(`.${ERROR_TEXT_CLASS}`)
    if (!errorText) {
      errorText = document.createElement('p')
      errorText.className = ERROR_TEXT_CLASS
      wrap.append(errorText)
    }
    errorText.textContent = message
  }

  const markSuccess = (node: HTMLElement, current: string): void => {
    node.removeAttribute(FAILED_ATTRIBUTE)
    node.removeAttribute(ERROR_ATTRIBUTE)
    node.setAttribute(DRAWN_ATTRIBUTE, current)
    const wrap = wrapperOf(node)
    wrap?.removeAttribute(ERROR_ATTRIBUTE)
    wrap?.setAttribute('role', 'img')
    clearErrorText(wrap)
  }

  const markFailure = (node: HTMLElement, current: string, message: string, source: string): void => {
    node.textContent = source
    node.removeAttribute('data-processed')
    node.removeAttribute(DRAWN_ATTRIBUTE)
    node.setAttribute(FAILED_ATTRIBUTE, current)
    node.setAttribute(ERROR_ATTRIBUTE, message)
    const wrap = wrapperOf(node)
    wrap?.setAttribute(ERROR_ATTRIBUTE, message)
    wrap?.removeAttribute('role')
    showErrorText(wrap, message)
  }

  const raceUntil = async (work: Promise<unknown>, isStale: () => boolean): Promise<void> => {
    const timeout = Promise.withResolvers<never>()
    const cancelled = Promise.withResolvers<never>()
    const timer = window.setTimeout(
      () => timeout.reject(new Error('Mermaid did not finish drawing')),
      RENDER_TIMEOUT_MS,
    )
    const poll = window.setInterval(() => {
      if (isStale()) cancelled.reject(new Error('Mermaid render was cancelled'))
    }, 50)
    void work.catch(() => undefined)
    void timeout.promise.catch(() => undefined)
    void cancelled.promise.catch(() => undefined)
    try {
      await Promise.race([work, timeout.promise, cancelled.promise])
    } finally {
      window.clearTimeout(timer)
      window.clearInterval(poll)
    }
  }

  /** Redraws one diagram, resolving to the failure message, if any. */
  const draw = async (instance: Mermaid, node: HTMLElement, current: string, started: number): Promise<string | null> => {
    const source = sources.get(node) ?? node.textContent ?? ''
    sources.set(node, source)
    const attempt = (attempts.get(node) ?? 0) + 1
    attempts.set(node, attempt)

    // Drop any previous drawing *and* its success marker before the attempt.
    // Leaving `data-mermaid-drawn` in place would make a later pass skip this
    // node after a failed theme change, so it could never recover.
    node.textContent = source
    node.removeAttribute('data-processed')
    node.removeAttribute(DRAWN_ATTRIBUTE)
    node.removeAttribute(ERROR_ATTRIBUTE)
    node.removeAttribute(FAILED_ATTRIBUTE)
    const wrap = wrapperOf(node)
    wrap?.removeAttribute(ERROR_ATTRIBUTE)
    clearErrorText(wrap)

    const width = Math.max(node.clientWidth, wrap?.clientWidth ?? 0, 640)
    const stage = document.createElement('pre')
    stage.className = 'mermaid'
    stage.textContent = source
    stage.setAttribute('aria-hidden', 'true')
    stage.style.cssText = `position:absolute;left:-99999px;top:0;width:${width}px;`
    document.body.append(stage)

    const isStale = (): boolean =>
      epoch !== started
      || !node.isConnected
      || attempts.get(node) !== attempt
      || theme() !== current

    const turn = Promise.withResolvers<void>()
    const previous = mermaidGate
    mermaidGate = turn.promise.then(
      () => undefined,
      () => undefined,
    )

    try {
      // Bound the wait for the previous turn. A hung Mermaid run must not pin
      // this drawing past the timeout; we never call `run()` if that wait dies.
      await raceUntil(previous, isStale)
      if (isStale()) return null
      instance.initialize({ startOnLoad: false, securityLevel: 'strict', theme: current })
      await raceUntil(instance.run({ nodes: [stage] }), isStale)
      if (isStale()) return null
      if (!stage.querySelector('svg g')) throw new Error('Mermaid produced no drawing')
      node.replaceChildren(...Array.from(stage.childNodes))
      markSuccess(node, current)
      return null
    } catch (error) {
      if (isStale()) return null
      const message = errorMessage(error)
      markFailure(node, current, message, source)
      return message
    } finally {
      turn.resolve()
      stage.remove()
    }
  }

  const render = async (): Promise<void> => {
    const started = epoch
    const current = theme()
    const nodes = Array.from(document.querySelectorAll<HTMLElement>(DIAGRAM_SELECTOR)).filter(
      (node) =>
        node.isConnected
        && node.getAttribute(DRAWN_ATTRIBUTE) !== current
        && node.getAttribute(FAILED_ATTRIBUTE) !== current,
    )
    if (nodes.length === 0) return

    let instance: Mermaid
    try {
      instance = await load()
    } catch (error) {
      // A chunk that never arrives must not leave a blank space behind: show
      // the fence and keep the reason. The next color scheme change retries.
      const message = errorMessage(error)
      loading = null
      for (const node of nodes) {
        if (!node.isConnected || epoch !== started) continue
        const source = sources.get(node) ?? node.textContent ?? ''
        sources.set(node, source)
        markFailure(node, current, message, source)
      }
      console.error('[spotask-docs] Mermaid could not be loaded', message)
      return
    }

    for (const node of nodes) {
      if (epoch !== started) return
      if (!node.isConnected) continue
      if (theme() !== current) return
      const message = await draw(instance, node, current, started)
      if (message) {
        console.error('[spotask-docs] Mermaid diagram failed to render', message, node)
      }
    }
  }

  const schedule = (): void => {
    if (scheduled) return
    scheduled = true
    // VitePress swaps page content on navigation, so wait for the DOM to settle
    // before deciding whether anything is pending. Mermaid's own writes also
    // trip the observer; those passes no-op once the drawing is committed.
    requestAnimationFrame(() => {
      scheduled = false
      passes = passes.then(render).catch((error) => {
        console.error('[spotask-docs] Mermaid diagram pass failed', error)
      })
    })
  }

  schedule()

  new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true })
  new MutationObserver(() => {
    epoch += 1
    schedule()
  }).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['class'],
  })
}
