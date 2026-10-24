import { defineConfig, fontProviders } from 'astro/config';

export default defineConfig({
  site: 'https://php.mintopia.net',
  trailingSlash: 'always',
  fonts: [
    {
      provider: fontProviders.google(),
      name: 'Hanken Grotesk',
      cssVariable: '--font-hanken',
      weights: [400, 500, 700],
      styles: ['normal'],
      subsets: ['latin'],
      display: 'swap',
      fallbacks: ['system-ui', 'sans-serif'],
    },
    {
      provider: fontProviders.google(),
      name: 'JetBrains Mono',
      cssVariable: '--font-jbmono',
      weights: [400, 500, 700],
      styles: ['normal'],
      subsets: ['latin'],
      display: 'swap',
      fallbacks: ['ui-monospace', 'monospace'],
    },
  ],
});
