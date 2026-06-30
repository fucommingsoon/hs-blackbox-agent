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
        outputDir = parseOutputFlag flagArgs
        bindingPath = parseBindingFlag flagArgs
    case positional of
        ["dtc", "plan", name] -> runPlan (T.pack name)
        ["dtc", "coverage", name] -> runCoverage (T.pack name)
        ["dtc", "requirements", archetype] -> runRequirements (T.pack archetype)
        ["dtc", "validate-binding"] -> runValidateBinding bindingPath
        ["dtc", "flow"]       -> TIO.putStrLn DTC.dtcFlowMermaid
        ["dtc", "run", name]  -> runDtc appPath outputDir (T.pack name)
        _                     -> die usage


usage :: String
usage = unlines
    [ "usage:"
    , "  hsbb dtc plan <entr|bat>"
    , "  hsbb dtc coverage <entr|bat>"
    , "  hsbb dtc requirements <WatcherCli>"
    , "  hsbb dtc validate-binding --binding=<file>"
    , "  hsbb dtc flow"
    , "  hsbb dtc run <entr|bat> --app=<binary> [--out=<dir>]"
    ]


parseAppFlag :: [String] -> Maybe FilePath
parseAppFlag flags =
    case mapMaybe (stripPrefix "--app=") flags of
        []      -> Nothing
        (p : _) -> Just p


parseOutputFlag :: [String] -> Maybe FilePath
parseOutputFlag flags =
    case mapMaybe (stripPrefix "--out=") flags of
        []      -> Nothing
        (p : _) -> Just p


parseBindingFlag :: [String] -> Maybe FilePath
parseBindingFlag flags =
    case mapMaybe (stripPrefix "--binding=") flags of
        []      -> Nothing
        (p : _) -> Just p


runPlan :: T.Text -> IO ()
runPlan name =
    case DTC.planByName name of
        Just plan -> BL.putStr (A.encode plan)
        Nothing   -> die $ "unknown DTC plan: " ++ T.unpack name


runCoverage :: T.Text -> IO ()
runCoverage name =
    case DTC.planByName name of
        Just plan -> BL.putStr (A.encode (DTC.summarizePlanCoverage plan))
        Nothing   -> die $ "unknown DTC plan: " ++ T.unpack name


runRequirements :: T.Text -> IO ()
runRequirements archetype =
    case DTC.archetypeRequirementByName archetype of
        Just requirement -> BL.putStr (A.encode requirement)
        Nothing -> die $ "unknown or unsupported DTC archetype: " ++ T.unpack archetype


runValidateBinding :: Maybe FilePath -> IO ()
runValidateBinding Nothing =
    die "hsbb dtc validate-binding requires --binding=<file>"
runValidateBinding (Just path) = do
    bytes <- BL.readFile path
    case A.eitherDecode bytes of
        Left err -> die $ "invalid binding JSON: " ++ err
        Right binding -> BL.putStr (A.encode (DTC.validateBinding binding))


runDtc :: Maybe FilePath -> Maybe FilePath -> T.Text -> IO ()
runDtc Nothing _ _ =
    die "hsbb dtc run requires --app=<binary>"
runDtc (Just appPath) outputDir name =
    case DTC.planByName name of
        Just plan -> do
            results <- Runtime.runPlan (Runtime.RunOptions outputDir) appPath plan
            BL.putStr (A.encode results)
        Nothing -> die $ "unknown DTC plan: " ++ T.unpack name
