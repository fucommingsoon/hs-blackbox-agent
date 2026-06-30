{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Binding
    ( BindingInput (..)
    , BindingIssue (..)
    , BindingStatus (..)
    , BindingValue (..)
    , BindingValidation (..)
    , validateBinding
    ) where

import qualified Data.Aeson        as A
import           Data.Aeson        ((.!=), (.:), (.:?), (.=))
import qualified Data.Aeson.Key    as K
import qualified Data.Aeson.KeyMap as KM
import           Data.Aeson.Types  (Parser)
import           Data.List         (find)
import qualified Data.Text         as T
import           Data.Text         (Text)

import           Blackbox.DTC.Requirements (archetypeRequirementByName)
import           Blackbox.DTC.Types


data BindingInput = BindingInput
    { biArchetype :: Text
    , biProject   :: Maybe Text
    , biValues    :: [BindingValue]
    } deriving (Eq, Show)


data BindingValue = BindingValue
    { bvName       :: Text
    , bvValue      :: Text
    , bvSource     :: Text
    , bvConfidence :: Text
    } deriving (Eq, Show)


data BindingStatus
    = BindingReady
    | BindingMissing
    | BindingAmbiguous
    | BindingUnsupportedArchetype
    deriving (Eq, Show)


data BindingIssue = BindingIssue
    { issueField   :: Text
    , issueKind    :: Text
    , issueMessage :: Text
    } deriving (Eq, Show)


data BindingValidation = BindingValidation
    { bvArchetype       :: Text
    , bvProject         :: Maybe Text
    , bvStatus          :: BindingStatus
    , bvMissingRequired :: [Text]
    , bvAmbiguousFields :: [Text]
    , bvOptionalMissing :: [Text]
    , bvAcceptedFields  :: [Text]
    , bvIssues          :: [BindingIssue]
    , bvRecommendedNext :: Text
    } deriving (Eq, Show)


instance A.FromJSON BindingInput where
    parseJSON = A.withObject "BindingInput" $ \o -> do
        archetype <- o .: "archetype"
        project <- o .:? "project"
        bindingObject <- o .: "binding"
        values <- traverse parseBindingPair (KM.toList bindingObject)
        pure BindingInput
            { biArchetype = archetype
            , biProject = project
            , biValues = values
            }


parseBindingPair :: (K.Key, A.Value) -> Parser BindingValue
parseBindingPair (key, valueJson) =
    A.withObject "BindingValue" parseValue valueJson
  where
    name = K.toText key
    parseValue o = do
        value <- o .: "value"
        source <- o .:? "source" .!= ""
        confidence <- o .:? "confidence" .!= ""
        pure BindingValue
            { bvName = name
            , bvValue = value
            , bvSource = source
            , bvConfidence = confidence
            }


instance A.ToJSON BindingStatus where
    toJSON BindingReady = A.String "binding_ready"
    toJSON BindingMissing = A.String "binding_missing"
    toJSON BindingAmbiguous = A.String "binding_ambiguous"
    toJSON BindingUnsupportedArchetype = A.String "unsupported_archetype"


instance A.ToJSON BindingIssue where
    toJSON issue = A.object
        [ "field" .= issueField issue
        , "kind" .= issueKind issue
        , "message" .= issueMessage issue
        ]


instance A.ToJSON BindingValidation where
    toJSON validation = A.object
        [ "archetype" .= bvArchetype validation
        , "project" .= bvProject validation
        , "status" .= bvStatus validation
        , "missingRequired" .= bvMissingRequired validation
        , "ambiguousFields" .= bvAmbiguousFields validation
        , "optionalMissing" .= bvOptionalMissing validation
        , "acceptedFields" .= bvAcceptedFields validation
        , "issues" .= bvIssues validation
        , "recommendedNext" .= bvRecommendedNext validation
        ]


validateBinding :: BindingInput -> BindingValidation
validateBinding input =
    case archetypeRequirementByName (biArchetype input) of
        Nothing -> unsupportedValidation input
        Just requirement -> validateAgainst requirement input


unsupportedValidation :: BindingInput -> BindingValidation
unsupportedValidation input =
    BindingValidation
        { bvArchetype = biArchetype input
        , bvProject = biProject input
        , bvStatus = BindingUnsupportedArchetype
        , bvMissingRequired = []
        , bvAmbiguousFields = []
        , bvOptionalMissing = []
        , bvAcceptedFields = map bvName (biValues input)
        , bvIssues =
            [ BindingIssue
                { issueField = biArchetype input
                , issueKind = "unsupported_archetype"
                , issueMessage = "No Haskell requirement contract exists for this archetype."
                }
            ]
        , bvRecommendedNext = "switch_or_define_archetype"
        }


validateAgainst :: ArchetypeRequirement -> BindingInput -> BindingValidation
validateAgainst requirement input =
    BindingValidation
        { bvArchetype = biArchetype input
        , bvProject = biProject input
        , bvStatus = status
        , bvMissingRequired = missingRequired <> emptyRequired
        , bvAmbiguousFields = ambiguousRequired
        , bvOptionalMissing = optionalMissing
        , bvAcceptedFields = acceptedFields
        , bvIssues = issues
        , bvRecommendedNext = recommendedNext status
        }
  where
    requiredFields = [bfName f | f <- arFields requirement, bfNecessity f == Required]
    optionalFields = [bfName f | f <- arFields requirement, bfNecessity f == Optional]
    acceptedFields = [bvName v | v <- biValues input, not (T.null (T.strip (bvValue v)))]
    missingRequired = [name | name <- requiredFields, lookupBinding name input == Nothing]
    emptyRequired =
        [ name
        | name <- requiredFields
        , Just value <- [lookupBinding name input]
        , T.null (T.strip (bvValue value))
        ]
    ambiguousRequired =
        [ name
        | name <- requiredFields
        , Just value <- [lookupBinding name input]
        , not (T.null (T.strip (bvValue value)))
        , bindingAmbiguous value
        ]
    optionalMissing = [name | name <- optionalFields, lookupBinding name input == Nothing]
    issues =
        missingIssues missingRequired
            <> emptyIssues emptyRequired
            <> ambiguousIssues ambiguousRequired
    status
        | not (null missingRequired) || not (null emptyRequired) = BindingMissing
        | not (null ambiguousRequired) = BindingAmbiguous
        | otherwise = BindingReady


lookupBinding :: Text -> BindingInput -> Maybe BindingValue
lookupBinding name input =
    find ((== name) . bvName) (biValues input)


bindingAmbiguous :: BindingValue -> Bool
bindingAmbiguous value =
    T.null (T.strip (bvSource value))
        || normalizeConfidence (bvConfidence value) == "low"
        || T.null (normalizeConfidence (bvConfidence value))


normalizeConfidence :: Text -> Text
normalizeConfidence =
    T.toLower . T.strip


missingIssues :: [Text] -> [BindingIssue]
missingIssues =
    map $ \name -> BindingIssue
        { issueField = name
        , issueKind = "binding_missing"
        , issueMessage = "Required binding field is absent."
        }


emptyIssues :: [Text] -> [BindingIssue]
emptyIssues =
    map $ \name -> BindingIssue
        { issueField = name
        , issueKind = "binding_empty"
        , issueMessage = "Required binding field is present but empty."
        }


ambiguousIssues :: [Text] -> [BindingIssue]
ambiguousIssues =
    map $ \name -> BindingIssue
        { issueField = name
        , issueKind = "binding_ambiguous"
        , issueMessage = "Required binding field needs a non-empty source and medium/high confidence."
        }


recommendedNext :: BindingStatus -> Text
recommendedNext BindingReady = "run_archetype_flow"
recommendedNext BindingMissing = "refine_binding"
recommendedNext BindingAmbiguous = "refine_binding"
recommendedNext BindingUnsupportedArchetype = "switch_or_define_archetype"
