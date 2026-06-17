{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Oracle module — single chokepoint for oracle.yaml + probes.jsonl I/O.
-- harness uses summary / appendProbe.
-- LLM-facing tool calls (readSlot / writeSlot / lookupProbe) dispatch through here.
module Blackbox.Oracle
    ( -- harness-facing
      Oracle
    , initOracle
    , summary
    , appendProbe
    , countProbes
    , loadOracle      -- for belief synthesis
    , lastProbeRecord -- for step mode resume
      -- LLM-facing tool dispatcher
    , dispatchTool
      -- direct ops used by Init
    , writeSlotRaw
    ) where

import           Control.Exception       (SomeException, try)
import qualified Data.Aeson              as A
import qualified Data.Aeson.Key          as Key
import qualified Data.Aeson.KeyMap       as KM
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Lazy    as BL
import qualified Data.HashMap.Strict     as HM
import           Data.IORef              (IORef, atomicModifyIORef', newIORef,
                                          readIORef)
import qualified Data.Text               as T
import           Data.Text               (Text)
import qualified Data.Text.Encoding      as TE
import qualified Data.Text.IO            as TIO
import           Data.Time               (UTCTime, getCurrentTime)
import qualified Data.Vector             as V
import qualified Data.Yaml               as Y
import qualified System.Directory
import           System.Directory        (doesFileExist)
import           System.FilePath         ((</>))
import           System.IO               (IOMode (..), withFile, hClose,
                                          openFile)

import           Blackbox.Types          (universalSlots)


-- ---------------------------------------------------------------
-- Oracle handle (paths + in-memory mirror)
-- ---------------------------------------------------------------

data Oracle = Oracle
    { oraclePath     :: FilePath          -- oracle.yaml
    , probesPath     :: FilePath          -- probes.jsonl
    , oracleState    :: IORef A.Value     -- mirror of oracle.yaml
    , probesCount    :: IORef Int         -- cached count
    }


initOracle :: FilePath -> IO Oracle
initOracle taskDir = do
    let hsbbDir = taskDir </> ".hsbb"
    System.Directory.createDirectoryIfMissing True hsbbDir
    let oP = hsbbDir </> "oracle.yaml"
        pP = hsbbDir </> "probes.jsonl"
    initialOracle <- loadOrEmptyYaml oP
    initialCount  <- countLinesIfExists pP
    oRef <- newIORef initialOracle
    pRef <- newIORef initialCount
    pure Oracle { oraclePath = oP, probesPath = pP
                , oracleState = oRef, probesCount = pRef }


loadOrEmptyYaml :: FilePath -> IO A.Value
loadOrEmptyYaml p = do
    ex <- doesFileExist p
    if not ex then pure emptyOracle
    else do
        r <- try (Y.decodeFileEither p) :: IO (Either SomeException (Either Y.ParseException A.Value))
        case r of
            Right (Right v)  -> pure v
            _                -> pure emptyOracle


emptyOracle :: A.Value
emptyOracle = A.Object $ KM.fromList
    [ ("slots", A.Object KM.empty)
    , ("other", A.Array V.empty)
    ]


countLinesIfExists :: FilePath -> IO Int
countLinesIfExists p = do
    ex <- doesFileExist p
    if not ex then pure 0
    else do
        contents <- TIO.readFile p
        pure (length (filter (not . T.null) (T.lines contents)))


-- ---------------------------------------------------------------
-- harness-facing API
-- ---------------------------------------------------------------

-- Render the projection summary used in prompts.
summary :: Oracle -> IO Text
summary o = do
    val <- readIORef (oracleState o)
    pure (renderSummary val)


renderSummary :: A.Value -> Text
renderSummary (A.Object root) =
    let slots = case KM.lookup "slots" root of
                    Just (A.Object s) -> s
                    _                 -> KM.empty
        other = case KM.lookup "other" root of
                    Just (A.Array a) -> V.toList a
                    _                -> []
        slotLines = concatMap (slotLine slots) universalSlots
        otherLines = if null other then []
                     else "- other:" : map otherLine other
    in T.unlines $
        [ "## oracle 摘要"
        , "(confidence: 0 = 未经 probe 验证的文档推断, 不可置信; > 0 = probe 实测后逐步升级)"
        ]
        ++ slotLines
        ++ otherLines
renderSummary _ = "## oracle 摘要\n(空)\n"


slotLine :: KM.KeyMap A.Value -> Text -> [Text]
slotLine slots sid =
    let padded = T.justifyLeft 18 ' ' sid
    in case KM.lookup (Key.fromText sid) slots of
        Just (A.Object so) ->
            let title = textField so "title" "(无标题)"
                conf  = numberField so "confidence" 0
            in [ "- " <> padded <> " [" <> formatConf conf <> "]  " <> title ]
        _ -> [ "- " <> padded <> " [EMPTY]  (未填)" ]


otherLine :: A.Value -> Text
otherLine (A.Object so) =
    let oid   = textField so "id" "(无id)"
        title = textField so "title" "(无标题)"
        conf  = numberField so "confidence" 0
        ix    = case KM.lookup "index" so of
                    Just (A.Number n) -> "[" <> T.pack (show (truncate n :: Int)) <> "] "
                    _                 -> ""
    in "  - " <> ix <> oid <> " [" <> formatConf conf <> "]  " <> title
otherLine _ = "  - (无效条目)"


textField :: KM.KeyMap A.Value -> Text -> Text -> Text
textField o k def = case KM.lookup (Key.fromText k) o of
    Just (A.String s) -> s
    _                 -> def


numberField :: KM.KeyMap A.Value -> Text -> Double -> Double
numberField o k def = case KM.lookup (Key.fromText k) o of
    Just (A.Number n) -> realToFrac n
    _                 -> def


formatConf :: Double -> Text
formatConf x = T.pack (showFixed2 x)
  where
    showFixed2 n = let r = round (n * 100) :: Int
                   in case show r of
                       [a]      -> "0.0" ++ [a]
                       [a,b]    -> "0." ++ [a,b]
                       cs       -> let (i, d) = splitAt (length cs - 2) cs
                                   in i ++ "." ++ d


-- Append a probe record (as JSON line) to probes.jsonl.
appendProbe :: Oracle -> A.Value -> IO ()
appendProbe o v = do
    let line = BL.toStrict (A.encode v) `BS.append` "\n"
    BS.appendFile (probesPath o) line
    atomicModifyIORef' (probesCount o) (\n -> (n + 1, ()))


countProbes :: Oracle -> IO Int
countProbes o = readIORef (probesCount o)


-- Load oracle.yaml from disk (used by belief synthesis to get full content).
loadOracle :: Oracle -> IO A.Value
loadOracle o = readIORef (oracleState o)


-- Read the last probe record from probes.jsonl (used by step mode to rebuild last_result).
lastProbeRecord :: Oracle -> IO (Maybe A.Value)
lastProbeRecord o = do
    ex <- doesFileExist (probesPath o)
    if not ex then pure Nothing
    else do
        contents <- TIO.readFile (probesPath o)
        let ls = filter (not . T.null) (T.lines contents)
        case ls of
            [] -> pure Nothing
            _  -> do
                let lastLine = last ls
                case A.eitherDecodeStrict (TE.encodeUtf8 lastLine) of
                    Right v -> pure (Just v)
                    Left _  -> pure Nothing


-- ---------------------------------------------------------------
-- LLM-facing tool dispatcher
-- ---------------------------------------------------------------

-- Dispatch a tool call. Returns the tool's reply as a Text (will be sent
-- back to the LLM as a tool result message).
dispatchTool :: Oracle -> Text -> A.Value -> IO Text
dispatchTool o "readSlot" args     = readSlotTool o args
dispatchTool o "writeSlot" args    = writeSlotTool o args
dispatchTool o "lookupProbe" args  = lookupProbeTool o args
dispatchTool _ name _              = pure ("error: unknown tool " <> name)


