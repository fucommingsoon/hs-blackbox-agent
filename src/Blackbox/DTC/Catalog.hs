{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Catalog
    ( batPlan
    , entrPlan
    , planByName
    ) where

import           Data.Text (Text)

import           Blackbox.DTC.Archetype.HttpClientCli
import           Blackbox.DTC.Archetype.WatcherCli
import           Blackbox.DTC.Types


entrPlan :: DtcPlan
entrPlan = DtcPlan
    { dpName = "entr"
    , dpInputs = entrInputs
    , dpArchetypes = [WatcherCli, FileInputCli]
    , dpSteps = watcherCliSteps entrWatcherSpec
    }


entrInputs :: [CorpusInput]
entrInputs =
    [ SourceTree "corpus/probe-plan-seeds/entr/source/github"
    , UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
    , GraderTests "corpus/probe-plan-seeds/entr/grader"
    ]


entrWatcherSpec :: WatcherCliSpec
entrWatcherSpec = WatcherCliSpec
    { wcsName = "entr"
    , wcsSources =
        [ UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
        , GraderTests "corpus/probe-plan-seeds/entr/grader"
        ]
    , wcsNonInteractiveFlag = "-n"
    , wcsOneshotFlag = "-z"
    , wcsPostponeFlag = "-p"
    , wcsDirectoryWatchFlag = "-d"
    , wcsChangedPathToken = "/_"
    , wcsUsageNeedle = "usage:"
    , wcsNoRegularFilesNeedle = "No regular files"
    , wcsUnableToStatNeedle = "unable to stat"
    , wcsDirectoryAlteredNeedle = "directory altered"
    }


batPlan :: DtcPlan
batPlan = DtcPlan
    { dpName = "bat"
    , dpInputs = batInputs
    , dpArchetypes = [HttpClientCli, StdoutFormatterCli]
    , dpSteps = httpClientCliSteps batHttpSpec
    }


batInputs :: [CorpusInput]
batInputs =
    [ SourceTree "corpus/probe-plan-seeds/bat/source/github"
    , UpstreamTests "corpus/probe-plan-seeds/bat/source/github/httplib/httplib_test.go"
    , GraderTests "corpus/probe-plan-seeds/bat/grader"
    ]


batHttpSpec :: HttpClientCliSpec
batHttpSpec = HttpClientCliSpec
    { hcsName = "bat"
    , hcsSources =
        [ SourceTree "corpus/probe-plan-seeds/bat/source/github/README.md"
        , SourceTree "corpus/probe-plan-seeds/bat/source/github/bat.go"
        , SourceTree "corpus/probe-plan-seeds/bat/source/github/http.go"
        , GraderTests "corpus/probe-plan-seeds/bat/grader"
        ]
    , hcsUsageNeedle = "Usage"
    , hcsSuccessExitCode = 0
    , hcsGetMethodToken = "GET"
    , hcsPostMethodToken = "POST"
    , hcsPutMethodToken = "PUT"
    , hcsJsonBodyItems = ["name=John", "email=john@example.org"]
    , hcsJsonBodyNeedles = ["John", "john@example.org"]
    , hcsQueryItems = ["q=bat", "page=1"]
    , hcsQueryNeedles = ["q=bat", "page=1"]
    , hcsHeaderItems = ["X-HSBB:works"]
    , hcsHeaderNeedles = ["X-HSBB: works"]
    , hcsFormFlag = "-form"
    , hcsFormItems = ["name=John", "email=john@example.org"]
    , hcsFormNeedles = ["name=John", "email=john%40example.org"]
    , hcsRawBodyFlag = "-body="
    , hcsRawBodyValue = "{\"custom\":\"data\"}"
    , hcsRawBodyNeedles = ["custom", "data"]
    , hcsPrettyFalseFlag = "-pretty=false"
    , hcsPrintResponseBodyFlag = Just "-print=b"
    , hcsPrintResponseHeaderFlag = Nothing
    , hcsAuthFlag = Just "-auth=user:pass"
    , hcsAuthHeaderNeedle = Just "Authorization: Basic dXNlcjpwYXNz"
    , hcsDownloadFlag = Just "-download=true"
    , hcsDownloadFileName = Just "report.txt"
    , hcsDownloadBodyNeedle = Just "download-ok"
    , hcsBasicResponseNeedle = "\"ok\""
    , hcsJsonResponseNeedle = "created"
    , hcsStatusErrorNeedle = "not_found"
    }


planByName :: Text -> Maybe DtcPlan
planByName "entr" = Just entrPlan
planByName "bat"  = Just batPlan
planByName _      = Nothing
