<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'
import { isSettingsSectionId, settingsDeepLink, settingsSectionTitle } from '../spotaskSettings'

const props = defineProps<{ section: string }>()

const { lang } = useData()
const isChinese = computed(() => lang.value.startsWith('zh'))

/**
 * The deep link is a convenience, never the only way in, so every call to
 * action also states the manual path for readers who have not installed the app.
 */
const section = computed(() => {
  if (isSettingsSectionId(props.section)) return props.section
  // A typo would silently drop the call to action, so say so during the build.
  console.warn(`[spotask-docs] Unknown SpotAsk settings section "${props.section}"`)
  return null
})
const url = computed(() => (section.value ? settingsDeepLink(section.value) : ''))
const title = computed(() => (section.value ? settingsSectionTitle(section.value, lang.value) : ''))
const menuPath = computed(() => (isChinese.value ? `SpotAsk 菜单栏图标 → 设置… → ${title.value}` : `SpotAsk menu bar icon → Settings... → ${title.value}`))
</script>

<template>
  <div v-if="section" class="spotask-settings-link">
    <a class="spotask-settings-link__action" :href="url" @click.stop>
      {{ isChinese ? '在 SpotAsk 中打开设置' : 'Open Settings in SpotAsk' }}
    </a>
    <p class="spotask-settings-link__hint">
      <template v-if="isChinese">
        打开 SpotAsk 的「{{ title }}」页。未安装 SpotAsk 时此链接不会有反应，可手动打开：{{ menuPath }}，或按 <kbd>⌘</kbd> + <kbd>,</kbd> 打开设置。直接使用链接：<code>{{ url }}</code>
      </template>
      <template v-else>
        Opens the <strong>{{ title }}</strong> page in SpotAsk. If SpotAsk is not installed this link
        does nothing — open it by hand instead: {{ menuPath }}, or press <kbd>⌘</kbd> + <kbd>,</kbd> to
        open Settings. Direct link: <code>{{ url }}</code>
      </template>
    </p>
  </div>
</template>

<style scoped>
.spotask-settings-link {
  margin: 16px 0;
  padding: 16px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  background-color: var(--vp-c-bg-soft);
}

.spotask-settings-link__action {
  display: inline-block;
  padding: 8px 16px;
  border-radius: 20px;
  background-color: var(--vp-button-brand-bg);
  color: var(--vp-button-brand-text);
  font-size: 14px;
  font-weight: 600;
  line-height: 1.4;
  text-decoration: none;
  transition: background-color 0.25s;
}

.spotask-settings-link__action:hover {
  background-color: var(--vp-button-brand-hover-bg);
  color: var(--vp-button-brand-hover-text);
}

.spotask-settings-link__hint {
  margin: 12px 0 0;
  color: var(--vp-c-text-2);
  font-size: 13px;
  line-height: 1.6;
}

.spotask-settings-link__hint code {
  font-size: 12px;
}
</style>