readSlotTool :: Oracle -> A.Value -> IO Text
readSlotTool o (A.Object args) = do
    case KM.lookup "slot_id" args of
        Just (A.String sid) -> do
            cur <- readIORef (oracleState o)
            pure (renderSlot cur sid)
        _ -> pure "error: missing slot_id"
readSlotTool _ _ = pure "error: bad args"


renderSlot :: A.Value -> Text -> Text
renderSlot (A.Object root) sid =
    -- Try universal slots first
    case KM.lookup "slots" root of
        Just (A.Object slotsMap)
            | Just rec_ <- KM.lookup (Key.fromText sid) slotsMap ->
                TE.decodeUtf8 (Y.encode rec_)
        _ ->
            -- Try other array
            case KM.lookup "other" root of
                Just (A.Array a) ->
                    case [ rec_ | A.Object rec_ <- V.toList a
                                , KM.lookup "id" rec_ == Just (A.String sid)
                                ] of
                        (r : _) -> TE.decodeUtf8 (Y.encode (A.Object r))
                        []      -> "slot not found: " <> sid
                _ -> "slot not found: " <> sid
renderSlot _ sid = "slot not found: " <> sid


writeSlotTool :: Oracle -> A.Value -> IO Text
writeSlotTool o (A.Object args) = do
    case KM.lookup "slot_id" args of
        Just (A.String sid) -> do
            now <- getCurrentTime
            writeSlotRaw o sid args now
            pure ("ok: wrote " <> sid)
        _ -> pure "error: missing slot_id"
