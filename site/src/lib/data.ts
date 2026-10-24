import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { marked } from 'marked';

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
  package?: string;
  platforms: Record<string, string>;
  tags: string[];
  modules?: string[];
  sizes?: Record<string, number>;
  labels: Record<string, string>;
}

export interface Change {
  kind: 'php' | 'component' | 'base' | 'rebuild' | 'first';
  text: string;
}

export interface Cve {
  id: string;
  severity: string;
  pkg: string;
  fixed: string;
  url?: string;
}

export interface Build extends BuildRecord {
  changes: Change[];
  cves: Cve[] | null;
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
  patch: string | null;
  parent: Image | null;
  previous: Image | null;
  tags: string[];
  current: Build | null;
  builds: Build[];
}

export const versions: Record<string, VersionEntry> = JSON.parse(
  readFileSync(resolve(root, 'versions.json'), 'utf8'),
).variable.VERSIONS.default;

export const byVersion = (a: string, b: string) => a.localeCompare(b, undefined, { numeric: true });
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

// written by scripts/scan-cves.sh on each site build; absent when the scan failed
const cvesFile = process.env.SITE_CVES ?? resolve(root, '.site-data/cves.json');
const scans: { scanned?: string; php?: { id: string; url: string; severity: string; fixed: string[] }[]; builds: Record<string, Cve[]> } =
  existsSync(cvesFile) ? JSON.parse(readFileSync(cvesFile, 'utf8')) : { builds: {} };
export const scannedAt = scans.scanned ?? null;

export const criticals = (b: { cves: Cve[] | null }) => b.cves?.filter((c) => c.severity === 'CRITICAL').length ?? 0;
export const SEVERITIES = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNKNOWN'];

// php-src advisories name a fixed X.Y.Z per minor; earlier patches of that minor are affected
function cves(r: BuildRecord): Cve[] | null {
  if (!scannedAt) return null;
  const minor = r.php.split('.').slice(0, 2).join('.');
  const php = r.variant === 'nginx' ? [] : (scans.php ?? []).flatMap((a) => {
    const fixed = a.fixed.find((f) => f.startsWith(`${minor}.`));
    return fixed && byVersion(r.php, fixed) < 0 ? [{ id: a.id, url: a.url, severity: a.severity, pkg: 'php', fixed }] : [];
  });
  return [...new Map([...php, ...(scans.builds[r.digest] ?? [])].map((c) => [c.id, c])).values()].sort((a, b) => SEVERITIES.indexOf(a.severity) - SEVERITIES.indexOf(b.severity));
}

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
  if (prev.modules?.length && cur.modules?.length) {
    for (const m of prev.modules) if (!cur.modules.includes(m)) out.push({ kind: 'component', text: `${m} removed` });
    for (const m of cur.modules) if (!prev.modules.includes(m)) out.push({ kind: 'component', text: `${m} added` });
  }
  if (out.length === 0 && prev.labels[BASE] && prev.labels[BASE] !== cur.labels[BASE]) {
    const name = cur.labels['org.opencontainers.image.base.name']?.replace('docker.io/library/', '');
    out.push({ kind: 'base', text: name ? `${name} base image updated` : 'New OS base image' });
  }
  if (out.length === 0) out.push({ kind: 'rebuild', text: cur.variant === 'nginx' ? 'Rebuilt with the same versions' : 'Rebuilt with the same PHP and extension versions' });
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

// rebuilds that changed nothing tracked are hidden unless the tags still point at them
function history(mine: { r: BuildRecord; changes: Change[] }[]): Build[] {
  const kept = mine.filter(({ changes }, i) => i === mine.length - 1 || changes.some((c) => c.kind !== 'rebuild'));
  return kept
    .map(({ r, changes }, i) => ({ ...r, changes, cves: cves(r), live: i === kept.length - 1, until: kept[i + 1]?.r.time ?? null }))
    .reverse();
}

