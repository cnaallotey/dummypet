# DummyPet 🐶

A dog that lives on your Mac screen. It walks along the top of your Dock, naps, digs, chases
butterflies, and gets bored if you ignore it. Everything is drawn in code (no image or sound files),
and the app runs from the menu bar (🐶).

## Build & run

Needs only the Xcode Command Line Tools (Swift 5.8+), macOS 12+.

```bash
./build.sh run
```

This makes a universal `build/DummyPet.app`. Drag it to `/Applications` to keep it.

## Installer

```bash
./make-dmg.sh --rebuild
```

This builds `build/DummyPet-<version>.dmg`, a drag-to-Applications disk image with custom background
art drawn by the app's own renderer. It also copies the DMG and icon into `website/` and updates the
file size shown on the download page. The first run asks to let your terminal control Finder (that's
how the window layout gets set).

The app is ad-hoc signed, not notarized, so first launch on another Mac shows a Gatekeeper warning
(the download page explains how to get past it). To remove the warning you need an Apple Developer ID
($99/year), then sign with `codesign --sign "Developer ID Application: …" --options runtime` and
notarize with `xcrun notarytool submit DummyPet-1.0.dmg --wait` followed by `xcrun stapler staple`.

## Website

`website/` is a static site (no build step) with a live, playable port of the dog in `dog.js`.
Preview it with:

```bash
python3 -m http.server 4173 --directory website
```

It's hosted on Cloudflare (a static-assets Worker configured in `wrangler.jsonc`) at
https://dummypet.charlesallotey1995.workers.dev. To publish changes, including a new DMG:

```bash
./make-dmg.sh && npx wrangler@4 deploy
```

The download buttons point at `downloads/DummyPet.dmg`, and `website/_headers` makes it download as a file.

## Playing

| Do this | And your dog… |
| --- | --- |
| Rub the cursor over it | gets hearts. Keep going and it rolls over for belly rubs |
| Click / double-click | gets a pat / barks |
| Drag it | dangles and wiggles. Toss it and it lands with a "Wheee!" |
| **Play Fetch** | the ball sticks to your cursor. Flick and click to throw; it brings the ball back to you |
| **Give a Treat** | begs if you hold it low, leaps for mid-air catches if you toss it |
| **Go for a Walk** | a leash runs from the collar to your cursor, flowers pop up, it sniffs around, and steps get counted |
| **Laser Pointer** | it goes nuts chasing a red dot on your cursor |
| **Feed** | runs to the bowl and crunches away (and may need a potty break later 💩, which you click to scoop) |
| **Bath Time** | gets sudsy (rub to scrub faster), then shakes water everywhere |
| **Tricks** | Sit, Speak, Beg, Spin, High Five, Roll Over, Play Dead, Backflip. These unlock as your Bond level goes up |

Hover over the dog to see its Food / Fun / Energy / Clean meters. Stats save automatically and
drift slowly while the app is closed (gently: it never gets hurt). Change breed, size, and name
under **Appearance**.

## Social and press images

```bash
./press/render.sh            # OG image, square post, Product Hunt gallery (headless Chrome, a few minutes)
./press/render-thumbnail.sh  # animated 240×240 Product Hunt thumbnail
```

The cards are plain HTML in `press/cards.html` using the site's fonts, WebGL sky, and dog renderer.
Output lands in `website/assets/` (OG and square images) and `press/producthunt/`, which also holds
`LAUNCH.md` with the listing copy and maker comment. SEO tags, `robots.txt`, `sitemap.xml`, and the
JSON-LD in `index.html` use the workers.dev URL; update them if you add a custom domain.

## Code map

- `Sources/World.swift`: the brain (behavior state machine, physics, stats, input, drawing order)
- `Sources/Renderer.swift`: procedural dog skeleton and props drawn with CoreGraphics
- `Sources/Model.swift`: poses, breeds, entities
- `Sources/Sound.swift`: tiny synth that generates barks, crunches, and squeaks at launch
- `Sources/App.swift`: click-through overlay window, menu bar, and menus
