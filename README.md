# Zhang Recipes

A recipe site built with [Hakyll](https://jaspervdj.be/hakyll/) and
[hakyll-flint](https://github.com/brnzhg/hakyll-flint), deployed to GitHub
Pages.

## Recipes

Each recipe is a Markdown file in `recipes/`. Its file name is the title:

```markdown
---
type: recipe
protein: chicken          # one value; gets a page at protein/chicken.html
category: [entree, meal prep]   # any number; category/<value>.html
servings: 4
source: [https://example.com/original]
---
# Ingredients
- ...
# Instructions
- ...
```

Recipes are written in Obsidian and copied in with:

```sh
scripts/import-recipes.sh <path to the vault's Reference/Recipes>
git diff --stat   # review what changed before committing
```

Markdown is read as CommonMark, the same as Obsidian renders it.

## Building

The toolchain is ghcup's recommended GHC 9.10.3 and cabal 3.16.

```sh
cabal run site -- watch     # preview at http://localhost:8000
cabal run site -- build     # writes _site/
```

Every push to `main` builds the site and deploys it to GitHub Pages
(`.github/workflows/deploy.yml`). The first deploy takes about 15 minutes
while dependencies compile. After that the cabal store is cached, and a
deploy takes a minute or two.

hakyll-flint is pinned to a commit in `cabal.project`. To work on the library
and the site together, create a `cabal.project.local` (git-ignored)
containing `packages: ../hakyll-flint`.