const PATCH = /^\d+\.\d+\.\d+$/;

// the minor's page holds the current patch; each older X.Y.Z gets its own page, chained via previous
function image(version: string, os: string, variant: Variant): Image {
  const nginx = variant === 'nginx';
  const all = records
    .filter((r) => r.os === os && r.variant === variant && (nginx || r.version === version || r.version.startsWith(`${version}.`)))
    .sort((a, b) => a.time.localeCompare(b.time));
  // patch lanes interleave, so a build compares with its own patch, else the minor's previous build
  const diffed = all.map((r, i) => {
    const before = all.slice(0, i);
    const prev = before.findLast((p) => p.php === r.php && PATCH.test(r.php)) ?? before.findLast((p) => p.version === r.version);
    return { r, changes: diff(prev, r) };
  });
  const lane = all.filter((r) => r.version === version);
  const live = nginx ? '' : lane.at(-1)?.php ?? '';
  const older = (r: BuildRecord) => !nginx && PATCH.test(r.php) && r.php !== live;
  const builds = history(diffed.filter(({ r }) => !older(r)));
  const current = builds[0] ?? null;
  const repo = nginx ? 'ghcr.io/mintopia/nginx' : 'ghcr.io/mintopia/php';
  const tag = nginx ? os : `${version}-${os}-${variant}`;
  const stable = versions[version]?.stable ?? true;
  const img: Image = {
    id: nginx ? `nginx-${os}` : tag, repo, version, os, variant, stable, tag, patch: PATCH.test(live) ? live : null, parent: null, previous: null,
    tags: current?.tags ?? fallbackTags(version, os, variant), current, builds,
  };
  let prev = img;
  for (const php of [...new Set(diffed.filter(({ r }) => older(r)).map(({ r }) => r.php))].sort(byVersion).reverse()) {
    const b = history(diffed.filter(({ r }) => r.php === php));
    const ptag = `${php}-${os}-${variant}`;
    // a build of the then-current patch also carried minor tags that have since moved
    const tags = b[0].tags.filter((t) => t === php || t.startsWith(`${php}-`));
    prev = prev.previous = { ...img, id: ptag, tag: ptag, patch: php, parent: img, previous: null, tags, current: b[0], builds: b };
  }
  return img;
}

export const images: Image[] = [
  ...versionKeys.flatMap((v) =>
    versions[v].os.flatMap((os) =>
      VARIANTS.filter((t) => t !== 'frankenphp' || versions[v].frankenphp).map((t) => image(v, os, t)),
    ),
  ),
  ...OSES.map((os) => image(latestStable, os, 'nginx')),
];

export const chain = (img: Image) => {
  const out: Image[] = [];
  for (let i: Image | null = img; i; i = i.previous) out.push(i);
  return out;
};
// every image page: the minor images plus their older patches
export const pages = images.flatMap(chain);

export interface Commit {
  sha: string;
  time: string;
  subject: string;
}

// igbinary was never in a listed build (ADR 0017); null hides the commit
const SUBJECTS: Record<string, string | null> = {
  a146abfa53b6ed9ce061cce326fc2a41ac4146b7: null,
  '601b64058c81c6d1f1d07d0fdb7316780be0edc6': null,
  'cccaa5ca6a3883cfa0cbe286febe426972e9e593': null,
  '0d91d6e2482ee4e71ad708b30c950a20c5e11a55': 'Bundle intl, zip, exif, sockets, gmp, soap and apcu so common frameworks run without a compiler stage',
};

export const commits: Commit[] = execFileSync('git', ['log', '--no-merges', '--format=%H%x09%cI%x09%s', '-n', '400'], {
  cwd: root,
  encoding: 'utf8',
})
  .split('\n')
  .filter(Boolean)
  .map((l) => {
    const [sha, time, subject] = l.split('\t');
    return { sha, time, subject: sha in SUBJECTS ? SUBJECTS[sha] : subject };
  })
  .filter((c): c is Commit => c.subject !== null);

