---
name: mintopia/php
description: PHP base image catalogue drawn as a railway timetable; every PHP version is a coloured line, every build a departure row.
colors:
  line-82-violet: "#6e4bc8"
  line-83-teal: "#00796f"
  line-84-orange: "#b8580c"
  line-85-blue: "#0a64c8"
  line-86-amber: "#e8b100"
  live-green: "#2fbf6a"
  sev-critical: "#e5484d"
  sev-high: "#f0898c"
  sev-medium: "#c7a3a5"
  sev-low: "#7d8087"
  ground: "#0f1113"
  board: "#17191c"
  raise: "#1d2024"
  ink: "#e9eaec"
  muted: "#a0a3a9"
  rule: "#2a2d31"
  control: "#3a3e44"
typography:
  display:
    fontFamily: "JetBrains Mono, ui-monospace, monospace"
    fontSize: "clamp(28px, 4.2vw, 52px)"
    fontWeight: 500
    lineHeight: 1.05
    letterSpacing: "-0.03em"
  headline:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "clamp(28px, 4vw, 40px)"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.03em"
  title:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 700
    letterSpacing: "0.08em"
  body:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  mono:
    fontFamily: "JetBrains Mono, ui-monospace, monospace"
    fontSize: "13px"
    fontWeight: 500
    fontFeature: "tnum"
rounded:
  chip: "4px"
  bullet: "5px"
  control: "6px"
  bullet-lg: "10px"
  dot: "50%"
spacing:
  gutter: "clamp(16px, 6vw, 120px)"
  row: "10px"
  cell: "14px"
  section: "44px"
  column-gap: "64px"
components:
  line-bullet:
    backgroundColor: "{colors.line-85-blue}"
    textColor: "#ffffff"
    typography: "{typography.mono}"
    rounded: "{rounded.bullet}"
    padding: "0 8px"
    height: "26px"
  line-bullet-rc:
    backgroundColor: "{colors.line-86-amber}"
    textColor: "{colors.ink}"
    rounded: "{rounded.bullet}"
    height: "26px"
  line-bullet-lg:
    rounded: "{rounded.bullet-lg}"
    size: "72px"
  segmented-option:
    backgroundColor: "{colors.raise}"
    textColor: "{colors.muted}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "38px"
  segmented-option-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
  button:
    backgroundColor: "{colors.raise}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 16px"
    height: "40px"
  button-primary:
    backgroundColor: "{colors.line-85-blue}"
    textColor: "#ffffff"
    rounded: "{rounded.control}"
    padding: "0 16px"
    height: "44px"
  chip:
    backgroundColor: "{colors.raise}"
    textColor: "{colors.ink}"
    typography: "{typography.mono}"
    rounded: "{rounded.chip}"
    padding: "2px 8px"
---

# Design System: mintopia/php

## Overview

**Creative North Star: "The Station Timetable"**

The site is a departures board for container images. Each PHP minor is a transit line with its own colour; each published build is a departure row in a timetable; the image reference is the destination, set large in monospace. The ground is near-black, the header is quiet neutral ink, and the only saturated colour on any page belongs to a PHP line. Everything else is ink, grey and hairline rules.

Density is operational, not editorial: tables, definition lists and segmented controls carry the content, separated by 1px rules rather than cards. The grey board is the one tonal surface, used for the home hero, the image picker and the destination band. Depth is flat throughout.

The signature move: on an image page (and the home hero), the selected line's colour becomes the page accent. Focus rings, the primary Copy button, the live-row marker in the timetable and text selection all repaint to the chosen PHP version.

**Key Characteristics:**
- Line colours belong to PHP versions only; nothing else is coloured.
- Selected line becomes the accent (image pages and home hero).
- Hanken Grotesk for interface; JetBrains Mono only for tags, digests, versions and other machine strings.
- Flat surfaces, hairline rules, one grey board.
- Dark only. There is no light theme and no theme switcher, by the user's choice.

## Colors

A neutral ink-on-near-black system with five transit-line colours reserved for PHP versions and one green for live status.

### Primary (line colours)
- **8.2 Violet** (line-82-violet): PHP 8.2 bullets, chips, matrix underlines and accent when selected.
- **8.3 Teal** (line-83-teal): PHP 8.3.
- **8.4 Orange** (line-84-orange): PHP 8.4.
- **8.5 Blue** (line-85-blue): PHP 8.5, the latest stable. Also the site-wide default `--accent` outside image pages.
- **8.6 RC Amber** (line-86-amber): PHP 8.6 release candidate. Amber with dark ink text and a dashed inset outline, marking it as provisional. Too light for white text, so the primary button keeps amber fill with dark ink text when 8.6 is selected; the amber itself serves as the accent on the dark ground.

Line colours are mid-luminance so they hold on the dark ground. Lines are applied by `data-line="8.x"` setting `--line`; components read `var(--line)`.

