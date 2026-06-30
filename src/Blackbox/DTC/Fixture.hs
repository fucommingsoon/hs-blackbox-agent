{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Fixture
    ( FixtureState (..)
    , setupFixtures
    ) where

import           Control.Concurrent (threadDelay)
import           Control.Monad      (forM, when)
import           Data.Text          (Text)
import qualified Data.Text.IO       as TIO
import           System.Directory   (createDirectoryIfMissing)
import           System.FilePath    (takeDirectory)

import           Blackbox.DTC
import           Blackbox.DTC.Env


data FixtureState = FixtureState
    { fsUnsupported :: [Text]
    } deriving (Eq, Show)


setupFixtures :: DtcEnv -> [FixtureAction] -> IO FixtureState
setupFixtures env actions = do
    unsupported <- fmap concat $ forM actions $ \action ->
        case action of
            TouchFile path -> do
                let expanded = expandPath env path
                ensureParent expanded
                TIO.writeFile expanded ""
                pure []
            WriteFileText path txt -> do
                let expanded = expandPath env path
                ensureParent expanded
                TIO.writeFile expanded (expandText env txt)
                pure []
            AppendFileText path txt -> do
                let expanded = expandPath env path
                ensureParent expanded
                TIO.appendFile expanded (expandText env txt)
                pure []
            SleepMs ms -> do
                threadDelay (ms * 1000)
                pure []
            StartHttpFixture _ ->
                pure ["fixture backend unsupported: http"]
    pure FixtureState { fsUnsupported = unsupported }


ensureParent :: FilePath -> IO ()
ensureParent path =
    when (not (null dir) && dir /= ".") $
        createDirectoryIfMissing True dir
  where
    dir = takeDirectory path
