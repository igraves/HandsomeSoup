module HandsomeSoup where

import Text.XML.HXT.Core
import Network.HTTP
import Network.URI
import Data.Tree.NTree.TypeDefs
import Control.Monad.Maybe
import Control.Monad.Trans
import Data.Maybe
import Text.Parsec
import qualified Data.Map as M
import Data.Monoid (mconcat)

data Selector = Selector { sName :: String, sAttrs :: M.Map String String }

instance Show Selector where
  show (Selector name attrs) = show name ++ ":" ++ showMap attrs
      where showMap m = (init.init $ "{" ++ (foldl (\acc (k,v) -> acc ++ (show k) ++ ":" ++ (show v) ++ ", ") "" (M.assocs m))) ++ "}"

combinator = char ' ' <|> char '+' <|> char '>' <|> char ','

tag = many1 alphaNum

-- secondarySelector = char ':' >> many1 (alphaNum <|> oneOf "-")

-- tagAttribute = between (char '[') (char ']') (many1 alphaNum)

klass = do
    char '.' 
    val <- many1 alphaNum
    return ("class", val)

id_ = do
    char '#'
    val <- many1 alphaNum
    return ("id", val)

universalSelector = do
    string "*"
    return $ Selector "*" M.empty

-- TODO the tag name should be optional, and if not given should default to
-- "*"
tagSelector = do
    tagName <- tag
    -- many1 (klass <|> id_ <|> secondarySelector <|> tagAttribute)
    attrs <- many1 (klass <|> id_)
    return $ Selector tagName (M.fromList attrs)

singleSelector = universalSelector <|> tagSelector

selector = many1 singleSelector `sepBy` (spaces >> combinator >> spaces)

css tag = case (parse selector "" tag) of
       Left err -> print err
       Right x  -> fromSelectors (mconcat x)


-- make an arrow from selectors

-- TODO remember to account for "*"! The universal selector.
fromSelectors (s:selectors) = foldl (\acc selector -> acc <+> make selector) (make s) selectors
  where make (Selector name attrs) = multi $ hasName name >>> makeAttrs (M.toList attrs)
        makeAttrs (a:attrs) = foldl (\acc attr -> acc >>> makeAttr attr) (makeAttr a) attrs
        makeAttr (name, value) = hasAttrValue name (==value)


-- helper function for getting page content
openUrl :: String -> MaybeT IO String
openUrl url = case parseURI url of
    Nothing -> fail "couldn't parse url"
    Just u  -> liftIO (getResponseBody =<< simpleHTTP (mkRequest GET u))

-- given a url, returns a document
fromUrl :: String -> IO (IOSArrow XmlTree (NTree XNode))
fromUrl url = do
  contents <- runMaybeT $ openUrl url
  return $ parseHtml (fromMaybe "" contents)

parseHtml :: String -> IOSArrow XmlTree (NTree XNode)
parseHtml = readString [withParseHTML yes, withWarnings no]

(!) :: ArrowXml cat => cat a XmlTree -> String -> cat a String
(!) a str = a >>> getAttrValue str

-- str = "h1.class, h2#someid, h3[lang], h4:first-child > h5, h6 h7"
str = "h1.class, h2#someid"

main = do
  doc <- fromUrl
  links <- runX $ doc >>> css "h3.r" >>> css "a" ! "href"
  mapM_ putStrLn links