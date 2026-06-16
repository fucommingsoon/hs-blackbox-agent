{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- The inner probe loop.
--
-- v1.1 idiom-driven design:
--   Stage 0: seed probes (identity / help / no-args + self-describe attempts)
--   Stage 1: classify, instantiate plan
--   Stage 2: per plan stage, ask LLM to pick an idiom from a filtered list;
--            agent executes idiom's ProbeAction; runs PostProcess to extract Facts;
--            facts accumulate into Belief
--   Stage 3: write belief.md
module Blackbox.InnerLoop
    ( runAgent
    ) where

import           Control.Exception (catch, SomeException)
import           Control.Monad (unless)
import qualified Data.Aeson as A
import qualified Data.Aeson.KeyMap as KM
import           Data.List (find)
import qualified Data.Text as T
import           Data.Text (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import           System.Directory (listDirectory)
import           System.Environment (lookupEnv)
import           System.FilePath ((</>), takeBaseName)
import           System.IO (hFlush, stdout)

import           Blackbox.Belief
import           Blackbox.Classifier
import           Blackbox.EmbeddedData (embeddedMethodology)
import           Blackbox.Extract
import           Blackbox.Idiom
import           Blackbox.LLM
import           Blackbox.Plan
import           Blackbox.Probe
import           Blackbox.Types


-- Entry point.
runAgent :: FilePath -> IO ()
runAgent taskDir = do
    putStrLn $ "=== hs-blackbox-agent v0.1.1 — " ++ taskDir ++ " ==="
    probeOk <- probeExists taskDir
    unless probeOk $ error ("no ./probe in " ++ taskDir)

    -- Stage 0: doc + asset inventory + seed probes
    putStrLn "[stage 0] doc & asset inventory..."
    docLines <- countDocLines taskDir
    let strategy = chooseStrategy docLines
    putStrLn $ "  doc lines: " ++ show docLines
    putStrLn $ "  strategy: " ++ show strategy

    putStrLn "[stage 0] seed probes (help / version / no-args)..."
    helpRes <- runProbe taskDir (ProbeCmd ["--help"]    Nothing "seed: help")
    verRes  <- runProbe taskDir (ProbeCmd ["--version"] Nothing "seed: version")
    defRes  <- runProbe taskDir (ProbeCmd []            Nothing "seed: no-args")

    let helpOut  = prStdout helpRes <> prStderr helpRes
        defOut   = prStdout defRes
        defErr   = prStderr defRes
        verBlob  = prStdout verRes <> prStderr verRes

    taskDirContents <- safeListDir taskDir

    let detected = classifyByForm helpOut defOut defErr taskDirContents docLines
        plan     = planFor detected
    putStrLn $ "[stage 1] detected form: " ++ T.unpack (bbtName detected)
    putStrLn $ "  plan stages (" ++ show (length plan) ++ "):"
    mapM_ (\ps -> putStrLn $ "    - " ++ T.unpack (psNameRaw ps)) plan

    putStrLn "[stage 0+] self-describe seed probes..."
    sdRes <- selfDescribeProbes taskDir detected
    let sdHits = filter isInformative sdRes
    putStrLn $ "  self-describe: " ++ show (length sdRes) ++ " tried, "
                                   ++ show (length sdHits) ++ " informative"

    let seedAll      = [helpRes, verRes, defRes] ++ sdRes
        helpFromAll  = T.unlines (helpOut : [prStdout r | r <- sdHits])
        seedBlob = helpOut <> "\n" <> verBlob <> "\n" <> defErr
                <> "\n" <> T.unlines [prStdout r <> "\n" <> prStderr r | r <- sdRes]
        seedExits = nubExitCodes
                      [(prExitCode r, classifyExitCode (prExitCode r)) | r <- seedAll]
        seedBuckets = collectBuckets seedAll
        seedBugs    = collectBugs    seedAll
        initBelief = (emptyBelief (T.pack (takeBaseName taskDir)))
                        { bDetectedType   = detected
                        , bProbeCount     = 3 + length sdRes
                        , bIdentity       = extractIdentity verBlob
                        , bCliSurface     = extractCliFlags helpFromAll
                        , bIoModel        = if T.isInfixOf "stdin" (T.toLower helpOut)
                                              then Just "Accepts stdin"
                                              else Nothing
                        , bExitCodes      = seedExits
                        , bErrorBuckets   = seedBuckets
                        , bBugsToReplica  = seedBugs
                        , bLibFingerprint = guessLibraries seedBlob
                        , bProbeFacts     = map summarizeProbe seedAll
                        }

        baseSt = (initialState taskDir (T.pack (takeBaseName taskDir)))
                    { asPlan         = plan
                    , asStrategy     = strategy
                    , asHistory      = reverse seedAll
                    , asBelief       = initBelief
                    , asCurrentStage = 0
                    }

    apiKey <- lookupEnv "DEEPSEEK_API_KEY"
    finalSt <- case apiKey of
        Nothing -> do
            putStrLn "[stage 2] no DEEPSEEK_API_KEY — stopping after seed."
            pure baseSt
        Just k  -> do
            putStrLn "[stage 2] LLM-driven idiom-based probing..."
            driveLLM (T.pack k) baseSt

    putStrLn "[stage 3] writing belief.md..."
    writeBelief taskDir (asBelief finalSt)
    putStrLn $ "  wrote " ++ taskDir </> "belief.md"
    putStrLn $ "  total probes: " ++ show (bProbeCount (asBelief finalSt))
    putStrLn "=== done ==="


-- ---------------------------------------------------------------
-- LLM-driven loop (idiom-aware)
-- ---------------------------------------------------------------

driveLLM :: Text -> AgentState -> IO AgentState
driveLLM apiKey = go (0 :: Int) (0 :: Int) (0 :: Int)
  where
    maxAddProbes  = 20
    maxDupRetries = 2

    currentStage :: AgentState -> Maybe PlanStage
    currentStage st =
        let i  = asCurrentStage st
            pl = asPlan st
        in if i < length pl then Just (pl !! i) else Nothing

    advanceStage :: AgentState -> AgentState
    advanceStage st = st
        { asCurrentStage = asCurrentStage st + 1
        , asPlan = map (\p -> if psId p == asCurrentStage st then p { psDone = True } else p) (asPlan st)
        }

    go n dupCount novStreak st
        | n >= maxAddProbes = do
            putStrLn $ "  reached probe cap (" ++ show maxAddProbes
                        ++ ") — StopMaxProbesHit"
            pure st
        | novStreak >= asNoveltyWindow st = do
            putStrLn $ "  no new facts in " ++ show novStreak
                        ++ " consecutive probes — StopNoveltyExhausted"
            pure st
        | otherwise = case currentStage st of
            Nothing -> do
                putStrLn "  plan complete — StopPlanDone."
                pure st
            Just stage -> handleStage n dupCount novStreak st stage

    handleStage n dupCount novStreak st stage = do
        let candidates = applicableProbeIdioms (bDetectedType (asBelief st)) stage st
            prompt     = buildPrompt st stage candidates
        putStrLn $ "  [probe " ++ show (n + 1) ++ "/" ++ show maxAddProbes
                     ++ "  stage " ++ show (asCurrentStage st) ++ ": "
                     ++ T.unpack (psNameRaw stage)
                     ++ "  candidates=" ++ show (length candidates)
                     ++ "  novStreak=" ++ show novStreak ++ "]"
        hFlush stdout
        reply <- callChat apiKey (defaultRequest [Message "user" prompt])
        handleReply n dupCount novStreak st stage (parseAction reply)

    handleReply n _ novStreak st _ Nothing = do
        putStrLn "  LLM reply unparseable — advancing stage."
        go n 0 novStreak (advanceStage st)
    handleReply _ _ _ st _ (Just (ActStopLLM reason)) = do
        putStrLn $ "  LLM stop: " ++ T.unpack reason
        pure st
    handleReply n _ novStreak st stage (Just ActStageDone) = do
        putStrLn $ "  LLM marks stage done: " ++ T.unpack (psNameRaw stage)
        go n 0 novStreak (advanceStage st)
    handleReply n dupCount novStreak st stage (Just (ActRunIdiom iid mArgs mStdin)) =
        case idiomById iid of
            Nothing ->
                if dupCount + 1 >= maxDupRetries
                    then do
                        putStrLn $ "  LLM picked unknown idiom \""
                                ++ T.unpack iid ++ "\" twice — advancing stage."
                        go n 0 novStreak (advanceStage st)
                    else do
                        putStrLn $ "  LLM picked unknown idiom: " ++ T.unpack iid
                        go n (dupCount + 1) novStreak st
            Just idi -> handleIdiom n dupCount novStreak st stage idi mArgs mStdin
    handleReply n dupCount novStreak st _ (Just (ActRawProbe args mStdin why)) =
        let cmd = ProbeCmd { pcArgs = args, pcStdin = mStdin, pcReason = "raw: " <> why }
        in if seenBefore cmd st
            then handleDup n dupCount novStreak st cmd "raw_probe"
            else runRawProbe n novStreak st cmd why

    handleIdiom n _ novStreak st _ idi _ _ | not (isProbeAction (iAction idi)) = do
        putStrLn $ "  idiom " ++ T.unpack (iId idi) ++ " is rule/post-process only — recording as ack"
        let st' = appendFact (FactByteAtom ("rule_acknowledged: " <> iId idi)) st
        go n 0 novStreak st'
    handleIdiom n dupCount novStreak st stage idi mArgs mStdin =
        case toProbeCmd idi mArgs mStdin of
            Nothing -> do
                putStrLn $ "  idiom " ++ T.unpack (iId idi) ++ " produced no probe cmd — skipping"
                go n (dupCount + 1) novStreak st
            Just cmd
                | seenBefore cmd st -> handleDup n dupCount novStreak st cmd (iId idi)
                | otherwise         -> runIdiomProbe n novStreak st idi cmd

    handleDup n dupCount novStreak st cmd iid = do
        putStrLn $ "    SKIP (dup): " ++ T.unpack iid
                    ++ " ./probe " ++ T.unpack (T.unwords (pcArgs cmd))
        if dupCount + 1 >= maxDupRetries
            then do
                putStrLn "  LLM repeats — advancing stage."
                go n 0 novStreak (advanceStage st)
            else
                let rebuke = ProbeResult
                        { prCmd      = cmd { pcReason = "REJECTED-DUP " <> iid }
                        , prStdout   = "(skipped: duplicate probe)"
                        , prStderr   = ""
                        , prExitCode = -1
                        , prDuration = 0
                        }
                    st' = st { asHistory = rebuke : asHistory st }
                in go n (dupCount + 1) novStreak st'

    runIdiomProbe n novStreak st idi cmd = do
        putStrLn $ "    run idiom " ++ T.unpack (iId idi)
                    ++ ": ./probe " ++ T.unpack (T.unwords (pcArgs cmd))
        let preMass = beliefMass (asBelief st)
        res <- case pcStdin cmd of
            Nothing -> runProbe          (asTaskDir st) cmd
            Just s  -> runProbeWithStdin (asTaskDir st) cmd s
        let derivedFacts = runPostProcess idi res
        putStrLn $ "      exit=" ++ show (prExitCode res)
                    ++ " dur=" ++ show (prDuration res)
                    ++ "s facts+=" ++ show (length derivedFacts)
        let stWithFacts = foldr appendFact st derivedFacts
            st' = applyExtractors res (stWithFacts
                    { asHistory = res : asHistory stWithFacts
                    , asBelief  = (asBelief stWithFacts)
                                    { bProbeCount = bProbeCount (asBelief stWithFacts) + 1
                                    , bProbeFacts = summarizeProbe res
                                                    : bProbeFacts (asBelief stWithFacts)
                                    }
                    })
            grew = beliefMass (asBelief st') > preMass
            novStreak' = if grew then 0 else novStreak + 1
        go (n + 1) 0 novStreak' st'

    isProbeAction (ActProbe _ _)       = True
    isProbeAction (ActProbeFamily _)   = True
    isProbeAction _                    = False

    runRawProbe n novStreak st cmd why = do
        putStrLn $ "    run raw probe (" <> T.unpack why
                    <> "): ./probe " <> T.unpack (T.unwords (pcArgs cmd))
        let preMass = beliefMass (asBelief st)
        res <- case pcStdin cmd of
            Nothing -> runProbe          (asTaskDir st) cmd
            Just s  -> runProbeWithStdin (asTaskDir st) cmd s
        putStrLn $ "      exit=" ++ show (prExitCode res)
                    ++ " dur=" ++ show (prDuration res) ++ "s"
        let st' = applyExtractors res (st
                { asHistory = res : asHistory st
                , asBelief  = (asBelief st)
                                { bProbeCount = bProbeCount (asBelief st) + 1
                                , bProbeFacts = summarizeProbe res
                                                : bProbeFacts (asBelief st)
                                }
                })
            grew = beliefMass (asBelief st') > preMass
            novStreak' = if grew then 0 else novStreak + 1
        go (n + 1) 0 novStreak' st'


-- ---------------------------------------------------------------
-- Action protocol
-- ---------------------------------------------------------------

data Action
    = ActRunIdiom Text (Maybe [Text]) (Maybe Text)
    | ActRawProbe [Text] (Maybe Text) Text   -- args, stdin, rationale
    | ActStopLLM Text
    | ActStageDone


parseAction :: Text -> Maybe Action
parseAction raw =
    let txt = extractJsonObject raw
    in case A.eitherDecodeStrict (TE.encodeUtf8 txt) of
        Right (A.Object o)
            | Just (A.String iid) <- KM.lookup "idiom" o ->
                let mArgs = case KM.lookup "args" o of
                                Just (A.Array v) -> Just [s | A.String s <- V.toList v]
                                _                -> Nothing
                    mStdin = case KM.lookup "stdin" o of
                                Just (A.String s) -> Just s
                                _                 -> Nothing
                in Just (ActRunIdiom iid mArgs mStdin)
            | Just (A.Array argsV) <- KM.lookup "raw_probe_args" o ->
                let args = [s | A.String s <- V.toList argsV]
                    mStdin = case KM.lookup "stdin" o of
                                Just (A.String s) -> Just s
                                _                 -> Nothing
                    why = case KM.lookup "why" o of
                            Just (A.String s) -> s
                            _                 -> "LLM raw probe"
                in Just (ActRawProbe args mStdin why)
            | Just (A.String reason) <- KM.lookup "stop" o ->
                Just (ActStopLLM reason)
            | Just _ <- KM.lookup "stage_done" o ->
                Just ActStageDone
        _ -> Nothing
  where
    extractJsonObject t =
        let afterOpen = T.dropWhile (/= '{') t
            beforeClose = T.dropWhileEnd (/= '}') afterOpen
        in beforeClose


-- ---------------------------------------------------------------
-- Idiom → ProbeCmd
-- ---------------------------------------------------------------

-- Resolve an idiom into a concrete ProbeCmd.
-- LLM-provided args override the idiom's canonical args (for parameterized templates).
toProbeCmd :: Idiom -> Maybe [Text] -> Maybe Text -> Maybe ProbeCmd
toProbeCmd idi mArgs mStdin = case iAction idi of
    ActProbe baseArgs baseStdin -> Just ProbeCmd
        { pcArgs   = maybe baseArgs id mArgs
        , pcStdin  = maybe baseStdin Just mStdin
        , pcReason = "idiom " <> iId idi <> ": " <> iName idi
        }
    ActProbeFamily ((vArgs, vStdin) : _) -> Just ProbeCmd
        { pcArgs   = maybe vArgs id mArgs
        , pcStdin  = maybe vStdin Just mStdin
        , pcReason = "idiom " <> iId idi <> " (variant): " <> iName idi
        }
    ActProbeFamily [] -> Nothing
    ActPostProcess _  -> Nothing  -- can't run a post-process standalone
    ActRule _         -> Nothing


-- Only idioms that the agent can actually invoke standalone (Probe / ProbeFamily).
applicableProbeIdioms :: BlackBoxType -> PlanStage -> AgentState -> [Idiom]
applicableProbeIdioms form stage st =
    let candidates = idiomsFor form (Just (psNameRaw stage))
        isProbe i = case iAction i of
                       ActProbe _ _      -> True
                       ActProbeFamily _  -> True
                       _                 -> False
    in filter isProbe candidates


-- ---------------------------------------------------------------
-- Prompt construction
-- ---------------------------------------------------------------

buildPrompt :: AgentState -> PlanStage -> [Idiom] -> Text
buildPrompt st stage candidates = T.unlines
    [ "You are a black-box probe agent. Pick the NEXT probe by selecting an idiom from the candidate list."
    , ""
    , "## Detected form: " <> bbtName (bDetectedType (asBelief st))
    , ""
    , "## Current plan stage (#" <> tshow (psId stage) <> ")"
    , "  name: " <> psNameRaw stage
    , "  hint: " <> psPromptRaw stage
    , ""
    , "## Candidate idioms for this stage (" <> tshow (length candidates) <> " applicable)"
    , T.unlines [ "  • `" <> iId i <> "` — " <> iSummary i | i <- candidates ]
    , if null candidates
        then "  (no applicable idioms — mark stage done OR pick from full registry by id)"
        else ""
    , ""
    , "## Last 8 probes (newest first) — DO NOT repeat (args, stdin)"
    , T.intercalate "\n---\n" (map briefProbe (take 8 (asHistory st)))
    , ""
    , "## Reply protocol — STRICTLY ONE JSON object"
    , "  Run idiom (canonical args):  {\"idiom\":\"<id>\"}"
    , "  Run idiom (override args):   {\"idiom\":\"<id>\",\"args\":[\"--flag\",\"v\"]}"
    , "  Run idiom with stdin:        {\"idiom\":\"<id>\",\"stdin\":\"<content>\"}"
    , "  Raw probe (bypass idiom):    {\"raw_probe_args\":[\"--flag\",\"v\"],\"stdin\":\"...\",\"why\":\"<reason>\"}"
    , "  Mark this stage done:        {\"stage_done\":true}"
    , "  Stop the whole probe:        {\"stop\":\"<reason>\"}"
    , ""
    , "Pick idioms that maximize NEW information for this stage."
    , "If no listed idiom fits, use raw_probe_args to drive your own probe (with a short why)."
    , "If you can't think of a productive new probe in this stage, mark stage_done."
    ]
  where
    tshow :: Show a => a -> Text
    tshow = T.pack . show


briefProbe :: ProbeResult -> Text
briefProbe pr = T.intercalate "\n"
    [ "  cmd: ./probe " <> T.unwords (pcArgs (prCmd pr))
        <> maybe "" (\s -> "  stdin: " <> T.take 40 s) (pcStdin (prCmd pr))
    , "  exit: " <> T.pack (show (prExitCode pr))
    , "  stdout(≤300): " <> T.take 300 (prStdout pr)
    , "  stderr(≤150): " <> T.take 150 (prStderr pr)
    ]


-- ---------------------------------------------------------------
-- Belief field accumulator
-- ---------------------------------------------------------------

appendFact :: Fact -> AgentState -> AgentState
appendFact f st =
    let b = asBelief st
        b' = case f of
            FactIdentity s         -> b { bIdentity      = Just s }
            FactCli xs             -> b { bCliSurface    = bCliSurface b ++ xs }
            FactExit n s           -> b { bExitCodes     = nubExitCodes ((n, s) : bExitCodes b) }
            FactErrorBucket s      -> b { bErrorBuckets  = bErrorBuckets b ++ [s] }
            FactLibFingerprint s   -> b { bLibFingerprint = bLibFingerprint b ++ [s] }
            FactBug s              -> b { bBugsToReplica = bBugsToReplica b ++ [s] }
            FactKnownUnknown s     -> b { bKnownUnknown  = bKnownUnknown b ++ [s] }
            FactByteAtom s         -> b { bProbeFacts    = bProbeFacts b ++ [s] }
            FactKAT inp fl hex     -> b { bProbeFacts    = bProbeFacts b ++
                                            [ "KAT: input=" <> inp <> "  flags=" <> T.unwords fl
                                                <> "  expected_hex=" <> hex ] }
    in st { asBelief = b' }


-- Naive dedup for exit code table.
nubExitCodes :: [(Int, Text)] -> [(Int, Text)]
nubExitCodes = goNub []
  where
    goNub seen [] = seen
    goNub seen ((n, s) : rest)
        | any ((== n) . fst) seen = goNub seen rest
        | otherwise               = goNub (seen ++ [(n, s)]) rest


-- ---------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------

seenBefore :: ProbeCmd -> AgentState -> Bool
seenBefore cmd st =
    let key c = (pcArgs c, pcStdin c)
    in any ((== key cmd) . key . prCmd) (asHistory st)


-- After every probe, harvest belief fields from its result.
applyExtractors :: ProbeResult -> AgentState -> AgentState
applyExtractors res st =
    let b   = asBelief st
        ec  = prExitCode res
        ecRow = (ec, classifyExitCode ec)
        bucket = case bucketError (prStderr res) of
                    Just s | T.length s > 0 -> [s]
                    _                       -> []
        bug    = case detectBug ec (prStderr res) of
                    Just s  -> [s]
                    Nothing -> []
        libs   = guessLibraries (prStdout res <> "\n" <> prStderr res)
        magic  = case detectMagicBytes (prStdout res) of
                    Just s  -> [s]
                    Nothing -> []
        diag   = case detectDiagnosticFormat (prStdout res) of
                    Just s  -> [s]
                    Nothing -> []
        binAtom = if isMostlyBinary (prStdout res)
                    then ["binary stdout hex(16): " <> hexDump 16 (prStdout res)]
                    else []
    in st { asBelief = b
                { bExitCodes      = nubExitCodes (ecRow : bExitCodes b)
                , bErrorBuckets   = nubKeep (bErrorBuckets b ++ bucket)
                , bBugsToReplica  = nubKeep (bBugsToReplica b ++ bug)
                , bLibFingerprint = nubKeep (bLibFingerprint b ++ libs ++ magic ++ diag)
                , bProbeFacts     = bProbeFacts b ++ binAtom
                }
          }


collectBuckets :: [ProbeResult] -> [Text]
collectBuckets rs =
    nubKeep [b | r <- rs, Just b <- [bucketError (prStderr r)]]


collectBugs :: [ProbeResult] -> [Text]
collectBugs rs =
    nubKeep [b | r <- rs, Just b <- [detectBug (prExitCode r) (prStderr r)]]


-- O(n²) but n is small (< 30 buckets per task).
nubKeep :: Eq a => [a] -> [a]
nubKeep = goK []
  where
    goK seen [] = seen
    goK seen (x : xs)
        | x `elem` seen = goK seen xs
        | otherwise     = goK (seen ++ [x]) xs


-- "Information mass" — sum of distinct field entries in belief.
-- bProbeFacts is excluded because it grows on every probe (would mask novelty).
beliefMass :: Belief -> Int
beliefMass b =
    length (bCliSurface b)
    + length (bExitCodes b)
    + length (bErrorBuckets b)
    + length (bBugsToReplica b)
    + length (bLibFingerprint b)
    + length (bKnownUnknown b)
    + (if isJust (bIdentity b) then 1 else 0)
    + (if isJust (bIoModel  b) then 1 else 0)
  where
    isJust (Just _) = True
    isJust Nothing  = False


safeListDir :: FilePath -> IO [FilePath]
safeListDir dir = listDirectory dir `catch` \(_ :: SomeException) -> pure []


-- Methodology §7: cheap "inventory" probes that may reveal entire flag spaces.
-- Form-conditional: large-flag-space + linter forms benefit most.
selfDescribeProbes :: FilePath -> BlackBoxType -> IO [ProbeResult]
selfDescribeProbes taskDir form =
    mapM (\args -> runProbe taskDir (ProbeCmd args Nothing ("self-describe: " <> T.unwords args)))
         (commonArgs ++ formArgs form)
  where
    commonArgs =
        [ ["-h"]              -- some tools reject --help
        , ["-V"]              -- some tools use -V instead of --version
        , ["--help-all"]      -- clap / fish style extended help
        ]
    formArgs F10_LargeFlagSpace =
        [ ["--list-types"], ["--type-list"]
        , ["--generate=man"], ["--list"]
        ]
    formArgs F12_AssetDependent =
        [ ["-I", "0"]         -- figlet-style infocode 0
        , ["-I", "1"], ["-I", "2"], ["-I", "3"]
        ]
    formArgs F9_MultiStagePipeline =
        [ ["--list"], ["--list-formatters"], ["--list-styles"], ["--list-lexers"] ]
    formArgs F8_BinaryByteExact =
        [ ["--list"], ["--list-codecs"] ]
    formArgs _ = []


-- A self-describe probe is informative if it returned non-empty stdout and exit 0.
-- (Errors / "unknown flag" results don't count.)
isInformative :: ProbeResult -> Bool
isInformative pr =
    prExitCode pr == 0 && not (T.null (T.strip (prStdout pr)))


extractIdentity :: Text -> Maybe Text
extractIdentity t =
    case T.lines t of
        []      -> Nothing
        (l : _) ->
            let s = T.strip l
            in if T.null s then Nothing else Just s


summarizeProbe :: ProbeResult -> Text
summarizeProbe pr = T.intercalate " | "
    [ "./probe " <> T.unwords (pcArgs (prCmd pr))
    , "exit=" <> T.pack (show (prExitCode pr))
    , "stdout=" <> T.take 80 (T.filter (/= '\n') (prStdout pr))
    ]
