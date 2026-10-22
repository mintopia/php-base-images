import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { marked } from 'marked';
import { codeToHtml } from 'shiki';

const root = resolve(process.cwd(), '..');
const recordsDir = process.env.SITE_RECORDS ?? resolve(root, '.site-data/records');

export const VARIANTS = ['cli', 'php-fpm', 'php-fpm-nginx', 'frankenphp'] as const;
export const OSES = ['alpine', 'trixie'] as const;
export const ARCHES = ['amd64', 'arm64'] as const;
export type Variant = (typeof VARIANTS)[number] | 'nginx';

interface VersionEntry {
  tag: string;
  stable: boolean;
  os: string[];
  frankenphp: boolean;
  extensions: string[];
  dropped?: Record<string, string>;
}

export interface BuildRecord {
  time: string;
  run: string;
  commit: string;
  image: string;
  version: string;
  os: string;
  variant: Variant;
  php: string;
  stable: boolean;
  digest: string;
  platforms: Record<string, string>;
  tags: string[];
  modules?: string[];
  labels: Record<string, string>;
}

export interface Change {
  kind: 'php' | 'component' | 'base' | 'rebuild' | 'first';
  text: string;
}

export interface Build extends BuildRecord {
  changes: Change[];
  live: boolean;
  until: string | null;
}

export interface Image {
  id: string;
  repo: string;
  version: string;
  os: string;
  variant: Variant;
  stable: boolean;
  tag: string;
  tags: string[];
  current: Build | null;
  builds: Build[];
}

export const versions: Record<string, VersionEntry> = JSON.parse(
  readFileSync(resolve(root, 'versions.json'), 'utf8'),
).variable.VERSIONS.default;

const byVersion = (a: string, b: string) => a.localeCompare(b, undefined, { numeric: true });
export const versionKeys = Object.keys(versions).sort(byVersion);
export const latestStable = versionKeys.filter((k) => versions[k].stable).at(-1)!;

// first site run backfills images the same run also records; keep one per image digest, preferring the workflow's
const records: BuildRecord[] = [
  ...new Map(
    (existsSync(recordsDir) ? readdirSync(recordsDir).filter((f) => f.endsWith('.json')) : [])
      .map((f): BuildRecord => JSON.parse(readFileSync(resolve(recordsDir, f), 'utf8')))
      .sort((a, b) => Number(a.run !== 'backfill') - Number(b.run !== 'backfill'))
      .map((r) => [`${r.image}|${r.os}|${r.variant}|${r.digest}`, r] as const),
  ).values(),
];

const COMPONENT = /^net\.mintopia\.(?:ext\.)?([a-z0-9]+)\.version$/;
const BASE = 'org.opencontainers.image.base.digest';

export function components(labels: Record<string, string>) {
  return Object.entries(labels)
    .map(([k, v]) => [k.match(COMPONENT)?.[1], v] as const)
    .filter((e): e is [string, string] => !!e[0])
    .sort(([a], [b]) => a.localeCompare(b));
}

function diff(prev: BuildRecord | undefined, cur: BuildRecord): Change[] {
  if (!prev) return [{ kind: 'first', text: 'First recorded build' }];
  const out: Change[] = [];
  if (prev.php !== cur.php && cur.variant !== 'nginx') {
    out.push({ kind: 'php', text: `PHP ${prev.php || '?'} → ${cur.php}` });
  }
  const before = Object.fromEntries(components(prev.labels));
  for (const [name, v] of components(cur.labels)) {
    // a label missing before means the label was added, not the component
    if (before[name] && before[name] !== v) out.push({ kind: 'component', text: `${name} ${before[name]} → ${v}` });
  }
  if (out.length === 0 && prev.labels[BASE] && prev.labels[BASE] !== cur.labels[BASE]) {
    out.push({ kind: 'base', text: 'New OS base image' });
  }
  if (out.length === 0) out.push({ kind: 'rebuild', text: 'Rebuilt, no tracked version changed' });
  return out;
}

function fallbackTags(version: string, os: string, variant: Variant) {
  const out = execFileSync(
    resolve(root, 'scripts/tags.sh'),
    [version, String(versions[version]?.stable ?? false), os, variant, latestStable],
    { encoding: 'utf8' },
  );
  return [...new Set(out.split('\n').filter(Boolean))];
}

function image(version: string, os: string, variant: Variant): Image {
  const mine = records
    .filter((r) => r.os === os && r.variant === variant && (variant === 'nginx' || r.version === version))
    .sort((a, b) => a.time.localeCompare(b.time));
  // a rebuild with no tracked change replaces the build before it, which keeps its changes
  const kept: { r: BuildRecord; changes: Change[] }[] = [];
  for (const r of mine) {
    const prev = kept.at(-1);
    const changes = diff(prev?.r, r);
    if (prev && changes.every((c) => c.kind === 'rebuild')) prev.r = r;
    else kept.push({ r, changes });
  }
  const builds: Build[] = kept
    .map(({ r, changes }, i) => ({ ...r, changes, live: i === kept.length - 1, until: kept[i + 1]?.r.time ?? null }))
    .reverse();
  const current = builds[0] ?? null;
  const tags = current?.tags ?? fallbackTags(version, os, variant);
  const repo = variant === 'nginx' ? 'ghcr.io/mintopia/nginx' : 'ghcr.io/mintopia/php';
  const tag = variant === 'nginx' ? os : `${version}-${os}-${variant}`;
  return { id: variant === 'nginx' ? `nginx-${os}` : tag, repo, version, os, variant, stable: versions[version]?.stable ?? true, tag, tags, current, builds };
}

