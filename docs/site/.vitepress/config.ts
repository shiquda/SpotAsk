import { defineConfig, type HeadConfig } from 'vitepress'

const docsUrl = 'https://shiquda.github.io/SpotAsk/'
const socialImageUrl = `${docsUrl}images/spotask-chat.png`

function routeForPage(page: string): string {
  const withoutExtension = page.replace(/\.md$/, '')
  if (withoutExtension === 'index') return ''
  return withoutExtension.endsWith('/index')
    ? withoutExtension.slice(0, -'index'.length)
    : withoutExtension
}

function canonicalUrlForPage(page: string): string {
  return `${docsUrl}${routeForPage(page)}`
}

function markdownUrlForPage(page: string): string {
  return `${docsUrl}markdown/${page}`
}

function localizedPages(page: string): { english: string; chinese: string } {
  const english = page.startsWith('zh-CN/') ? page.slice('zh-CN/'.length) : page
  return { english, chinese: `zh-CN/${english}` }
}

function chineseTokenizer(text: string): string[] {
  if (!text) return []

  const tokens: string[] = []
  const segmenter = new Intl.Segmenter('zh-Hans', { granularity: 'word' })

  for (const part of segmenter.segment(text)) {
    const raw = part.segment.trim()
    if (!raw) continue

    if (/^[\p{Script=Han}]+$/u.test(raw)) {
      tokens.push(raw)
      for (let index = 0; index < raw.length - 1; index += 1) {
        tokens.push(raw.slice(index, index + 2))
      }
      tokens.push(...Array.from(raw))
      continue
    }

    tokens.push(
      ...raw
        .toLowerCase()
        .split(/[\s\p{P}\p{S}]+/u)
        .filter(Boolean)
    )
  }

  return Array.from(new Set(tokens))
}

const englishSidebar = [
  {
    text: 'Start Here',
    items: [
      { text: 'Getting Started', link: '/getting-started' },
      { text: 'Explore SpotAsk', link: '/explore' },
      { text: 'Privacy & Local Data', link: '/privacy' }
    ]
  },
  {
    text: 'Guides',
    items: [
      { text: 'Connect an OpenAI-Compatible Service', link: '/guides/connect-openai-compatible' },
      { text: 'Connect Anthropic', link: '/guides/connect-anthropic' },
      { text: 'Service Root vs Full Request Address', link: '/guides/service-addresses' },
      { text: 'Providers & Models', link: '/guides/providers-and-models' },
      { text: 'Selection Assistant', link: '/guides/selection-assistant' },
      { text: 'Prompts', link: '/guides/prompts' },
      { text: 'Images & Files', link: '/guides/attachments' },
      { text: 'Spotlight, Siri & Shortcuts', link: '/guides/macos-integration' },
      { text: 'Proxy', link: '/guides/proxy' },
      { text: 'Appearance & Behavior', link: '/guides/appearance' }
    ]
  },
  {
    text: 'Help',
    items: [
      { text: 'Troubleshooting', link: '/troubleshooting' },
      { text: 'Settings & Shortcuts Reference', link: '/reference' }
    ]
  }
]

const chineseSidebar = [
  {
    text: '从这里开始',
    items: [
      { text: '快速开始', link: '/zh-CN/getting-started' },
      { text: '探索 SpotAsk', link: '/zh-CN/explore' },
      { text: '隐私与本地数据', link: '/zh-CN/privacy' }
    ]
  },
  {
    text: '指南',
    items: [
      { text: '连接 OpenAI 兼容服务', link: '/zh-CN/guides/connect-openai-compatible' },
      { text: '连接 Anthropic', link: '/zh-CN/guides/connect-anthropic' },
      { text: '服务根地址与完整请求地址', link: '/zh-CN/guides/service-addresses' },
      { text: '服务与模型', link: '/zh-CN/guides/providers-and-models' },
      { text: '划词助手', link: '/zh-CN/guides/selection-assistant' },
      { text: '提示词', link: '/zh-CN/guides/prompts' },
      { text: '图片与文件', link: '/zh-CN/guides/attachments' },
      { text: 'Spotlight、Siri 与快捷指令', link: '/zh-CN/guides/macos-integration' },
      { text: '代理', link: '/zh-CN/guides/proxy' },
      { text: '外观与行为', link: '/zh-CN/guides/appearance' }
    ]
  },
  {
    text: '帮助',
    items: [
      { text: '故障排查', link: '/zh-CN/troubleshooting' },
      { text: '设置与快捷键参考', link: '/zh-CN/reference' }
    ]
  }
]

