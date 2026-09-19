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
 *   when that attempt is still current.
 * - `run()` feeds a module-level execution queue inside Mermaid. An entry that
 *   never settles keeps every later `run()` waiting behind it, so this module
 *   never starts a second `run()` until the first settles, and a timed-out
 *   instance is abandoned. A hung run still occupies that gate, but the page
 *   render pass does not wait on it: a new page shows its source instead of
 *   staying hidden until the timeout.
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
/** Reveals source while Mermaid is busy with another page's run. */
const WAITING_ATTRIBUTE = 'data-mermaid-waiting'
/** A cold visit downloads Mermaid and the diagram code; give that time. */
const RENDER_TIMEOUT_MS = 15000
const MERMAID_TIMEOUT = 'Mermaid did not finish drawing'
const MERMAID_LOAD_TIMEOUT = 'Mermaid did not load'
const MERMAID_POISONED = 'Mermaid stopped responding'

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
  let watchingLoad = false
  let scheduled = false
  /** Serializes render passes so we never inspect the DOM mid-commit. */
  let passes: Promise<void> = Promise.resolve()
  /**
   * Bumped when the color scheme changes. In-flight draws compare against the
   * epoch they started with and abandon the commit if it moved.
   */
  let epoch = 0
  /**
   * Turns of `mermaid.run`. Released when the current `run()` settles or times
   * out, not when the page that started it goes away.
   */
  let mermaidGate: Promise<void> = Promise.resolve()
  /** True while a `run()` is in flight, including after its page has gone. */
  let mermaidBusy = false
  /** Once a `run()` times out, this instance's execution queue is unusable. */
  let mermaidPoisoned: string | null = null

  const withTimeout = async (work: Promise<unknown>, message: string): Promise<void> => {
    const timeout = Promise.withResolvers<never>()
    const timer = window.setTimeout(() => timeout.reject(new Error(message)), RENDER_TIMEOUT_MS)
    void Promise.resolve(work).catch(() => undefined)
    void timeout.promise.catch(() => undefined)
    try {
      await Promise.race([work, timeout.promise])
    } finally {
      window.clearTimeout(timer)
    }
  }

  const kickLoad = (): void => {
    if (mermaid || mermaidPoisoned) return
    loading ??= import('mermaid').then((module) => {
      mermaid = module.default
    })
    if (watchingLoad) return
    watchingLoad = true
    void withTimeout(loading, MERMAID_LOAD_TIMEOUT).then(
      () => {
        watchingLoad = false
        schedule()
      },
      (error) => {
        watchingLoad = false
        mermaidPoisoned = errorMessage(error)
        schedule()
      },
    )
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
    node.removeAttribute(WAITING_ATTRIBUTE)
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
    node.removeAttribute(WAITING_ATTRIBUTE)
    node.setAttribute(FAILED_ATTRIBUTE, current)
    node.setAttribute(ERROR_ATTRIBUTE, message)
    const wrap = wrapperOf(node)
    wrap?.setAttribute(ERROR_ATTRIBUTE, message)
    wrap?.removeAttribute('role')
    showErrorText(wrap, message)
  }

  const markWaiting = (node: HTMLElement): void => {
    const source = sources.get(node) ?? node.textContent ?? ''
    sources.set(node, source)
    if (node.getAttribute(DRAWN_ATTRIBUTE) || node.getAttribute(ERROR_ATTRIBUTE)) return
    node.setAttribute(WAITING_ATTRIBUTE, '')
  }

  const waitForTurn = async (work: Promise<unknown>, isStale: () => boolean): Promise<void> => {
    const cancelled = Promise.withResolvers<never>()
    const poll = window.setInterval(() => {
      if (isStale()) cancelled.reject(new Error('Mermaid render was cancelled'))
    }, 50)
    void work.catch(() => undefined)
    void cancelled.promise.catch(() => undefined)
    try {
      await Promise.race([work, cancelled.promise])
    } finally {
      window.clearInterval(poll)
    }
  }

  const untilStale = (isStale: () => boolean): { promise: Promise<void>; stop: () => void } => {
    const done = Promise.withResolvers<void>()
    const poll = window.setInterval(() => {
      if (isStale()) done.resolve()
    }, 50)
    const stop = (): void => window.clearInterval(poll)
    void done.promise.then(stop, stop)
    return { promise: done.promise, stop }
  }

  /** Redraws one diagram, resolving to the failure message, if any. */
  const draw = async (instance: Mermaid, node: HTMLElement, current: string, started: number): Promise<string | null> => {
    const source = sources.get(node) ?? node.textContent ?? ''
    sources.set(node, source)
    if (mermaidPoisoned) {
      markFailure(node, current, mermaidPoisoned, source)
      return mermaidPoisoned
    }
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
    node.removeAttribute(WAITING_ATTRIBUTE)
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
    let startedRun = false

    try {
      await waitForTurn(previous, isStale)
      if (isStale()) return null
      if (mermaidPoisoned) {
        markFailure(node, current, mermaidPoisoned, source)
        return mermaidPoisoned
      }
      instance.initialize({ startOnLoad: false, securityLevel: 'strict', theme: current })
      startedRun = true
      mermaidBusy = true
      const finished = withTimeout(instance.run({ nodes: [stage] }), MERMAID_TIMEOUT)
      const settleGate = (): void => {
        mermaidBusy = false
        turn.resolve()
        schedule()
      }
      void finished.then(settleGate, settleGate)
      const stale = untilStale(isStale)
      try {
        await Promise.race([finished, stale.promise])
      } finally {
        stale.stop()
      }
      if (isStale()) return null
      mermaidBusy = false
      if (!stage.querySelector('svg g')) throw new Error('Mermaid produced no drawing')
      node.replaceChildren(...Array.from(stage.childNodes))
      markSuccess(node, current)
      return null
    } catch (error) {
      const message = errorMessage(error)
      if (message === MERMAID_TIMEOUT) mermaidPoisoned = MERMAID_POISONED
      const shown = mermaidPoisoned ?? message
      if (!node.isConnected) return shown
      if (isStale() && !mermaidPoisoned) return null
      markFailure(node, current, shown, source)
      return shown
    } finally {
      if (!startedRun) turn.resolve()
      stage.remove()
    }
  }

  const failNodes = (nodes: HTMLElement[], current: string, message: string): void => {
    for (const node of nodes) {
      if (!node.isConnected) continue
      const source = sources.get(node) ?? node.textContent ?? ''
      sources.set(node, source)
      markFailure(node, current, message, source)
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

    if (mermaidPoisoned) {
      failNodes(nodes, current, mermaidPoisoned)
      return
    }

    // A previous page's run still owns Mermaid. Do not call `run()` again, and
    // do not wait here: reveal source so the new page is not hidden for 15s.
    if (mermaidBusy) {
      for (const node of nodes) markWaiting(node)
      return
    }

    if (!mermaid) {
      kickLoad()
      for (const node of nodes) markWaiting(node)
      return
    }

    const instance = mermaid

    for (const node of nodes) {
      if (epoch !== started) return
      if (!node.isConnected) continue
      if (theme() !== current) return
      if (mermaidBusy) {
        markWaiting(node)
        continue
      }
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
