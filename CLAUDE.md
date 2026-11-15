# zhang-recipes

A family recipe site built with Hakyll and
[hakyll-flint](https://github.com/brnzhg/hakyll-flint). It deploys to
GitHub Pages on every push to `main`. The README covers the front-matter
fields for recipes and user pages.

## Commands

```sh
cabal build
cabal run site -- build     # writes _site/
cabal run site -- watch     # preview at http://localhost:8000
```

## Layout

- `Site.hs`: all the rules.
- `recipes/*.md`: one recipe per file. The file name is the title.
- `users/*.md`: one homepage per person. A user's file name must match the
  slug of their `recipe-contributor` value (`kevin.md` ↔ `Kevin`).
- `templates/`, `css/default.css`: the fantasy-RPG theme. `images/` and
  `favicon.ico` hold the crest site icon, copied as is.
- `css/palette.css` is generated and not in the repo. It sets the
  protein and person colours.

## Conventions

- **Fail on bad data in `Rules`.** Check user-editable data (favorites,
  tag-sections, gems, `added` dates) in `Rules`, before templates run, and
  fail with a message naming the file. Inside a template, `$if(...)$`
  swallows errors and silently hides the content.
- **Listings use `$if$`.** List fields are absent when empty (see
  `nonEmptyListField`), so templates wrap `$for$` in `$if$`. `$for$` over a
  missing field is an error.
- **Markdown is CommonMark.** It's read as CommonMark (`commonmark_x`), the
  same as Obsidian renders it. Bold under `# Ingredients` means "fresh,
  probably need to buy".
- **Library pin.** hakyll-flint is pinned by commit in `cabal.project`. To
  change the library alongside the site, use a git-ignored
  `cabal.project.local` with `packages: ../hakyll-flint`.

## Gotchas

- **Stale `watch` processes.** A running `watch` keeps the code it started
  with, and it shares `_cache` with any other run. Restart it after
  changing `Site.hs`, and don't run `build` while it runs: the watcher
  takes the change first, and `build` then appears to ignore edits.
- **The `setup.Cabal` pin.** `cabal.project` pins it so `cabal build` and
  HLS share one build of pandoc.
- **First build is slow.** The first CI deploy takes about 20 minutes. After
  that the cabal store is cached and a deploy takes 3–4 minutes.