export default defineConfig({
  lang: 'en-US',
  title: 'SpotAsk Docs',
  description: 'Learn what SpotAsk can do, connect your AI service, and solve common problems.',
  base: '/SpotAsk/',
  srcExclude: ['public/markdown/**/*.md'],
  cleanUrls: true,
  lastUpdated: true,
  sitemap: {
    hostname: docsUrl
  },
  transformHead({ page, title, description }): HeadConfig[] {
    if (page === '404.md') {
      return [['meta', { name: 'robots', content: 'noindex, nofollow' }]]
    }

    const canonicalUrl = canonicalUrlForPage(page)
    const markdownUrl = markdownUrlForPage(page)
    const pages = localizedPages(page)
    const isChinese = page.startsWith('zh-CN/')
    const language = isChinese ? 'zh-CN' : 'en'
    const structuredData = {
      '@context': 'https://schema.org',
      '@type': routeForPage(page) ? 'WebPage' : 'WebSite',
      name: title,
      description,
      url: canonicalUrl,
      inLanguage: language,
      isPartOf: routeForPage(page)
        ? {
            '@type': 'WebSite',
            name: 'SpotAsk Documentation',
            url: docsUrl
          }
        : undefined
    }

    return [
      ['link', { rel: 'canonical', href: canonicalUrl }],
      ['link', { rel: 'alternate', hreflang: 'en', href: canonicalUrlForPage(pages.english) }],
      ['link', { rel: 'alternate', hreflang: 'zh-CN', href: canonicalUrlForPage(pages.chinese) }],
      ['link', { rel: 'alternate', hreflang: 'x-default', href: canonicalUrlForPage(pages.english) }],
      ['link', { rel: 'alternate', type: 'text/markdown', href: markdownUrl }],
      ['link', { rel: 'describedby', type: 'text/plain', href: `${docsUrl}llms.txt` }],
      ['meta', { property: 'og:type', content: 'website' }],
      ['meta', { property: 'og:site_name', content: 'SpotAsk Documentation' }],
      ['meta', { property: 'og:title', content: title }],
      ['meta', { property: 'og:description', content: description }],
      ['meta', { property: 'og:url', content: canonicalUrl }],
      ['meta', { property: 'og:image', content: socialImageUrl }],
      ['meta', { property: 'og:locale', content: isChinese ? 'zh_CN' : 'en_US' }],
      ['meta', { property: 'og:locale:alternate', content: isChinese ? 'en_US' : 'zh_CN' }],
      ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
      ['meta', { name: 'twitter:title', content: title }],
      ['meta', { name: 'twitter:description', content: description }],
      ['meta', { name: 'twitter:image', content: socialImageUrl }],
      ['script', { type: 'application/ld+json' }, JSON.stringify(structuredData)]
    ]
  },
  head: [
    ['link', { rel: 'icon', href: '/SpotAsk/spotask-icon.png' }],
    ['link', { rel: 'sitemap', type: 'application/xml', href: `${docsUrl}sitemap.xml` }]
  ],
  locales: {
    root: {
      label: 'English',
      lang: 'en',
      title: 'SpotAsk Docs',
      description: 'Learn what SpotAsk can do, connect your AI service, and solve common problems.',
      themeConfig: {
        nav: [
          { text: 'Getting Started', link: '/getting-started' },
          { text: 'Explore', link: '/explore' },
          { text: 'Guides', link: '/guides/connect-openai-compatible' },
          { text: 'Troubleshooting', link: '/troubleshooting' },
          { text: 'Reference', link: '/reference' }
        ],
        sidebar: englishSidebar
      }
    },
    'zh-CN': {
      label: '简体中文',
      lang: 'zh-CN',
      title: 'SpotAsk 文档',
      description: '了解 SpotAsk 能做什么，连接你的 AI 服务，并解决常见问题。',
      markdown: {
        container: {
          tipLabel: '提示',
          warningLabel: '注意',
          dangerLabel: '危险',
          infoLabel: '信息',
          detailsLabel: '详情'
        },
        codeCopyButton: {
          tooltipText: '复制代码',
          copiedText: '已复制'
        }
      },
      themeConfig: {
        nav: [
          { text: '快速开始', link: '/zh-CN/getting-started' },
          { text: '能力地图', link: '/zh-CN/explore' },
          { text: '指南', link: '/zh-CN/guides/connect-openai-compatible' },
          { text: '故障排查', link: '/zh-CN/troubleshooting' },
          { text: '参考', link: '/zh-CN/reference' }
        ],
        sidebar: chineseSidebar,
        outlineTitle: '本页目录',
        lastUpdatedText: '最后更新',
        docFooter: {
          prev: '上一页',
          next: '下一页'
        },
        editLink: {
          text: '编辑此页'
        },
        sidebarMenuLabel: '目录',
        returnToTopLabel: '返回顶部',
        darkModeSwitchLabel: '深色模式',
        lightModeSwitchLabel: '浅色模式',
        langMenuLabel: '切换语言',
        navScreenTitle: 'SpotAsk 文档',
        footer: {
          message: '原生 macOS 菜单栏 AI 助手',
          copyright: 'Copyright © SpotAsk Contributors'
        }
      }
    }
  },
  themeConfig: {
    logo: '/spotask-icon.png',
    outline: { level: [2, 3] },
    search: {
      provider: 'local',
      options: {
        locales: {
          root: {
            translations: {
              button: {
                buttonText: 'Search docs',
                buttonAriaLabel: 'Search docs'
              },
              modal: {
                displayDetails: 'Display detailed results',
                resetButtonTitle: 'Reset search',
                backButtonTitle: 'Close search',
                noResultsText: 'No results',
                footer: {
                  selectText: 'Select',
                  selectKeyAriaLabel: 'Enter',
                  navigateText: 'Navigate',
                  navigateUpKeyAriaLabel: 'Up arrow',
                  navigateDownKeyAriaLabel: 'Down arrow',
                  closeText: 'Close',
                  closeKeyAriaLabel: 'Escape'
                }
              }
            }
          },
          'zh-CN': {
            translations: {
              button: {
                buttonText: '搜索文档',
                buttonAriaLabel: '搜索文档'
              },
              modal: {
                displayDetails: '显示详细结果',
                resetButtonTitle: '重置搜索',
                backButtonTitle: '关闭搜索',
                noResultsText: '没有找到结果',
                footer: {
                  selectText: '选择',
                  selectKeyAriaLabel: '回车',
                  navigateText: '切换',
                  navigateUpKeyAriaLabel: '上箭头',
                  navigateDownKeyAriaLabel: '下箭头',
                  closeText: '关闭',
                  closeKeyAriaLabel: 'Esc'
                }
              }
            }
          }
        },
        miniSearch: {
          options: {
            tokenize: chineseTokenizer
          }
        }
      }
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/shiquda/SpotAsk' }
    ],
    editLink: {
      pattern: 'https://github.com/shiquda/SpotAsk/edit/main/docs/site/:path'
    },
    footer: {
      message: 'Native macOS menu-bar AI assistant',
      copyright: 'Copyright © SpotAsk Contributors'
    },
    docFooter: {
      prev: 'Previous',
      next: 'Next'
    }
  }
})