export interface Day {
  date: string;
  changes: { text: string; kind: Change['kind']; images: string[] }[];
  commits: Commit[];
}

// the registry was reset by the rebuild started at this time; earlier records and commits stay off the changelog
const CHANGELOG_SINCE = Date.parse('2026-10-24T17:43:00Z');

// one entry per day; identical changes across images collapse into one line
export const changelog: Day[] = (() => {
  const days = new Map<string, Day>();
  const day = (date: string) => days.get(date) ?? days.set(date, { date, changes: [], commits: [] }).get(date)!;
  for (const img of pages) {
    for (const b of img.builds) {
      if (Date.parse(b.time) < CHANGELOG_SINCE) continue;
      const d = day(b.time.slice(0, 10));
      for (const c of b.changes) {
        const hit = d.changes.find((x) => x.text === c.text);
        if (hit) hit.images.push(img.id);
        else d.changes.push({ ...c, images: [img.id] });
      }
    }
  }
  for (const c of commits.filter((c) => Date.parse(c.time) >= CHANGELOG_SINCE)) day(c.time.slice(0, 10)).commits.push(c);
  return [...days.values()].filter((d) => d.changes.length || d.commits.length).sort((a, b) => b.date.localeCompare(a.date));
})();

export const extensions = [...new Set(versionKeys.flatMap((k) => [...versions[k].extensions, ...Object.keys(versions[k].dropped ?? {})]))].sort();

export function extensionVersion(version: string, ext: string) {
  const byOs = OSES.map((os) => [os, images.find((i) => i.version === version && i.os === os && i.variant === 'cli')?.current?.labels[`net.mintopia.ext.${ext}.version`]] as const)
    .filter((e): e is readonly [(typeof OSES)[number], string] => !!e[1]);
  if (byOs.length === 0) return undefined;
  return new Set(byOs.map(([, v]) => v)).size === 1 ? byOs[0][1] : byOs.map(([os, v]) => `${v} ${os}`).join(' · ');
}

export const siteBuilt = new Date().toISOString();
export const repoUrl = 'https://github.com/mintopia/php-base-images';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const fmtDate = (iso: string) => `${+iso.slice(8, 10)} ${MONTHS[+iso.slice(5, 7) - 1]} ${iso.slice(0, 4)}`;
export const fmtTime = (iso: string) => `${fmtDate(iso)} ${iso.slice(11, 16)}`;
export const fmtSeverity = (s: string) => s === 'UNKNOWN' ? 'Unrated' : s.charAt(0) + s.slice(1).toLowerCase();
export const fmtSize = (bytes: number) => `${(bytes / 1e6).toFixed(1)} MB`;
export const shortDigest = (d: string) => d.replace('sha256:', '').slice(0, 12);
export const packageUrl = (repo: string, id?: string) => `${repoUrl}/pkgs/container/${repo.split('/').pop()}${id ? `/${id}` : ''}`;
export const commitUrl = (sha: string) => `${repoUrl}/commit/${sha}`;
export const imageName = (img: Image) => (img.variant === 'nginx' ? `nginx:${img.tag}` : img.tag);
// registry path shown above imageName in headings
export const imageHost = (img: Image) => (img.variant === 'nginx' ? img.repo.replace(/\/nginx$/, '') : img.repo);
export const imagePath = (img: Image) => `${import.meta.env.BASE_URL}images/${img.id}/`;
export const buildPath = (img: Image, b: BuildRecord) => `${imagePath(img)}${shortDigest(b.digest)}/`;
export const pinRef = (img: Image, b: BuildRecord) => `${img.repo}:${img.tag}@${b.digest}`;
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
// a single README table, found by the start of its header row
export function readmeTable(header: string) {
  const start = readme.indexOf(`\n${header}`);
  const end = readme.indexOf('\n\n', start + 1);
  return marked.parse(readme.slice(start, end), { async: false }) as string;
}
