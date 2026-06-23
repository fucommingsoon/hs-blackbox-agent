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
    , dynamicSection      -- 本轮动态 / 未触槽 / 累计次数
    , appendProbe
    , countProbes
    , countDecisionProbes -- 只算 round>0 的 probe (init 阶段机械 probe round=0)
    , setCurrentRound     -- 设置当前轮号供 writeSlot 元数据记录
    , setLastIntegrationAttempts  -- 整理阶段结束时记录 LLM 尝试 writeSlot 次数
    , resetNextRoundHints -- integration 开始时清空给下一轮的 hint
    , readNextRoundHints  -- decision 渲染 user prompt 时读上一发 integration 留的 hint
    , loadOracle          -- for belief synthesis
    , lastProbeRecord     -- for step mode resume
    , uniqueProbeCommands -- 去重的历史 probe cmd 列表
    , referenceProbes     -- 常驻参考文档 (--help / --version 类)
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
    { oraclePath              :: FilePath
    , probesPath              :: FilePath
    , oracleState             :: IORef A.Value
    , probesCount             :: IORef Int
    , currentRound            :: IORef Int           -- 0 for init, ≥1 for main loop
    , lastIntegrationAttempts :: IORef Int           -- 上一次 integration 里 LLM 尝试了几次 writeSlot
    , nextRoundHints          :: IORef [Text]        -- 上一发 integration 留给下一发 decision 的 actionable hint
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
    rRef <- newIORef (-1)
    aRef <- newIORef 0
    -- 从 oracle.yaml.next_round_hints 字段恢复 IORef (跨 hsbb step 进程持久)
    hRef <- newIORef (readNextRoundHintsField initialOracle)
    pure Oracle { oraclePath = oP, probesPath = pP
                , oracleState = oRef, probesCount = pRef
                , currentRound = rRef
                , lastIntegrationAttempts = aRef
                , nextRoundHints = hRef }


setCurrentRound :: Oracle -> Int -> IO ()
setCurrentRound o n = atomicModifyIORef' (currentRound o) (\_ -> (n, ()))


setLastIntegrationAttempts :: Oracle -> Int -> IO ()
setLastIntegrationAttempts o n = atomicModifyIORef' (lastIntegrationAttempts o) (\_ -> (n, ()))


-- integration phase 开始时清空 hint buffer; integration writeSlot 时累加。
-- 持久化到 oracle.yaml `next_round_hints` 字段 (hsbb step 是 one-shot 进程, IORef 不能跨进程)。
resetNextRoundHints :: Oracle -> IO ()
resetNextRoundHints o = do
    atomicModifyIORef' (nextRoundHints o) (\_ -> ([], ()))
    atomicModifyIORef' (oracleState o) $ \v ->
        (setNextRoundHintsField v [], ())
    persistOracle o


readNextRoundHints :: Oracle -> IO [Text]
readNextRoundHints o = readIORef (nextRoundHints o)


-- 把 hints 列表写入 oracleState 的 next_round_hints 字段
setNextRoundHintsField :: A.Value -> [Text] -> A.Value
setNextRoundHintsField (A.Object root) hs =
    A.Object $ KM.insert "next_round_hints" (A.Array $ V.fromList (map A.String hs)) root
setNextRoundHintsField v _ = v


-- 从 oracleState 读 next_round_hints 字段 (供 initOracle 恢复 IORef)
readNextRoundHintsField :: A.Value -> [Text]
readNextRoundHintsField (A.Object root) =
    case KM.lookup "next_round_hints" root of
        Just (A.Array a) -> [t | A.String t <- V.toList a]
        _                -> []
readNextRoundHintsField _ = []


persistOracle :: Oracle -> IO ()
persistOracle o = do
    cur <- readIORef (oracleState o)
    BS.writeFile (oraclePath o) (Y.encode cur)


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
            let title    = textField so "title" "(无标题)"
                content_ = textField so "content" ""
                conf     = numberField so "confidence" 0
                inconN   = truncate (numberField so "inconclusive_count" 0) :: Int
                tag      = if inconN >= 2
                           then "[INCONCLUSIVE ×" <> T.pack (show inconN) <> "]"
                           else "[" <> formatConf conf <> "]"
                header   = "- " <> padded <> " " <> tag <> "  " <> title
                -- content 也渲染给 decision LLM (init 的文档推断 + integration 的实测 fact)
                -- 缩进对齐 + 截断 1200 字符避免单 slot 占满 prompt
                contentLines =
                    if T.null (T.strip content_)
                        then []
                        else map ("    " <>) (T.lines (T.take 1200 content_))
            in header : contentLines
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


-- Render 本轮动态 / 未触槽 / 累计 writeSlot 次数。
-- `currentRoundN`: harness 即将进入的 round 号，用于判定哪一槽是"上轮"升级的。
dynamicSection :: Oracle -> Int -> IO Text
dynamicSection o currentRoundN = do
    val <- readIORef (oracleState o)
    attempts <- readIORef (lastIntegrationAttempts o)
    case val of
        A.Object root ->
            let slotsMap = case KM.lookup "slots" root of
                              Just (A.Object s) -> s
                              _                 -> KM.empty
                slotInfo = [ extractInfo sid slotsMap | sid <- universalSlots ]
                lastRoundUpdate = currentRoundN - 1
                upgraded = [ (sid, d, lpc, conf)
                           | (sid, _wc, lr, d, lpc, conf) <- slotInfo
                           , lr == lastRoundUpdate, lr > 0 ]
                untouched = [ sid | (sid, wc, _lr, _d, _lpc, _conf) <- slotInfo, wc == 0 ]
                counts = [ (sid, wc) | (sid, wc, _lr, _d, _lpc, _conf) <- slotInfo ]
                upgradeRender =
                    case upgraded of
                        [] -> [ "- 上轮升级: (无)" ]
                        xs -> [ "- 上轮升级: " <> sid
                                <> "  (你给 " <> T.pack (showFixed3 lpc)
                                <> ", decay 后实际 +" <> T.pack (showDelta d)
                                <> " → 当前 " <> T.pack (showFixed3 conf) <> ")"
                              | (sid, d, lpc, conf) <- xs ]
                attemptRender =
                    if attempts > 1
                    then [ "- 上轮 writeSlot 尝试: " <> T.pack (show attempts)
                           <> " 次, 实际生效 1 个 (后续被 harness 静默丢弃, 浪费 "
                           <> T.pack (show (attempts - 1)) <> " 次 tool call)" ]
                    else if attempts == 1
                         then [ "- 上轮 writeSlot 尝试: 1 次, 生效" ]
                         else [ "- 上轮 writeSlot 尝试: 0 次 (上轮整理未发 writeSlot)" ]
                lines_ =
                    [ "## 本轮动态" ]
                    ++ upgradeRender
                    ++ attemptRender
                    ++ (case untouched of
                          [] -> [ "- 未触槽: (无)" ]
                          xs -> [ "- 未触槽: " <> T.intercalate ", " xs ])
                    ++ [ "- 各槽累计 writeSlot 次数:" ]
                    ++ [ "    " <> T.intercalate "  "
                          [ sid <> ":" <> T.pack (show wc) | (sid, wc) <- counts ] ]
            in pure (T.unlines lines_)
        _ -> pure "## 本轮动态\n(empty)\n"
  where
    extractInfo sid slotsMap =
        case KM.lookup (Key.fromText sid) slotsMap of
            Just (A.Object so) ->
                let wc  = case KM.lookup "write_count" so of
                            Just (A.Number n) -> truncate n :: Int
                            _                 -> 0
                    lr  = case KM.lookup "last_round" so of
                            Just (A.Number n) -> truncate n :: Int
                            _                 -> 0
                    ld  = case KM.lookup "last_delta" so of
                            Just (A.Number n) -> realToFrac n :: Double
                            _                 -> 0
                    lpc = case KM.lookup "last_proposed_conf" so of
                            Just (A.Number n) -> realToFrac n :: Double
                            _                 -> 0
                    cf  = case KM.lookup "confidence" so of
                            Just (A.Number n) -> realToFrac n :: Double
                            _                 -> 0
                in (sid, wc, lr, ld, lpc, cf)
            _ -> (sid, 0, 0, 0, 0, 0)


showFixed3 :: Double -> String
showFixed3 x =
    let r = round (x * 1000) :: Int
        s = show (abs r)
        padded = case s of
                    [a]    -> "00" ++ [a]
                    [a, b] -> "0" ++ [a, b]
                    cs     -> cs
        (intPart, decPart) = splitAt (length padded - 3) padded
        intStr = if null intPart then "0" else intPart
    in intStr ++ "." ++ decPart


showDelta :: Double -> String
showDelta d =
    let r = round (d * 1000) :: Int
        s = show (abs r)
        padded = case s of
                    [a]       -> "00" ++ [a]
                    [a, b]    -> "0" ++ [a, b]
                    cs        -> cs
        (intPart, decPart) = splitAt (length padded - 3) padded
        intStr = if null intPart then "0" else intPart
    in intStr ++ "." ++ decPart


-- Append a probe record (as JSON line) to probes.jsonl.
appendProbe :: Oracle -> A.Value -> IO ()
appendProbe o v = do
    let line = BL.toStrict (A.encode v) `BS.append` "\n"
    BS.appendFile (probesPath o) line
    atomicModifyIORef' (probesCount o) (\n -> (n + 1, ()))


countProbes :: Oracle -> IO Int
countProbes o = readIORef (probesCount o)


-- 只算 round > 0 的 probe (round = 0 是 init 阶段机械执行的 --help / --version 等).
countDecisionProbes :: Oracle -> IO Int
countDecisionProbes o = do
    txt <- (try (TIO.readFile (probesPath o)) :: IO (Either SomeException Text))
              >>= either (const (pure "")) pure
    pure $ length $ filter isDecisionLine $ T.lines txt
  where
    isDecisionLine l = case A.decodeStrict (TE.encodeUtf8 l) of
        Just (A.Object obj) -> case KM.lookup "round" obj of
            Just (A.Number n) -> (truncate n :: Int) > 0
            _                 -> False
        _                   -> False


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


-- 返回当前 probes.jsonl 里的"参考文档" probe (--help / --version 类)。
-- 按优先级 (help: --help > -h > -?; version: --version > -v > -V) 每类只挑 1 个胜出者。
-- 有效判定: max(stdout, stderr) >= 200 字节 AND 内容含 usage / option / flag / version 等关键词。
-- 返回 [(probe_id, cmd, 内容)], 最多 2 条 (help 类 + version 类各 1)。
referenceProbes :: Oracle -> IO [(Text, Text, Text)]
referenceProbes o = do
    ex <- doesFileExist (probesPath o)
    if not ex then pure []
    else do
        contents <- TIO.readFile (probesPath o)
        let ls = filter (not . T.null) (T.lines contents)
            records = [ (pid, cmd, stdout, stderr)
                      | line <- ls
                      , Right (A.Object obj) <- [A.eitherDecodeStrict (TE.encodeUtf8 line)]
                      , Just (A.String pid)    <- [KM.lookup "id" obj]
                      , Just (A.String cmd)    <- [KM.lookup "cmd" obj]
                      , Just (A.String stdout) <- [KM.lookup "stdout" obj]
                      , Just (A.String stderr) <- [KM.lookup "stderr" obj]
                      ]
            helpRef = pickByPriority records ["--help", "-h", "-?"] isHelpContent
            verRef  = pickByPriority records ["--version", "-v", "-V"] isVersionContent
        pure (catMaybes [helpRef, verRef])
  where
    catMaybes = foldr (\m acc -> case m of Just x -> x : acc; Nothing -> acc) []

    -- 经验法则源自 30 道 PB 任务实测 (2026-06-22):
    --   - 29/30 canonical 是 --help; 1 真 blocker (容器没起来)
    --   - 通道分布: 20 stdout / 9 stderr -> 必须 concat 两边再校验
    --   - exit code 70% 是 0, 30% 是 1/2 -> 不按 exit 过滤
    --   - 长度 56B (elfcat) ~ 几 KB (ripgrep) -> 阈值降到 50B
    --   - "usage:" 命中 23/27, "usage of" (Go std) 命中 2/27, flag-line 缩进列表 命中 29/30
    pickByPriority records flags validate =
        let cands = [ (pid, cmd, displayContent)
                    | flag <- flags
                    , (pid, cmd, stdout, stderr) <- records
                    , flagMatches cmd flag
                    , let combined = stdout <> "\n" <> stderr
                    , T.length combined >= 50
                    , validate combined
                    , let displayContent = pickContent stdout stderr
                    ]
        in case cands of
            (x : _) -> Just x
            []      -> Nothing

    pickContent stdout stderr =
        if T.length stdout >= T.length stderr then stdout else stderr

    flagMatches cmd flag =
        -- 简单匹配: cmd 含 flag 子串, 但排除 "--help-all" 类长前缀冒充
        T.isInfixOf (" " <> flag) cmd

    isHelpContent t =
        let lower = T.toLower t
            hasKeyword = any (`T.isInfixOf` lower)
                [ "usage:"       -- GNU canonical
                , "usage of"     -- Go std flag (Usage of /path/to/binary:)
                , "options:"
                , "flags:"
                , "arguments:"
                , "command:"
                , "summary:"     -- BSD/POSIX (entr 等)
                , "synopsis:"    -- man-style
                , "commands:"
                , "subcommands:"
                , "examples:"
                ]
            -- 缩进 flag 列表: "\n  -" / "\n    -" / "\n\t-" 是 29/30 的兜底信号
            hasFlagLine = any (`T.isInfixOf` t)
                [ "\n  -"
                , "\n    -"
                , "\n\t-"
                ]
        in hasKeyword || hasFlagLine

    isVersionContent t =
        let lower = T.toLower t
        in any (`T.isInfixOf` lower) ["version", " v.", "build", "rev "]


-- 返回去重后的 cmd 列表 (保留首次出现顺序)。用于 decision prompt 防 LLM 重复探。
uniqueProbeCommands :: Oracle -> IO [Text]
uniqueProbeCommands o = do
    ex <- doesFileExist (probesPath o)
    if not ex then pure []
    else do
        contents <- TIO.readFile (probesPath o)
        let ls = filter (not . T.null) (T.lines contents)
            cmds = [ c
                   | line <- ls
                   , Right (A.Object obj) <- [A.eitherDecodeStrict (TE.encodeUtf8 line)]
                   , Just (A.String c) <- [KM.lookup "cmd" obj]
                   ]
        pure (dedupKeepOrder cmds)
  where
    dedupKeepOrder = goD []
    goD seen [] = reverse seen
    goD seen (x : xs)
        | x `elem` seen = goD seen xs
        | otherwise     = goD (x : seen) xs


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
--
-- Confidence 应用衰减公式 (LLM 不知道):
--   obtained = min(LLM 给的值, 0.2)
--   delta    = obtained * (1 - current)
--   new      = current + delta
-- 这样 LLM 即便每次都给 1.0, 实际累加也是逐步收敛的。
writeSlotRaw :: Oracle -> Text -> KM.KeyMap A.Value -> UTCTime -> IO ()
writeSlotRaw o sid args now = do
    let isUniversal = sid `elem` universalSlots
    currentState <- readIORef (oracleState o)
    roundN <- readIORef (currentRound o)
    let isInitPhase    = roundN < 0
        currentConf    = getCurrentConfidence currentState sid isUniversal
        currentCount   = getCurrentWriteCount currentState sid isUniversal
        currentIncon   = getCurrentInconclusiveCount currentState sid isUniversal
        llmValue       = case KM.lookup "confidence" args of
                           Just (A.Number n) -> realToFrac n :: Double
                           _                 -> 0
        isInconclusive = case KM.lookup "inconclusive" args of
                           Just (A.Bool b) -> b
                           _               -> False
        -- inconclusive=true 时 confidence 不动, 只累加 inconclusive_count
        newConf      = if isInconclusive then currentConf
                       else applyConfidenceDecay currentConf llmValue
        delta        = newConf - currentConf
        newIncon     = if isInconclusive then currentIncon + 1 else currentIncon
        -- init 阶段不算"实际探测", write_count 不递增, last_round 保持 -1 标记
        newCount     = if isInitPhase then currentCount else currentCount + 1
        argsExtended = KM.insert "confidence"           (A.Number (realToFrac newConf))
                     $ KM.insert "write_count"          (A.Number (fromIntegral newCount))
                     $ KM.insert "inconclusive_count"   (A.Number (fromIntegral newIncon))
                     $ KM.insert "last_round"           (A.Number (fromIntegral roundN))
                     $ KM.insert "last_delta"           (A.Number (realToFrac delta))
                     $ KM.insert "last_proposed_conf"   (A.Number (realToFrac llmValue))
                       args
    let rec_ = makeSlotRecord argsExtended now
    if isUniversal
        then atomicModifyIORef' (oracleState o) $ \v ->
                (updateUniversalSlot v sid rec_, ())
        else atomicModifyIORef' (oracleState o) $ \v ->
                (updateOtherSlot v sid rec_, ())
    cur <- readIORef (oracleState o)
    BS.writeFile (oraclePath o) (Y.encode cur)
    -- 抽 hint_for_next_round 同步到 IORef + oracle.yaml.next_round_hints 字段
    -- (hsbb step 是 one-shot 进程, 必须持久才能跨 step 传给下一发 decision)
    case KM.lookup "hint_for_next_round" args of
        Just (A.String h) | not (T.null (T.strip h)) -> do
            newHints <- atomicModifyIORef' (nextRoundHints o) $ \hs ->
                let hs' = hs ++ [T.strip h] in (hs', hs')
            atomicModifyIORef' (oracleState o) $ \v ->
                (setNextRoundHintsField v newHints, ())
            persistOracle o
        _ -> pure ()


getCurrentWriteCount :: A.Value -> Text -> Bool -> Int
getCurrentWriteCount (A.Object root) sid True =
    case KM.lookup "slots" root of
        Just (A.Object slotsMap) ->
            case KM.lookup (Key.fromText sid) slotsMap of
                Just (A.Object so) ->
                    case KM.lookup "write_count" so of
                        Just (A.Number n) -> truncate n
                        _                 -> 0
                _ -> 0
        _ -> 0
getCurrentWriteCount _ _ _ = 0


getCurrentInconclusiveCount :: A.Value -> Text -> Bool -> Int
getCurrentInconclusiveCount (A.Object root) sid True =
    case KM.lookup "slots" root of
        Just (A.Object slotsMap) ->
            case KM.lookup (Key.fromText sid) slotsMap of
                Just (A.Object so) ->
                    case KM.lookup "inconclusive_count" so of
                        Just (A.Number n) -> truncate n
                        _                 -> 0
                _ -> 0
        _ -> 0
getCurrentInconclusiveCount (A.Object root) sid False =
    case KM.lookup "other" root of
        Just (A.Array a) ->
            case [ truncate n :: Int
                 | A.Object o <- V.toList a
                 , KM.lookup "id" o == Just (A.String sid)
                 , Just (A.Number n) <- [KM.lookup "inconclusive_count" o]
                 ] of
                (x:_) -> x
                _     -> 0
        _ -> 0
getCurrentInconclusiveCount _ _ _ = 0


-- 衰减公式：每次 probe 单次上升受 0.2 上限 + (1-current) 衰减。
applyConfidenceDecay :: Double -> Double -> Double
applyConfidenceDecay current llmValue =
    let obtained = min 0.2 llmValue
        delta    = obtained * (1 - current)
    in current + delta


-- 读 slot 现有 confidence (universal 走 slots dict, other 走 array)。
getCurrentConfidence :: A.Value -> Text -> Bool -> Double
getCurrentConfidence (A.Object root) sid True =
    case KM.lookup "slots" root of
        Just (A.Object slotsMap) ->
            case KM.lookup (Key.fromText sid) slotsMap of
                Just (A.Object so) ->
                    case KM.lookup "confidence" so of
                        Just (A.Number n) -> realToFrac n
                        _                 -> 0
                _ -> 0
        _ -> 0
getCurrentConfidence (A.Object root) sid False =
    case KM.lookup "other" root of
        Just (A.Array a) ->
            case [ realToFrac n
                 | A.Object o <- V.toList a
                 , KM.lookup "id" o == Just (A.String sid)
                 , Just (A.Number n) <- [KM.lookup "confidence" o]
                 ] of
                (c : _) -> c
                _       -> 0
        _ -> 0
getCurrentConfidence _ _ _ = 0


makeSlotRecord :: KM.KeyMap A.Value -> UTCTime -> A.Value
makeSlotRecord args now = A.Object $ KM.fromList $
    [ ("title",              pickField "title" args (A.String ""))
    , ("confidence",         pickField "confidence" args (A.Number 0))
    , ("content",            pickField "content" args (A.String ""))
    , ("evidence",           pickField "evidence" args (A.Array V.empty))
    , ("notes",              pickField "notes" args (A.String ""))
    , ("write_count",        pickField "write_count" args (A.Number 0))
    , ("last_round",         pickField "last_round"  args (A.Number 0))
    , ("last_delta",         pickField "last_delta"  args (A.Number 0))
    , ("last_proposed_conf", pickField "last_proposed_conf" args (A.Number 0))
    , ("updated_at",         A.String (T.pack (show now)))
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
