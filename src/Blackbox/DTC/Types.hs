{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Types
    ( Archetype (..)
    , ArchetypeRequirement (..)
    , BindingField (..)
    , BindingNecessity (..)
    , BehaviorSurface (..)
    , CorpusInput (..)
    , DtcPlan (..)
    , Expectation (..)
    , FeatureId (..)
    , FixtureAction (..)
    , HttpRoute (..)
    , PlanStep (..)
    , RunMode (..)
    , RunSpec (..)
    , SpecSurface (..)
    , StepKind (..)
    , StopCondition (..)
    , TriggerAction (..)
    ) where

import qualified Data.Aeson   as A
import           Data.Aeson   ((.=))
import           Data.Text    (Text)
import           GHC.Generics (Generic)


data CorpusInput
    = SourceTree FilePath
    | UpstreamTests FilePath
    | GraderTests FilePath
    deriving (Eq, Show, Generic)

instance A.ToJSON CorpusInput


newtype FeatureId = FeatureId { unFeatureId :: Text }
    deriving (Eq, Ord, Show, Generic)

instance A.ToJSON FeatureId


newtype BehaviorSurface = BehaviorSurface { unBehaviorSurface :: Text }
    deriving (Eq, Ord, Show, Generic)

instance A.ToJSON BehaviorSurface


newtype SpecSurface = SpecSurface { unSpecSurface :: Text }
    deriving (Eq, Ord, Show, Generic)

instance A.ToJSON SpecSurface


data Archetype
    = WatcherCli
    | HttpClientCli
    | StructuredSubcommandCli
    | TabularRenderCli
    | FileInputCli
    | StdoutFormatterCli
    deriving (Eq, Show, Generic)

instance A.ToJSON Archetype


data BindingNecessity
    = Required
    | Optional
    deriving (Eq, Show, Generic)

instance A.ToJSON BindingNecessity where
    toJSON Required = A.String "required"
    toJSON Optional = A.String "optional"


data BindingField = BindingField
    { bfName        :: Text
    , bfNecessity   :: BindingNecessity
    , bfDescription :: Text
    , bfSourceHints :: [Text]
    , bfExamples    :: [Text]
    } deriving (Eq, Show, Generic)

instance A.ToJSON BindingField where
    toJSON field = A.object
        [ "name" .= bfName field
        , "necessity" .= bfNecessity field
        , "description" .= bfDescription field
        , "sourceHints" .= bfSourceHints field
        , "examples" .= bfExamples field
        ]


data ArchetypeRequirement = ArchetypeRequirement
    { arArchetype :: Archetype
    , arPurpose   :: Text
    , arFields    :: [BindingField]
    } deriving (Eq, Show, Generic)

instance A.ToJSON ArchetypeRequirement where
    toJSON requirement = A.object
        [ "archetype" .= arArchetype requirement
        , "purpose" .= arPurpose requirement
        , "fields" .= arFields requirement
        ]


data DtcPlan = DtcPlan
    { dpName       :: Text
    , dpInputs     :: [CorpusInput]
    , dpArchetypes :: [Archetype]
    , dpSteps      :: [PlanStep]
    } deriving (Eq, Show, Generic)

instance A.ToJSON DtcPlan


data PlanStep = PlanStep
    { psId       :: Text
    , psFeature  :: FeatureId
    , psBehaviorSurfaces :: [BehaviorSurface]
    , psSpecSurfaces     :: [SpecSurface]
    , psKind     :: StepKind
    , psSetup    :: [FixtureAction]
    , psRun      :: RunSpec
    , psTriggers :: [TriggerAction]
    , psExpect   :: [Expectation]
    , psSource   :: [CorpusInput]
    , psNotes    :: [Text]
    } deriving (Eq, Show, Generic)

instance A.ToJSON PlanStep


data StepKind
    = SyncProbe
    | AsyncProbe
    | FixtureProbe
    deriving (Eq, Show, Generic)

instance A.ToJSON StepKind


data FixtureAction
    = TouchFile FilePath
    | WriteFileText FilePath Text
    | AppendFileText FilePath Text
    | StartHttpFixture [HttpRoute]
    | SleepMs Int
    deriving (Eq, Show, Generic)

instance A.ToJSON FixtureAction


data HttpRoute = HttpRoute
    { hrMethod :: Text
    , hrPath   :: Text
    , hrStatus :: Int
    , hrBody   :: Text
    , hrResponseContentType :: Text
    , hrRequestPathNeedles :: [Text]
    , hrRequestHeaderNeedles :: [Text]
    , hrRequestBodyNeedles :: [Text]
    } deriving (Eq, Show, Generic)

instance A.ToJSON HttpRoute


data RunSpec = RunSpec
    { rsCmd       :: Text
    , rsStdin     :: Maybe Text
    , rsTimeoutMs :: Int
    , rsMode      :: RunMode
    , rsStopWhen  :: [StopCondition]
    } deriving (Eq, Show, Generic)

instance A.ToJSON RunSpec


data StopCondition
    = StopWhenStdoutContains Text
    | StopWhenStderrContains Text
    deriving (Eq, Show, Generic)

instance A.ToJSON StopCondition


data RunMode
    = RunSync
    | RunAsync
    deriving (Eq, Show, Generic)

instance A.ToJSON RunMode


data TriggerAction
    = TriggerAppend FilePath Text Int
    | TriggerTouch FilePath Int
    | TriggerMkdir FilePath Int
    | TriggerHttpReady
    deriving (Eq, Show, Generic)

instance A.ToJSON TriggerAction


data Expectation
    = ExpectExit Int
    | ExpectStdoutContains Text
    | ExpectStderrContains Text
    | ExpectStdoutEmpty
    | ExpectStderrEmpty
    | ExpectCompletesWithinMs Int
    deriving (Eq, Show, Generic)

instance A.ToJSON Expectation
