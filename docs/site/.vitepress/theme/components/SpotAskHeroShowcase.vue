<script setup lang="ts">
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

interface HeroShowcase {
  src: string
  alt?: string
}

/**
 * The home flow diagram has to read directly under the hero actions, but
 * `layout: home` renders `<Content />` below `VPHomeFeatures`, so a Markdown
 * image always lands under the feature cards. The `home-hero-after` slot (see
 * `../Layout.vue`) is the only insertion point between the two, and frontmatter
 * keeps each language free to name its own asset and alt text.
 */
const { frontmatter } = useData()

const showcase = computed<HeroShowcase | null>(() => {
  const value = frontmatter.value.heroShowcase
  return value && typeof value.src === 'string' && value.src ? value : null
})
</script>

<template>
  <div v-if="showcase" class="spotask-hero-showcase">
    <div class="spotask-hero-showcase__container">
      <img
        class="spotask-hero-showcase__image"
        :src="withBase(showcase.src)"
        :alt="showcase.alt ?? ''"
        width="1600"
        height="900"
        decoding="async"
      >
    </div>
  </div>
</template>

<style scoped>
.spotask-hero-showcase {
  margin: 0 0 48px;
  padding: 0 24px;
}

/* Mirrors VPHero's horizontal padding and bottom padding, and VPFeatures'
   container width, so the diagram edges line up with the cards below it. */
@media (min-width: 640px) {
  .spotask-hero-showcase {
    margin-bottom: 64px;
    padding: 0 48px;
  }
}

@media (min-width: 960px) {
  .spotask-hero-showcase {
    padding: 0 64px;
  }
}

.spotask-hero-showcase__container {
  margin: 0 auto;
  max-width: 1152px;
}

.spotask-hero-showcase__image {
  display: block;
  width: 100%;
  height: auto;
  /* The diagram carries its own light canvas: a hairline and the feature
     cards' radius keep it reading as a panel in both color schemes. */
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
}
</style>
