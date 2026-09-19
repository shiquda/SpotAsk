/**
 * The Settings pages a documentation link can open, mirrored from the app's
 * frozen deep-link contract (`Sources/SpotAsk/Settings/SettingsDeepLink.swift`).
 *
 * A page is addressed by its stable ASCII id, never by its localized title.
 * The manual path shown next to a call to action uses the titles the app itself
 * displays (`settings.<id>` in `Sources/SpotAsk/Resources/*.lproj`), so a reader
 * who cannot follow the link can still find the page by hand.
 *
 * Titles live in `../settings-sections.json` so the Markdown mirror generator
 * validates the same ids the site component does.
 */

import sectionTitlesJson from '../settings-sections.json'

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

type SectionTitle = { en: string; 'zh-CN': string }

const sectionTitles = sectionTitlesJson as Record<SettingsSectionId, SectionTitle>

for (const id of settingsSectionIds) {
  if (!(id in sectionTitlesJson)) {
    throw new Error(`[spotask-docs] Missing settings section "${id}" in settings-sections.json`)
  }
}
for (const id of Object.keys(sectionTitlesJson)) {
  if (!isSettingsSectionId(id)) {
    throw new Error(`[spotask-docs] Unknown settings section "${id}" in settings-sections.json`)
  }
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
