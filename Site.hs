-- | The recipe site.
--
-- * @recipes/*.md@: one recipe per file; the file name is the title. Front
--   matter: @protein@ (one value), @recipe-tag@ (a list),
--   @recipe-contributor@ (whose recipe page it is), @added@ (YYYY-MM-DD),
--   @servings@, and @source@ (where it came from: links or plain text).
-- * @users/*.md@: one homepage per person. Front matter: @name@, @class@,
--   @gem@ (their colour), @favorites@ (recipe titles) and @tag-sections@
--   (tags shown as sections).
module Main (main) where

import Control.Applicative ((<|>))
import Control.Monad (forM, forM_, unless, (>=>))
import Data.Char (ord)
import Data.Functor ((<&>))
import Data.List (groupBy, isPrefixOf, sortOn, stripPrefix)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, mapMaybe)
import Data.Ord (Down (..))
import Data.Text qualified as T
import Data.Time (Day, defaultTimeLocale, parseTimeM)
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

-- | The site's sources live at the repo root, next to cabal's build
-- directory. Hakyll would scan dist-newstyle too, and with it there,
-- incremental builds stopped noticing edits to recipes.
config :: Configuration
config =
    defaultConfiguration
        { ignoreFile = \name -> name `elem` ["dist-newstyle", "Site.hs"] || ignoreFile defaultConfiguration name
        }

main :: IO ()
main = hakyllWith config $ do
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
    checkGems
    checkAddedDates recipeIds

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

    -- A colour per protein and per person, generated from the data.
    rulesExtraDependencies [indexDependency proteins] . create ["css/palette.css"] $ do
        route idRoute
        compile $ do
            userIds <- getMatches users
            userRules <- forM userIds $ \ident ->
                hueRule "user" (userSlug ident) . userHue ident <$> getMetadataField ident "gem"
            let proteinRules =
                    [ hueRule "protein" slug (proteinHue slug)
                    | slug <- map (slugString . entrySlug) $ indexEntries proteins
                    ]
            makeItem . unlines $ proteinRules <> userRules

    rulesExtraDependencies [indexDependency favorites] . match recipes $ do
        route slugRoute
        compile $ do
            let ctx =
                    propertyLinksField "proteinLinks" proteins
                        <> propertyLinksField "tagLinks" tags
                        <> propertyLinksField "contributorLinks" contributors
                        <> favoritedByField favorites
                        <> sourcesField
                        <> proteinSlugField
                        <> slugField "contributorSlug" "recipe-contributor"
                        <> baseCtx
            renderMarkdown markFreshIngredients
                >>= loadAndApplyTemplate "templates/recipe.html" ctx
                >>= finish ctx

    rulesExtraDependencies (map indexDependency [contributors, tags, favorites]) . match users $ do
        route (setExtension "html")
        compile $ do
            let ctx =
                    favoritesField favorites
                        <> myRecipesFields contributors
                        <> tagSectionsField tags
                        <> field "title" userName
                        <> initialField
                        <> userSlugField
                        <> baseCtx
            renderMarkdown id
                >>= loadAndApplyTemplate "templates/user.html" ctx
                >>= finish ctx

    -- protein/chicken.html, tag/meal-prep.html, ...
    forM_ [("Protein", "protein", proteins), ("Tag", "tag", tags)] $ \(heading, kind, idx) ->
        valuePageRules idx $ \entry -> do
            route idRoute
            compile $ do
                let ctx =
                        constField "heading" heading
                            <> constField "kind" kind
                            <> constField "countLabel" (recipesLabel . length $ entryMembers entry)
                            <> valuePageContext "recipes" recipeListing entry
                            <> baseCtx
                makeItem "" >>= loadAndApplyTemplate "templates/value.html" ctx >>= finish ctx

    create ["index.html"] $ do
        route idRoute
        compile $ do
            let ctx =
                    constField "title" "Recipes"
                        <> listField "recipes" recipeCardContext (pure $ pageRefs recipeIds)
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
        <> userSlugField
        <> pageRefContext

-- | users/kevin.md is "kevin": what @data-user@ and the palette use.
userSlug :: Identifier -> String
userSlug = takeBaseName . toFilePath

userSlugField :: Context a
userSlugField = field "userSlug" (pure . userSlug . itemIdentifier)

-- | How many recipe cards My Recipes shows before "Show all".
recentCount :: Int
recentCount = 6

-- | The user's recipes, newest first: @$recentRecipes$@ (the first few),
-- @$olderRecipes$@ (the rest) and @$myRecipeCount$@.
myRecipesFields :: PropertyIndex -> Context String
myRecipesFields contributors =
    nonEmptyListField "recentRecipes" recipeCardContext (fmap (take recentCount) . mine)
        <> nonEmptyListField "olderRecipes" recipeCardContext (fmap (drop recentCount) . mine)
        <> field "myRecipeCount" (pure . recipesLabel . length . contributedBy contributors . itemIdentifier)
  where
    mine = fmap pageRefs . newestFirst . contributedBy contributors . itemIdentifier

-- | The user's @favorites@, in the order they listed them.
favoritesField :: PropertyIndex -> Context String
favoritesField favorites =
    nonEmptyListField "favorites" recipeCardContext $
        pure . pageRefs . map entryPage . favoriteEntries . itemIdentifier
  where
    favoriteEntries = mapMaybe (lookupValue favorites) . valuesOfPage favorites

-- | One section per tag in the user's @tag-sections@ (checked by
-- 'checkTagSections').
tagSectionsField :: PropertyIndex -> Context String
tagSectionsField tags = nonEmptyListField "tagSections" (valueEntryContextWith recipeListing) $ \item ->
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
    nonEmptyListField "favoritedBy" (userSlugField <> pageRefContext) $
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

-- | Each person picks a gem for their colour (@gem: emerald@). Hues for
-- CSS @hsl()@.
gemHues :: Map String Int
gemHues =
    Map.fromList
        [ ("ruby", 350)
        , ("garnet", 10)
        , ("amber", 32)
        , ("topaz", 45)
        , ("citrine", 55)
        , ("peridot", 85)
        , ("emerald", 145)
        , ("jade", 165)
        , ("aquamarine", 185)
        , ("sapphire", 215)
        , ("lapis", 230)
        , ("amethyst", 275)
        , ("rose quartz", 330)
        ]

-- | No gem: a colour picked from the file name, so it's at least stable.
userHue :: Identifier -> Maybe String -> Int
userHue ident gem = fromMaybe (nameHue $ userSlug ident) $ (`Map.lookup` gemHues) =<< gem

checkGems :: Rules ()
checkGems = do
    userIds <- getMatches users
    forM_ userIds $ \ident -> do
        gem <- getMetadataField ident "gem"
        forM_ gem $ \g ->
            unless (g `Map.member` gemHues) . fail $
                toFilePath ident
                    <> ": unknown gem "
                    <> show g
                    <> "; pick one of "
                    <> show (Map.keys gemHues)

--------------------------------------------------------------------------------
-- Colours

-- | Hand-picked protein hues; any other protein gets one from its name.
proteinHue :: String -> Int
proteinHue slug = Map.findWithDefault (nameHue slug) slug hues
  where
    hues =
        Map.fromList
            [ ("beef", 355)
            , ("pork", 330)
            , ("salmon", 15)
            , ("chicken", 38)
            , ("egg", 52)
            , ("chickpea", 75)
            , ("lentil", 125)
            , ("tofu", 150)
            , ("turkey", 180)
            , ("fish", 205)
            , ("bean", 285)
            ]

-- | A stable hue from a name.
nameHue :: String -> Int
nameHue = (`mod` 360) . foldl (\h c -> h * 31 + ord c) 7

-- | @[data-protein="chicken"]{--hue:40}@
hueRule :: String -> String -> Int -> String
hueRule attr slug hue = "[data-" <> attr <> "=\"" <> slug <> "\"]{--hue:" <> show hue <> "}"

-- | A metadata field, slugged (for @data-*@ attributes).
slugField :: String -> String -> Context a
slugField key metaKey = field key $ \item ->
    getMetadataField (itemIdentifier item) metaKey
        >>= maybe (noResult $ "no " <> metaKey) (pure . slugString . valueSlug . PropertyValue . T.pack)

proteinSlugField :: Context a
proteinSlugField = slugField "proteinSlug" "protein"

-- | A recipe in a list of cards: its protein (for colour) and front matter.
recipeCardContext :: Context ()
recipeCardContext = proteinSlugField <> pageRefContext

recipeListing :: PageListing
recipeListing = PageListing recipeCardContext pure

--------------------------------------------------------------------------------
-- Recipes

recipesLabel :: Int -> String
recipesLabel = \case
    1 -> "1 recipe"
    n -> show n <> " recipes"

-- | The @added@ date, if any.
addedDate :: (MonadMetadata m) => Identifier -> m (Maybe Day)
addedDate ident = (parseDay =<<) <$> getMetadataField ident "added"
  where
    parseDay = parseTimeM True defaultTimeLocale "%Y-%m-%d"

-- | Newest first; recipes without a date count as newest. Ties by title.
newestFirst :: [Identifier] -> Compiler [Identifier]
newestFirst idents = do
    dated <- forM idents $ \ident -> (,ident) <$> addedDate ident
    pure . map snd $ sortOn key dated
  where
    key (day, ident) = (isJust day, Down day, recipeTitle ident)

-- | Fail the build on an @added@ date that isn't YYYY-MM-DD.
checkAddedDates :: [Identifier] -> Rules ()
checkAddedDates recipeIds =
    forM_ recipeIds $ \ident -> do
        raw <- getMetadataField ident "added"
        parsed <- addedDate ident
        unless (isNothing raw || isJust parsed) . fail $
            toFilePath ident <> ": added should be a date like 2026-11-15, not " <> show (fromMaybe "" raw)

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
