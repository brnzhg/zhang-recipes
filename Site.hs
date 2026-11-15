-- | The recipe site.
--
-- * @recipes/*.md@: one recipe per file; the file name is the title. Front
--   matter: @protein@ (one value), @recipe-tag@ (a list),
--   @recipe-contributor@ (whose recipe page it is), @servings@, and @source@
--   (where it came from: links or plain text).
-- * @users/*.md@: one homepage per person. Front matter: @name@, @class@,
--   @favorites@ (recipe titles) and @tag-sections@ (tags shown as sections).
module Main (main) where

import Control.Applicative ((<|>))
import Control.Monad (forM_, unless, (>=>))
import Data.Functor ((<&>))
import Data.List (groupBy, isPrefixOf, stripPrefix)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text qualified as T
import Hakyll
import Hakyll.Flint
import System.FilePath (takeBaseName)
import Text.Pandoc
    ( Block (..)
    , Inline (..)
    , Pandoc (..)
    , ReaderOptions (..)
    , def
    , getDefaultExtensions
    , readCommonMark
    , runPure
    )
import Text.Pandoc.Shared (stringify)
import Text.Pandoc.Walk (query, walk)

--------------------------------------------------------------------------------
-- Properties

protein, recipeTag, contributor, favorite :: Property
protein = singleValued "protein"
recipeTag = manyValued "recipe-tag"
contributor = singleValued "recipe-contributor"
favorite = manyValued "favorites"

recipes, users :: Pattern
recipes = "recipes/*.md"
users = "users/*.md"

--------------------------------------------------------------------------------

main :: IO ()
main = hakyll $ do
    recipeIds <- getMatches recipes
    let recipeBySlug = Map.fromList [(titleSlug ident, ident) | ident <- recipeIds]

    proteins <- buildPropertyIndex protein recipes (valuePagesAt "protein/*.html")
    tags <- buildPropertyIndex recipeTag recipes (valuePagesAt "tag/*.html")
    -- A contributor's "value page" is their homepage, so links go there.
    contributors <- buildPropertyIndex contributor recipes (valuePagesAt "users/*.md")
    -- A favorite's "value page" is the recipe itself.
    favorites <- buildPropertyIndex favorite users $ \slug ->
        Map.findWithDefault (fromFilePath "missing") slug recipeBySlug
    checkFavorites recipeBySlug favorites
    checkTagSections tags

    let party = listField "party" (userRefContext contributors) (pageRefs <$> getMatches users)
        baseCtx = party <> defaultContext
        finish ctx = loadAndApplyTemplate "templates/default.html" ctx >=> relativizeUrls
        renderMarkdown transform =
            getResourceBody
                >>= readObsidianMarkdown
                <&> writePandocWith defaultHakyllWriterOptions . fmap transform

    match "templates/*" $ compile templateBodyCompiler

    match "css/*" $ do
        route idRoute
        compile compressCssCompiler

    rulesExtraDependencies [indexDependency favorites] . match recipes $ do
        route slugRoute
        compile $ do
            let ctx =
                    propertyLinksField "proteinLinks" proteins
                        <> propertyLinksField "tagLinks" tags
                        <> propertyLinksField "contributorLinks" contributors
                        <> favoritedByField favorites
                        <> sourcesField
                        <> baseCtx
            renderMarkdown markFreshIngredients
                >>= loadAndApplyTemplate "templates/recipe.html" ctx
                >>= finish ctx

    rulesExtraDependencies (map indexDependency [contributors, tags, favorites]) . match users $ do
        route (setExtension "html")
        compile $ do
            let ctx =
                    favoritesField favorites
                        <> myRecipesField contributors
                        <> tagSectionsField tags
                        <> field "title" userName
                        <> initialField
                        <> baseCtx
            renderMarkdown id
                >>= loadAndApplyTemplate "templates/user.html" ctx
                >>= finish ctx

    -- protein/chicken.html, tag/meal-prep.html, ...
    forM_ [("Protein", proteins), ("Tag", tags)] $ \(heading, idx) ->
        valuePageRules idx $ \entry -> do
            route idRoute
            compile $ do
                let ctx =
                        constField "heading" heading
                            <> constField "countLabel" (recipesLabel . length $ entryMembers entry)
                            <> valuePageContext "recipes" defaultListing entry
                            <> baseCtx
                makeItem "" >>= loadAndApplyTemplate "templates/value.html" ctx >>= finish ctx

    create ["index.html"] $ do
        route idRoute
        compile $ do
            let ctx =
                    constField "title" "Recipes"
                        <> listField "recipes" pageRefContext (pure $ pageRefs recipeIds)
                        <> constField "recipeCount" (show $ length recipeIds)
                        <> allValuesField "proteins" proteins
                        <> allValuesField "tags" tags
                        <> baseCtx
            makeItem "" >>= loadAndApplyTemplate "templates/index.html" ctx >>= finish ctx

--------------------------------------------------------------------------------
-- Users

userName :: Item a -> Compiler String
userName = fmap (fromMaybe "") . flip getMetadataField "name" . itemIdentifier

-- | @$name$@ is front matter; @$initial$@ is its first letter, for the badge.
initialField :: Context a
initialField = field "initial" (fmap (take 1) . userName)

-- | Recipes whose contributor matches this user's file name (users/kevin.md
-- matches @recipe-contributor: Kevin@).
contributedBy :: PropertyIndex -> Identifier -> [Identifier]
contributedBy contributors =
    pagesWithValue contributors . PropertyValue . T.pack . takeBaseName . toFilePath

-- | A person in a list: their front matter, URL, and recipe count.
userRefContext :: PropertyIndex -> Context ()
userRefContext contributors =
    field "recipeCount" (pure . recipesLabel . length . contributedBy contributors . itemIdentifier)
        <> initialField
        <> pageRefContext

myRecipesField :: PropertyIndex -> Context String
myRecipesField contributors =
    nonEmptyListField "myRecipes" pageRefContext $
        pure . pageRefs . contributedBy contributors . itemIdentifier

-- | The user's @favorites@, in the order they listed them.
favoritesField :: PropertyIndex -> Context String
favoritesField favorites =
    nonEmptyListField "favorites" pageRefContext $
        pure . pageRefs . map entryPage . favoriteEntries . itemIdentifier
  where
    favoriteEntries = mapMaybe (lookupValue favorites) . valuesOfPage favorites

-- | One section per tag in the user's @tag-sections@ (checked by
-- 'checkTagSections').
tagSectionsField :: PropertyIndex -> Context String
tagSectionsField tags = nonEmptyListField "tagSections" valueEntryContext $ \item ->
    map toItem . mapMaybe (lookupValue tags) <$> tagSections (itemIdentifier item)
  where
    toItem entry = Item (entryPage entry) entry

tagSections :: (MonadMetadata m) => Identifier -> m [PropertyValue]
tagSections = fmap (map (PropertyValue . T.pack) . fromMaybe [] . lookupStringList "tag-sections") . getMetadata

-- | Fail the build on a tag section no recipe uses. (Inside a template,
-- @$if$@ would swallow the error and silently drop the section.)
checkTagSections :: PropertyIndex -> Rules ()
checkTagSections tags = do
    userIds <- getMatches users
    forM_ userIds $ \ident -> do
        unknown <- filter (null . pagesWithValue tags) <$> tagSections ident
        unless (null unknown) . fail $
            toFilePath ident
                <> ": tag-sections has "
                <> show (map valueString unknown)
                <> ", which no recipe uses"

-- | Users who list this recipe in their @favorites@.
favoritedByField :: PropertyIndex -> Context String
favoritedByField favorites =
    nonEmptyListField "favoritedBy" pageRefContext $
        pure . pageRefs . pagesWithValue favorites . PropertyValue . T.pack . recipeTitle . itemIdentifier

-- | Fail the build on a favorite that isn't a recipe title, naming the user.
checkFavorites :: Map ValueSlug Identifier -> PropertyIndex -> Rules ()
checkFavorites recipeBySlug favorites =
    forM_ (indexEntries favorites) $ \entry ->
        unless (entrySlug entry `Map.member` recipeBySlug) . fail $
            "favorites: no recipe called "
                <> show (valueString $ entryValue entry)
                <> " (listed in "
                <> unwords (map toFilePath $ entryMembers entry)
                <> "). Use the recipe's file name without .md."

--------------------------------------------------------------------------------
-- Recipes

recipesLabel :: Int -> String
recipesLabel = \case
    1 -> "1 recipe"
    n -> show n <> " recipes"

recipeTitle :: Identifier -> String
recipeTitle = takeBaseName . toFilePath

titleSlug :: Identifier -> ValueSlug
titleSlug = valueSlug . PropertyValue . T.pack . recipeTitle

-- | @recipes/Wei's Beef Stew.md@ is served at @recipes/wei-s-beef-stew.html@.
slugRoute :: Routes
slugRoute = customRoute $ \ident -> "recipes/" <> slugString (titleSlug ident) <> ".html"

-- | The @source@ entries: links show their site name, anything else (a book,
-- a person) shows as text. Absent when there are none.
sourcesField :: Context String
sourcesField = nonEmptyListField "sources" sourceCtx $ \item ->
    map (Item $ itemIdentifier item) . fromMaybe [] . lookupStringList "source"
        <$> getMetadata (itemIdentifier item)
  where
    sourceCtx =
        field "label" (pure . siteName . itemBody)
            <> field "url" (urlOnly . itemBody)
    urlOnly s
        | isUrl s = pure s
        | otherwise = noResult "not a link"
    isUrl s = any (`isPrefixOf` s) ["http://", "https://"]
    siteName s
        | isUrl s = dropWww . takeWhile (/= '/') $ dropScheme s
        | otherwise = s
    dropScheme s = fromMaybe s $ stripPrefix "https://" s <|> stripPrefix "http://" s
    dropWww s = fromMaybe s $ stripPrefix "www." s

-- | Bold items under the Ingredients heading are ones you probably need to
-- buy (not pantry staples). Mark them, and explain the marking once.
markFreshIngredients :: Pandoc -> Pandoc
markFreshIngredients (Pandoc meta blocks) =
    Pandoc meta . concatMap section $ groupBy (const $ not . isTopHeading) blocks
  where
    section (heading@(Header 1 _ title) : body)
        | T.toLower (stringify title) == "ingredients" && hasBold body =
            heading : legend : walk fresh body
    section bs = bs

    hasBold = not . null . query bold
    bold = \case
        Strong _ -> [()]
        _ -> []

    fresh = \case
        Strong xs -> Span freshAttr xs
        other -> other

    freshAttr = ("", ["fresh"], [])
    legend =
        Div ("", ["legend"], []) . pure $
            Plain [Span freshAttr [Str "Marked"], Str " items are fresh: you probably need to buy them."]

    isTopHeading = \case
        Header 1 _ _ -> True
        _ -> False

--------------------------------------------------------------------------------
-- Helpers

-- | Read a note the way Obsidian renders it. Obsidian follows CommonMark,
-- where e.g. a heading straight after a list item ends the list; pandoc's
-- own Markdown would fold the heading into the last item instead.
readObsidianMarkdown :: Item String -> Compiler (Item Pandoc)
readObsidianMarkdown = traverse $ \body ->
    either (fail . ("markdown: " <>) . show) pure . runPure $
        readCommonMark
            def {readerExtensions = getDefaultExtensions "commonmark_x"}
            (T.pack body)

-- | A list field that is absent when empty, so @$if(key)$@ works.
nonEmptyListField :: String -> Context a -> (Item b -> Compiler [Item a]) -> Context b
nonEmptyListField key ctx items = listFieldWith key ctx $ \item ->
    items item >>= \case
        [] -> noResult $ key <> " is empty"
        xs -> pure xs
