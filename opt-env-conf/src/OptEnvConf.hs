{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}

module OptEnvConf
  ( module OptEnvConf,
    module Control.Applicative,
  )
where

import Control.Applicative
import Data.Aeson as JSON
import qualified Data.Aeson.Key as Key
-- import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Types as JSON
import System.Environment (getArgs, getEnvironment)
import System.Exit

data Parser a where
  -- Functor
  ParserPure :: a -> Parser a
  -- Applicative
  ParserFmap :: (a -> b) -> Parser a -> Parser b
  ParserAp :: Parser (a -> b) -> Parser a -> Parser b
  -- Alternative
  ParserEmpty :: Parser a
  ParserAlt :: Parser a -> Parser a -> Parser a
  -- | Arguments and options
  ParserArg :: Parser String
  -- | Env vars
  ParserEnvVar :: String -> Parser String
  -- | Configuration file
  ParserConfig :: FromJSON a => String -> Parser a

instance Functor Parser where
  fmap = ParserFmap

instance Applicative Parser where
  pure = ParserPure
  (<*>) = ParserAp

instance Alternative Parser where
  empty = ParserEmpty
  (<|>) p1 p2 = case p1 of
    ParserEmpty -> p2
    _ -> case p2 of
      ParserEmpty -> p1
      _ -> ParserAlt p1 p2

class HasParser a where
  optEnvParser :: Parser a

envVar :: String -> Parser String
envVar = ParserEnvVar

strArg :: Parser String
strArg = ParserArg

strOpt :: String -> Parser String
strOpt = ParserEnvVar

confVar :: String -> Parser String
confVar = ParserConfig

documentParser :: Parser a -> String
documentParser = unlines . go
  where
    go :: Parser a -> [String]
    go = \case
      ParserFmap _ p -> go p
      ParserPure _ -> []
      ParserAp pf pa -> go pf ++ go pa
      ParserEmpty -> []
      ParserAlt p1 ParserEmpty -> go p1
      ParserAlt p1 p2 -> go p1 ++ ["or"] ++ go p2
      ParserArg -> ["Argument"]
      ParserEnvVar v -> ["Env var: " <> show v]
      ParserConfig key -> ["Config var: " <> show key]

showParserABit :: Parser a -> String
showParserABit = ($ "") . go 0
  where
    go :: Int -> Parser a -> ShowS
    go d = \case
      ParserFmap _ p -> showParen (d > 10) $ showString "Fmap _ " . go 11 p
      ParserPure _ -> showParen (d > 10) $ showString "Pure _"
      ParserAp pf pa -> showParen (d > 10) $ showString "Ap " . go 11 pf . go 11 pa
      ParserEmpty -> showString "Empty"
      ParserAlt p1 p2 -> showParen (d > 10) $ showString "Alt " . go 11 p1 . showString " " . go 11 p2
      ParserArg -> showString "Arg"
      ParserEnvVar v -> showParen (d > 10) $ showString "EnvVar " . showsPrec 11 v
      ParserConfig key -> showParen (d > 10) $ showString "Config " . showsPrec 11 key

runParser :: Parser a -> IO a
runParser p = do
  args <- getArgs
  envVars <- getEnvironment
  let mConf = Nothing

  -- TODO map
  case runParserPure p args envVars mConf of
    Left err -> die err
    Right a -> pure a

runParserPure :: Parser a -> [String] -> [(String, String)] -> Maybe JSON.Object -> Either String a
runParserPure p args envVars mConfig = go args envVars mConfig p
  where
    -- TODO maybe use validation instead of either
    go :: [String] -> [(String, String)] -> Maybe JSON.Object -> Parser a -> Either String a
    go as es mConf = \case
      ParserFmap f p' -> f <$> go as es mConf p'
      ParserPure a -> pure a
      ParserAp ff fa -> go as es mConf ff <*> go as es mConf fa
      ParserEmpty -> Left "ParserEmpty"
      ParserAlt p1 p2 -> case go as es mConf p1 of
        Right a -> pure a
        Left _ -> go as es mConf p2 -- TODO: Maybe collect the error?
      ParserArg -> case as of
        [] -> Left "No argument to consume" -- TODO consume the arg
        (a : _) -> Right a
      ParserEnvVar v -> case lookup v es of
        Nothing -> Left $ "Env var not found: " <> show v
        Just s -> pure s
      ParserConfig key -> case mConf of
        Nothing -> Left "No config"
        Just conf -> case JSON.parseEither (.: Key.fromString key) conf of
          Left err -> Left err
          Right v -> pure v
