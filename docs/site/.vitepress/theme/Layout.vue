<script setup lang="ts">
import DefaultTheme from 'vitepress/theme'
import SpotAskHeroCompat from './components/SpotAskHeroCompat.vue'
import SpotAskHeroInstall from './components/SpotAskHeroInstall.vue'
import SpotAskHeroShowcase from './components/SpotAskHeroShowcase.vue'

const { Layout } = DefaultTheme
</script>

<template>
  <Layout>
    <template #home-hero-info-after>
      <SpotAskHeroCompat />
    </template>
    <template #home-hero-image>
      <SpotAskHeroInstall />
    </template>
    <template #home-hero-after>
      <SpotAskHeroShowcase />
    </template>
  </Layout>
</template>

<style>
/* Balance the hero section when the Homebrew terminal card occupies the right column */
.VPHero.has-image .container {
  align-items: center;
}

/* On mobile, ensure the main heading and CTA buttons appear above the terminal card */
.VPHero.has-image .image {
  order: 2 !important;
  margin: 32px 0 0 !important;
  width: 100%;
  display: flex;
  justify-content: center;
}

@media (min-width: 960px) {
  .VPHero.has-image .image {
    order: 2 !important;
    margin: 0 !important;
    display: flex;
    justify-content: flex-end;
    align-items: center;
  }
}

.VPHero.has-image .image-container {
  width: 100% !important;
  max-width: 480px !important;
  height: auto !important;
  min-height: unset !important;
  transform: none !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
}

.VPHero.has-image .image-bg {
  display: none !important;
}
</style>
