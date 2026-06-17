{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.Text          as T
import           System.Environment (getArgs, lookupEnv)
import           System.Exit        (die)

import qualified Blackbox.Belief    as Belief
import qualified Blackbox.Init      as Init
import qualified Blackbox.Loop      as Loop
import qualified Blackbox.Oracle    as Oracle
import qualified Blackbox.Trace     as Trace


main :: IO ()
main = do
    args <- getArgs
    case args of
        ["init",   taskDir] -> runInit   taskDir
        ["step",   taskDir] -> runStep   taskDir
        ["loop",   taskDir] -> runLoop   taskDir
        ["belief", taskDir] -> runBelief taskDir
        ["full",   taskDir] -> runFull   taskDir
        [taskDir]           -> runFull   taskDir
        _                   -> die $ unlines
            [ "usage:"
            , "  hsbb init   <task-dir>   # digest docs → oracle.yaml"
            , "  hsbb step   <task-dir>   # one round (decision + maybe explore + integration)"
            , "  hsbb loop   <task-dir>   # loop until 20 min wall-clock or stop"
            , "  hsbb belief <task-dir>   # synthesize belief.md from oracle.yaml"
            , "  hsbb full   <task-dir>   # init + loop + belief"
            ]


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


runInit :: FilePath -> IO ()
runInit taskDir = do
    putStrLn $ "=== hsbb init — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Init.runInit oracle apiKey model taskDir traceDir
    putStrLn "[init] done"


runStep :: FilePath -> IO ()
runStep taskDir = do
    putStrLn $ "=== hsbb step — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Loop.runStep oracle apiKey model taskDir traceDir


runLoop :: FilePath -> IO ()
runLoop taskDir = do
    putStrLn $ "=== hsbb loop — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Loop.runLoop oracle apiKey model taskDir traceDir
    putStrLn "[loop] done"


runBelief :: FilePath -> IO ()
runBelief taskDir = do
    putStrLn $ "=== hsbb belief — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    Belief.synthesize oracle apiKey model taskDir traceDir
    putStrLn "[belief] done"


runFull :: FilePath -> IO ()
runFull taskDir = do
    putStrLn $ "=== hsbb full — " ++ taskDir ++ " ==="
    (oracle, apiKey, model, traceDir) <- setup taskDir
    nProbes <- Oracle.countProbes oracle
    if nProbes == 0
        then do
            putStrLn "[full] fresh; running init"
            Init.runInit oracle apiKey model taskDir traceDir
        else
            putStrLn $ "[full] resume detected (" ++ show nProbes ++ " probes), skip init"
    Loop.runLoop oracle apiKey model taskDir traceDir
    Belief.synthesize oracle apiKey model taskDir traceDir
    putStrLn "=== done ==="