export const images: Image[] = [
  ...versionKeys.flatMap((v) =>
    versions[v].os.flatMap((os) =>
      VARIANTS.filter((t) => t !== 'frankenphp' || versions[v].frankenphp).map((t) => image(v, os, t)),
    ),
  ),
  ...OSES.map((os) => image(latestStable, os, 'nginx')),
];

export interface Commit {
  sha: string;
  time: string;
  subject: string;
}

export const commits: Commit[] = execFileSync('git', ['log', '--no-merges', '--format=%H%x09%cI%x09%s', '-n', '400'], {
  cwd: root,
  encoding: 'utf8',
})
  .split('\n')
  .filter(Boolean)
  .map((l) => {
    const [sha, time, subject] = l.split('\t');
    return { sha, time, subject };
  });

export interface Day {
  date: string;
  changes: { text: string; kind: Change['kind']; images: string[] }[];
  commits: Commit[];
}

// one entry per day; identical changes across images collapse into one line
export const changelog: Day[] = (() => {
  const days = new Map<string, Day>();
  const day = (date: string) => days.get(date) ?? days.set(date, { date, changes: [], commits: [] }).get(date)!;
  for (const img of images) {
    for (const b of img.builds) {
      const d = day(b.time.slice(0, 10));
      for (const c of b.changes) {
        if (c.kind === 'first') continue;
        const hit = d.changes.find((x) => x.text === c.text);
        if (hit) hit.images.push(img.id);
        else d.changes.push({ ...c, images: [img.id] });
      }
    }
  }
  for (const c of commits) day(c.time.slice(0, 10)).commits.push(c);
  return [...days.values()].filter((d) => d.changes.length || d.commits.length).sort((a, b) => b.date.localeCompare(a.date));
})();

export const extensions = [...new Set(versionKeys.flatMap((k) => [...versions[k].extensions, ...Object.keys(versions[k].dropped ?? {})]))].sort();

export function extensionVersion(version: string, ext: string) {
  const byOs = OSES.map((os) => [os, images.find((i) => i.version === version && i.os === os && i.variant === 'cli')?.current?.labels[`net.mintopia.ext.${ext}.version`]] as const)
    .filter((e): e is readonly [(typeof OSES)[number], string] => !!e[1]);
  if (byOs.length === 0) return undefined;
  return new Set(byOs.map(([, v]) => v)).size === 1 ? byOs[0][1] : byOs.map(([os, v]) => `${v} ${os}`).join(' · ');
}

export const repoUrl = 'https://github.com/mintopia/php-base-images';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const fmtDate = (iso: string) => `${+iso.slice(8, 10)} ${MONTHS[+iso.slice(5, 7) - 1]} ${iso.slice(0, 4)}`;
export const fmtTime = (iso: string) => `${fmtDate(iso)} ${iso.slice(11, 16)}`;
export const shortDigest = (d: string) => d.replace('sha256:', '').slice(0, 12);
export const commitUrl = (sha: string) => `${repoUrl}/commit/${sha}`;
export const imagePath = (img: Image) => `${import.meta.env.BASE_URL}images/${img.id}/`;
export const buildPath = (img: Image, b: BuildRecord) => `${imagePath(img)}${shortDigest(b.digest)}/`;
export const runUrl = (run: string) => (/^\d+$/.test(run) ? `${repoUrl}/actions/runs/${run}` : null);

const moduleKey = (m: string) => m.toLowerCase().replace(/^zend /, '');
export const isAddedExtension = (m: string) => extensions.includes(moduleKey(m));

// every compiled-in module per PHP line, from the live cli images; value lists the OSes that have it
export const builtInModules = (() => {
  const out = new Map<string, Map<string, string[]>>();
  for (const img of images) {
    if (img.variant !== 'cli') continue;
    for (const m of img.current?.modules ?? []) {
      if (isAddedExtension(m)) continue;
      const row = out.get(m) ?? out.set(m, new Map()).get(m)!;
      row.set(img.version, [...(row.get(img.version) ?? []), img.os]);
    }
  }
  return [...out.entries()].sort(([a], [b]) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
})();

// README is the single source for configuration docs; the site renders its sections rather than copying them
const readme = readFileSync(resolve(root, 'README.md'), 'utf8');
const LANGS: Record<string, string> = { 'compose.yaml': 'yaml', shell: 'sh', Dockerfile: 'dockerfile', dockerfile: 'dockerfile', sh: 'sh', ini: 'ini', yaml: 'yaml' };
export const highlight = (code: string, lang: string) =>
  codeToHtml(code, { lang: LANGS[lang] ?? 'text', theme: 'github-dark' });

const unescape = (t: string) => t.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');

async function render(md: string) {
  let html = marked.parse(md, { async: false }) as string;
  html = html.replace(/<h(\d)>(.*?)<\/h\1>/g, (_, n, text) =>
    `<h${n} id="${text.replace(/<[^>]+>/g, '').toLowerCase().replace(/[^a-z0-9 -]/g, '').replace(/ /g, '-')}">${text}</h${n}>`);
  const blocks = [...html.matchAll(/<pre><code(?: class="language-(\w+)")?>([\s\S]*?)<\/code><\/pre>/g)];
  for (const [whole, lang = 'text', body] of blocks) html = html.replace(whole, await highlight(unescape(body).replace(/\n$/, ''), lang));
  return html;
}

export function readmeSection(from: string, to: string) {
  const start = readme.indexOf(`\n${from}\n`);
  const end = readme.indexOf(`\n${to}\n`, start + 1);
  return render(readme.slice(start, end === -1 ? undefined : end).replace(/^(#+) /gm, '$1# '));
}

// a single README table, found by the start of its header row
export function readmeTable(header: string) {
  const start = readme.indexOf(`\n${header}`);
  const end = readme.indexOf('\n\n', start + 1);
  return render(readme.slice(start, end));
}
