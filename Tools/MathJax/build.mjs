import * as esbuild from 'esbuild';
import { fileURLToPath } from 'node:url';

await esbuild.build({
  entryPoints: [fileURLToPath(new URL('src/index.js', import.meta.url))],
  outfile: fileURLToPath(new URL('../../Sources/SpotAsk/Resources/MathJax/mathjax.js', import.meta.url)),
  bundle: true,
  format: 'iife',
  target: 'es2020',
  platform: 'browser',
  minify: true,
  legalComments: 'none'
});
