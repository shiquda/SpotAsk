<script setup lang="ts">
import DefaultTheme from 'vitepress/theme'
import SpotAskHeroShowcase from './components/SpotAskHeroShowcase.vue'

const { Layout } = DefaultTheme
</script>

<template>
  <Layout>
    <template #home-hero-after>
      <SpotAskHeroShowcase />
    </template>
  </Layout>
</template>