writeSlotTool _ _ = pure "error: bad args"


-- Raw writeSlot — used both by tool dispatcher and Init phase.
writeSlotRaw :: Oracle -> Text -> KM.KeyMap A.Value -> UTCTime -> IO ()
writeSlotRaw o sid args now = do
    let isUniversal = sid `elem` universalSlots
    let rec_ = makeSlotRecord args now
    if isUniversal
        then atomicModifyIORef' (oracleState o) $ \v ->
                (updateUniversalSlot v sid rec_, ())
        else atomicModifyIORef' (oracleState o) $ \v ->
                (updateOtherSlot v sid rec_, ())
    cur <- readIORef (oracleState o)
    -- Persist
    BS.writeFile (oraclePath o) (Y.encode cur)


makeSlotRecord :: KM.KeyMap A.Value -> UTCTime -> A.Value
makeSlotRecord args now = A.Object $ KM.fromList $
    [ ("title",      pickField "title" args (A.String ""))
    , ("confidence", pickField "confidence" args (A.Number 0))
    , ("content",    pickField "content" args (A.String ""))
    , ("evidence",   pickField "evidence" args (A.Array V.empty))
    , ("notes",      pickField "notes" args (A.String ""))
    , ("updated_at", A.String (T.pack (show now)))
    ] ++ indexEntry args


pickField :: Text -> KM.KeyMap A.Value -> A.Value -> A.Value
pickField k m def = case KM.lookup (Key.fromText k) m of
    Just v -> v
    _      -> def


indexEntry :: KM.KeyMap A.Value -> [(Key.Key, A.Value)]
indexEntry m = case KM.lookup "index" m of
    Just v -> [("index", v)]
    _      -> []


updateUniversalSlot :: A.Value -> Text -> A.Value -> A.Value
updateUniversalSlot (A.Object root) sid rec_ =
    let slots = case KM.lookup "slots" root of
                    Just (A.Object s) -> s
                    _                 -> KM.empty
        slots' = KM.insert (Key.fromText sid) rec_ slots
    in A.Object (KM.insert "slots" (A.Object slots') root)
updateUniversalSlot v _ _ = v


updateOtherSlot :: A.Value -> Text -> A.Value -> A.Value
updateOtherSlot (A.Object root) sid rec_ =
    let other = case KM.lookup "other" root of
                    Just (A.Array a) -> V.toList a
                    _                -> []
        recWithId = case rec_ of
                       A.Object r -> A.Object (KM.insert "id" (A.String (uniqueId other sid)) r)
                       _          -> rec_
        other'    = filter (notSameId sid) other ++ [recWithId]
    in A.Object (KM.insert "other" (A.Array (V.fromList other')) root)
updateOtherSlot v _ _ = v


notSameId :: Text -> A.Value -> Bool
notSameId sid (A.Object o) = case KM.lookup "id" o of
    Just (A.String s) -> s /= sid
    _                 -> True
notSameId _ _ = True


-- If user-supplied id collides, suffix with _2, _3, ...
uniqueId :: [A.Value] -> Text -> Text
uniqueId existing base =
    let usedIds = [s | A.Object o <- existing
                     , Just (A.String s) <- [KM.lookup "id" o]]
    in goU 1 usedIds base
  where
    goU :: Int -> [Text] -> Text -> Text
    goU n used b =
        let candidate = if n == 1 then b else b <> "_" <> T.pack (show n)
        in if candidate `elem` used && n < 100
           then goU (n + 1) used b
           else candidate


lookupProbeTool :: Oracle -> A.Value -> IO Text
lookupProbeTool o (A.Object args) = do
    case KM.lookup "probe_id" args of
        Just (A.String pid) -> do
            ex <- doesFileExist (probesPath o)
            if not ex then pure ("probe not found: " <> pid)
            else do
                ls <- T.lines <$> TIO.readFile (probesPath o)
                let match = [l | l <- ls, T.isInfixOf ("\"id\":\"" <> pid <> "\"") l]
                case match of
                    (l : _) -> pure l
                    []      -> pure ("probe not found: " <> pid)
        _ -> pure "error: missing probe_id"
lookupProbeTool _ _ = pure "error: bad args"
