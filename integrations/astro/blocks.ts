/**
 * Helpers for rendering the CMS's `blocks: CmsBlock[]` array into a
 * page. The CMS doesn't return HTML — every block is `{ type, version,
 * data }`, and it's the consumer's job to map `type` → component.
 *
 * Recommended pattern: define your component map alongside your
 * components and pass it in. No global registry — keeps each page
 * self-contained.
 *
 *   // src/pages/[...slug].astro
 *   ---
 *   import Hero from "~/components/blocks/Hero.astro";
 *   import Prose from "~/components/blocks/Prose.astro";
 *   import { cms } from "~/lib/cms/cms";
 *   import { resolveBlocks } from "~/lib/cms/blocks";
 *
 *   const page = await cms.pages.get(Astro.params.slug ?? "home");
 *   const blocks = resolveBlocks(page.blocks, {
 *     hero:  Hero,
 *     prose: Prose,
 *   });
 *   ---
 *   {blocks.map(({ Component, data }) => <Component {...data} />)}
 */

import type { CmsBlock } from "./types";

/**
 * Pair each block with the matching component (or `null` if the type
 * isn't in the map). Skips unknown blocks rather than throwing — that
 * way a CMS editor can preview a new block type before the consumer
 * has shipped a renderer for it.
 */
export function resolveBlocks<C>(
  blocks: CmsBlock[] | undefined,
  componentMap: Record<string, C>,
): { Component: C; data: Record<string, unknown>; block: CmsBlock }[] {
  if (!blocks) return [];

  return blocks.flatMap((block) => {
    const Component = componentMap[block.type];
    if (!Component) {
      if (typeof console !== "undefined") {
        console.warn(`[cms-blocks] no component registered for type "${block.type}"`);
      }
      return [];
    }
    return [{ Component, data: { ...block.data, _resolved: block.resolved }, block }];
  });
}

/**
 * Narrow a block to a specific type. Useful when you're treating a
 * single block independently rather than walking the whole page.
 *
 *   if (isBlockOfType(block, "hero")) {
 *     // block.data is now narrowed if you give it a type parameter
 *   }
 */
export function isBlockOfType<T extends string>(
  block: CmsBlock | undefined | null,
  type: T,
): block is CmsBlock & { type: T } {
  return !!block && block.type === type;
}
