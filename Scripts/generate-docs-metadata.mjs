import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const docsRoot = path.join(repositoryRoot, 'docs/site')
const publicRoot = path.join(docsRoot, 'public')
const markdownRoot = path.join(publicRoot, 'markdown')
const docsUrl = 'https://shiquda.github.io/SpotAsk/'

async function collectMarkdownFiles(directory, prefix = '') {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = []

  for (const entry of entries) {
    if (entry.name === '.vitepress' || entry.name === 'public') continue

    const relativePath = path.posix.join(prefix, entry.name)
    const absolutePath = path.join(directory, entry.name)
    if (entry.isDirectory()) {
      files.push(...await collectMarkdownFiles(absolutePath, relativePath))
    } else if (entry.isFile() && entry.name.endsWith('.md')) {
      files.push(relativePath)
    }
  }

  return files.sort((left, right) => left.localeCompare(right, 'en'))
}

function frontmatterValue(source, key) {
  if (!source.startsWith('---\n')) return undefined
  const end = source.indexOf('\n---\n', 4)
  if (end === -1) return undefined

  const match = source.slice(4, end).match(new RegExp(`^${key}:\\s*(.+)$`, 'm'))
  return match?.[1].trim().replace(/^['"]|['"]$/g, '')
}

function pageMetadata(relativePath, source) {
  const isChinese = relativePath.startsWith('zh-CN/')
  const fallbackTitle = isChinese ? 'SpotAsk 文档' : 'SpotAsk Documentation'
  const fallbackDescription = isChinese
    ? 'SpotAsk 用户手册、配置指南、功能说明与故障排查。'
    : 'SpotAsk user manual, setup guides, feature documentation, and troubleshooting.'

  return {
    title: frontmatterValue(source, 'title') ?? fallbackTitle,
    description: frontmatterValue(source, 'description') ?? fallbackDescription,
    markdownUrl: `${docsUrl}markdown/${relativePath}`
  }
}

function llmsSection(title, documents) {
  const lines = [`## ${title}`, '']
  for (const document of documents) {
    lines.push(`- [${document.title}](${document.markdownUrl}): ${document.description}`)
  }
  return lines.join('\n')
}

const sectionTitles = JSON.parse(
  await readFile(path.join(docsRoot, '.vitepress/settings-sections.json'), 'utf8')
)

function isSettingsSectionId(value) {
  return Object.hasOwn(sectionTitles, value)
}

/**
 * Documentation pages render the SpotAsk call to action as a Vue component,
 * which means nothing outside the site. Markdown consumers get the same deep
 * link, section title, and manual path the component shows, so a reader without
 * the app still has a way in. Unknown section ids are dropped, matching the
 * site component, instead of publishing a broken `spotask://` URL.
 */
function markdownForConsumers(relativePath, source) {
  const isChinese = relativePath.startsWith('zh-CN/')
  return source.replace(/^<SpotAskSettingsLink section="([^"]+)" \/>$/gm, (_match, section) => {
    if (!isSettingsSectionId(section)) {
      console.warn(`[spotask-docs] Unknown SpotAsk settings section "${section}"`)
      return ''
    }
    const url = `spotask://settings/${section}`
    const title = isChinese ? sectionTitles[section]['zh-CN'] : sectionTitles[section].en
    if (isChinese) {
      return [
        `在 SpotAsk 中打开设置：\`${url}\``,
        '',
        `打开 SpotAsk 的「${title}」页。未安装 SpotAsk 时此链接不会有反应，可手动打开：SpotAsk 菜单栏图标 → 设置… → ${title}，或按 ⌘ + , 打开设置。`
      ].join('\n')
    }
    return [
      `Open Settings in SpotAsk: \`${url}\``,
      '',
      `Opens the ${title} page in SpotAsk. If SpotAsk is not installed this link does nothing — open it by hand instead: SpotAsk menu bar icon → Settings... → ${title}, or press ⌘ + , to open Settings.`
    ].join('\n')
  })
}

/**
 * The repository root stays the single source of truth for release notes: the
 * site pages below are build products, rewritten from the root Markdown on
 * every `docs:prepare` and never edited in place. `source` frontmatter records
 * the owning root file, which the site turns into that page's edit link (see
 * `.vitepress/config.ts`).
 */
