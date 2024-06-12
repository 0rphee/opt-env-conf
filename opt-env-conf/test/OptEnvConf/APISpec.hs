{-# LANGUAGE ScopedTypeVariables #-}

module OptEnvConf.APISpec (spec) where

import Data.Map (Map)
import Data.Text (Text)
import qualified Data.Text as T
import OptEnvConf
import OptEnvConf.Lint
import OptEnvConf.Parser
import Test.Syd
import Text.Colour
import Text.Show.Pretty as Pretty

spec :: Spec
spec = do
  exampleParserSpec "args" argsParser
  exampleParserSpec "optional" optionalParser
  exampleParserSpec "big-config" bigConfigParser
  exampleParserSpec "hidden" hiddenParser
  exampleParserSpec "greet" greetParser

exampleParserSpec :: FilePath -> Parser a -> Spec
exampleParserSpec dir p = describe dir $ do
  let parser = internalParser p

  it "passes the linter" $
    case lintParser parser of
      Nothing -> pure ()
      Just errs ->
        expectationFailure $ T.unpack $ renderChunksText With24BitColours $ renderLintErrors errs

  it "produces the same docs structure as before" $
    pureGoldenStringFile ("test_resources/docs/" <> dir <> "/docs.txt") $
      ppShow $
        parserDocs parser

  it "produces the same opt docs structure as before" $
    pureGoldenStringFile ("test_resources/docs/" <> dir <> "/opt-docs.txt") $
      ppShow $
        parserOptDocs parser

  it "produces the same env docs structure as before" $
    pureGoldenStringFile ("test_resources/docs/" <> dir <> "/env-docs.txt") $
      ppShow $
        parserConfDocs parser

  it "produces the same conf docs structure as before" $
    pureGoldenStringFile ("test_resources/docs/" <> dir <> "/config-docs.txt") $
      ppShow $
        parserEnvDocs parser

  it "documents the man page in the same way" $
    pureGoldenChunksFile ("test_resources/docs/" <> dir <> "/man.txt") $
      renderManPage dir $
        parserDocs parser

  it "documents the help page in the same way" $
    pureGoldenChunksFile ("test_resources/docs/" <> dir <> "/help.txt") $
      renderHelpPage dir $
        parserDocs parser

  it "documents the short opt parser in the same way" $
    pureGoldenChunksFile ("test_resources/docs/" <> dir <> "/opt-short.txt") $
      renderShortOptDocs dir $
        parserOptDocs parser

  it "documents the long opt parser in the same way" $
    pureGoldenChunksFile ("test_resources/docs/" <> dir <> "/opt-long.txt") $
      renderLongOptDocs $
        parserOptDocs parser

  it "documents the env parser in the same way" $
    pureGoldenChunksFile ("test_resources/docs/" <> dir <> "/env.txt") $
      renderEnvDocs $
        parserEnvDocs parser

  it "documents the conf parser in the same way" $
    pureGoldenChunksFile ("test_resources/docs/" <> dir <> "/config.txt") $
      renderConfDocs $
        parserConfDocs parser

  it "shows the parser in the same way" $
    goldenStringFile ("test_resources/docs/" <> dir <> "/show.txt") $
      case Pretty.parseValue (showParserABit parser) of
        Nothing -> expectationFailure "Error parsing value"
        Just v -> pure $ Pretty.valToStr v

pureGoldenChunksFile :: FilePath -> [Chunk] -> GoldenTest Text
pureGoldenChunksFile fp cs =
  pureGoldenTextFile fp $ renderChunksText With24BitColours cs

data Greet = Greet
  { greetGreetee :: String,
    greetGreeting :: Maybe String,
    greetPolite :: Bool
  }
  deriving (Show)

greetParser :: Parser Greet
greetParser =
  prefixed "GREET_" $
    Greet
      <$> setting
        [ reader str,
          argument,
          help "Who to greet",
          value "world",
          metavar "SUBJECT"
        ]
      <*> optional
        ( setting
            [ reader str,
              option,
              short 'g',
              long "greeting",
              metavar "GREETING",
              env "GREETING",
              conf "greeting",
              help "Greeting to use"
            ]
        )
      <*> setting
        [ reader exists,
          switch True,
          short 'p',
          long "polite",
          env "POLITE",
          conf "polite",
          value False,
          help "Whether to be polite"
        ]

data BigConfig = BigConfig (Map String (Map String Int))

bigConfigParser :: Parser BigConfig
bigConfigParser =
  BigConfig
    <$> setting
      [ conf "big",
        help "multi-line config codec explanation"
      ]

data Args = Args [String]
  deriving (Show)

argsParser :: Parser Args
argsParser =
  Args
    <$> many
      ( setting
          [ reader str,
            argument,
            help "Argument",
            metavar "ARGUMENT"
          ]
      )

data Optional = Optional (Maybe String)

optionalParser :: Parser Optional
optionalParser =
  Optional
    <$> optional
      ( setting
          [ reader str,
            argument,
            help "Argument",
            metavar "ARGUMENT"
          ]
      )

data Hidden = Hidden String

hiddenParser :: Parser Hidden
hiddenParser =
  Hidden
    <$> setting
      [ reader str,
        argument,
        hidden,
        value "default",
        help "Example of a hidden setting"
      ]
