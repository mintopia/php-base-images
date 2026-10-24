import type { APIRoute } from 'astro';
import { images, versions, versionKeys, latestStable, extensions, repoUrl } from '../lib/data';

export const GET: APIRoute = ({ site }) => {
  const url = (p: string) => new URL(`${import.meta.env.BASE_URL}${p}`, site).href;
  const lines = versionKeys.map((v) => {
    const patch = images.find((i) => i.version === v && i.patch)?.patch;
    return `- PHP ${v}${versions[v].stable ? '' : ' (release candidate)'}${patch ? `: currently ${patch}` : ''}`;
  });
  const imgs = images.map((i) => `- [${i.repo}:${i.tag}](${url(`images/${i.id}/`)}): also tagged ${i.tags.filter((t) => t !== i.tag).join(', ') || 'nothing else'}`);
  const body = `# mintopia/php

> Multi-arch (amd64, arm64) PHP base images for Alpine and Debian trixie, published to ghcr.io/mintopia/php, built from php-src tags, signed with cosign and rebuilt daily for OS and extension updates. Composer is not included.

Tags are \`<version>-<os>-<variant>\`; a missing part takes its default. Version: \`8.x\` (latest patch of a minor) or \`8.x.y\` (a specific patch, still rebuilt), default ${latestStable}. OS: \`alpine\` (default) or \`trixie\`. Variant: \`cli\` (default), \`php-fpm\`, \`php-fpm-nginx\` or \`frankenphp\`. \`latest\` is PHP ${latestStable} cli on Alpine. A matching nginx image is ghcr.io/mintopia/nginx:<os>.

Runtime settings (PHP-FPM tuning, document root, PUID/PGID, status page) are environment variables.

## PHP versions

${lines.join('\n')}

## Docs

- [Usage](${url('usage/')}): running, configuring and extending the images, with compose files and Dockerfiles
- [Matrix](${url('matrix/')}): extensions and versions in every image
- [Changelog](${url('changelog/')}): changes build by build
- [About](${url('about/')}): what is built, how it is built and tested, and when images are rebuilt
- [README](${repoUrl}#readme): every environment variable and configuration option

## Images

${imgs.join('\n')}

## Optional

- Bundled extensions: ${extensions.join(', ')}
- [Source](${repoUrl})
`;
  return new Response(body, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
