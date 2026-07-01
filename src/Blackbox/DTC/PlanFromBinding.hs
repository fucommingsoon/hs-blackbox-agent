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
import           Blackbox.DTC.Archetype.TabularRenderCli
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
    | biArchetype input == "TabularRenderCli" =
        tabularRenderPlanFromBinding input
    | biArchetype input == "tabular-render-cli" =
        tabularRenderPlanFromBinding input
    | biArchetype input == "table-render-cli" =
        tabularRenderPlanFromBinding input
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
        <*> pure (optionalField "printResponseBodyFlag" input)
        <*> pure (optionalField "printResponseHeaderFlag" input)
        <*> pure (optionalField "authFlag" input)
        <*> pure (optionalField "authHeaderNeedle" input)
        <*> pure (optionalField "downloadFlag" input)
        <*> pure (optionalField "downloadFileName" input)
        <*> pure (optionalField "downloadBodyNeedle" input)
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
    completion <- optionalCommandNeedle input "completionCommand" "completionNeedle"
    version <- optionalCommandNeedle input "versionCommand" "versionNeedle"
    license <- optionalCommandNeedle input "licenseCommand" "licenseNeedle"
    configEnvVar <- structuredConfigEnvVar input
    spec <- StructuredSubcommandCliSpec
        <$> pure name
        <*> pure (bindingSources input)
        <*> pure successExitCode
        <*> field "usageNeedle" input
        <*> listField "topLevelNeedles" input
        <*> listField "nestedHelpCommands" input
        <*> pure (optionalField "noArgsNeedle" input)
        <*> pure completion
        <*> pure version
        <*> pure license
        <*> fmap T.unpack (field "formatInputPath" input)
        <*> field "formatInputText" input
        <*> field "formatCommand" input
        <*> field "formatCheckNeedle" input
        <*> fmap T.unpack (field "migrationDirPath" input)
        <*> field "migrationNewCommand" input
        <*> field "migrationFileNeedle" input
        <*> field "migrationSqlFileName" input
        <*> field "migrationSqlText" input
        <*> field "migrationHashCommand" input
        <*> field "migrationValidateCommand" input
        <*> field "migrationChecksumErrorNeedle" input
        <*> pure configEnvVar
    pure DtcPlan
        { dpName = name
        , dpInputs = bindingSources input
        , dpArchetypes = [StructuredSubcommandCli]
        , dpSteps = structuredSubcommandCliSteps spec
        }


optionalCommandNeedle :: BindingInput -> Text -> Text -> Either Text (Maybe CommandNeedleSpec)
optionalCommandNeedle input commandField needleField =
    case (optionalField commandField input, optionalField needleField input) of
        (Nothing, Nothing) -> Right Nothing
        (Just command, Just needle) -> Right (Just (CommandNeedleSpec command needle))
        _ -> Left ("structured command binding requires both fields or neither: " <> commandField <> "," <> needleField)


structuredConfigEnvVar :: BindingInput -> Either Text (Maybe ConfigEnvVarSpec)
structuredConfigEnvVar input =
    case present of
        [] -> Right Nothing
        fields
            | length fields == length names -> do
                spec <- ConfigEnvVarSpec
                    <$> fmap T.unpack (field "configFilePath" input)
                    <*> field "configFileText" input
                    <*> fmap T.unpack (field "configSchemaPath" input)
                    <*> field "configSchemaText" input
                    <*> field "configEnvVarCommand" input
                    <*> field "configEnvVarNeedle" input
                Right (Just spec)
            | otherwise ->
                Left ("structured config/env/var binding requires all optional fields when any are present: " <> T.intercalate "," names)
  where
    names =
        [ "configFilePath"
        , "configFileText"
        , "configSchemaPath"
        , "configSchemaText"
        , "configEnvVarCommand"
        , "configEnvVarNeedle"
        ]
    present = [name | name <- names, lookupValue name input /= Nothing]


