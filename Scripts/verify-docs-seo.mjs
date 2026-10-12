import { readdir, readFile, stat } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const distRoot = path.join(repositoryRoot, 'docs/site/.vitepress/dist')
const docsUrl = 'https://shiquda.github.io/SpotAsk/'
const basePath = '/SpotAsk/'

async function collectHtmlFiles(directory, prefix = '') {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const rel = path.posix.join(prefix, entry.name)
    const abs = path.join(directory, entry.name)
    if (entry.isDirectory()) {
      files.push(...await collectHtmlFiles(abs, rel))
    } else if (entry.isFile() && entry.name.endsWith('.html')) {
      files.push(rel)
    }
  }
  return files.sort((a, b) => a.localeCompare(b, 'en'))
}

async function fileExists(filePath) {
  try {
    const info = await stat(filePath)
    return info.isFile()
  } catch {
    return false
  }
}

function parseAttributes(attrText) {
  const attrs = {}
  const regex = /([a-zA-Z0-9_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g
  let match
  while ((match = regex.exec(attrText)) !== null) {
    attrs[match[1].toLowerCase()] = match[2] ?? match[3] ?? ''
  }
  return attrs
}

const errors = []
const htmlFiles = await collectHtmlFiles(distRoot)
if (htmlFiles.length === 0) {
  throw new Error(`No built HTML files found in ${distRoot}. Run "npm run docs:build" first.`)
}

// Map exact served URLs on GitHub Pages with VitePress cleanUrls:
// - index.html -> /SpotAsk/
// - zh-CN/index.html -> /SpotAsk/zh-CN/
// - foo.html -> /SpotAsk/foo (Note: /SpotAsk/foo/ returns HTTP 404 on GitHub Pages)
const servedFullUrls = new Map()
const servedPathUrls = new Map()

for (const rel of htmlFiles) {
  if (rel === '404.html') continue
  if (rel === 'index.html') {
    servedFullUrls.set(docsUrl, rel)
    servedPathUrls.set(basePath, rel)
  } else if (rel.endsWith('/index.html')) {
    const sub = rel.slice(0, -'index.html'.length)
    servedFullUrls.set(`${docsUrl}${sub}`, rel)
    servedPathUrls.set(`${basePath}${sub}`, rel)
  } else {
    const route = rel.slice(0, -'.html'.length)
    servedFullUrls.set(`${docsUrl}${route}`, rel)
    servedPathUrls.set(`${basePath}${route}`, rel)
  }
}

// 1. Verify sitemap.xml
const sitemapPath = path.join(distRoot, 'sitemap.xml')
if (!(await fileExists(sitemapPath))) {
  errors.push('Missing sitemap.xml in build output')
} else {
  const sitemapXml = await readFile(sitemapPath, 'utf8')
  const locMatches = [...sitemapXml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1].trim())
  const sitemapLocSet = new Set(locMatches)

  if (locMatches.length === 0) {
    errors.push('sitemap.xml contains zero <loc> entries')
  }
  for (const loc of locMatches) {
    if (!servedFullUrls.has(loc)) {
      errors.push(`sitemap.xml <loc> does not resolve to an exact 200 HTML page: ${loc}`)
    }
  }
  for (const [fullUrl, rel] of servedFullUrls.entries()) {
    if (!sitemapLocSet.has(fullUrl)) {
      errors.push(`HTML page ${rel} (${fullUrl}) is missing from sitemap.xml`)
    }
  }

  const xhtmlLinks = [...sitemapXml.matchAll(/<xhtml:link\s+([^>]+?)\/?>/g)].map((m) => parseAttributes(m[1]))
  for (const link of xhtmlLinks) {
    if (link.rel === 'alternate' && link.href && !servedFullUrls.has(link.href)) {
      errors.push(`sitemap.xml xhtml:link hreflang="${link.hreflang}" points to non-200 URL: ${link.href}`)
    }
  }
}

// 2. Verify every HTML file
for (const rel of htmlFiles) {
  const html = await readFile(path.join(distRoot, rel), 'utf8')
  const linkTags = [...html.matchAll(/<link\s+([^>]+?)\/?>/gi)].map((m) => parseAttributes(m[1]))
  const metaTags = [...html.matchAll(/<meta\s+([^>]+?)\/?>/gi)].map((m) => parseAttributes(m[1]))

  const robotsMeta = metaTags.find((m) => m.name === 'robots')?.content ?? ''
  if (rel === '404.html') {
    if (!robotsMeta.includes('noindex')) {
      errors.push('404.html must include <meta name="robots" content="noindex, nofollow">')
    }
    continue
  }

  if (robotsMeta.includes('noindex')) {
    errors.push(`[${rel}] Unexpected noindex meta tag: ${robotsMeta}`)
  }

  // Verify <html lang="...">
  const htmlTagMatch = html.match(/<html\s+([^>]+)>/i)
  const htmlLang = htmlTagMatch ? parseAttributes(htmlTagMatch[1]).lang : ''
  const expectedLang = rel.startsWith('zh-CN/') ? 'zh-CN' : 'en'
  if (htmlLang !== expectedLang) {
    errors.push(`[${rel}] Expected <html lang="${expectedLang}">, found "${htmlLang}"`)
  }

  // Verify <title> and <meta name="description">
  const titleMatch = html.match(/<title>([^<]*)<\/title>/i)
  const title = titleMatch ? titleMatch[1].trim() : ''
  if (!title) {
    errors.push(`[${rel}] Empty or missing <title>`)
  }
  const description = metaTags.find((m) => m.name === 'description')?.content?.trim() ?? ''
  if (!description) {
    errors.push(`[${rel}] Empty or missing <meta name="description">`)
  }

  // Verify canonical URL matches exact served URL
  const canonical = linkTags.find((l) => l.rel === 'canonical')?.href ?? ''
  if (!canonical || servedFullUrls.get(canonical) !== rel) {
    errors.push(`[${rel}] Canonical URL "${canonical}" does not match page's served URL`)
  }

  // Verify hreflang reciprocity (en, zh-CN, x-default)
  const hreflangs = new Map(
    linkTags
      .filter((l) => l.rel === 'alternate' && l.hreflang)
      .map((l) => [l.hreflang, l.href])
  )
  for (const requiredLang of ['en', 'zh-CN', 'x-default']) {
    const targetHref = hreflangs.get(requiredLang)
    if (!targetHref) {
      errors.push(`[${rel}] Missing hreflang="${requiredLang}" link`)
    } else if (!servedFullUrls.has(targetHref)) {
      errors.push(`[${rel}] hreflang="${requiredLang}" points to non-existent/non-200 URL: ${targetHref}`)
    }
  }

  // Verify Markdown mirror exists and includes canonical frontmatter
  const mdHref = linkTags.find((l) => l.rel === 'alternate' && l.type === 'text/markdown')?.href ?? ''
  if (!mdHref || !mdHref.startsWith(docsUrl)) {
    errors.push(`[${rel}] Missing or invalid <link rel="alternate" type="text/markdown">`)
  } else {
    const mdRelPath = mdHref.slice(docsUrl.length)
    const mdAbsPath = path.join(distRoot, mdRelPath)
    if (!(await fileExists(mdAbsPath))) {
      errors.push(`[${rel}] Markdown mirror missing in dist: ${mdRelPath}`)
    } else {
      const mdContent = await readFile(mdAbsPath, 'utf8')
      if (!mdContent.includes(`canonical: ${canonical}`)) {
        errors.push(`[${rel}] Markdown mirror ${mdRelPath} missing "canonical: ${canonical}" in frontmatter`)
      }
    }
  }

  // Verify JSON-LD syntax and schema fields
  const jsonLdMatches = [...html.matchAll(/<script\s+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)]
  if (jsonLdMatches.length === 0) {
    errors.push(`[${rel}] Missing <script type="application/ld+json"> structured data`)
  } else {
    for (const m of jsonLdMatches) {
      try {
        const parsed = JSON.parse(m[1])
        if (parsed['@context'] !== 'https://schema.org') {
          errors.push(`[${rel}] JSON-LD unexpected @context: ${parsed['@context']}`)
        }
        if (rel === 'index.html' || rel === 'zh-CN/index.html') {
          const graph = Array.isArray(parsed['@graph']) ? parsed['@graph'] : []
          const hasWebSite = graph.some((node) => node['@type'] === 'WebSite' && node.url === canonical)
          const hasSoftwareApp = graph.some(
            (node) =>
              node['@type'] === 'SoftwareApplication' &&
              node.name === 'SpotAsk' &&
              node.operatingSystem &&
              node.downloadUrl
          )
          if (!hasWebSite || !hasSoftwareApp) {
            errors.push(`[${rel}] Homepage JSON-LD must include WebSite and SoftwareApplication in @graph`)
          }
        } else if (parsed['@type'] !== 'WebPage' || parsed.url !== canonical) {
          errors.push(`[${rel}] Subpage JSON-LD must have @type="WebPage" and url="${canonical}"`)
        }
      } catch (err) {
        errors.push(`[${rel}] Invalid JSON-LD syntax: ${err.message}`)
      }
    }
  }

  // Verify SSR body content is present (not client-only empty shell)
  const textWithoutScripts = html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  if (textWithoutScripts.length < 200) {
    errors.push(`[${rel}] SSR body text suspiciously short (${textWithoutScripts.length} chars)`)
  }

  // Verify internal <a href="..."> links resolve to 200 pages or static files
  const anchorTags = [...html.matchAll(/<a\s+([^>]+?)>/gi)].map((m) => parseAttributes(m[1]))
  for (const a of anchorTags) {
    const rawHref = a.href
    if (!rawHref) continue
    const cleanHref = rawHref.split('#')[0].split('?')[0]
    if (!cleanHref) continue
    if (/^(mailto:|spotask:|javascript:)/i.test(cleanHref)) continue

    if (/^https?:\/\//i.test(cleanHref)) {
      if (cleanHref.startsWith(docsUrl)) {
        const assetRel = cleanHref.slice(docsUrl.length)
        if (!servedFullUrls.has(cleanHref) && !(await fileExists(path.join(distRoot, assetRel)))) {
          errors.push(`[${rel}] Broken or non-canonical full internal link: ${rawHref}`)
        }
      }
      continue
    }

    if (!cleanHref.startsWith(basePath)) {
      errors.push(`[${rel}] Internal link missing "${basePath}" base prefix: ${rawHref}`)
      continue
    }

    const assetRel = cleanHref.slice(basePath.length)
    if (!servedPathUrls.has(cleanHref) && !(await fileExists(path.join(distRoot, assetRel)))) {
      errors.push(`[${rel}] Broken or 404 trailing-slash internal link: ${rawHref}`)
    }
  }
}

if (errors.length > 0) {
  console.error(`SEO verification failed with ${errors.length} issue(s):`)
  for (const err of errors) {
    console.error(`  - ${err}`)
  }
  process.exit(1)
}

console.log(
  `Verified ${servedFullUrls.size} indexed HTML pages, sitemap.xml, hreflang reciprocity, Markdown mirrors, JSON-LD, and internal links with 0 SEO issues.`
)
