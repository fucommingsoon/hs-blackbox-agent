{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Requirements
    ( archetypeRequirementByName
    , requirementsByArchetype
    ) where

import           Data.Text (Text)

import           Blackbox.DTC.Archetype.HttpClientCli (httpClientCliRequirements)
import           Blackbox.DTC.Archetype.WatcherCli (watcherCliRequirements)
import           Blackbox.DTC.Types


requirementsByArchetype :: Archetype -> Maybe ArchetypeRequirement
requirementsByArchetype WatcherCli = Just watcherCliRequirements
requirementsByArchetype HttpClientCli = Just httpClientCliRequirements
requirementsByArchetype FileInputCli = Nothing
requirementsByArchetype StdoutFormatterCli = Nothing


archetypeRequirementByName :: Text -> Maybe ArchetypeRequirement
archetypeRequirementByName "WatcherCli" = requirementsByArchetype WatcherCli
archetypeRequirementByName "watcher-cli" = requirementsByArchetype WatcherCli
archetypeRequirementByName "watcher" = requirementsByArchetype WatcherCli
archetypeRequirementByName "HttpClientCli" = requirementsByArchetype HttpClientCli
archetypeRequirementByName "http-client-cli" = requirementsByArchetype HttpClientCli
archetypeRequirementByName "http-client" = requirementsByArchetype HttpClientCli
archetypeRequirementByName _ = Nothing