tabularRenderPlanFromBinding :: BindingInput -> Either Text DtcPlan
tabularRenderPlanFromBinding input = do
    name <- field "name" input
    successExitCode <- intField "successExitCode" input
    version <- optionalPair "versionCommand" "versionNeedle" input
    noHeader <- optionalStdinRender "noHeaderCommand" "noHeaderInputText" "noHeaderNeedles" input
    sequenceRender <- optionalStdinRender "sequenceCommand" "sequenceInputText" "sequenceNeedles" input
    layout <- optionalStdinRender "layoutCommand" "layoutInputText" "layoutNeedles" input
    wideChar <- optionalStdinRender "wideCharCommand" "wideCharInputText" "wideCharNeedles" input
    malformed <- optionalErrorRender
        "malformedInputCommand"
        "malformedInputText"
        "malformedInputExitCode"
        "malformedInputStderrNeedle"
        input
    spec <- TabularRenderCliSpec
        <$> pure name
        <*> pure (bindingSources input)
        <*> pure successExitCode
        <*> field "usageNeedle" input
        <*> field "csvStdinText" input
        <*> listField "csvStdinNeedles" input
        <*> fmap T.unpack (field "fileInputPath" input)
        <*> field "fileInputText" input
        <*> field "fileRenderCommand" input
        <*> listField "fileRenderNeedles" input
        <*> field "tsvStdinText" input
        <*> field "tsvRenderCommand" input
        <*> listField "tsvRenderNeedles" input
        <*> field "missingFileCommand" input
        <*> field "missingFileErrorNeedle" input
        <*> pure (fst version)
        <*> pure (snd version)
        <*> pure noHeader
        <*> pure sequenceRender
        <*> pure layout
        <*> pure wideChar
        <*> pure malformed
    pure DtcPlan
        { dpName = name
        , dpInputs = bindingSources input
        , dpArchetypes = [TabularRenderCli]
        , dpSteps = tabularRenderCliSteps spec
        }


optionalPair :: Text -> Text -> BindingInput -> Either Text (Maybe Text, Maybe Text)
optionalPair left right input =
    case (optionalField left input, optionalField right input) of
        (Nothing, Nothing) -> Right (Nothing, Nothing)
        (Just a, Just b)   -> Right (Just a, Just b)
        _ -> Left ("binding requires both optional fields or neither: " <> left <> "," <> right)


optionalStdinRender :: Text -> Text -> Text -> BindingInput -> Either Text (Maybe StdinRenderSpec)
optionalStdinRender commandName inputName needlesName input =
    case (optionalField inputName input, optionalField needlesName input) of
        (Nothing, Nothing)
            | lookupValue commandName input == Nothing -> Right Nothing
            | otherwise -> Left ("tabular stdin render binding requires input and needles when command is present: " <> commandName <> "," <> inputName <> "," <> needlesName)
        (Just inputText, Just needlesText) ->
            Right (Just StdinRenderSpec
                { srsCommand = maybe "" id (optionalField commandName input)
                , srsInput = inputText
                , srsNeedles = splitList needlesText
                })
        _ -> Left ("tabular stdin render binding requires input and needles together: " <> inputName <> "," <> needlesName)


optionalErrorRender :: Text -> Text -> Text -> Text -> BindingInput -> Either Text (Maybe ErrorRenderSpec)
optionalErrorRender commandName inputName exitName stderrName input =
    case present of
        []
            | lookupValue commandName input == Nothing -> Right Nothing
            | otherwise -> Left ("tabular malformed-input binding requires input, exit code, and stderr needle when command is present: " <> commandName)
        fields
            | length fields == length requiredNames -> do
                inputText <- field inputName input
                exitCode <- intField exitName input
                stderrNeedle <- field stderrName input
                Right (Just ErrorRenderSpec
                    { ersCommand = maybe "" id (optionalField commandName input)
                    , ersInput = inputText
                    , ersExitCode = exitCode
                    , ersStderrNeedle = stderrNeedle
                    })
            | otherwise ->
                Left ("tabular malformed-input binding requires all required optional fields when any are present: " <> T.intercalate "," requiredNames)
  where
    requiredNames = [inputName, exitName, stderrName]
    present = [name | name <- requiredNames, lookupValue name input /= Nothing]


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
    let cleaned = splitList value
    if null cleaned
        then Left ("binding list field is empty: " <> name)
        else Right cleaned


splitList :: Text -> [Text]
splitList value =
    filter (not . T.null) (map T.strip parts)
  where
    parts
        | "," `T.isInfixOf` value = T.splitOn "," value
        | otherwise               = T.words value


lookupValue :: Text -> BindingInput -> Maybe BindingValue
lookupValue name input =
    find ((== name) . bvName) (biValues input)


optionalField :: Text -> BindingInput -> Maybe Text
optionalField name input =
    case lookupValue name input of
        Nothing -> Nothing
        Just value
            | T.null (T.strip (bvValue value)) -> Nothing
            | otherwise -> Just (T.strip (bvValue value))
