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
added: 2026-11-20             # newest recipes come first on your page
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
gem: emerald                     # your colour: ruby, garnet, amber, topaz, citrine,
                                 # peridot, emerald, jade, aquamarine, sapphire,
                                 # lapis, amethyst or rose quartz
favorites: [Oyakodon, Wei's Beef Stew]   # recipe file names, without .md
tag-sections: [vegetarian]       # extra sections, one per tag
```

Anything written below the front matter appears at the top of the page.
"My Recipes" lists every recipe whose `recipe-contributor` matches the
file name (`kevin.md` matches `Kevin`). It shows the newest six by `added`
date, and the rest open under "Show all". Each recipe page also shows who
has it as a favorite. If a favorite, tag section, gem or date is wrong,
the build fails and names the file and the problem.

Each protein gets a colour automatically (`css/palette.css` is generated).
To pick one for a new protein, add it to `proteinHue` in `Site.hs`.

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
