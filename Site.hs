-- | The recipe site.
--
-- Recipes are plain Markdown notes in @recipes/@, in the same format as the
-- Planner vault's @Reference/Recipes/@ (see @scripts/import-recipes.sh@):
-- the file name is the title, and the front matter has @protein@ (one
-- value), @category@ (a list), @servings@ and @source@ (a list of URLs).
module Main (main) where

import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Hakyll
import Hakyll.Flint
import System.FilePath (takeBaseName)
import Data.Functor ((<&>))
import Text.Pandoc (Pandoc, ReaderOptions (..), def, getDefaultExtensions, readCommonMark, runPure)

--------------------------------------------------------------------------------
-- Properties

protein, category :: Property
protein = singleValued "protein"
category = manyValued "category"

recipes :: Pattern
recipes = "recipes/*.md"

--------------------------------------------------------------------------------

main :: IO ()
main = hakyll $ do
    proteins <- buildPropertyIndex protein recipes (valuePagesAt "protein/*.html")
    categories <- buildPropertyIndex category recipes (valuePagesAt "category/*.html")

    match "templates/*" $ compile templateBodyCompiler

    match "css/*" $ do
        route idRoute
        compile compressCssCompiler

    match recipes $ do
        route slugRoute
        compile $ do
            let ctx =
                    propertyLinksField "proteinLinks" proteins
                        <> propertyLinksField "categoryLinks" categories
                        <> sourcesField
                        <> defaultContext
            getResourceBody
                >>= readObsidianMarkdown
                <&> writePandocWith defaultHakyllWriterOptions
                >>= loadAndApplyTemplate "templates/recipe.html" ctx
                >>= loadAndApplyTemplate "templates/default.html" ctx
                >>= relativizeUrls

    -- protein/chicken.html, category/entree.html, ...
    let valuePages heading idx = valuePageRules idx $ \entry -> do
            route idRoute
            compile $ do
                let ctx =
                        constField "heading" heading
                            <> valuePageContext "recipes" defaultListing entry
                            <> defaultContext
                makeItem ""
                    >>= loadAndApplyTemplate "templates/value.html" ctx
                    >>= loadAndApplyTemplate "templates/default.html" ctx
                    >>= relativizeUrls
    valuePages "Protein" proteins
    valuePages "Category" categories

    create ["index.html"] $ do
        route idRoute
        compile $ do
            let ctx =
                    constField "title" "Recipes"
                        <> listField "recipes" pageRefContext (pageRefs <$> getMatches recipes)
                        <> allValuesField "proteins" proteins
                        <> allValuesField "categories" categories
                        <> defaultContext
            makeItem ""
                >>= loadAndApplyTemplate "templates/index.html" ctx
                >>= loadAndApplyTemplate "templates/default.html" ctx
                >>= relativizeUrls

--------------------------------------------------------------------------------

-- | Read a note the way Obsidian renders it. Obsidian follows CommonMark,
-- where e.g. a heading straight after a list item ends the list; pandoc's
-- own Markdown would fold the heading into the last item instead.
-- @commonmark_x@ adds tables, task lists, strikeout and heading ids.
readObsidianMarkdown :: Item String -> Compiler (Item Pandoc)
readObsidianMarkdown = traverse $ \body ->
    either (fail . ("markdown: " <>) . show) pure . runPure $
        readCommonMark
            def {readerExtensions = getDefaultExtensions "commonmark_x"}
            (T.pack body)

-- | @recipes/Adam Chicken Breast Sandwich.md@ is served at
-- @recipes/adam-chicken-breast-sandwich.html@.
slugRoute :: Routes
slugRoute = customRoute $ \ident ->
    "recipes/" <> T.unpack (slugify (T.pack (takeBaseName (toFilePath ident)))) <> ".html"

-- | The @source@ URLs as a list (@$for(sources)$ $url$ $endfor$@). Absent
-- when there are none, so @$if(sources)$@ works.
sourcesField :: Context String
sourcesField = listFieldWith "sources" (field "url" (pure . itemBody)) $ \item -> do
    urls <- fromMaybe [] . lookupStringList "source" <$> getMetadata (itemIdentifier item)
    case urls of
        [] -> noResult "no sources"
        _ -> pure [Item (itemIdentifier item) url | url <- urls]
