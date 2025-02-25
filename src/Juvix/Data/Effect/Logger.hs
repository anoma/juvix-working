module Juvix.Data.Effect.Logger
  ( defaultLoggerOptions,
    replLoggerOptions,
    defaultLogLevel,
    Logger,
    LoggerOptions (..),
    LogLevel (..),
    logMessage,
    logError,
    logErrorWithTag,
    logVerbose,
    logProgress,
    logInfo,
    logWarn,
    logDebug,
    runLoggerIO,
    ignoreLogger,
    localLogger,
    loggerUseColors,
    loggerLevel,
    silenceProgressLog,
  )
where

import Juvix.Data.CodeAnn
import Juvix.Prelude.Base.Foundation
import Juvix.Prelude.Effects.Base
import Juvix.Prelude.Effects.Output
import Prelude (show)

data LogLevel
  = LogLevelError
  | LogLevelWarn
  | LogLevelInfo
  | LogLevelProgress
  | LogLevelVerbose
  | LogLevelDebug
  deriving stock (Eq, Ord, Enum, Bounded)

instance Show LogLevel where
  show = \case
    LogLevelError -> "error"
    LogLevelWarn -> "warn"
    LogLevelInfo -> "info"
    LogLevelProgress -> "progress"
    LogLevelVerbose -> "verbose"
    LogLevelDebug -> "debug"

instance Pretty LogLevel where
  pretty = pretty . Prelude.show

data Logger :: Effect where
  LogMessage :: LogLevel -> AnsiText -> Logger m ()
  LocalLogger :: ((LogLevel -> Bool) -> LogLevel -> Bool) -> m a -> Logger m a

data LoggerOptions = LoggerOptions
  { _loggerUseColors :: Bool,
    _loggerLevel :: LogLevel
  }

defaultLogLevel :: LogLevel
defaultLogLevel = LogLevelProgress

replLoggerOptions :: LoggerOptions
replLoggerOptions =
  LoggerOptions
    { _loggerUseColors = True,
      _loggerLevel = LogLevelWarn
    }

defaultLoggerOptions :: LoggerOptions
defaultLoggerOptions =
  LoggerOptions
    { _loggerUseColors = True,
      _loggerLevel = defaultLogLevel
    }

makeSem ''Logger
makeLenses ''LoggerOptions

logTag :: LogLevel -> Doc CodeAnn
logTag = \case
  LogLevelError -> annotate AnnError "[Error]"
  LogLevelWarn -> "[Warn]"
  LogLevelInfo -> "[Info]"
  LogLevelProgress -> "[Progress]"
  LogLevelVerbose -> "[Verbose]"
  LogLevelDebug -> "[Debug]"

logErrorWithTag :: (Members '[Logger] r) => AnsiText -> Sem r ()
logErrorWithTag msg = logError (mkAnsiText (logTag LogLevelError <> " ") <> msg)

logError :: (Members '[Logger] r) => AnsiText -> Sem r ()
logError = logMessage LogLevelError

logWarn :: (Members '[Logger] r) => AnsiText -> Sem r ()
logWarn = logMessage LogLevelWarn

logInfo :: (Members '[Logger] r) => AnsiText -> Sem r ()
logInfo = logMessage LogLevelInfo

logProgress :: (Members '[Logger] r) => AnsiText -> Sem r ()
logProgress = logMessage LogLevelProgress

logVerbose :: (Members '[Logger] r) => AnsiText -> Sem r ()
logVerbose = logMessage LogLevelVerbose

logDebug :: (Members '[Logger] r) => AnsiText -> Sem r ()
logDebug = logMessage LogLevelDebug

silenceProgressLog :: (Members '[Logger] r) => Sem r a -> Sem r a
silenceProgressLog = localLogger (\f -> f .&&. (/= LogLevelProgress))

runLoggerIO :: forall r a. (Members '[EmbedIO] r) => LoggerOptions -> Sem (Logger ': r) a -> Sem r a
runLoggerIO opts m = do
  liftIO (hSetBuffering stderr LineBuffering)
  interp (re m)
  where
    interp :: Sem (Output AnsiText ': Reader (LogLevel -> Bool) ': r) a -> Sem r a
    interp = runReader (<= (opts ^. loggerLevel)) . runOutputSem printMsg

    printMsg :: forall r'. (Members '[EmbedIO] r') => AnsiText -> Sem r' ()
    printMsg = hRenderIO (opts ^. loggerUseColors) stderr

re :: Sem (Logger ': r) a -> Sem (Output AnsiText ': Reader (LogLevel -> Bool) ': r) a
re = interpretTop2H handler

handler ::
  EffectHandler Logger (Output AnsiText ': Reader (LogLevel -> Bool) ': r)
handler localEnv =
  \case
    LocalLogger adjustPred localLog ->
      localSeqUnlift localEnv $ \unlift ->
        local adjustPred (unlift localLog)
    LogMessage lvl msg -> do
      loggerPredicate <- ask
      when (loggerPredicate lvl) (output (msg <> ansiTextNewline))

ignoreLogger :: forall r a. Sem (Logger ': r) a -> Sem r a
ignoreLogger = interpretH $ \localEnv -> \case
  LogMessage {} -> return ()
  LocalLogger _ localLog ->
    localSeqUnlift localEnv $ \unlift ->
      unlift localLog
