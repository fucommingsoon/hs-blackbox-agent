{-# LANGUAGE OverloadedStrings #-}

-- Trace logging — append-only JSONL event stream.
-- One trace.jsonl per task. Each event line carries: ts, type, phase + payload.
-- Event types: phase_start / phase_end / llm_request / llm_response
--              / tool_dispatch_start / tool_dispatch_result / error / meta
module Blackbox.Trace
    ( TraceHandle
    , openTrace
    , appendEvent
    , phaseStart
    , phaseEnd
    , noTrace
    ) where

import qualified Data.Aeson         as A
import qualified Data.Aeson.KeyMap  as KM
import qualified Data.ByteString    as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text          as T
import           Data.Text          (Text)
import           Data.Time          (getCurrentTime)
import           System.Directory   (createDirectoryIfMissing)
import           System.FilePath    ((</>))


newtype TraceHandle = TraceHandle FilePath


openTrace :: FilePath -> IO TraceHandle
openTrace taskDir = do
    let dir = taskDir </> ".hsbb"
    createDirectoryIfMissing True dir
    pure (TraceHandle (dir </> "trace.jsonl"))


-- Append one event to the trace file as a single JSONL line.
appendEvent :: TraceHandle -> Text -> A.Value -> IO ()
appendEvent (TraceHandle path) eventType payload = do
    now <- getCurrentTime
    let baseObj = case payload of
            A.Object o -> o
            _          -> KM.singleton "payload" payload
        eventObj = KM.insert "ts"   (A.String (T.pack (show now)))
                 $ KM.insert "type" (A.String eventType) baseObj
        line = BL.toStrict (A.encode (A.Object eventObj)) `BS.append` "\n"
    BS.appendFile path line


phaseStart :: TraceHandle -> Text -> IO ()
phaseStart th phase = appendEvent th "phase_start" (A.object ["phase" A..= phase])


phaseEnd :: TraceHandle -> Text -> IO ()
phaseEnd th phase = appendEvent th "phase_end" (A.object ["phase" A..= phase])


-- A no-op trace handler (writes to /dev/null logically).
-- Useful for tests / dry runs.
noTrace :: Text -> A.Value -> IO ()
noTrace _ _ = pure ()
