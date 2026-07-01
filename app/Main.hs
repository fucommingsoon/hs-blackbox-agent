{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.Aeson           as A
import           Data.Aeson           ((.=))
import qualified Data.ByteString.Lazy as BL
import           Data.List            (isPrefixOf, partition, stripPrefix)
import           Data.Maybe           (mapMaybe)
import qualified Data.Text            as T
import qualified Data.Text.Encoding   as TE
import qualified Data.Text.IO         as TIO
import           System.Directory     (createDirectoryIfMissing)
import           System.Environment   (getArgs, lookupEnv)
import           System.Exit          (ExitCode (..), die)
import           System.FilePath      (takeDirectory)
import           System.Process       (readCreateProcessWithExitCode, proc)

import qualified Blackbox.DTC         as DTC
import qualified Blackbox.DTC.Runtime as Runtime


main :: IO ()
main = do
    allArgs <- getArgs
    let (flagArgs, positional) = partition ("--" `isPrefixOf`) allArgs
        appPath = parseAppFlag flagArgs
        outputDir = parseOutputFlag flagArgs
        bindingPath = parseBindingFlag flagArgs
        corpusPath = parseCorpusFlag flagArgs
        packetPath = parsePacketFlag flagArgs
        responsePath = parseResponseFlag flagArgs
        resultsPath = parseResultsFlag flagArgs
        stageName = parseStageFlag flagArgs
        modelName = maybe "deepseek-chat" T.pack (parseModelFlag flagArgs)
        apiUrl = maybe "https://api.deepseek.com/chat/completions" id (parseApiUrlFlag flagArgs)
    case positional of
        ["dtc", "plan", name] -> runPlan (T.pack name)
        ["dtc", "coverage", name] -> runCoverage (T.pack name)
        ["dtc", "requirements", archetype] -> runRequirements (T.pack archetype)
        ["dtc", "validate-binding"] -> runValidateBinding bindingPath
        ["dtc", "plan-binding"] -> runPlanBinding bindingPath
        ["dtc", "run-binding"] -> runBinding appPath outputDir bindingPath
        ["dtc", "system-prepare"] -> runSystemPrepare corpusPath resultsPath outputDir
        ["dtc", "system-call"] -> runSystemCall packetPath stageName modelName apiUrl outputDir
        ["dtc", "system-validate"] -> runSystemValidate packetPath stageName responsePath
        ["dtc", "flow"]       -> TIO.putStrLn DTC.dtcFlowMermaid
        ["dtc", "run", name]  -> runDtc appPath outputDir (T.pack name)
        _                     -> die usage


usage :: String
usage = unlines
    [ "usage:"
    , "  hsbb dtc plan <entr|bat>"
    , "  hsbb dtc coverage <entr|bat>"
    , "  hsbb dtc requirements <WatcherCli|HttpClientCli>"
    , "  hsbb dtc validate-binding --binding=<file>"
    , "  hsbb dtc plan-binding --binding=<file>"
    , "  hsbb dtc run-binding --binding=<file> --app=<binary> [--out=<dir>]"
    , "  hsbb dtc system-prepare --corpus=<dir> [--results=<results.jsonl>] [--out=<file>]"
    , "  hsbb dtc system-call --packet=<file> --stage=<stage> [--model=<model>] [--api-url=<url>] [--out=<file>]"
    , "  hsbb dtc system-validate --packet=<file> --stage=<stage> --response=<file>"
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


parseCorpusFlag :: [String] -> Maybe FilePath
parseCorpusFlag flags =
    case mapMaybe (stripPrefix "--corpus=") flags of
        []      -> Nothing
        (p : _) -> Just p


parseResultsFlag :: [String] -> Maybe FilePath
parseResultsFlag flags =
    case mapMaybe (stripPrefix "--results=") flags of
        []      -> Nothing
        (p : _) -> Just p


parsePacketFlag :: [String] -> Maybe FilePath
parsePacketFlag flags =
    case mapMaybe (stripPrefix "--packet=") flags of
        []      -> Nothing
        (p : _) -> Just p


parseResponseFlag :: [String] -> Maybe FilePath
parseResponseFlag flags =
    case mapMaybe (stripPrefix "--response=") flags of
        []      -> Nothing
        (p : _) -> Just p


parseStageFlag :: [String] -> Maybe T.Text
parseStageFlag flags =
    case mapMaybe (stripPrefix "--stage=") flags of
        []      -> Nothing
        (p : _) -> Just (T.pack p)


parseModelFlag :: [String] -> Maybe String
parseModelFlag flags =
    case mapMaybe (stripPrefix "--model=") flags of
        []      -> Nothing
        (p : _) -> Just p


parseApiUrlFlag :: [String] -> Maybe String
parseApiUrlFlag flags =
    case mapMaybe (stripPrefix "--api-url=") flags of
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
    binding <- readBinding path
    BL.putStr (A.encode (DTC.validateBinding binding))


runPlanBinding :: Maybe FilePath -> IO ()
runPlanBinding Nothing =
    die "hsbb dtc plan-binding requires --binding=<file>"
runPlanBinding (Just path) = do
    binding <- readBinding path
    case DTC.planFromBinding binding of
        Left err   -> die (T.unpack err)
        Right plan -> BL.putStr (A.encode plan)


runBinding :: Maybe FilePath -> Maybe FilePath -> Maybe FilePath -> IO ()
runBinding Nothing _ _ =
    die "hsbb dtc run-binding requires --app=<binary>"
runBinding _ _ Nothing =
    die "hsbb dtc run-binding requires --binding=<file>"
runBinding (Just appPath) outputDir (Just bindingPath) = do
    binding <- readBinding bindingPath
    let validation = DTC.validateBinding binding
    case DTC.bvStatus validation of
        DTC.BindingReady ->
            case DTC.planFromBinding binding of
                Left err -> die (T.unpack err)
                Right plan -> do
                    results <- Runtime.runPlan (Runtime.RunOptions outputDir) appPath plan
                    BL.putStr (A.encode results)
        _ ->
            die $ "binding is not ready: " ++ show (DTC.bvStatus validation)


runSystemPrepare :: Maybe FilePath -> Maybe FilePath -> Maybe FilePath -> IO ()
runSystemPrepare Nothing _ _ =
    die "hsbb dtc system-prepare requires --corpus=<dir>"
runSystemPrepare (Just corpusPath) resultsPath outputPath = do
    digest <- DTC.collectCorpusDigest corpusPath
    packet <- DTC.prepareDeepSeekPacket digest resultsPath
    let bytes = A.encode packet
    case outputPath of
        Nothing -> BL.putStr bytes
        Just path -> do
            ensureParent path
            BL.writeFile path bytes
            BL.putStr (A.encode (systemPrepareSummary path packet))


runSystemCall :: Maybe FilePath -> Maybe T.Text -> T.Text -> String -> Maybe FilePath -> IO ()
runSystemCall Nothing _ _ _ _ =
    die "hsbb dtc system-call requires --packet=<file>"
runSystemCall _ Nothing _ _ _ =
    die "hsbb dtc system-call requires --stage=<stage>"
runSystemCall (Just packetPath) (Just stage) model apiUrl outputPath = do
    packet <- readDeepSeekPacket packetPath
    request <- case DTC.deepSeekRequestJson model packet stage of
        Left err    -> die (T.unpack err)
        Right value -> pure value
    apiKey <- lookupEnv "DEEPSEEK_API_KEY"
    key <- case apiKey of
        Nothing -> die "DEEPSEEK_API_KEY is required for hsbb dtc system-call"
        Just k  -> pure k
    let requestBytes = A.encode request
    (exitCode, out, err) <- readCreateProcessWithExitCode
        (proc "curl"
            [ "-sS"
            , "-X", "POST"
            , apiUrl
            , "-H", "Content-Type: application/json"
            , "-H", "Authorization: Bearer " <> key
            , "--data-binary", "@-"
            ])
        (T.unpack (TE.decodeUtf8 (BL.toStrict requestBytes)))
    case exitCode of
        ExitSuccess -> do
            let bytes = BL.fromStrict (TE.encodeUtf8 (T.pack out))
                validation = DTC.validateDeepSeekOutput packet stage bytes
                summary = A.object
                    [ "stage" .= stage
                    , "model" .= model
                    , "responseOut" .= outputPath
                    , "validation" .= validation
                    ]
            case outputPath of
                Nothing -> BL.putStr bytes
                Just path -> do
                    ensureParent path
                    BL.writeFile path bytes
                    BL.putStr (A.encode summary)
        _ -> die ("DeepSeek curl failed: " <> err)


runSystemValidate :: Maybe FilePath -> Maybe T.Text -> Maybe FilePath -> IO ()
runSystemValidate Nothing _ _ =
    die "hsbb dtc system-validate requires --packet=<file>"
runSystemValidate _ Nothing _ =
    die "hsbb dtc system-validate requires --stage=<stage>"
runSystemValidate _ _ Nothing =
    die "hsbb dtc system-validate requires --response=<file>"
runSystemValidate (Just packetPath) (Just stage) (Just responsePath) = do
    packet <- readDeepSeekPacket packetPath
    response <- BL.readFile responsePath
    BL.putStr (A.encode (DTC.validateDeepSeekOutput packet stage response))


readBinding :: FilePath -> IO DTC.BindingInput
readBinding path = do
    bytes <- BL.readFile path
    case A.eitherDecode bytes of
        Left err -> die $ "invalid binding JSON: " ++ err
        Right binding -> pure binding


readDeepSeekPacket :: FilePath -> IO DTC.DeepSeekPacket
readDeepSeekPacket path = do
    bytes <- BL.readFile path
    case A.eitherDecode bytes of
        Left err     -> die $ "invalid DeepSeek packet JSON: " ++ err
        Right packet -> pure packet


runDtc :: Maybe FilePath -> Maybe FilePath -> T.Text -> IO ()
runDtc Nothing _ _ =
    die "hsbb dtc run requires --app=<binary>"
runDtc (Just appPath) outputDir name =
    case DTC.planByName name of
        Just plan -> do
            results <- Runtime.runPlan (Runtime.RunOptions outputDir) appPath plan
            BL.putStr (A.encode results)
        Nothing -> die $ "unknown DTC plan: " ++ T.unpack name


ensureParent :: FilePath -> IO ()
ensureParent path =
    case takeDirectory path of
        ""  -> pure ()
        "." -> pure ()
        dir -> createDirectoryIfMissing True dir


systemPrepareSummary :: FilePath -> DTC.DeepSeekPacket -> A.Value
systemPrepareSummary path packet =
    A.object
        [ "out" .= path
        , "provider" .= DTC.dspProvider packet
        , "corpusRoot" .= DTC.cdRoot (DTC.dspCorpusDigest packet)
        , "filesScanned" .= DTC.cdFilesScanned (DTC.dspCorpusDigest packet)
        , "filesIncluded" .= DTC.cdFilesIncluded (DTC.dspCorpusDigest packet)
        , "chunks" .= length (DTC.cdChunks (DTC.dspCorpusDigest packet))
        , "resultChunks" .= length (DTC.dspResultChunks packet)
        , "stages" .= map DTC.lspStage (DTC.dspStagePrompts packet)
        ]
