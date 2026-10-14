<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

/**
 * Compatibility line for the home hero.
 *
 * `layout: home` renders it through the `home-hero-info-after` slot (see
 * `../Layout.vue`), which sits between the tagline and the hero actions, so a
 * reader learns the platform requirement before acting on the download button
 * instead of after opening a package that cannot run.
 *
 * The text lives in the `heroInstall.compat` frontmatter key so each locale
 * spells out its own line.
 */
const { frontmatter } = useData()

const compat = computed(() => {
  const value = frontmatter.value.heroInstall?.compat
  return typeof value === 'string' && value.trim() ? value : null
})
</script>

<template>
  <p v-if="compat" class="spotask-hero-compat">{{ compat }}</p>
</template>

<style scoped>
.spotask-hero-compat {
  padding-top: 12px;
  line-height: 24px;
  font-size: 15px;
  font-weight: 500;
  color: var(--vp-c-text-2);
}

@media (min-width: 640px) {
  .spotask-hero-compat {
    font-size: 16px;
  }
}
</style>
