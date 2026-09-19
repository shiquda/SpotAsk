/**
 * The Settings pages a documentation link can open, mirrored from the app's
 * frozen deep-link contract (`Sources/SpotAsk/Settings/SettingsDeepLink.swift`).
 *
 * A page is addressed by its stable ASCII id, never by its localized title.
 * The manual path shown next to a call to action uses the titles the app itself
 * displays (`settings.<id>` in `Sources/SpotAsk/Resources/*.lproj`), so a reader
 * who cannot follow the link can still find the page by hand.
 */

export const settingsSectionIds = [
  'provider',
  'prompts',
  'external-ask',
  'selection-assistant',
  'shortcuts',
  'general',
  'appearance',
  'about'
] as const

export type SettingsSectionId = (typeof settingsSectionIds)[number]

/** Section titles as the app renders them, per documentation locale. */
const sectionTitles: Record<SettingsSectionId, { en: string; 'zh-CN': string }> = {
  provider: { en: 'Service', 'zh-CN': '服务设置' },
  prompts: { en: 'Prompts', 'zh-CN': '提示词' },
  'external-ask': { en: 'External Ask', 'zh-CN': '外部提问' },
  'selection-assistant': { en: 'Selection Assistant', 'zh-CN': '划词助手' },
  shortcuts: { en: 'Shortcuts', 'zh-CN': '快捷键' },
  general: { en: 'General', 'zh-CN': '通用' },
  appearance: { en: 'Appearance', 'zh-CN': '外观' },
  about: { en: 'About', 'zh-CN': '关于' }
}

export function isSettingsSectionId(value: string): value is SettingsSectionId {
  return (settingsSectionIds as readonly string[]).includes(value)
}

/** `spotask://settings/<section-id>`, the only stable form the app promises. */
export function settingsDeepLink(section: SettingsSectionId): string {
  return `spotask://settings/${section}`
}

export function settingsSectionTitle(section: SettingsSectionId, locale: string): string {
  const titles = sectionTitles[section]
  return locale === 'zh-CN' ? titles['zh-CN'] : titles.en
}
