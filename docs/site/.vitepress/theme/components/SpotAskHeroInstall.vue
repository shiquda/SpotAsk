<script setup lang="ts">
import { computed, onUnmounted, ref } from 'vue'
import { useData } from 'vitepress'

/**
 * Homebrew install block for the home hero, rendered directly under the hero
 * actions through the `home-hero-actions-after` slot (see `../Layout.vue`).
 *
 * Homebrew is the secondary path on purpose: the primary action stays the DMG
 * download button, because every release publishes separate `arm64` and
 * `x86_64` packages rather than one universal installer.
 *
 * These two commands are the canonical pair repeated in `README.md`,
 * `README.zh-CN.md`, `docs/site/getting-started.md` and the use case pages —
 * keep them identical everywhere.
 */
const HOMEBREW_COMMANDS: readonly string[] = [
  'brew tap shiquda/spotask https://github.com/shiquda/SpotAsk',
  'brew install --cask shiquda/spotask/spotask'
]

const { frontmatter, lang } = useData()

const install = computed(() => frontmatter.value.heroInstall ?? null)

const labels = computed(() =>
  lang.value.startsWith('zh')
    ? { label: '或使用 Homebrew 安装', copy: '复制', copied: '已复制' }
    : { label: 'Or install with Homebrew', copy: 'Copy', copied: 'Copied' }
)

const copied = ref(false)
let resetTimer: ReturnType<typeof setTimeout> | undefined

async function writeClipboard(text: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text)
    return
  }
  // `navigator.clipboard` needs a secure context; keep a plain fallback for
  // plain-HTTP previews and older browsers.
  const area = document.createElement('textarea')
  area.value = text
  area.setAttribute('readonly', '')
  area.style.position = 'absolute'
  area.style.left = '-9999px'
  document.body.appendChild(area)
  area.select()
  document.execCommand('copy')
  document.body.removeChild(area)
}

async function copyCommands() {
  try {
    await writeClipboard(HOMEBREW_COMMANDS.join('\n'))
    copied.value = true
    clearTimeout(resetTimer)
    resetTimer = setTimeout(() => {
      copied.value = false
    }, 2000)
  } catch {
    // Clipboard access denied: leave the commands selectable by hand instead of
    // claiming a copy that never happened.
    copied.value = false
  }
}

onUnmounted(() => clearTimeout(resetTimer))
</script>

<template>
  <div v-if="install" class="spotask-hero-install">
    <div class="spotask-hero-install__header">
      <span class="spotask-hero-install__label">{{ labels.label }}</span>
      <button
        type="button"
        class="spotask-hero-install__copy"
        :aria-label="labels.copy"
        @click="copyCommands"
      >
        {{ copied ? labels.copied : labels.copy }}
      </button>
    </div>
    <pre class="spotask-hero-install__code" tabindex="0"><code>{{ HOMEBREW_COMMANDS.join('\n') }}</code></pre>
  </div>
</template>

<style scoped>
.spotask-hero-install {
  padding-top: 24px;
  max-width: 520px;
}

@media (min-width: 640px) {
  .spotask-hero-install {
    padding-top: 32px;
  }
}

.spotask-hero-install__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 8px;
}

.spotask-hero-install__label {
  font-size: 13px;
  color: var(--vp-c-text-3);
}

.spotask-hero-install__copy {
  flex-shrink: 0;
  padding: 2px 10px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 6px;
  background-color: var(--vp-c-bg-soft);
  font-size: 12px;
  line-height: 20px;
  color: var(--vp-c-text-2);
  cursor: pointer;
  transition: color 0.2s, border-color 0.2s;
}

.spotask-hero-install__copy:hover {
  border-color: var(--vp-c-brand-1);
  color: var(--vp-c-brand-1);
}

.spotask-hero-install__code {
  margin: 0;
  padding: 12px 16px;
  overflow-x: auto;
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  background-color: var(--vp-code-block-bg);
  font-family: var(--vp-font-family-mono);
  font-size: 13px;
  line-height: 1.7;
}

.spotask-hero-install__code code {
  font-family: inherit;
  font-size: inherit;
  white-space: pre;
}
</style>
