import type { Image, BuildRecord } from './data';
export type { Image, Build } from './data';

// repo:tag@digest; the tag is the one this build was published under
export const pinRef = (img: Image, b: BuildRecord) => `${img.repo}:${img.tag}@${b.digest}`;
