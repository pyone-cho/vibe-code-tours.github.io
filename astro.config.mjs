// @ts-check
import { defineConfig } from "astro/config";
import tailwind from "@astrojs/tailwind";
import sitemap from "@astrojs/sitemap";

// NOTE: `site` + `base` target GitHub Pages at code-caravan.github.io/code-caravan-site.
// When the custom domain (codecaravan.dev) is live, set:
//   site: "https://codecaravan.dev", base: "/"
// The link helper in src/i18n/utils.ts reads BASE_URL, so links adapt automatically.
export default defineConfig({
  site: "https://code-caravan.github.io",
  base: "/code-caravan-site",
  trailingSlash: "ignore",
  i18n: {
    defaultLocale: "en",
    locales: ["en", "my"],
    routing: {
      prefixDefaultLocale: false,
    },
  },
  integrations: [tailwind(), sitemap()],
});
