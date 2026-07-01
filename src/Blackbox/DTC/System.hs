{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.System
    ( CorpusChunk (..)
    , CorpusDigest (..)
    , DeepSeekPacket (..)
    , DeepSeekValidation (..)
    , LlmStagePrompt (..)
    , ResultChunk (..)
    , ResultStepSummary (..)
    , ResultSummary (..)
    , collectCorpusDigest
    , deepSeekRequestJson
    , extractDeepSeekContent
    , prepareDeepSeekPacket
    , validateDeepSeekOutput
    ) where

import           Control.Exception      (IOException, catch)
import           Control.Monad          (filterM, forM)
import qualified Data.Aeson             as A
import           Data.Aeson             ((.:), (.:?), (.!=), (.=))
import qualified Data.Aeson.Key         as K
import qualified Data.Aeson.KeyMap      as KM
import           Data.Aeson.Types       (Parser)
import qualified Data.ByteString.Lazy   as BL
import           Data.List              (find, nub, sort)
import qualified Data.Vector            as V
import qualified Data.Text              as T
import           Data.Text              (Text)
import qualified Data.Text.Encoding     as TE
import qualified Data.Text.IO           as TIO
import           GHC.Generics           (Generic)
import           System.Directory       (doesDirectoryExist, doesFileExist,
                                          getFileSize, listDirectory)
import           System.FilePath        (dropExtension, makeRelative,
                                          takeDirectory, takeExtension, takeFileName,
                                          (</>))

import           Blackbox.DTC.Binding   (BindingInput, BindingStatus (..),
                                          BindingValidation (..),
                                          validateBinding)
import           Blackbox.DTC.Requirements (requirementsByArchetype)
import           Blackbox.DTC.Types      (Archetype (..), ArchetypeRequirement)


data CorpusDigest = CorpusDigest
    { cdRoot          :: FilePath
    , cdFilesScanned  :: Int
    , cdFilesIncluded :: Int
    , cdBytesIncluded :: Integer
    , cdChunks        :: [CorpusChunk]
    , cdSkipped       :: [FilePath]
    } deriving (Eq, Show, Generic)

instance A.ToJSON CorpusDigest where
    toJSON digest = A.object
        [ "root" .= cdRoot digest
        , "filesScanned" .= cdFilesScanned digest
        , "filesIncluded" .= cdFilesIncluded digest
        , "bytesIncluded" .= cdBytesIncluded digest
        , "chunks" .= cdChunks digest
        , "skipped" .= cdSkipped digest
        ]

instance A.FromJSON CorpusDigest where
    parseJSON = A.withObject "CorpusDigest" $ \o -> CorpusDigest
        <$> o .: "root"
        <*> o .: "filesScanned"
        <*> o .: "filesIncluded"
        <*> o .: "bytesIncluded"
        <*> o .: "chunks"
        <*> o .: "skipped"


data CorpusChunk = CorpusChunk
    { ccId          :: Text
    , ccPath        :: FilePath
    , ccChunkIndex  :: Int
    , ccTotalChunks :: Int
    , ccLineStart   :: Int
    , ccLineEnd     :: Int
    , ccCharCount   :: Int
    , ccKeywords    :: [Text]
    , ccSignalLines :: [Text]
    , ccText        :: Text
    } deriving (Eq, Show, Generic)

instance A.ToJSON CorpusChunk where
    toJSON chunk = A.object
        [ "id" .= ccId chunk
        , "path" .= ccPath chunk
        , "chunkIndex" .= ccChunkIndex chunk
        , "totalChunks" .= ccTotalChunks chunk
        , "lineStart" .= ccLineStart chunk
        , "lineEnd" .= ccLineEnd chunk
        , "charCount" .= ccCharCount chunk
        , "keywords" .= ccKeywords chunk
        , "signalLines" .= ccSignalLines chunk
        , "text" .= ccText chunk
        ]

instance A.FromJSON CorpusChunk where
    parseJSON = A.withObject "CorpusChunk" $ \o -> CorpusChunk
        <$> o .: "id"
        <*> o .: "path"
        <*> o .: "chunkIndex"
        <*> o .: "totalChunks"
        <*> o .: "lineStart"
        <*> o .: "lineEnd"
        <*> o .: "charCount"
        <*> o .: "keywords"
        <*> o .:? "signalLines" .!= []
        <*> o .: "text"


data ResultChunk = ResultChunk
    { rcId         :: Text
    , rcSource     :: FilePath
    , rcLineStart  :: Int
    , rcLineEnd    :: Int
    , rcKeywords   :: [Text]
    , rcText       :: Text
    } deriving (Eq, Show, Generic)

instance A.ToJSON ResultChunk where
    toJSON chunk = A.object
        [ "id" .= rcId chunk
        , "source" .= rcSource chunk
        , "lineStart" .= rcLineStart chunk
        , "lineEnd" .= rcLineEnd chunk
        , "keywords" .= rcKeywords chunk
        , "text" .= rcText chunk
        ]

instance A.FromJSON ResultChunk where
    parseJSON = A.withObject "ResultChunk" $ \o -> ResultChunk
        <$> o .: "id"
        <*> o .: "source"
        <*> o .: "lineStart"
        <*> o .: "lineEnd"
        <*> o .: "keywords"
        <*> o .: "text"


data ResultSummary = ResultSummary
    { rsSource                 :: Maybe FilePath
    , rsTotalSteps             :: Int
    , rsVerdictCounts          :: [(Text, Int)]
    , rsCoveredBehaviorSurfaces :: [Text]
    , rsCoveredSpecSurfaces    :: [Text]
    , rsStepSummaries          :: [ResultStepSummary]
    , rsProblemSteps           :: [ResultStepSummary]
    } deriving (Eq, Show, Generic)

instance A.ToJSON ResultSummary where
    toJSON summary = A.object
        [ "source" .= rsSource summary
        , "totalSteps" .= rsTotalSteps summary
        , "verdictCounts" .=
            [ A.object ["verdict" .= verdict, "count" .= count]
            | (verdict, count) <- rsVerdictCounts summary
            ]
        , "coveredBehaviorSurfaces" .= rsCoveredBehaviorSurfaces summary
        , "coveredSpecSurfaces" .= rsCoveredSpecSurfaces summary
        , "stepSummaries" .= rsStepSummaries summary
        , "problemSteps" .= rsProblemSteps summary
        ]

instance A.FromJSON ResultSummary where
    parseJSON = A.withObject "ResultSummary" $ \o -> ResultSummary
        <$> o .:? "source"
        <*> o .:? "totalSteps" .!= 0
        <*> (parseVerdictCounts =<< o .:? "verdictCounts" .!= [])
        <*> o .:? "coveredBehaviorSurfaces" .!= []
        <*> o .:? "coveredSpecSurfaces" .!= []
        <*> o .:? "stepSummaries" .!= []
        <*> o .:? "problemSteps" .!= []


data ResultStepSummary = ResultStepSummary
    { rssStepId           :: Text
    , rssVerdict          :: Text
    , rssBehaviorSurfaces :: [Text]
    , rssSpecSurfaces     :: [Text]
    , rssExit             :: Maybe Int
    , rssStopReason       :: Text
    , rssEvidence         :: [Text]
    } deriving (Eq, Show, Generic)

instance A.ToJSON ResultStepSummary where
    toJSON step = A.object
        [ "stepId" .= rssStepId step
        , "verdict" .= rssVerdict step
        , "behaviorSurfaces" .= rssBehaviorSurfaces step
        , "specSurfaces" .= rssSpecSurfaces step
        , "exit" .= rssExit step
        , "stopReason" .= rssStopReason step
        , "evidence" .= rssEvidence step
        ]

instance A.FromJSON ResultStepSummary where
    parseJSON = A.withObject "ResultStepSummary" $ \o -> ResultStepSummary
        <$> o .: "stepId"
        <*> o .: "verdict"
        <*> o .:? "behaviorSurfaces" .!= []
        <*> o .:? "specSurfaces" .!= []
        <*> o .:? "exit"
        <*> o .:? "stopReason" .!= ""
        <*> o .:? "evidence" .!= []


data LlmStagePrompt = LlmStagePrompt
    { lspStage              :: Text
    , lspRole               :: Text
    , lspRequiredInputs     :: [Text]
    , lspOutputContract     :: Text
    , lspAntiShortcutRules  :: [Text]
    , lspPrompt             :: Text
    } deriving (Eq, Show, Generic)

instance A.ToJSON LlmStagePrompt where
    toJSON prompt = A.object
        [ "stage" .= lspStage prompt
        , "role" .= lspRole prompt
        , "requiredInputs" .= lspRequiredInputs prompt
        , "outputContract" .= lspOutputContract prompt
        , "antiShortcutRules" .= lspAntiShortcutRules prompt
        , "prompt" .= lspPrompt prompt
        ]

instance A.FromJSON LlmStagePrompt where
    parseJSON = A.withObject "LlmStagePrompt" $ \o -> LlmStagePrompt
        <$> o .: "stage"
        <*> o .: "role"
        <*> o .: "requiredInputs"
        <*> o .: "outputContract"
        <*> o .: "antiShortcutRules"
        <*> o .: "prompt"


data DeepSeekPacket = DeepSeekPacket
    { dspProvider          :: Text
    , dspModelRole         :: Text
    , dspMechanicalReading :: [Text]
    , dspCorpusDigest      :: CorpusDigest
    , dspResultChunks      :: [ResultChunk]
    , dspResultSummary     :: ResultSummary
    , dspStagePrompts      :: [LlmStagePrompt]
    } deriving (Eq, Show, Generic)

instance A.ToJSON DeepSeekPacket where
    toJSON packet = A.object
        [ "provider" .= dspProvider packet
        , "modelRole" .= dspModelRole packet
        , "mechanicalReading" .= dspMechanicalReading packet
        , "corpusDigest" .= dspCorpusDigest packet
        , "resultChunks" .= dspResultChunks packet
        , "resultSummary" .= dspResultSummary packet
        , "stagePrompts" .= dspStagePrompts packet
        ]

instance A.FromJSON DeepSeekPacket where
    parseJSON = A.withObject "DeepSeekPacket" $ \o -> DeepSeekPacket
        <$> o .: "provider"
        <*> o .: "modelRole"
        <*> o .: "mechanicalReading"
        <*> o .: "corpusDigest"
        <*> o .: "resultChunks"
        <*> o .:? "resultSummary" .!= emptyResultSummary
        <*> o .: "stagePrompts"


data DeepSeekValidation = DeepSeekValidation
    { dsvStage            :: Text
    , dsvValid            :: Bool
    , dsvReferencedIds    :: [Text]
    , dsvMissingFields    :: [Text]
    , dsvUnknownCitations :: [Text]
    , dsvIssues           :: [Text]
    } deriving (Eq, Show, Generic)

instance A.ToJSON DeepSeekValidation where
    toJSON validation = A.object
        [ "stage" .= dsvStage validation
        , "valid" .= dsvValid validation
        , "referencedIds" .= dsvReferencedIds validation
        , "missingFields" .= dsvMissingFields validation
        , "unknownCitations" .= dsvUnknownCitations validation
        , "issues" .= dsvIssues validation
        ]


collectCorpusDigest :: FilePath -> IO CorpusDigest
collectCorpusDigest root = do
    allFiles <- recursiveFiles root
    let candidateFiles = filter isIncludedTextFile allFiles
        skipped = map (makeRelative root) (filter (not . isIncludedTextFile) allFiles)
    included <- forM candidateFiles $ \path -> do
        size <- getFileSize path
        text <- safeReadText path
        let rel = makeRelative root path
            chunks = chunkDocument rel (normalizeCorpusText rel text)
        pure (size, chunks)
    let chunks = concatMap snd included
        totalBytes = sum (map fst included)
    pure CorpusDigest
        { cdRoot = root
        , cdFilesScanned = length allFiles
        , cdFilesIncluded = length candidateFiles
        , cdBytesIncluded = totalBytes
        , cdChunks = chunks
        , cdSkipped = skipped
        }


prepareDeepSeekPacket :: CorpusDigest -> Maybe FilePath -> IO DeepSeekPacket
prepareDeepSeekPacket digest mResultsPath = do
    (resultChunks, resultSummary) <- maybe (pure ([], emptyResultSummary)) collectResultEvidence mResultsPath
    pure DeepSeekPacket
        { dspProvider = "deepseek"
        , dspModelRole = "system-level DTC decision/evaluation/oracle node"
        , dspMechanicalReading =
            [ "Read every corpusDigest.chunks[*].id before deciding the archetype."
            , "Use only cited chunk ids and result chunk ids as evidence."
            , "If required binding fields cannot be cited, return missing_or_ambiguous instead of guessing."
            , "For binding_generation, binding keys must exactly match Haskell requirements JSON field names."
            , "For binding_generation, every binding.<field>.value must be a string because hsbb BindingInput consumes Text."
            , "The target executable is always called app in DTC plans; PB probe wrappers are environment bridges, not business commands."
            , "Do not call hsbb runtime or mutate oracle; produce JSON decisions for the deterministic Haskell layer."
            ]
        , dspCorpusDigest = digest
        , dspResultChunks = resultChunks
        , dspResultSummary = resultSummary
        , dspStagePrompts =
            [ decisionPrompt
            , bindingPrompt
            , evaluationPrompt
            , oraclePrompt
            ]
        }


deepSeekRequestJson :: Text -> DeepSeekPacket -> Text -> Either Text A.Value
deepSeekRequestJson model packet stage = do
    prompt <- findStagePrompt packet stage
    pure (A.object
        [ "model" .= model
        , "temperature" .= (0 :: Int)
        , "response_format" .= A.object ["type" .= ("json_object" :: Text)]
        , "messages" .=
            [ A.object
                [ "role" .= ("system" :: Text)
                , "content" .= systemContent prompt
                ]
            , A.object
                [ "role" .= ("user" :: Text)
                , "content" .= userContent packet prompt
                ]
            ]
        ])


extractDeepSeekContent :: BL.ByteString -> Either Text Text
extractDeepSeekContent bytes =
    case A.eitherDecode bytes of
        Left err -> Left ("invalid DeepSeek API JSON: " <> T.pack err)
        Right value ->
            case extractContentValue value of
                Just content -> Right content
                Nothing      -> Left "DeepSeek API JSON missing choices[0].message.content"


validateDeepSeekOutput :: DeepSeekPacket -> Text -> BL.ByteString -> DeepSeekValidation
validateDeepSeekOutput packet stage bytes =
    case normalizeOutputJson bytes of
        Left err ->
            validation
                { dsvIssues = [err]
                , dsvValid = False
                }
        Right value ->
            let missing = missingFields stage value
                known = knownCitationIds packet
                referenced = referencedIdsInValue known value
                suspicious = filter looksLikeCitation (allStringValues value)
                unknown = filter (not . containsKnownId known) suspicious
                citationIssues =
                    if null referenced
                        then ["output does not cite any known corpus/result chunk id"]
                        else []
                issues = citationIssues <> if null unknown then [] else ["output cites unknown chunk/result ids"]
                stageIssues = stageSpecificIssues packet stage value
                allIssues = issues <> stageIssues
                ok = null missing && null unknown && null allIssues
            in validation
                { dsvReferencedIds = referenced
                , dsvMissingFields = missing
                , dsvUnknownCitations = unknown
                , dsvIssues = allIssues
                , dsvValid = ok
                }
  where
    validation = DeepSeekValidation
        { dsvStage = stage
        , dsvValid = False
        , dsvReferencedIds = []
        , dsvMissingFields = []
        , dsvUnknownCitations = []
        , dsvIssues = []
        }


systemContent :: LlmStagePrompt -> Text
systemContent prompt =
    T.unlines
        [ "You are DeepSeek inside hs-blackbox-agent's system layer."
        , "You must obey the stage contract and output JSON only."
        , "Stage: " <> lspStage prompt
        , "Role: " <> lspRole prompt
        , "Output contract: " <> lspOutputContract prompt
        , "Anti-shortcut rules:"
        , T.unlines (map ("- " <>) (lspAntiShortcutRules prompt))
        ]


userContent :: DeepSeekPacket -> LlmStagePrompt -> Text
userContent packet prompt =
    T.unlines
        [ lspPrompt prompt
        , ""
        , "Stage request envelope JSON:"
        , TE.decodeUtf8 (BL.toStrict (A.encode (stageRequestJson packet prompt)))
        ]


stageRequestJson :: DeepSeekPacket -> LlmStagePrompt -> A.Value
stageRequestJson packet prompt =
    A.object
        [ "stage" .= lspStage prompt
        , "role" .= lspRole prompt
        , "requiredInputs" .= lspRequiredInputs prompt
        , "outputContract" .= lspOutputContract prompt
        , "mechanicalReading" .= dspMechanicalReading packet
        , "haskellRequirements" .= requirementsForStage (lspStage prompt)
        , "corpusDigest" .= dspCorpusDigest packet
        , "resultChunks" .= dspResultChunks packet
        , "resultSummary" .= dspResultSummary packet
        ]


requirementsForStage :: Text -> [ArchetypeRequirement]
requirementsForStage "archetype_decision" = haskellRequirementsJson
requirementsForStage "binding_generation" = haskellRequirementsJson
requirementsForStage _ = []


haskellRequirementsJson :: [ArchetypeRequirement]
haskellRequirementsJson =
    [ requirement
    | archetype <- [WatcherCli, HttpClientCli, FileInputCli, StdoutFormatterCli]
    , Just requirement <- [requirementsByArchetype archetype]
    ]


stageSpecificIssues :: DeepSeekPacket -> Text -> A.Value -> [Text]
stageSpecificIssues _ "binding_generation" value =
    case A.fromJSON value :: A.Result BindingInput of
        A.Error err ->
            ["binding JSON does not match Haskell BindingInput: " <> T.pack err]
        A.Success input ->
            let bindingValidation = validateBinding input
            in case bvStatus bindingValidation of
                BindingReady -> []
                status ->
                    [ "binding validation status: " <> bindingStatusText status
                    , "missing required fields: " <> T.intercalate "," (bvMissingRequired bindingValidation)
                    , "ambiguous fields: " <> T.intercalate "," (bvAmbiguousFields bindingValidation)
                    ]
stageSpecificIssues packet "result_evaluation" value =
    resultEvaluationIssues (dspResultSummary packet) value
stageSpecificIssues _ _ _ =
    []


bindingStatusText :: BindingStatus -> Text
bindingStatusText BindingReady = "binding_ready"
bindingStatusText BindingMissing = "binding_missing"
bindingStatusText BindingAmbiguous = "binding_ambiguous"
bindingStatusText BindingUnsupportedArchetype = "unsupported_archetype"


findStagePrompt :: DeepSeekPacket -> Text -> Either Text LlmStagePrompt
findStagePrompt packet stage =
    case find ((== stage) . lspStage) (dspStagePrompts packet) of
        Just prompt -> Right prompt
        Nothing     -> Left ("unknown DeepSeek stage in packet: " <> stage)


extractContentValue :: A.Value -> Maybe Text
extractContentValue (A.Object o) = do
    A.Array choices <- KM.lookup "choices" o
    firstChoice <- choices V.!? 0
    case firstChoice of
        A.Object choiceObj -> do
            A.Object messageObj <- KM.lookup "message" choiceObj
            case KM.lookup "content" messageObj of
                Just (A.String content) -> Just content
                _                       -> Nothing
        _ -> Nothing
extractContentValue _ = Nothing


normalizeOutputJson :: BL.ByteString -> Either Text A.Value
normalizeOutputJson bytes =
    case extractDeepSeekContent bytes of
        Right content ->
            case A.eitherDecode (BL.fromStrict (TE.encodeUtf8 content)) of
                Right value -> Right value
                Left err    -> Left ("DeepSeek content is not valid JSON: " <> T.pack err)
        Left _ ->
            case A.eitherDecode bytes of
                Right value -> Right value
                Left err    -> Left ("invalid output JSON: " <> T.pack err)


missingFields :: Text -> A.Value -> [Text]
missingFields stage value =
    case value of
        A.Object o -> filter (not . (`KM.member` o) . K.fromText) (requiredFieldsForStage stage)
        _          -> requiredFieldsForStage stage


requiredFieldsForStage :: Text -> [Text]
requiredFieldsForStage "archetype_decision" =
    ["archetype", "confidence", "citedChunkIds", "missingEvidence", "rationale"]
requiredFieldsForStage "binding_generation" =
    ["archetype", "project", "binding"]
requiredFieldsForStage "result_evaluation" =
    ["verdict", "archetypeStillFits", "coveredSurfaces", "gaps", "nextAction", "citedResultChunkIds"]
requiredFieldsForStage "oracle_generation" =
    ["oracleVersion", "supportedFacts", "uncertainty", "regenerationTriggers", "citedEvidence"]
requiredFieldsForStage _ =
    []


knownCitationIds :: DeepSeekPacket -> [Text]
knownCitationIds packet =
    map ccId (cdChunks (dspCorpusDigest packet)) <> map rcId (dspResultChunks packet)


referencedIdsInValue :: [Text] -> A.Value -> [Text]
referencedIdsInValue known value =
    [ knownId
    | knownId <- known
    , any (knownId `T.isInfixOf`) strings
    ]
  where
    strings = allStringValues value


allStringValues :: A.Value -> [Text]
allStringValues (A.String text) = [text]
allStringValues (A.Array values) = concatMap allStringValues (V.toList values)
allStringValues (A.Object values) = concatMap allStringValues (KM.elems values)
allStringValues _ = []


looksLikeCitation :: Text -> Bool
looksLikeCitation text =
    "#" `T.isInfixOf` text || "result:" `T.isPrefixOf` text


containsKnownId :: [Text] -> Text -> Bool
containsKnownId known text =
    any (`T.isInfixOf` text) known


decisionPrompt :: LlmStagePrompt
decisionPrompt = LlmStagePrompt
    { lspStage = "archetype_decision"
    , lspRole = "Decide the black-box archetype from mechanically read corpus chunks."
    , lspRequiredInputs = ["corpusDigest.chunks", "haskellRequirements"]
    , lspOutputContract = "JSON: {archetype, confidence, citedChunkIds, missingEvidence, rationale}"
    , lspAntiShortcutRules = commonAntiShortcutRules
    , lspPrompt =
        "Classify the target into one existing Haskell DTC archetype from haskellRequirements. "
        <> "Every claim must cite chunk ids. If multiple archetypes fit, list candidates in missingEvidence with the evidence that would disambiguate them. "
        <> "Keep citedChunkIds to the smallest decisive set."
    }


bindingPrompt :: LlmStagePrompt
bindingPrompt = LlmStagePrompt
    { lspStage = "binding_generation"
    , lspRole = "Fill the Haskell archetype binding contract from cited corpus chunks."
    , lspRequiredInputs = ["corpusDigest.chunks", "hsbb dtc requirements <archetype> output"]
    , lspOutputContract = "BindingInput JSON: {archetype, project, binding:{fieldName:{value:string,source:string,confidence:string}}}"
    , lspAntiShortcutRules = commonAntiShortcutRules
    , lspPrompt =
        "For every required Haskell binding field, use the exact field names from haskellRequirements. "
        <> "Every binding.<field>.value must be a string. "
        <> "Copy or synthesize the smallest executable value supported by cited chunks. "
        <> "The source field must name chunk ids and optional line ranges, or source/value/confidence must state missing_or_ambiguous."
    }


evaluationPrompt :: LlmStagePrompt
evaluationPrompt = LlmStagePrompt
    { lspStage = "result_evaluation"
    , lspRole = "Evaluate DTC run results and decide whether the current archetype/binding is adequate."
    , lspRequiredInputs = ["corpusDigest.chunks", "resultChunks", "resultSummary"]
    , lspOutputContract = "JSON: {verdict, archetypeStillFits, coveredSurfaces, gaps, nextAction, citedResultChunkIds}"
    , lspAntiShortcutRules = commonAntiShortcutRules
    , lspPrompt =
        "Compare DTC run results with the original corpus evidence. "
        <> "Use resultSummary as the authoritative mechanical summary of executed steps, verdicts, and covered surfaces. "
        <> "A pass only proves the listed behavior/spec surfaces, not full correctness. "
        <> "Do not list a behavior surface as a gap when resultSummary.coveredBehaviorSurfaces already contains it. "
        <> "Do not list binding field names as gaps; gaps are only missing behavior/spec surfaces or failing/unsupported step evidence. "
        <> "Name missing behavior surfaces explicitly and keep gaps focused on unexecuted or unsupported surfaces."
    }


oraclePrompt :: LlmStagePrompt
oraclePrompt = LlmStagePrompt
    { lspStage = "oracle_generation"
    , lspRole = "Generate an oracle/report proposal from cited corpus and execution evidence."
    , lspRequiredInputs = ["corpusDigest.chunks", "resultChunks", "resultSummary", "result_evaluation JSON"]
    , lspOutputContract = "JSON: {oracleVersion, supportedFacts, uncertainty, regenerationTriggers, citedEvidence}"
    , lspAntiShortcutRules = commonAntiShortcutRules
    , lspPrompt =
        "Generate only evidence-backed oracle facts. "
        <> "Each fact must cite corpus chunk ids or result chunk ids and must include a regeneration trigger when evidence changes."
    }


commonAntiShortcutRules :: [Text]
commonAntiShortcutRules =
    [ "Do not answer from project name alone."
    , "Do not infer unsupported flags, exit codes, or output formats."
    , "Do not mark a field high confidence unless at least one chunk id supports it."
    , "When evidence is absent, emit missing_or_ambiguous rather than fabricating a value."
    ]


collectResultEvidence :: FilePath -> IO ([ResultChunk], ResultSummary)
collectResultEvidence path = do
    text <- safeReadText path
    let pieces = chunkLines 60 (T.lines text)
        total = length pieces
        chunks =
            [ ResultChunk
                { rcId = T.pack ("result:" <> show i <> "/" <> show total)
                , rcSource = path
                , rcLineStart = start
                , rcLineEnd = end
                , rcKeywords = extractKeywords body
                , rcText = T.unlines body
                }
            | (i, (start, end, body)) <- zip [(1 :: Int)..] pieces
            ]
        summary = summarizeResults path text
    pure (chunks, summary)


emptyResultSummary :: ResultSummary
emptyResultSummary = ResultSummary
    { rsSource = Nothing
    , rsTotalSteps = 0
    , rsVerdictCounts = []
    , rsCoveredBehaviorSurfaces = []
    , rsCoveredSpecSurfaces = []
    , rsStepSummaries = []
    , rsProblemSteps = []
    }


summarizeResults :: FilePath -> Text -> ResultSummary
summarizeResults path text =
    ResultSummary
        { rsSource = Just path
        , rsTotalSteps = length stepSummaries
        , rsVerdictCounts = countTexts (map rssVerdict stepSummaries)
        , rsCoveredBehaviorSurfaces =
            sort . nub . concat $
                [ rssBehaviorSurfaces step
                | step <- stepSummaries
                , rssVerdict step == "Pass"
                ]
        , rsCoveredSpecSurfaces =
            sort . nub . concat $
                [ rssSpecSurfaces step
                | step <- stepSummaries
                , rssVerdict step == "Pass"
                ]
        , rsStepSummaries = stepSummaries
        , rsProblemSteps = filter ((/= "Pass") . rssVerdict) stepSummaries
        }
  where
    values = mapMaybeDecodeJsonLine (T.lines text)
    stepSummaries = mapMaybeResultStep values


mapMaybeDecodeJsonLine :: [Text] -> [A.Value]
mapMaybeDecodeJsonLine =
    foldr collect []
  where
    collect line acc =
        case A.eitherDecode (BL.fromStrict (TE.encodeUtf8 line)) of
            Right value -> value : acc
            Left _      -> acc


mapMaybeResultStep :: [A.Value] -> [ResultStepSummary]
mapMaybeResultStep =
    foldr collect []
  where
    collect value acc =
        case resultStepSummary value of
            Just step -> step : acc
            Nothing   -> acc


resultStepSummary :: A.Value -> Maybe ResultStepSummary
resultStepSummary (A.Object o) = do
    stepId <- textField "drrStepId" o
    verdictValue <- KM.lookup "drrVerdict" o
    let verdict = verdictTag verdictValue
        behaviorSurfaces = maybe [] (surfaceTexts "unBehaviorSurface") (arrayField "drrBehaviorSurfaces" o)
        specSurfaces = maybe [] (surfaceTexts "unSpecSurface") (arrayField "drrSpecSurfaces" o)
        exitCode = intMaybeField "drrExit" o
        stopReason = maybe "" stopReasonText (KM.lookup "drrStopReason" o)
        evidence = take 6 (resultEvidenceLines o)
    pure ResultStepSummary
        { rssStepId = stepId
        , rssVerdict = verdict
        , rssBehaviorSurfaces = behaviorSurfaces
        , rssSpecSurfaces = specSurfaces
        , rssExit = exitCode
        , rssStopReason = stopReason
        , rssEvidence = evidence
        }
resultStepSummary _ =
    Nothing


textField :: K.Key -> KM.KeyMap A.Value -> Maybe Text
textField key object =
    case KM.lookup key object of
        Just (A.String value) -> Just value
        _                     -> Nothing


arrayField :: K.Key -> KM.KeyMap A.Value -> Maybe [A.Value]
arrayField key object =
    case KM.lookup key object of
        Just (A.Array values) -> Just (V.toList values)
        _                     -> Nothing


intMaybeField :: K.Key -> KM.KeyMap A.Value -> Maybe Int
intMaybeField key object =
    case KM.lookup key object of
        Just value ->
            case A.fromJSON value :: A.Result Int of
                A.Success n -> Just n
                A.Error _   -> Nothing
        _ -> Nothing


surfaceTexts :: K.Key -> [A.Value] -> [Text]
surfaceTexts key values =
    [ text
    | A.Object object <- values
    , Just (A.String text) <- [KM.lookup key object]
    ]


verdictTag :: A.Value -> Text
verdictTag (A.Object object) =
    case KM.lookup "tag" object of
        Just (A.String tag) -> tag
        _                   -> "Unknown"
verdictTag _ =
    "Unknown"


stopReasonText :: A.Value -> Text
stopReasonText (A.String text) = text
stopReasonText (A.Object object) =
    case KM.lookup "tag" object of
        Just (A.String tag) -> tag
        _                   -> "Unknown"
stopReasonText _ =
    "Unknown"


resultEvidenceLines :: KM.KeyMap A.Value -> [Text]
resultEvidenceLines object =
    conciseEvidence "stdout" (textLookup "drrStdout" object)
        <> conciseEvidence "stderr" (textLookup "drrStderr" object)
  where
    textLookup key object0 =
        case KM.lookup key object0 of
            Just (A.String text) -> text
            _                    -> ""


conciseEvidence :: Text -> Text -> [Text]
conciseEvidence label text =
    [ label <> ": " <> line
    | line <- take 3 (filter (not . T.null) (map T.strip (T.lines text)))
    ]


countTexts :: [Text] -> [(Text, Int)]
countTexts values =
    [ (value, length (filter (== value) values))
    | value <- sort (nub values)
    ]


parseVerdictCounts :: [A.Value] -> Parser [(Text, Int)]
parseVerdictCounts =
    traverse $ A.withObject "VerdictCount" $ \o ->
        (,) <$> o .: "verdict" <*> o .: "count"


resultEvaluationIssues :: ResultSummary -> A.Value -> [Text]
resultEvaluationIssues summary value =
    case value of
        A.Object object ->
            verdictIssue object <> coveredSurfaceIssues object <> gapIssues object
        _ ->
            ["result_evaluation output must be an object"]
  where
    allStepsPassed =
        rsTotalSteps summary > 0
            && null (rsProblemSteps summary)
            && lookup "Pass" (rsVerdictCounts summary) == Just (rsTotalSteps summary)
    verdictIssue object
        | not allStepsPassed = []
        | Just (A.String verdict) <- KM.lookup "verdict" object
        , T.toLower verdict == "pass" = []
        | allStepsPassed = ["all DTC steps passed, but result_evaluation verdict is not Pass"]
        | otherwise = []
    coveredSurfaceIssues object =
        case KM.lookup "coveredSurfaces" object of
            Just (A.Array values) ->
                let reported = [text | A.String text <- V.toList values]
                    missing = [s | s <- rsCoveredBehaviorSurfaces summary, s `notElem` reported]
                in if null missing
                    then []
                    else ["result_evaluation coveredSurfaces omits passed behavior surfaces: " <> T.intercalate "," missing]
            _ -> ["result_evaluation coveredSurfaces must be an array of strings"]
    gapIssues object =
        case KM.lookup "gaps" object of
            Just (A.Array values) ->
                let gaps = [text | A.String text <- V.toList values]
                    covered = rsCoveredBehaviorSurfaces summary <> rsCoveredSpecSurfaces summary
                    contradicted =
                        [ gap
                        | gap <- gaps
                        , any (`T.isInfixOf` gap) covered
                        ]
                in if null contradicted
                    then []
                    else ["result_evaluation gaps mention already covered surfaces: " <> T.intercalate "," contradicted]
            _ -> ["result_evaluation gaps must be an array of strings"]


recursiveFiles :: FilePath -> IO [FilePath]
recursiveFiles root = do
    exists <- doesDirectoryExist root
    if not exists
        then pure []
        else go root
  where
    go dir = do
        names <- listDirectory dir
        let paths = map (dir </>) (filter (not . ignoredName) names)
        files <- filterM doesFileExist paths
        dirs <- filterM doesDirectoryExist paths
        nested <- concat <$> mapM go dirs
        pure (files <> nested)


ignoredName :: FilePath -> Bool
ignoredName path =
    name `elem` ignored
  where
    name = takeFileName path
    ignored =
        [ ".git"
        , ".hsbb"
        , "dist-newstyle"
        , ".stack-work"
        , "node_modules"
        , "__pycache__"
        ]


isIncludedTextFile :: FilePath -> Bool
isIncludedTextFile path =
    not noisyFile && not harnessBridge && (ext `elem` textExtensions || noExtension)
  where
    ext = takeExtension path
    noisyFile = takeFileName path `elem` ["LICENSE", "COPYING", "NOTICE"]
    harnessBridge = takeFileName path == "probe"
    noExtension = null (takeExtension path) && takeFileName path /= dropExtension (takeDirectory path)
    textExtensions =
        [ ".c", ".cc", ".cpp", ".go", ".h", ".hpp", ".hs", ".js", ".json"
        , ".md", ".py", ".rs", ".sh", ".txt", ".yaml", ".yml"
        ]


normalizeCorpusText :: FilePath -> Text -> Text
normalizeCorpusText rel text
    | takeFileName rel == "SPEC.md" =
        T.replace "./probe" "app" text
    | otherwise =
        T.replace "./probe" "app" text


safeReadText :: FilePath -> IO Text
safeReadText path =
    TIO.readFile path `catch` onReadFailure
  where
    onReadFailure :: IOException -> IO Text
    onReadFailure err =
        pure ("<read_error path=\"" <> T.pack path <> "\">" <> T.pack (show err))


chunkDocument :: FilePath -> Text -> [CorpusChunk]
chunkDocument rel text =
    [ CorpusChunk
        { ccId = T.pack (rel <> "#" <> show idx <> "/" <> show total)
        , ccPath = rel
        , ccChunkIndex = idx
        , ccTotalChunks = total
        , ccLineStart = start
        , ccLineEnd = end
        , ccCharCount = T.length (T.unlines body)
        , ccKeywords = extractKeywords body
        , ccSignalLines = extractSignalLines start body
        , ccText = T.unlines body
        }
    | (idx, (start, end, body)) <- zip [(1 :: Int)..] pieces
    ]
  where
    pieces = chunkLines 120 (T.lines text)
    total = length pieces


chunkLines :: Int -> [Text] -> [(Int, Int, [Text])]
chunkLines size lines0 =
    go 1 lines0
  where
    go _ [] = []
    go start remaining =
        let (body, rest) = splitAt size remaining
            end = start + length body - 1
        in (start, end, body) : go (end + 1) rest


extractKeywords :: [Text] -> [Text]
extractKeywords lines0 =
    [ keyword
    | keyword <- trackedKeywords
    , any (T.isInfixOf (T.toLower keyword) . T.toLower) lines0
    ]


trackedKeywords :: [Text]
trackedKeywords =
    [ "usage"
    , "help"
    , "flag"
    , "method"
    , "get"
    , "post"
    , "put"
    , "header"
    , "body"
    , "form"
    , "stdin"
    , "stdout"
    , "stderr"
    , "exit"
    , "error"
    , "watch"
    , "trigger"
    , "oracle"
    , "grader"
    , "test"
    ]


extractSignalLines :: Int -> [Text] -> [Text]
extractSignalLines lineStart lines0 =
    take 24
        [ T.pack (show lineNo) <> ": " <> T.strip line
        | (lineNo, line) <- zip [lineStart..] lines0
        , let low = T.toLower line
        , any (`T.isInfixOf` low) trackedKeywords
        , not (T.null (T.strip line))
        ]
