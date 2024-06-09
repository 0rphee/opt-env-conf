{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RecordWildCards #-}

module OptEnvConf.Opt where

import qualified Data.List.NonEmpty as NE
import Data.String
import OptEnvConf.ArgMap (Dashed (..))
import OptEnvConf.Reader
import Text.Show

type Metavar = String

type Help = String

data Setting a = Setting
  { -- | Which dashed values are required for parsing
    --
    -- No dashed values means this is an argument.
    settingDasheds :: ![Dashed],
    -- | What value to parse when the switch exists.
    --
    -- Nothing means this is not a switch.
    settingSwitchValue :: !(Maybe a),
    settingArguments :: [Reader a],
    settingOptions :: [Reader a],
    -- | Which env vars can be read.
    --
    -- Requires at least one Reader.
    settingEnvVars :: ![(Reader a, String)],
    -- | Which metavar should be show in documentation
    settingMetavar :: !(Maybe Metavar),
    settingHelp :: !(Maybe String)
  }

emptySetting :: Setting a
emptySetting =
  Setting
    { settingDasheds = [],
      settingSwitchValue = Nothing,
      settingArguments = [],
      settingOptions = [],
      settingEnvVars = [],
      settingMetavar = Nothing,
      settingHelp = Nothing
    }

showSettingABit :: Setting a -> ShowS
showSettingABit Setting {..} =
  showParen True $
    showString "Setting "
      . showsPrec 11 settingDasheds
      . showString " "
      . showMaybeWith (\_ -> showString "_") settingSwitchValue
      . showString " "
      . showListWith (\_ -> showString "_") settingArguments
      . showString " "
      . showListWith (\_ -> showString "_") settingOptions
      . showString " "
      . showListWith
        ( \(_, v) ->
            showParen True $
              showString "_, "
                . showsPrec 11 v
        )
        settingEnvVars
      . showString " "
      . showsPrec 11 settingMetavar
      . showString " "
      . showsPrec 11 settingHelp

showMaybeWith :: (a -> ShowS) -> Maybe a -> ShowS
showMaybeWith _ Nothing = showString "Nothing"
showMaybeWith func (Just a) = showParen True $ showString "Just " . func a

newtype Builder a = Builder {unBuilder :: Setting a -> Setting a}

instance Semigroup (Builder f) where
  (<>) (Builder f1) (Builder f2) = Builder (f1 . f2)

instance Monoid (Builder f) where
  mempty = Builder id
  mappend = (<>)

completeBuilder :: Builder a -> Setting a
completeBuilder b = unBuilder b emptySetting

help :: String -> Builder a
help s = Builder $ \op -> op {settingHelp = Just s}

metavar :: String -> Builder a
metavar mv = Builder $ \s -> s {settingMetavar = Just mv}

strArgument :: (IsString string) => Builder string
strArgument = argument str

argument :: Reader a -> Builder a
argument r = Builder $ \s -> s {settingArguments = r : settingArguments s}

strOption :: (IsString string) => Builder string
strOption = option str

option :: Reader a -> Builder a
option r = Builder $ \s -> s {settingOptions = r : settingOptions s}

switch :: a -> Builder a
switch v = Builder $ \s -> s {settingSwitchValue = Just v}

long :: String -> Builder a
long "" = error "Cannot use an empty long-form option."
long l = Builder $ \s -> s {settingDasheds = DashedLong (NE.fromList l) : settingDasheds s}

short :: Char -> Builder a
short c = Builder $ \s -> s {settingDasheds = DashedShort c : settingDasheds s}

strEnvVar :: (IsString string) => String -> Builder string
strEnvVar = envVar str

envVar :: Reader a -> String -> Builder a
envVar r v = Builder $ \s -> s {settingEnvVars = (r, v) : settingEnvVars s}
