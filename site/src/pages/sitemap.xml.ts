import type { APIRoute } from 'astro';
import { pages, shortDigest } from '../lib/data';

export const GET: APIRoute = ({ site }) => {
  const base = import.meta.env.BASE_URL;
  const paths = [
    '',
    'images/',
    'matrix/',
    'usage/',
    'changelog/',
    ...pages.flatMap((i) => [
      `images/${i.id}/`,
      ...i.builds.flatMap((b) => {
        const d = `images/${i.id}/${shortDigest(b.digest)}/`;
        return b.cves?.length ? [d, `${d}cves/`] : [d];
      }),
    ]),
  ];
  const urls = paths.map((p) => `<url><loc>${new URL(base + p, site).href}</loc></url>`).join('\n');
  return new Response(`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`, {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  });
};
