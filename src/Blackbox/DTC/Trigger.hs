{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Trigger
    ( triggerUnsupported
    , runTriggers
    ) where

import           Control.Concurrent (threadDelay)
import           Control.Monad      (forM_)
import           Data.Text          (Text)
import qualified Data.Text.IO       as TIO
import           System.Directory   (createDirectoryIfMissing)
import           System.FilePath    (takeDirectory)

import           Blackbox.DTC
import           Blackbox.DTC.Env


triggerUnsupported :: [TriggerAction] -> [Text]
triggerUnsupported =
    concatMap classify
  where
    classify TriggerHttpReady      = ["trigger unsupported: http ready"]
    classify (TriggerAppend _ _ _) = []
    classify (TriggerTouch _ _)    = []
    classify (TriggerMkdir _ _)    = []


runTriggers :: DtcEnv -> [TriggerAction] -> IO ()
runTriggers env actions =
    forM_ actions $ \action ->
        case action of
            TriggerAppend path txt delayMs -> do
                threadDelay (delayMs * 1000)
                let expanded = expandPath env path
                ensureParent expanded
                TIO.appendFile expanded (expandText env txt)
            TriggerTouch path delayMs -> do
                threadDelay (delayMs * 1000)
                let expanded = expandPath env path
                ensureParent expanded
                TIO.writeFile expanded ""
            TriggerMkdir path delayMs -> do
                threadDelay (delayMs * 1000)
                createDirectoryIfMissing True (expandPath env path)
            TriggerHttpReady ->
                pure ()


ensureParent :: FilePath -> IO ()
ensureParent path =
    createDirectoryIfMissing True (takeDirectory path)
