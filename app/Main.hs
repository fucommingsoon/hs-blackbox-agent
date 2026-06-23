{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           Control.Monad      (when)
import           Data.Char          (isDigit)
import           Data.List          (isPrefixOf, partition, stripPrefix)
import           Data.Maybe         (isJust, mapMaybe)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Directory   (doesDirectoryExist, doesFileExist,
                                     listDirectory)
import           System.Environment (getArgs, lookupEnv)
import           System.Exit        (die)
import           System.FilePath    ((</>))
import           System.Process     (callProcess)

import qualified Blackbox.Belief    as Belief
import qualified Blackbox.Init      as Init
import qualified Blackbox.Loop      as Loop
import qualified Blackbox.Oracle    as Oracle
import qualified Blackbox.Trace     as Trace


main :: IO ()
main = do
    allArgs <- getArgs
    let (flagArgs, positional) = partition ("--" `isPrefixOf`) allArgs
    overrides <- loadOverridesFromFlags flagArgs
    case positional of
        ["init",      taskDir] -> runInit     taskDir overrides
        ["step",      taskDir] -> runStep     taskDir overrides
        ["loop",      taskDir] -> runLoop     taskDir overrides
        ["belief",    taskDir] -> runBelief   taskDir
        ["full",      taskDir] -> runFull     taskDir overrides
        ["step-snap", rootDir] -> runStepSnap rootDir  overrides
        [taskDir]              -> runFull     taskDir overrides
        _                      -> die $ unlines
            [ "usage:"
            , "  hsbb init      <task-dir>   [--prompts-dir=<path>]"
            , "  hsbb step      <task-dir>   [--prompts-dir=<path>]"
            , "  hsbb loop      <task-dir>   [--prompts-dir=<path>]"
            , "  hsbb belief    <task-dir>"
            , "  hsbb full      <task-dir>   [--prompts-dir=<path>]"
            , "  hsbb step-snap <root-dir>   [--prompts-dir=<path>]"
            , ""
            , "--prompts-dir=<path>:"
            , "  Override built-in system prompts with files in <path>:"
            , "    decision.txt     → 决策 system prompt"
            , "    integration.txt  → 整理 system prompt"
            , "    gate.txt         → gate system prompt"
            , "    init.txt         → init system prompt"
            , "  任一文件不存在 → 回退到内置默认。"
            ]


-- ---------------------------------------------------------------
-- CLI flag parsing for --prompts-dir
-- ---------------------------------------------------------------

loadOverridesFromFlags :: [String] -> IO Loop.PromptOverrides
loadOverridesFromFlags flags =
    case mapMaybe (stripPrefix "--prompts-dir=") flags of
        []      -> pure Loop.emptyOverrides
        (p : _) -> loadPromptOverrides p

loadPromptOverrides :: FilePath -> IO Loop.PromptOverrides
loadPromptOverrides dir = do
    ex <- doesDirectoryExist dir
    when (not ex) (die $ "--prompts-dir: " ++ dir ++ " does not exist")
    decision    <- tryReadFile (dir </> "decision.txt")
    integration <- tryReadFile (dir </> "integration.txt")
    gate        <- tryReadFile (dir </> "gate.txt")
    initP       <- tryReadFile (dir </> "init.txt")
    let loadedCount = length (filter isJust [decision, integration, gate, initP])
    putStrLn $ "[prompts] loaded " ++ show loadedCount
            ++ "/4 overrides from " ++ dir
    pure Loop.PromptOverrides
        { Loop.poDecisionSystem    = decision
        , Loop.poIntegrationSystem = integration
        , Loop.poGateSystem        = gate
        , Loop.poInitSystem        = initP
        }
  where
    tryReadFile p = do
        ex <- doesFileExist p
        if ex then Just <$> TIO.readFile p else pure Nothing


-- ---------------------------------------------------------------
-- Common setup
-- ---------------------------------------------------------------

setup :: FilePath -> IO (Oracle.Oracle, T.Text, T.Text, Trace.TraceHandle)
setup taskDir = do
    mKey <- lookupEnv "DEEPSEEK_API_KEY"
    apiKey <- case mKey of
        Just k -> pure (T.pack k)
        Nothing -> die "DEEPSEEK_API_KEY not set"
    let model = "deepseek-chat"
    trace <- Trace.openTrace taskDir
    oracle <- Oracle.initOracle taskDir
    pure (oracle, apiKey, model, trace)


-- ---------------------------------------------------------------
-- Run sub-commands
-- ---------------------------------------------------------------

runInit :: FilePath -> Loop.PromptOverrides -> IO ()
runInit taskDir overrides = do
    putStrLn $ "=== hsbb init — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Init.runInit oracle apiKey model taskDir traceDir overrides
    putStrLn "[init] done"


runStep :: FilePath -> Loop.PromptOverrides -> IO ()
runStep taskDir overrides = do
    putStrLn $ "=== hsbb step — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Loop.runStep oracle apiKey model taskDir traceDir overrides


runLoop :: FilePath -> Loop.PromptOverrides -> IO ()
runLoop taskDir overrides = do
    putStrLn $ "=== hsbb loop — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Loop.runLoop oracle apiKey model taskDir traceDir overrides
    putStrLn "[loop] done"


runBelief :: FilePath -> IO ()
runBelief taskDir = do
    putStrLn $ "=== hsbb belief — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Belief.synthesize oracle apiKey model taskDir traceDir
    putStrLn "[belief] done"


runFull :: FilePath -> Loop.PromptOverrides -> IO ()
runFull taskDir overrides = do
    putStrLn $ "=== hsbb full — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    nProbes <- Oracle.countProbes oracle
    if nProbes == 0
        then do
            putStrLn "[full] fresh; running init"
            Init.runInit oracle apiKey model taskDir traceDir overrides
        else
            putStrLn $ "[full] resume detected (" ++ show nProbes ++ " probes), skip init"
    Loop.runLoop oracle apiKey model taskDir traceDir overrides
    Belief.synthesize oracle apiKey model taskDir traceDir
    putStrLn "=== done ==="


-- step-snap: snapshot mode. rootDir contains step_N/ subdirs.
-- - First step (only step_0 present): cp step_0 → step_1, run init in step_1.
-- - Subsequent: cp max step_N → step_(N+1), run one step in step_(N+1).
runStepSnap :: FilePath -> Loop.PromptOverrides -> IO ()
runStepSnap rootDir overrides = do
    putStrLn $ "=== hsbb step-snap — " ++ rootDir ++ " ==="
    rootExists <- doesDirectoryExist rootDir
    when (not rootExists) (die $ rootDir ++ " does not exist")
    entries <- listDirectory rootDir
    let stepNs = mapMaybe parseStepN entries
    case stepNs of
        [] -> die $ rootDir ++ ": no step_N/ subdir found. "
                 ++ "Create step_0/ with source materials first: "
                 ++ "mkdir -p " ++ rootDir ++ "/step_0 && cp -R <pb-task>/* " ++ rootDir ++ "/step_0/"
        ns -> do
            let maxN     = maximum ns
                nextN    = maxN + 1
                srcDir   = rootDir </> ("step_" ++ show maxN)
                dstDir   = rootDir </> ("step_" ++ show nextN)
            dstExists <- doesDirectoryExist dstDir
            when dstExists (die $ dstDir ++ " already exists; aborting")
            putStrLn $ "[step-snap] cp -R " ++ srcDir ++ " → " ++ dstDir
            callProcess "cp" ["-R", srcDir, dstDir]
            if maxN == 0
                then do
                    putStrLn "[step-snap] step_1: running init"
                    runInit dstDir overrides
                else do
                    putStrLn $ "[step-snap] step_" ++ show nextN ++ ": running step"
                    runStep dstDir overrides


parseStepN :: FilePath -> Maybe Int
parseStepN name = case stripPrefix "step_" name of
    Just s | not (null s), all isDigit s -> Just (read s)
    _                                    -> Nothing