### Secondary
- **Live Green** (live-green): the status dot for the build currently served by a tag. Never used for anything else.
- **Severity reds** (sev-critical, sev-high, sev-medium, sev-low): CVE severity dots and the critical-CVE alert only. A ramp from red to grey so critical reads loudest; Unrated is a hollow muted ring. Never used for anything but vulnerability status.

### Neutral
- **Ground** (ground): page background.
- **Board** (board): the home hero, the image picker and the destination band.
- **Raise** (raise): fill for buttons, segmented controls and chips.
- **Ink** (ink): text, table header rule, selected segment fill, nav underline, nginx bullet fill.
- **Muted** (muted): secondary text, legends, `dt` labels, superseded status.
- **Rule** (rule): 1px row dividers, header/footer borders, chip borders.
- **Control** (control): borders of interactive controls and disabled segment text.

### Named Rules
**The Lines Only Rule.** Saturated colour belongs only to PHP versions (8.2 violet, 8.3 teal, 8.4 orange, 8.5 blue, 8.6 amber) plus the two status exceptions: live green and the CVE severity reds. Variants, OSes, architectures and nginx are ink. Never introduce a colour for anything that is not a PHP line.

**The Selected Line Is The Accent Rule.** On image and build pages and in the home hero, `--accent` equals the selected `--line`. Focus outlines, the primary button, the timetable's live-row inset marker and `::selection` follow it. On nginx pages (no PHP line) the line falls back to ink.

**The Dashed RC Rule.** A release candidate line is drawn amber with a 1.5px dashed inset outline in dark ink and dark ink text. Stable lines are solid with white text.

## Typography

**UI Font:** Hanken Grotesk (with system-ui, sans-serif), weights 400/500/700
**Mono Font:** JetBrains Mono (with ui-monospace, monospace), weights 400/500/700, tabular numerals

**Character:** A plain, legible grotesk for the interface, with a technical mono reserved for strings a developer will copy or compare.

### Hierarchy
- **Display** (JetBrains Mono 500, clamp(28px, 4.2vw, 52px), 1.05, -0.03em): the image tag on image and build pages and the reference in the home hero. The repo name sits above it at 14px mono, muted.
- **Hero** (Hanken 700, clamp(40px, 6vw, 80px), 1, -0.03em): the home page's plain "PHP base images" title. No slogans; lede below at 18px muted.
- **Headline** (Hanken 700, clamp(28px, 4vw, 40px), 1.1, -0.03em): page titles on Images, Matrix, Usage, Changelog; lede below at 16px muted, never capped to a narrow measure.
- **Title** (Hanken 700, 13px, uppercase, 0.08em): section headings (`h2`) such as "Use it", "Every build", "On board now".
- **Body** (Hanken 400, 15px, 1.55): default text. Tables and lists step down to 13-14px.
- **Label** (Hanken 500, 12px, muted): table headers and picker legends.
- **Mono** (JetBrains Mono 500, 13px, tnum): tags, digests, versions, timestamps, commit hashes, chip text, bullets (700).

### Named Rules
**The Machine Strings Rule.** JetBrains Mono is for things a machine reads: image tags, digests, version numbers, build timestamps, commit hashes. Prose, labels, navigation and button text stay in Hanken Grotesk.

## Layout

Full-bleed bands with a fluid side gutter (`clamp(16px, 6vw, 120px)`); no centred max-width container. Header is 64px with brand, nav and a bottom hairline. Pages use 48px top / 96px bottom padding.

Home: one grey hero board, at least 72svh tall (capped at 720px) with content centred vertically: title, lede, PHP line picker, the reference at display size with the primary Copy button pushed right. Below it, three one-line fact rows (muted label, value) and links onward. Nothing else.

Image pages: the grey picker board (Image, PHP, OS, Variant in a wrapping flex row, 24px/40px gaps) flowing into the grey destination band (bullet, mono tag, Copy button pushed right, alias chips below), then a two-column detail grid (fluid main + 300px aside, 64px gap) holding "Use it" (reference row, Dockerfile and compose examples) and the timetable on the left and the on-board facts on the right. Build pages share the band and grid, with the pinned reference in "Use it". `/images/` is the picker board alone with a short page head, nothing selected. Section headings after the first get 44px top margin.

Rows are rhythm: 10px vertical padding for definition rows, 14px for table cells, 1px rule between.

Breakpoints: 960px collapses the detail grid to one column; 720px wraps the header nav to its own scrolling row; 560px stacks reference rows, wraps segmented controls, hides digest/commit columns and shrinks the large bullet to 52px.

## Elevation & Depth

Flat. No drop shadows anywhere. Depth comes from the single tonal step from ground to board, and from rules: 1px `rule` between rows, 2px `ink` under table headers and above the first changelog day. Ring shadows (`0 0 0 2px board, 0 0 0 4px ink|accent`) appear only as selection and focus indicators on line bullets in the picker (current image, or focus); the timetable's live row uses a 3px inset left bar in the accent.

