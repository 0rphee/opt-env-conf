{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module OptEnvConf.Parser
  ( -- * Parser API
    setting,
    prefixed,
    optionalFirst,
    requiredFirst,
    someNonEmpty,
    mapIO,
    withConfig,
    withYamlConfig,
    xdgYamlConfigFile,

    -- * Parser implementation
    Parser (..),
    Metavar,
    Help,
    showParserABit,
  )
where

import Autodocodec
import Autodocodec.Yaml
import Control.Applicative
import Control.Monad
import Control.Selective
import Data.Aeson as JSON
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import OptEnvConf.Opt
import OptEnvConf.Reader
import Path.IO
import System.FilePath
import Text.Show

data Parser a where
  -- Functor
  ParserPure :: a -> Parser a
  -- Applicative
  ParserFmap :: (a -> b) -> Parser a -> Parser b
  ParserAp :: Parser (a -> b) -> Parser a -> Parser b
  -- Selective
  ParserSelect :: Parser (Either a b) -> Parser (a -> b) -> Parser b
  -- Alternative
  ParserEmpty :: Parser a
  ParserAlt :: Parser a -> Parser a -> Parser a
  ParserMany :: Parser a -> Parser [a]
  ParserSome :: Parser a -> Parser (NonEmpty a)
  -- | Apply a computation to the result of a parser
  --
  -- This is intended for use-cases like resolving a file to an absolute path.
  -- It is morally ok for read-only IO actions but you will
  -- have a bad time if the action is not read-only.
  ParserMapIO :: (a -> IO b) -> Parser a -> Parser b
  -- | Load a configuration value and use it for the continuing parser
  ParserWithConfig :: Parser (Maybe JSON.Object) -> Parser a -> Parser a
  -- Combining
  -- TODO Maybe we can get rid of this constructor using 'optional requiredFirst'
  ParserOptionalFirst :: [Parser (Maybe a)] -> Parser (Maybe a)
  -- TODO maybe we can get rid of this constructor using Alt
  ParserRequiredFirst :: [Parser (Maybe a)] -> Parser a
  -- | General settings
  ParserSetting :: !(SettingParser a) -> Parser a
  -- | Prefixed env var
  ParserPrefixed :: !String -> !(Parser a) -> Parser a

instance Functor Parser where
  fmap = ParserFmap

instance Applicative Parser where
  pure = ParserPure
  (<*>) = ParserAp

instance Selective Parser where
  select = ParserSelect

instance Alternative Parser where
  empty = ParserEmpty
  (<|>) p1 p2 =
    let isEmpty :: Parser a -> Bool
        isEmpty = \case
          ParserFmap _ p' -> isEmpty p'
          ParserPure _ -> False
          ParserAp pf pa -> isEmpty pf && isEmpty pa
          ParserSelect pe pf -> isEmpty pe && isEmpty pf
          ParserEmpty -> True
          ParserAlt _ _ -> False
          ParserMany _ -> False
          ParserSome _ -> False
          ParserMapIO _ p' -> isEmpty p'
          ParserWithConfig pc ps -> isEmpty pc && isEmpty ps
          ParserOptionalFirst _ -> False
          ParserRequiredFirst ps -> null ps
          ParserSetting _ -> False
          ParserPrefixed _ p -> isEmpty p
     in case (isEmpty p1, isEmpty p2) of
          (True, True) -> ParserEmpty
          (True, False) -> p2
          (False, True) -> p1
          (False, False) -> ParserAlt p1 p2
  many = ParserMany

  -- TODO maybe we can get rid of the some constructor by using (:) <$> p <$> many p
  some = fmap NE.toList . ParserSome

showParserABit :: Parser a -> String
showParserABit = ($ "") . go 0
  where
    go :: Int -> Parser a -> ShowS
    go d = \case
      ParserFmap _ p ->
        showParen (d > 10) $
          showString "Fmap _ "
            . go 11 p
      ParserPure _ -> showParen (d > 10) $ showString "Pure _"
      ParserAp pf pa ->
        showParen (d > 10) $
          showString "Ap "
            . go 11 pf
            . showString " "
            . go 11 pa
      ParserSelect pe pf ->
        showParen (d > 10) $
          showString "Select "
            . go 11 pe
            . showString " "
            . go 11 pf
      ParserEmpty -> showString "Empty"
      ParserAlt p1 p2 ->
        showParen (d > 10) $
          showString "Alt "
            . go 11 p1
            . showString " "
            . go 11 p2
      ParserMany p ->
        showParen (d > 10) $
          showString "Many "
            . go 11 p
      ParserSome p ->
        showParen (d > 10) $
          showString "Some "
            . go 11 p
      ParserMapIO _ p ->
        showParen (d > 10) $
          showString "MapIO _ "
            . go 11 p
      ParserWithConfig p1 p2 ->
        showParen (d > 10) $
          showString "WithConfig _ "
            . go 11 p1
            . showString " "
            . go 11 p2
      ParserOptionalFirst ps ->
        showParen (d > 10) $
          showString "OptionalFirst "
            . showListWith (go 11) ps
      ParserRequiredFirst ps ->
        showParen (d > 10) $
          showString "RequiredFirst "
            . showListWith (go 11) ps
      ParserSetting p ->
        showParen (d > 10) $
          showString "Setting "
            . showSettingParserABit p
      ParserPrefixed prefix p ->
        showParen (d > 10) $
          showString "Prefixed "
            . showsPrec 11 prefix
            . showString " "
            . go 11 p

setting :: [SettingBuilder a] -> Parser a
setting = ParserSetting . completeBuilder . mconcat

prefixed :: String -> Parser a -> Parser a
prefixed = ParserPrefixed

optionalFirst :: [Parser (Maybe a)] -> Parser (Maybe a)
optionalFirst = ParserOptionalFirst

requiredFirst :: [Parser (Maybe a)] -> Parser a
requiredFirst = ParserRequiredFirst

someNonEmpty :: Parser a -> Parser (NonEmpty a)
someNonEmpty = ParserSome

mapIO :: (a -> IO b) -> Parser a -> Parser b
mapIO = ParserMapIO

withConfig :: Parser (Maybe JSON.Object) -> Parser a -> Parser a
withConfig = ParserWithConfig

withYamlConfig :: Parser (Maybe FilePath) -> Parser a -> Parser a
withYamlConfig pathParser = withConfig $ mapIO (fmap join . mapM (resolveFile' >=> readYamlConfigFile)) pathParser

xdgYamlConfigFile :: FilePath -> Parser FilePath
xdgYamlConfigFile subdir =
  (\xdgDir -> xdgDir </> subdir </> "config.yaml")
    <$> setting
      [ reader str,
        var "XDG_CONFIG_HOME",
        metavar "DIRECTORY"
      ]
