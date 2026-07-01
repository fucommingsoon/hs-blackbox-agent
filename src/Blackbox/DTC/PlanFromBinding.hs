{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.PlanFromBinding
    ( planFromBinding
    ) where

import           Data.List                            (find)
import qualified Data.Text                            as T
import           Data.Text                            (Text)
import           Text.Read                            (readMaybe)

import           Blackbox.DTC.Archetype.HttpClientCli
import           Blackbox.DTC.Archetype.StructuredSubcommandCli
import           Blackbox.DTC.Binding
import           Blackbox.DTC.Types


planFromBinding :: BindingInput -> Either Text DtcPlan
planFromBinding input
    | biArchetype input == "HttpClientCli" =
        httpClientPlanFromBinding input
    | biArchetype input == "http-client-cli" =
        httpClientPlanFromBinding input
    | biArchetype input == "http-client" =
        httpClientPlanFromBinding input
    | biArchetype input == "StructuredSubcommandCli" =
        structuredSubcommandPlanFromBinding input
    | biArchetype input == "structured-subcommand-cli" =
        structuredSubcommandPlanFromBinding input
    | biArchetype input == "subcommand-cli" =
        structuredSubcommandPlanFromBinding input
    | otherwise =
        Left ("unsupported binding archetype for plan generation: " <> biArchetype input)


httpClientPlanFromBinding :: BindingInput -> Either Text DtcPlan
httpClientPlanFromBinding input = do
    name <- field "name" input
    successExitCode <- intField "successExitCode" input
    spec <- HttpClientCliSpec
        <$> pure name
        <*> pure (bindingSources input)
        <*> field "usageNeedle" input
        <*> pure successExitCode
        <*> field "getMethodToken" input
        <*> field "postMethodToken" input
        <*> field "putMethodToken" input
        <*> listField "jsonBodyItems" input
        <*> listField "jsonBodyNeedles" input
        <*> listField "queryItems" input
        <*> listField "queryNeedles" input
        <*> listField "headerItems" input
        <*> listField "headerNeedles" input
        <*> field "formFlag" input
        <*> listField "formItems" input
        <*> listField "formNeedles" input
        <*> field "rawBodyFlag" input
        <*> field "rawBodyValue" input
        <*> listField "rawBodyNeedles" input
        <*> field "prettyFalseFlag" input
        <*> field "basicResponseNeedle" input
        <*> field "jsonResponseNeedle" input
        <*> field "statusErrorNeedle" input
    pure DtcPlan
        { dpName = name
        , dpInputs = bindingSources input
        , dpArchetypes = [HttpClientCli]
        , dpSteps = httpClientCliSteps spec
        }


structuredSubcommandPlanFromBinding :: BindingInput -> Either Text DtcPlan
structuredSubcommandPlanFromBinding input = do
    name <- field "name" input
    successExitCode <- intField "successExitCode" input
    spec <- StructuredSubcommandCliSpec
        <$> pure name
        <*> pure (bindingSources input)
        <*> pure successExitCode
        <*> field "usageNeedle" input
        <*> listField "topLevelNeedles" input
        <*> listField "nestedHelpCommands" input
        <*> field "completionCommand" input
        <*> field "completionNeedle" input
        <*> field "versionCommand" input
        <*> field "versionNeedle" input
        <*> field "licenseCommand" input
        <*> field "licenseNeedle" input
        <*> fmap T.unpack (field "formatInputPath" input)
        <*> field "formatInputText" input
        <*> field "formatCommand" input
        <*> field "formatCheckNeedle" input
        <*> fmap T.unpack (field "migrationDirPath" input)
        <*> field "migrationNewCommand" input
        <*> field "migrationFileNeedle" input
    pure DtcPlan
        { dpName = name
        , dpInputs = bindingSources input
        , dpArchetypes = [StructuredSubcommandCli]
        , dpSteps = structuredSubcommandCliSteps spec
        }


bindingSources :: BindingInput -> [CorpusInput]
bindingSources input =
    [ SourceTree ("binding:" <> T.unpack name) ]
  where
    name = maybe (biArchetype input) id (biProject input)


field :: Text -> BindingInput -> Either Text Text
field name input =
    case lookupValue name input of
        Nothing -> Left ("binding missing field required for plan generation: " <> name)
        Just value
            | T.null (T.strip (bvValue value)) ->
                Left ("binding field is empty: " <> name)
            | otherwise ->
                Right (T.strip (bvValue value))


intField :: Text -> BindingInput -> Either Text Int
intField name input = do
    value <- field name input
    case readMaybe (T.unpack value) of
        Just n  -> Right n
        Nothing -> Left ("binding field must be an integer: " <> name)


listField :: Text -> BindingInput -> Either Text [Text]
listField name input = do
    value <- field name input
    let parts
            | "," `T.isInfixOf` value = T.splitOn "," value
            | otherwise               = T.words value
        cleaned = filter (not . T.null) (map T.strip parts)
    if null cleaned
        then Left ("binding list field is empty: " <> name)
        else Right cleaned


lookupValue :: Text -> BindingInput -> Maybe BindingValue
lookupValue name input =
    find ((== name) . bvName) (biValues input)