### Named Rules
**The Hairline Not Card Rule.** Group content with rules and spacing, never with shadowed cards.

## Shapes

Small, consistent radii: 4px for chips, 5px for bullets, 6px for buttons and segmented controls, 10px for the large destination bullet. Status dots and matrix dots are circles. Segmented controls clip their children into one rounded pill with 1px internal dividers. The brand mark is five 4px-wide rounded bars in the five line colours.

## Components

### Line Bullet
The signature mark: a rounded mono label filled with the PHP line colour, like a transit route bullet.
- **Shape:** 5px radius, min 44x26px; `lg` 72x72px at 10px radius (52px under 560px); `sm` 36x20px at 4px radius.
- **Colour:** `var(--line)` fill, white 700 mono text. 8.6 is amber with dark ink text and a dashed inset outline. nginx uses an ink-filled bullet with ground text.
- **Picker state:** in the picker and home hero, bullets render at 60x40px (matching the segmented controls' outer height), 50% opacity at rest, 85% on hover, full with a 2px board + 2px ink ring when current, accent ring on keyboard focus. Lines not built for the current choice drop to 20% and are not links. With nothing selected (`/images/`) every bullet is full strength.

### Segmented Control
- **Style:** inline row in a 1px `control` border, 6px radius, `raise` fill, 38px tall, 14px horizontal padding, 500 14px UI text in muted.
- **State:** hover to ink text; selected fills ink with ground text; keyboard focus draws an inset accent outline; disabled options are control-coloured and struck through.
- Used for Image (php / nginx), OS and variant. In the picker each option is a link to that image's page (`aria-current` marks the current one); options with no image are struck-through spans. The home hero uses native radios.

### Buttons and Copy
- **Default:** 40px, 6px radius, 1px control border, raise fill, ink text, 16px copy icon; hover darkens the border to ink.
- **Primary:** accent fill and border, white text; hover brightens (1.08). On image pages and the home hero it is 44px and follows the selected line.
- **Copy:** button carrying `data-copy`; on click it writes to the clipboard and its label reads "Copied" for 1.4s. Compact 32px in reference rows and tables.

### Chip
- **Style:** mono 500 12px, 2px 8px padding, 1px rule border, 4px radius, raise fill. Used for alias tags and component version changes.
- **Variant:** `php` chip takes the line colour as its border.

### Status Dot
- **Live:** 9px filled circle in live green before 13px 500 label.
- **Superseded:** hollow 1.5px muted ring, muted label.

### Timetable
The build history table. Headers 12px muted over a 2px ink rule; rows separated by 1px rules; times, PHP versions, digests and commits in mono. PHP changes show a small line bullet; component changes show chips. The live row carries a 3px inset accent bar at its left edge. Every published build gets a row; rebuilds with no tracked change (not the live build) are dimmed to 50% opacity, full on hover. Base-image refreshes read "alpine:3.24 base image updated" and stay at full strength.

### Facts List
"On board" definition list: label left in muted UI text, value right in 500 13px mono, 10px rows divided by 1px rules. Includes compressed size per architecture when recorded.

### Code Example
Figure with a board-filled caption bar (file name in 12px mono, compact Copy button) over a Shiki block on `raise`, 1px rule border, 10px radius. On image and build pages a Dockerfile extending the image and a compose file using it directly, chosen per variant.

### Navigation
Header nav (Images, Matrix, Usage, Changelog; the brand links home) is 14px 500 muted, with ink text on hover; the current page is ink with a 2px ink underline sitting on the header's bottom rule. Under 720px it becomes a horizontally scrolling row.

## Do's and Don'ts

### Do:
- **Do** set `data-line="8.x"` on any element that represents a PHP version and read `var(--line)`; never hardcode a line hex in a component.
- **Do** let the selected line drive `--accent` on image pages and the home hero, and fall back to ink when no PHP line applies.
- **Do** draw 8.6 (and any future RC) amber with a dashed inset outline and dark ink text.
- **Do** set tags, digests, versions, timestamps and commit hashes in JetBrains Mono with tabular numerals.
- **Do** separate rows with 1px rules and keep surfaces flat.
- **Do** keep text accents on `--accent-text`, the line colour mixed 55% with white, so violet and blue stay readable on the dark ground; bullets and fills use the raw line colour.

### Don't:
- **Don't** give colour to OSes, variants, architectures or nginx; they stay ink.
- **Don't** treat nginx as a variant; it is its own Image choice with only an OS.
- **Don't** add slogans, maps or feature grids to the home page; keep it to the hero and three facts.
- **Don't** use green for anything but the live status dot.
- **Don't** use mono for prose, labels or buttons.
- **Don't** put white text on 8.6 amber; use dark ink text.
- **Don't** add drop shadows or card containers.
