# Zhang Recipes

A family recipe site, live at https://brnzhg.github.io/zhang-recipes/.
It's built with [Hakyll](https://jaspervdj.be/hakyll/) and
[hakyll-flint](https://github.com/brnzhg/hakyll-flint).

## Adding a recipe

Add a Markdown file to `recipes/`. The file name is the title:

```markdown
---
protein: chicken              # one value; gets a page at protein/chicken.html
recipe-tag: [entree, meal prep]   # any number; each gets a page under tag/
recipe-contributor: Kevin     # whose recipe this is; links to their page
servings: 4
source:                       # links, or plain text like a book or a person
- https://www.seriouseats.com/...
---
# Ingredients
- **2 lb chicken thighs**     # bold = fresh, probably need to buy
- 1 tbsp soy sauce            # plain = pantry staple
# Instructions
- ...
```

Bold items under `# Ingredients` are highlighted as things to buy, with a
legend at the top. Markdown is read as CommonMark, the same as Obsidian
renders it.

## Your page

Each person has a page in `users/` (`users/kevin.md` is at
`users/kevin.html`). Edit its front matter:

```yaml
name: Kevin
class: Sauce Alchemist           # the title under your name
favorites: [Oyakodon, Wei's Beef Stew]   # recipe file names, without .md
tag-sections: [vegetarian]       # extra sections, one per tag
```

Anything written below the front matter appears at the top of the page.
"My Recipes" lists every recipe whose `recipe-contributor` matches the
file name (`kevin.md` matches `Kevin`). Each recipe page also shows who
has it as a favorite. If a favorite or tag section doesn't exist, the
build fails and names the file and the problem.

## Building

The toolchain is ghcup's recommended GHC 9.10.3 and cabal 3.16.

```sh
cabal run site -- watch     # preview at http://localhost:8000
cabal run site -- build     # writes _site/
```

Every push to `main` deploys to GitHub Pages (`.github/workflows/deploy.yml`).

hakyll-flint is pinned to a commit in `cabal.project`. To work on the library
and the site together, create a `cabal.project.local` (git-ignored)
containing `packages: ../hakyll-flint`.
