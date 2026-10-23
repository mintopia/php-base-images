---
version: 1
slug: "site-src-pages-images-id-index-astro"
primary_target: "site/src/pages/images/[id]/index.astro"
related_targets: ["site/src/pages/images","site/src/pages/matrix","site/src/pages/changelog"]
---

# Surface: image site (image pages with picker, matrix, changelog)

Mode: Operate (builder, images) with Read pages (matrix, changelog). Code-led.
Audience/job: developers resolving a PHP base image to an exact, pinnable reference and tracing what changed between builds.
Constraints: all data derived from versions.json, scripts/tags.sh and site-data records; Astro static on GitHub Pages; dark only, by the user's choice: no light theme and no switcher.

## Direction contract

THESIS: The image catalogue as a railway timetable: every PHP version is a coloured line, every build a departure row. Refuses the docs-sidebar-plus-code-block page.
OWN-WORLD: White (or near-black in dark) ground, quiet neutral header with ink type, grey selection board. Line colours belong only to PHP versions: 8.2 violet, 8.3 teal, 8.4 orange, 8.5 blue, 8.6 RC amber drawn dashed. Green dot = live, hollow = superseded. Hanken Grotesk UI, JetBrains Mono for tags, digests, versions.
STORY: Visitor picks a line, OS, variant, arch; reads the reference large; copies it; sees the timetable of builds and what is on board; follows to matrix or changelog.
FIRST VIEWPORT: Neutral header with brand and nav. Grey board: line bullets for PHP, segmented OS / variant / arch. Destination row: line bullet + tag at ~52px mono + Copy button right. Alias chips beneath. Below: builds timetable (left) and on-board facts (right). Signature move: the selected line's colour becomes the page accent (focus rings, copy button, timetable current marker, selection highlight).
FORM: Station Timetable, my top grounded candidate (rank 1), steered by the user: add colour, drop red header, add dark mode. seed: none (unavailable)
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
