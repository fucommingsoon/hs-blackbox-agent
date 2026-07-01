{-# LANGUAGE OverloadedStrings #-}

-- Haskell DTC is the deterministic testing core.  It is meant to absorb
-- reusable flows from upstream regression suites, PB graders, and later
-- project-specific runners while keeping LLM calls outside the hot path.
module Blackbox.DTC
    ( Archetype (..)
    , ArchetypeRequirement (..)
    , BindingField (..)
    , BindingInput (..)
    , BindingIssue (..)
    , BindingNecessity (..)
    , BindingStatus (..)
    , BindingValidation (..)
    , BindingValue (..)
    , BehaviorSurface (..)
    , CorpusInput (..)
    , DtcPlan (..)
    , Expectation (..)
    , FeatureId (..)
    , FixtureAction (..)
    , HttpRoute (..)
    , CorpusChunk (..)
    , CorpusDigest (..)
    , DeepSeekPacket (..)
    , DeepSeekValidation (..)
    , LlmStagePrompt (..)
    , PlanStep (..)
    , ResultChunk (..)
    , RunMode (..)
    , RunSpec (..)
    , SpecSurface (..)
    , StepKind (..)
    , StopCondition (..)
    , TriggerAction (..)
    , batPlan
    , CoverageSummary (..)
    , dtcFlowMermaid
    , entrPlan
    , archetypeRequirementByName
    , planByName
    , planFromBinding
    , Readiness (..)
    , requirementsByArchetype
    , collectCorpusDigest
    , prepareDeepSeekPacket
    , deepSeekRequestJson
    , extractDeepSeekContent
    , validateDeepSeekOutput
    , summarizePlanCoverage
    , validateBinding
    ) where

import           Data.Text (Text)

import           Blackbox.DTC.Binding
import           Blackbox.DTC.Catalog
import           Blackbox.DTC.Coverage
import           Blackbox.DTC.PlanFromBinding
import           Blackbox.DTC.Requirements
import           Blackbox.DTC.System
import           Blackbox.DTC.Types


dtcFlowMermaid :: Text
dtcFlowMermaid = mconcat
    [ "## Build Flow\n"
    , "```mermaid\n"
    , "flowchart TD\n"
    , "    Corpus[Seed corpus<br/>source + upstream tests + grader] --> Read\n"
    , "    Read[Haskell readers<br/>source/test/grader adapters] --> Surface\n"
    , "    Surface[Behavior surfaces<br/>CLI flags / IO channels / fixtures / errors] --> Archetype\n"
    , "    Archetype[Coarse archetype hypothesis<br/>watcher CLI / HTTP client CLI / structured subcommand CLI] --> Requirements\n"
    , "    Requirements[Haskell archetype requirements<br/>required + optional binding fields] --> Calibrate\n"
    , "    Calibrate{DeepSeek/Codex binding extraction<br/>must cite corpus chunks} --> Plan\n"
    , "    Plan[DTC plan catalog<br/>archetype + project binding -> PlanStep] --> Review\n"
    , "    Review[Human/code review<br/>remove low-value or overfit flows] --> Versioned[Versioned Haskell plan]\n"
    , "```\n\n"
    , "## Agent Run Flow\n"
    , "```mermaid\n"
    , "flowchart TD\n"
    , "    Input[DTC plan + app binary] --> Select\n"
    , "    Select[Select PlanStep] --> Setup\n"
    , "    Setup[Fixture setup<br/>files / HTTP server / isolated workspace] --> Run\n"
    , "    Run[Tool workflow<br/>run app args + stdin + timeout + evidence-stop + sync/async process] --> Trigger\n"
    , "    Trigger[Trigger actions<br/>file append / HTTP ready / future events] --> Capture\n"
    , "    Capture[Capture evidence<br/>stdout / stderr / exit / duration / artifacts] --> Verify\n"
    , "    Verify[Haskell verifier<br/>expectations -> pass/fail/unsupported] --> Result\n"
    , "    Result[DTC run result JSON<br/>per-step verdict + surfaces + gaps] --> SystemPrepare\n"
    , "    SystemPrepare[Haskell system-prepare<br/>mechanical corpus/results chunks + signal lines] --> Report\n"
    , "    Report{DeepSeek result evaluation + oracle proposal<br/>must cite chunk ids} --> Done[Verified feature report]\n"
    , "```\n"
    ]
