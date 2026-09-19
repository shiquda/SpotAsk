import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import SpotAskSettingsLink from './components/SpotAskSettingsLink.vue'
import { installMermaidDiagrams } from './mermaid'
import './styles/diagrams.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('SpotAskSettingsLink', SpotAskSettingsLink)
    installMermaidDiagrams()
  }
} satisfies Theme
