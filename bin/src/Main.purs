module Main where

import Prelude

import Cmd.Compile as Compile
import Data.Foldable (fold)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Options.Applicative ((<**>))
import Options.Applicative as Ops
import Options.Applicative as Opts
import Version (versionString)

data Command = Compile Compile.Options

main :: Effect Unit
main = launchAff_ do
  opts <- liftEffect (Opts.execParser parser)
  case opts.command of
    Compile cmdOpts -> Compile.cmd opts.dist cmdOpts
  where
  parser = Opts.info (pinfo <**> Opts.helper <**> versionInfo)
    ( Opts.fullDesc
        <> Opts.header "Purvasm - the PureScript bytecode compiler and interpreter"
    )

  versionInfo :: forall a. Opts.Parser (a -> a)
  versionInfo = Opts.abortOption (Opts.InfoMsg versionString) $ fold
    [ Opts.long "version"
    , Opts.short 'v'
    , Opts.help "Show the version number"
    , Opts.hidden
    ]

  pinfo = ado
    dist <- Opts.strOption $ fold $
      [ Opts.long "dist"
      , Opts.short 'd'
      , Opts.value "purvasm-dist"
      , Opts.metavar "DIST_PATH"
      , Opts.help "Path to purvasm output directory"
      ]

    command <- Ops.hsubparser $ fold $
      [ Opts.command "compile"
          ( Opts.info (Compile <$> Compile.options)
              (Opts.progDesc "Compile PureScript corefn module")
          )
      ]
    in { dist, command }