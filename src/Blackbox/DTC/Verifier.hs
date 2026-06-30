{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Verifier
    ( verifyExpectations
    ) where

import qualified Data.Text             as T
import           Data.Text             (Text)

import           Blackbox.DTC
import           Blackbox.DTC.Result


verifyExpectations :: [Expectation] -> ProcessCapture -> [Text]
verifyExpectations expectations capture =
    concatMap check expectations
  where
    check expectation =
        case expectation of
            ExpectExit n ->
                case pcExit capture of
                    Just got | got == n -> []
                    Just got -> ["expected exit " <> tshow n <> ", got " <> tshow got]
                    Nothing  -> ["expected exit " <> tshow n <> ", got timeout/no-exit"]
            ExpectStdoutContains needle
                | needle `T.isInfixOf` pcStdout capture -> []
                | otherwise -> ["stdout missing: " <> needle]
            ExpectStderrContains needle
                | needle `T.isInfixOf` pcStderr capture -> []
                | otherwise -> ["stderr missing: " <> needle]
            ExpectStdoutEmpty
                | T.null (pcStdout capture) -> []
                | otherwise -> ["stdout expected empty"]
            ExpectStderrEmpty
                | T.null (pcStderr capture) -> []
                | otherwise -> ["stderr expected empty"]
            ExpectCompletesWithinMs n
                | pcDurationMs capture <= n -> []
                | otherwise ->
                    [ "expected duration <= "
                        <> tshow n <> "ms, got "
                        <> tshow (pcDurationMs capture) <> "ms"
                    ]


tshow :: Show a => a -> Text
tshow = T.pack . show
