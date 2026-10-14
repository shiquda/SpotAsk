<script setup lang="ts">
import { computed, onUnmounted, ref } from 'vue'
import { useData } from 'vitepress'

/**
 * Homebrew install terminal card for the home hero, rendered in the right
 * column through the `home-hero-image` slot (see `../Layout.vue`).
 *
 * This balances the hero on desktop:
 * - Left column: SpotAsk name, tagline, compatibility text, and direct DMG /
 *   Getting Started buttons.
 * - Right column: Compact, copyable Homebrew commands in a native terminal card.
 */
const HOMEBREW_COMMANDS: readonly string[] = [
  'brew tap shiquda/spotask https://github.com/shiquda/SpotAsk',
  'brew install --cask shiquda/spotask/spotask'
]

const { frontmatter, lang } = useData()

const install = computed(() => frontmatter.value.heroInstall ?? null)

const labels = computed(() =>
  lang.value.startsWith('zh')
    ? {
        title: 'Homebrew 极速安装',
        copy: '复制代码',
        copied: '已复制！',
        note: 'macOS 15+ · 自动匹配架构'
      }
    : {
        title: 'Install via Homebrew',
        copy: 'Copy',
        copied: 'Copied!',
        note: 'macOS 15+ · Auto-detects architecture'
      }
)

const copied = ref(false)
let resetTimer: ReturnType<typeof setTimeout> | undefined

async function writeClipboard(text: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text)
    return
  }
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
    copied.value = false
  }
}

onUnmounted(() => clearTimeout(resetTimer))
</script>

<template>
  <div v-if="install" class="spotask-hero-terminal">
    <div class="spotask-hero-terminal__titlebar">
      <div class="spotask-hero-terminal__dots" aria-hidden="true">
        <span class="dot dot--red" />
        <span class="dot dot--yellow" />
        <span class="dot dot--green" />
      </div>
      <div class="spotask-hero-terminal__title">
        {{ labels.title }}
      </div>
      <button
        type="button"
        class="spotask-hero-terminal__copy"
        :class="{ 'is-copied': copied }"
        :aria-label="labels.copy"
        @click="copyCommands"
      >
        <svg
          v-if="!copied"
          class="copy-icon"
          viewBox="0 0 24 24"
          width="14"
          height="14"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
        </svg>
        <svg
          v-else
          class="copy-icon"
          viewBox="0 0 24 24"
          width="14"
          height="14"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <polyline points="20 6 9 17 4 12" />
        </svg>
        <span>{{ copied ? labels.copied : labels.copy }}</span>
      </button>
    </div>

    <pre class="spotask-hero-terminal__body" tabindex="0"><code><span class="line"><span class="prompt">$</span> {{ HOMEBREW_COMMANDS[0] }}</span>
<span class="line"><span class="prompt">$</span> {{ HOMEBREW_COMMANDS[1] }}</span></code></pre>

    <div class="spotask-hero-terminal__footer">
      <span class="spotask-hero-terminal__note">{{ labels.note }}</span>
    </div>
  </div>
</template>

<style scoped>
.spotask-hero-terminal {
  width: 100%;
  max-width: 480px;
  background-color: var(--vp-code-block-bg);
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.08), 0 2px 6px rgba(0, 0, 0, 0.04);
  overflow: hidden;
  text-align: left;
  transition: border-color 0.25s, box-shadow 0.25s;
}

.spotask-hero-terminal:hover {
  border-color: var(--vp-c-brand-1);
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.12), 0 4px 12px rgba(0, 0, 0, 0.06);
}

.spotask-hero-terminal__titlebar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 14px;
  background-color: var(--vp-c-bg-mute);
  border-bottom: 1px solid var(--vp-c-divider);
}

.spotask-hero-terminal__dots {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 52px;
}

.dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  display: inline-block;
}

.dot--red {
  background-color: #ec6a5e;
}

.dot--yellow {
  background-color: #f4bf4f;
}

.dot--green {
  background-color: #61c554;
}

.spotask-hero-terminal__title {
  font-size: 12px;
  font-weight: 500;
  color: var(--vp-c-text-2);
  letter-spacing: 0.01em;
  text-align: center;
  flex: 1;
}

.spotask-hero-terminal__copy {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 6px;
  background-color: var(--vp-c-bg);
  font-size: 11px;
  line-height: 16px;
  font-weight: 500;
  color: var(--vp-c-text-2);
  cursor: pointer;
  transition: all 0.2s ease;
}

.spotask-hero-terminal__copy:hover {
  border-color: var(--vp-c-brand-1);
  color: var(--vp-c-brand-1);
}

.spotask-hero-terminal__copy.is-copied {
  border-color: var(--vp-c-green-1, #10b981);
  color: var(--vp-c-green-1, #10b981);
}

.copy-icon {
  flex-shrink: 0;
}

.spotask-hero-terminal__body {
  margin: 0;
  padding: 16px 16px 12px;
  overflow-x: auto;
  font-family: var(--vp-font-family-mono);
  font-size: 12.5px;
  line-height: 1.8;
  background-color: transparent;
}

.spotask-hero-terminal__body code {
  display: block;
  font-family: inherit;
  font-size: inherit;
  white-space: pre;
}

.line {
  display: block;
  color: var(--vp-c-text-1);
}

.prompt {
  color: var(--vp-c-brand-1);
  font-weight: 600;
  user-select: none;
  margin-right: 4px;
}

.spotask-hero-terminal__footer {
  padding: 6px 16px 10px;
  border-top: 1px dashed var(--vp-c-divider);
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.spotask-hero-terminal__note {
  font-size: 11.5px;
  color: var(--vp-c-text-3);
  letter-spacing: 0.01em;
}
</style>
