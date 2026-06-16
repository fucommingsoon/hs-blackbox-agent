{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           Data.List (nub)
import           Data.Maybe (isNothing)
import qualified Data.Text as T
import           System.Exit (exitFailure, exitSuccess)

import           Blackbox.Classifier
import           Blackbox.EmbeddedData (embeddedMethodology)
import           Blackbox.Extract
import           Blackbox.Idiom
import           Blackbox.Plan
import           Blackbox.Types


main :: IO ()
main = do
    let tests =
            [ ("embedded methodology non-empty",       not (T.null embeddedMethodology))
            , ("methodology lists 34 idioms",          T.isInfixOf "34" embeddedMethodology)
            , ("strategy < 200 = discovery",           chooseStrategy 100 == StrategyDiscovery)
            , ("strategy 500 = hybrid",                chooseStrategy 500 == StrategyHybrid)
            , ("strategy 2000 = landscape",            chooseStrategy 2000 == StrategyLandscape)
            , ("plan for F1 has stages",               not (null (planFor F1_PureFunction)))
            , ("plan for F6 silent has 'invert' stage",
                 any (\s -> "invert" `T.isInfixOf` psNameRaw s) (planFor F6_SilentLinter))
            , ("plan for F12 starts with asset listing",
                 case planFor F12_AssetDependent of
                     (s : _) -> "list_task_dir_assets" `T.isInfixOf` psNameRaw s
                     _       -> False)
            , ("all 12 forms have non-empty plans",
                 all (not . null . planFor) bbtAllForms)
            , ("idiom library has exactly 34 entries",
                 length allIdioms == 34)
            , ("all idioms have unique IDs",
                 length (map iId allIdioms) == length (nub (map iId allIdioms)))
            , ("F8 binary form has ≥ 4 applicable idioms (visualize/cmp/det/kat)",
                 length (idiomsFor F8_BinaryByteExact Nothing) >= 4)
            , ("F6 silent form has error_path_inversion idiom",
                 any (\i -> iId i == "error_path_inversion") (idiomsFor F6_SilentLinter Nothing))
            , ("F12 asset form has task_dir_asset_ls idiom",
                 any (\i -> iId i == "task_dir_asset_ls") (idiomsFor F12_AssetDependent Nothing))
            , ("idiomById finds 'exit_capture'",
                 case idiomById "exit_capture" of
                     Just i  -> iId i == "exit_capture"
                     Nothing -> False)
            , ("idiomById on bogus ID returns Nothing",
                 isNothing (idiomById "xyz_nosuch"))
            , ("extractCliFlags picks --help / -v lines",
                 let h = "Usage: foo [opts]\n  --help          show help\n  -v, --version   show version\n  not a flag line\n"
                 in length (extractCliFlags h) == 2)
            , ("classifyExitCode 139 mentions SIGSEGV",
                 T.isInfixOf "SIGSEGV" (classifyExitCode 139))
            , ("classifyExitCode 0 = success",
                 classifyExitCode 0 == "success")
            , ("bucketError nlohmann parse error",
                 bucketError "[json.exception.parse_error.101] parse error at line 1, column 1"
                   == Just "parser: input parse error")
            , ("bucketError empty = Nothing",
                 isNothing (bucketError ""))
            , ("guessLibraries detects Go flag",
                 "Go flag (std)" `elem`
                   guessLibraries "flag provided but not defined: -x\nUsage of foo:")
            , ("guessLibraries detects yaml.v2 reflect BUG",
                 any (T.isInfixOf "reflect-misuse")
                   (guessLibraries "Error writing YAML: reflect: call of reflect.Value.Set on zero Value"))
            , ("detectBug on exit 139 fires",
                 case detectBug 139 "Segmentation fault" of
                     Just s  -> T.isInfixOf "segfault" s
                     Nothing -> False)
            , ("detectBug on clean exit 0 stays silent",
                 isNothing (detectBug 0 ""))
            , ("hexDump renders first n bytes",
                 hexDump 3 "\x28\xb5\x2f\xfd\x24" == "28 b5 2f")
            , ("detectMagicBytes finds zstd",
                 case detectMagicBytes "\x28\xb5\x2f\xfd\x24\x0c\x61\x00" of
                     Just s  -> T.isInfixOf "Zstandard" s
                     Nothing -> False)
            , ("detectMagicBytes on plain text returns Nothing",
                 isNothing (detectMagicBytes "hello world\n"))
            , ("isMostlyBinary on plain text is False",
                 not (isMostlyBinary (T.replicate 100 "abc def\n")))
            , ("isMostlyBinary on zstd payload is True",
                 isMostlyBinary (T.replicate 50 "\x28\xb5\x2f\xfd\x00\x01\x02\x03"))
            , ("detectDiagnosticFormat picks Go-vet style",
                 case detectDiagnosticFormat "main.go:42:5: undefined: foo\n" of
                     Just s  -> T.isInfixOf "Go-vet" s
                     Nothing -> False)
            , ("detectDiagnosticFormat picks dupl range style",
                 case detectDiagnosticFormat "main.go:10,40: clone\n" of
                     Just s  -> T.isInfixOf "dupl" s
                     Nothing -> False)
            , ("detectDiagnosticFormat on plain text returns Nothing",
                 isNothing (detectDiagnosticFormat "hello world\n"))
            ]
    results <- mapM run tests
    if all snd results
        then do
            putStrLn $ "all " <> show (length results) <> " tests passed"
            exitSuccess
        else do
            putStrLn "FAILURES:"
            mapM_ (\(n, p) -> if p then pure () else putStrLn ("  - " <> n)) results
            exitFailure
  where
    run (name, p) = do
        putStrLn $ (if p then "  ok    " else "  FAIL  ") <> name
        pure (name, p)
