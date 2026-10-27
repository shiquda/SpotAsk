import { readdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Plugin } from 'vite'

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

function markdownRoutes(directory: string, prefix = ''): string[] {
  const routes: string[] = []
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name === 'public' || entry.name === 'node_modules') continue
    const relative = path.posix.join(prefix, entry.name)
    if (entry.isDirectory()) {
      routes.push(...markdownRoutes(path.join(directory, entry.name), relative))
    } else if (entry.name.endsWith('.md')) {
      routes.push(relative)
    }
  }
  return routes
}

/**
 * English pages that have no Chinese counterpart.
 *
 * The language switcher rewrites the current path into the other locale, so on a
 * page that only exists in English it produced a link to a page that is never
 * built. These routes let the switcher offer only translations that exist.
 */
export const englishOnlyRoutes: string[] = (() => {
  const pages = markdownRoutes(siteRoot)
  const chinesePages = new Set(pages.filter((page) => page.startsWith('zh-CN/')))
  return pages
    .filter((page) => !page.startsWith('zh-CN/'))
    .filter((page) => !chinesePages.has(`zh-CN/${page}`))
    .map((page) => `/${page.replace(/(^|\/)index\.md$/, '$1').replace(/\.md$/, '')}`)
})()

const LANGS_MODULE = path.join('theme-default', 'composables', 'langs.js')
const RETURN_MARKER = 'return { localeLinks, currentLang };'

/**
 * Hides translations that were never written from the language switcher.
 *
 * VitePress builds the switcher links by rewriting the page path into every
 * locale, with no check that the target exists. The composable is patched rather
 * than the two switcher components so the rule holds for every caller, and a
 * renamed marker fails the build instead of silently reintroducing dead links.
 */
export function localeLinkFilterPlugin(): Plugin {
  return {
    name: 'spotask-locale-link-filter',
    enforce: 'pre',
    transform(code, id) {
      if (!id.split('?')[0].endsWith(LANGS_MODULE)) return null
      if (!code.includes(RETURN_MARKER)) {
        throw new Error(
          `Cannot filter untranslated locale links: "${RETURN_MARKER}" is missing from ${id}. ` +
            'VitePress changed the language switcher; update localeLinkFilterPlugin().'
        )
      }
      const missing = JSON.stringify(englishOnlyRoutes)
      return {
        code: code.replace(
          RETURN_MARKER,
          `const englishOnlyRoutes = ${missing};
    const existingLocaleLinks = computed(() =>
        localeLinks.value.filter((entry) =>
            !englishOnlyRoutes.some((route) => entry.link === \`/zh-CN\${route}\` || entry.link === \`/zh-CN\${route}/\`)
        )
    );
    return { localeLinks: existingLocaleLinks, currentLang };`
        ),
        map: null
      }
    }
  }
}
