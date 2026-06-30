{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.Aeson           as A
import qualified Data.ByteString.Lazy as BL
import           Data.List            (isPrefixOf, partition, stripPrefix)
import           Data.Maybe           (mapMaybe)
import qualified Data.Text            as T
import qualified Data.Text.IO         as TIO
import           System.Environment   (getArgs)
import           System.Exit          (die)

import qualified Blackbox.DTC         as DTC
import qualified Blackbox.DTC.Runtime as Runtime


main :: IO ()
main = do
    allArgs <- getArgs
    let (flagArgs, positional) = partition ("--" `isPrefixOf`) allArgs
        appPath = parseAppFlag flagArgs
    case positional of
        ["dtc", "plan", name] -> runPlan (T.pack name)
        ["dtc", "flow"]       -> TIO.putStrLn DTC.dtcFlowMermaid
        ["dtc", "run", name]  -> runDtc appPath (T.pack name)
        _                     -> die usage


usage :: String
usage = unlines
    [ "usage:"
    , "  hsbb dtc plan <entr|bat>"
    , "  hsbb dtc flow"
    , "  hsbb dtc run <entr|bat> --app=<binary>"
    ]


parseAppFlag :: [String] -> Maybe FilePath
parseAppFlag flags =
    case mapMaybe (stripPrefix "--app=") flags of
        []      -> Nothing
        (p : _) -> Just p


runPlan :: T.Text -> IO ()
runPlan name =
    case DTC.planByName name of
        Just plan -> BL.putStr (A.encode plan)
        Nothing   -> die $ "unknown DTC plan: " ++ T.unpack name


runDtc :: Maybe FilePath -> T.Text -> IO ()
runDtc Nothing _ =
    die "hsbb dtc run requires --app=<binary>"
runDtc (Just appPath) name =
    case DTC.planByName name of
        Just plan -> do
            results <- Runtime.runPlan appPath plan
            BL.putStr (A.encode results)
        Nothing -> die $ "unknown DTC plan: " ++ T.unpack name
