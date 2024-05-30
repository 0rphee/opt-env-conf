{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE GADTs #-}
{-# OPTIONS_GHC -Wno-duplicate-exports #-}

module OptEnvConf
  ( module OptEnvConf,
    module OptEnvConf.Doc,
    module OptEnvConf.Opt,
    module OptEnvConf.Run,
    module OptEnvConf.Reader,
    Parser,
    HasParser (..),
    optional,
    module Control.Applicative,
  )
where

import Control.Applicative
import Data.Aeson as JSON
import Data.List.NonEmpty (NonEmpty)
import Data.String
import OptEnvConf.Doc
import OptEnvConf.Opt
import OptEnvConf.Parser
import OptEnvConf.Reader
import OptEnvConf.Run

strArgument :: IsString string => [ArgumentBuilder string] -> Parser string
strArgument = argument str

strOption :: IsString string => [OptionBuilder string] -> Parser string
strOption = option str

argument :: Reader a -> [ArgumentBuilder a] -> Parser a
argument r = ParserArg r . completeBuilder . mconcat

option :: Reader a -> [OptionBuilder a] -> Parser a
option r = ParserOpt r . completeBuilder . mconcat

envVar :: Reader a -> [EnvBuilder a] -> Parser a
envVar r = ParserEnvVar r . completeBuilder . mconcat

confVal :: FromJSON a => String -> Parser a
confVal = ParserConfig

optionalFirst :: [Parser (Maybe a)] -> Parser (Maybe a)
optionalFirst = ParserOptionalFirst

requiredFirst :: [Parser (Maybe a)] -> Parser a
requiredFirst = ParserRequiredFirst

someNonEmpty :: Parser a -> Parser (NonEmpty a)
someNonEmpty = ParserSome

-- TODO make make an OptEnvConfBuilder for this?
optEnvConf :: FromJSON a => Reader a -> String -> String -> Parser a
optEnvConf r key h =
  requiredFirst
    [ optional $
        option
          r
          [ long key,
            help h
          ],
      optional $
        envVar
          r
          [ var key
          ], -- TODO just using the key doesn't work, needs to be UPPER_SNAKE_CASE
      optional $ confVal key -- TODO just using the key doesn't work, needs to be kebab-case
    ]
