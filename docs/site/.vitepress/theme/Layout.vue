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
    <template #home-hero-actions-after>
      <SpotAskHeroInstall />
    </template>
    <template #home-hero-after>
      <SpotAskHeroShowcase />
    </template>
  </Layout>
</template>
