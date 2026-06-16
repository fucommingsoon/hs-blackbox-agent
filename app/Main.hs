{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           System.Environment (getArgs)
import           System.Exit (die)

import           Blackbox.InnerLoop (runAgent)


main :: IO ()
main = do
    args <- getArgs
    case args of
        ["agent", taskDir] -> runAgent taskDir
        ["--version"]      -> putStrLn "hs-blackbox-agent 0.1.0.0"
        _ -> die $ unlines
            [ "Usage:"
            , "  hsbb agent <task_dir>   — probe a PB task black box; write belief.md"
            , "  hsbb --version"
            ]