const changelogs = [
  {
    page: 'changelog.md',
    source: 'CHANGELOG.md',
    title: 'Changelog',
    description: 'Release history for SpotAsk, newest version first.'
  },
  {
    page: 'zh-CN/changelog.md',
    source: 'CHANGELOG.zh-CN.md',
    title: '更新日志',
    description: 'SpotAsk 各版本更新记录，最新版本在最前。'
  }
]

async function writeChangelogPages() {
  for (const changelog of changelogs) {
    const contents = await readFile(path.join(repositoryRoot, changelog.source), 'utf8')
    const destination = path.join(docsRoot, changelog.page)
    const frontmatter = [
      '---',
      `title: ${changelog.title}`,
      `description: ${changelog.description}`,
      `source: ${changelog.source}`,
      '---',
      '',
      ''
    ].join('\n')

    await mkdir(path.dirname(destination), { recursive: true })
    await writeFile(destination, `${frontmatter}${contents}`)
  }
}

await writeChangelogPages()

await rm(markdownRoot, { recursive: true, force: true })
await mkdir(markdownRoot, { recursive: true })

const relativePaths = await collectMarkdownFiles(docsRoot)
const documents = []

for (const relativePath of relativePaths) {
  const sourcePath = path.join(docsRoot, relativePath)
  const destinationPath = path.join(markdownRoot, relativePath)
  const source = await readFile(sourcePath, 'utf8')
  const markdown = markdownForConsumers(relativePath, source)

  await mkdir(path.dirname(destinationPath), { recursive: true })
  await writeFile(destinationPath, markdown)
  documents.push({ relativePath, source: markdown, ...pageMetadata(relativePath, source) })
}

const englishDocuments = documents.filter((document) => !document.relativePath.startsWith('zh-CN/'))
const chineseDocuments = documents.filter((document) => document.relativePath.startsWith('zh-CN/'))
const llmsIndex = [
  '# SpotAsk Documentation',
  '',
  '> SpotAsk is a native macOS menu-bar AI assistant for quick questions and actions on selected text. These links provide the official user documentation as clean Markdown.',
  '',
  'Use the English or Simplified Chinese section that matches the user. Start with Getting Started, then fetch only the guide needed for the current question. The complete combined corpus is available in [llms-full.txt](https://shiquda.github.io/SpotAsk/llms-full.txt).',
  '',
  '## Product facts',
  '',
  '- SpotAsk is a free, open-source, native macOS menu-bar AI assistant for quick, lightweight questions and text processing.',
  '- Primary workflows: summon a focused question window with a global hotkey (default Option + Space); run translate/explain/summarize/polish or custom prompts on selected text in other apps (Selection Assistant).',
  '- It is deliberately NOT a full AI workspace; complex tasks can be handed off to ChatGPT, Grok, other apps, or terminal commands via the External Ask feature (URL, URI scheme, or Bash command).',
  '- BYOK (bring your own key): connects to user-configured OpenAI-compatible and Anthropic services; access keys are stored in the macOS Keychain and data is sent only to the configured API provider. No account system, no telemetry.',
  '- Keyboard-first: every core action has a configurable shortcut; the pointer is optional. App size is under 10 MB; it lives in the menu bar.',
  '- Requirements: macOS 15 or later; supports Apple silicon and Intel Macs. Distribution: GitHub Releases (Developer ID signed and notarized). License: AGPL-3.0 (open source).',
  '- The design philosophy behind these choices is documented in the Design Philosophy / 设计理念 page.',
  '',
  llmsSection('English documentation', englishDocuments),
  '',
  llmsSection('简体中文文档', chineseDocuments),
  '',
  '## Optional',
  '',
  '- [GitHub repository](https://github.com/shiquda/SpotAsk): Source code, releases, issue tracking, and contribution history.',
  '- [Latest release](https://github.com/shiquda/SpotAsk/releases/latest): Current downloadable macOS packages.'
].join('\n')

const llmsFull = [
  '# SpotAsk Documentation: Full Markdown Corpus',
  '',
  '> Generated from the official bilingual documentation. Prefer llms.txt when only a small document map is needed.',
  ...documents.flatMap((document) => [
    '',
    '---',
    '',
    `## Source: ${document.relativePath}`,
    '',
    `Markdown URL: ${document.markdownUrl}`,
    '',
    document.source.trim()
  ]),
  ''
].join('\n')

await writeFile(path.join(publicRoot, 'llms.txt'), `${llmsIndex}\n`)
await writeFile(path.join(publicRoot, 'llms-full.txt'), llmsFull)

console.log(`Prepared ${documents.length} Markdown documents for search and LLM access.`)
