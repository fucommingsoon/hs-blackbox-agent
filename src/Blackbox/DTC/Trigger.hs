{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Trigger
    ( triggerUnsupported
    , runTriggers
    ) where

import           Control.Concurrent (threadDelay)
import           Control.Monad      (forM_)
import           Data.Text          (Text)
import qualified Data.Text.IO       as TIO

import           Blackbox.DTC


triggerUnsupported :: [TriggerAction] -> [Text]
triggerUnsupported =
    concatMap classify
  where
    classify TriggerHttpReady      = ["trigger unsupported: http ready"]
    classify (TriggerAppend _ _ _) = []


runTriggers :: [TriggerAction] -> IO ()
runTriggers actions =
    forM_ actions $ \action ->
        case action of
            TriggerAppend path txt delayMs -> do
                threadDelay (delayMs * 1000)
                TIO.appendFile path txt
            TriggerHttpReady ->
                pure ()
