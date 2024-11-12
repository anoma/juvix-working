module Commands.Dev.Nockma.Ide.Options where

import Commands.Dev.Nockma.Ide.Check.Options
import Commands.Dev.Nockma.Ide.Highlight.Options
import CommonOptions

data NockmaIdeCommand
  = NockmaIdeHighlight NockmaHighlightOptions
  | NockmaIdeCheck NockmaCheckOptions
  deriving stock (Data)

parseNockmaIdeCommand :: Parser NockmaIdeCommand
parseNockmaIdeCommand =
  hsubparser $
    mconcat
      [ commandHighlight,
        commandCheck
      ]
  where
    commandHighlight :: Mod CommandFields NockmaIdeCommand
    commandHighlight = command "highlight" runInfo
      where
        runInfo :: ParserInfo NockmaIdeCommand
        runInfo =
          info
            (NockmaIdeHighlight <$> parseNockmaHighlightOptions)
            (progDesc "Highlight a nockma term (only for Emacs)")

    commandCheck :: Mod CommandFields NockmaIdeCommand
    commandCheck = command "check" runInfo
      where
        runInfo :: ParserInfo NockmaIdeCommand
        runInfo =
          info
            (NockmaIdeCheck <$> parseNockmaCheckOptions)
            (progDesc "Parse a nockma term")
