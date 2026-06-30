{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Main ReAct loop.
-- Each round: decision prompt → action → (if explore) execute + integration prompt.
-- Convergence: wall-clock > 20 min OR LLM emits stop action.
module Blackbox.Loop
    ( runLoop
    , runStep
    , runShellInDir
    , probeToJson
    , mkProbeId
    , PromptOverrides (..)
    , emptyOverrides
    ) where

import           Control.Exception       (SomeException, try)
import           Control.Monad           (when)
import           Data.Char               (isSpace)
import           Data.IORef              (atomicModifyIORef', newIORef,
                                          readIORef)
import qualified Data.Aeson              as A
import qualified Data.Aeson.Key          as Key
import qualified Data.Aeson.KeyMap       as KM
import qualified Data.ByteString.Lazy    as BL
import           Data.List               (find)
import qualified Data.Text               as T
import           Data.Text               (Text)
import qualified Data.Text.Encoding      as TE
import qualified Data.Text.IO            as TIO
import           Data.Time               (UTCTime, diffUTCTime, getCurrentTime)
import           System.Directory        (doesFileExist)
import           System.Exit             (ExitCode (..))
import           System.FilePath         ((</>))
import           System.Process          (CreateProcess (..), shell,
                                          readCreateProcessWithExitCode)
import           System.Timeout          (timeout)

import           Blackbox.Deepseek       (Message (..), runChat,
                                          writeSlotTool,
                                          lookupProbeTool, ChatResult (..))
import           Blackbox.Oracle         (Oracle, summary, dynamicSection,
                                          fullSummary,
                                          appendProbe, countProbes,
                                          countDecisionProbes,
                                          dispatchTool, lastProbeRecord,
                                          setCurrentRound,
                                          setLastIntegrationAttempts,
                                          resetNextRoundHints,
                                         readNextRoundHints,
                                         uniqueProbeCommands,
                                         probeHistorySummary,
                                         slotConfidences,
                                         referenceProbes)
import           Blackbox.Trace          (TraceHandle, appendEvent,
                                          phaseStart, phaseEnd)
import           Blackbox.Types          (Action (..), LastResult (..),
                                          ProbeOutcome (..), makeLastResult,
                                          parseAction, universalSlots)
import           Data.Maybe              (fromMaybe)


-- ---------------------------------------------------------------
-- PromptOverrides: 运行时可注入的 system prompt (用于无重编译跑多变体实验)
-- 4 个 system prompt 字段, 任一为 Nothing 时回退到内置默认.
-- ---------------------------------------------------------------

data PromptOverrides = PromptOverrides
    { poDecisionSystem    :: Maybe Text  -- 决策阶段
    , poIntegrationSystem :: Maybe Text  -- 整理阶段
    , poGateSystem        :: Maybe Text  -- gate 阶段
    , poInitSystem        :: Maybe Text  -- init 阶段
    }

emptyOverrides :: PromptOverrides
emptyOverrides = PromptOverrides Nothing Nothing Nothing Nothing


-- Wall-clock budget in seconds.
budgetSeconds :: Double
budgetSeconds = 20 * 60


-- ---------------------------------------------------------------
-- Single-round step (for parallel observable execution)
-- ---------------------------------------------------------------

-- runStep runs exactly one round (decision + optional explore + optional integration)
-- then exits. Round number derived from probes.jsonl; last_result reconstructed from
-- the latest probe if any.
runStep :: Oracle -> Text -> Text -> FilePath -> TraceHandle -> PromptOverrides -> IO ()
runStep oracle apiKey model taskDir trace overrides = do
    -- 用 countDecisionProbes 而不是 countProbes: init 阶段的机械 probe (round=0) 不计入 round 编号
    nDec <- countDecisionProbes oracle
    let roundN = nDec + 1
    lastResult <- reconstructLastResult oracle
    putStrLn $ "[step] round " ++ show roundN
                ++ (case lastResult of
                      Just lr -> " (last_result probe=" ++ T.unpack (lrProbeId lr) ++ ")"
                      Nothing -> " (no prior probe)")

    let roundTag = T.pack ("round_" ++ pad3 roundN)
        pad3 k = let s = show k in replicate (3 - length s) '0' ++ s

    phaseStart trace (roundTag <> "_decision")
    putStrLn "[step] decision phase..."
    action <- decisionPhase oracle apiKey model trace roundN lastResult overrides
    phaseEnd trace (roundTag <> "_decision")

    case action of
        Nothing -> putStrLn "[step] no valid action; exit."
        Just (ActStop reason) -> putStrLn ("[step] LLM stop: " ++ T.unpack reason)
        Just act -> do
            putStrLn $ "[step] action: " ++ describeAction act
            appendEvent trace "action_chosen" (A.object
                [ "round" A..= roundN
                , "action" A..= actionJson act
                ])
            outcome <- executeAction taskDir act
            case outcome of
                Nothing -> putStrLn "[step] action returned no outcome"
                Just po -> do
                    pid <- mkProbeId roundN
                    appendProbe oracle (probeToJsonWithAction pid roundN act po)
                    appendEvent trace "probe_appended" (A.object
                        [ "round" A..= roundN
                        , "probe_id" A..= pid
                        , "exit" A..= poExit po
                        , "stdout_bytes" A..= T.length (poStdout po)
                        , "stderr_bytes" A..= T.length (poStderr po)
                        ])
                    let lr = makeLastResult pid po
                    phaseStart trace (roundTag <> "_integration")
                    putStrLn "[step] integration phase..."
                    integrationPhase oracle apiKey model trace roundN act lr overrides
                    phaseEnd trace (roundTag <> "_integration")
                    phaseStart trace (roundTag <> "_gate")
                    putStrLn "[step] gate phase..."
                    cont <- gatePhase oracle apiKey model trace roundN overrides
                    phaseEnd trace (roundTag <> "_gate")
                    if cont
                        then putStrLn "[step] gate 判 继续 (本步退出, 下次再调 step)"
                        else do
                            appendEvent trace "convergence" (A.object
                                [ "reason" A..= ("gate_stop" :: Text) ])
                            putStrLn "[step] gate 判 收敛"
                    putStrLn "[step] done."


-- Rebuild a LastResult from the last entry in probes.jsonl (if any).
reconstructLastResult :: Oracle -> IO (Maybe LastResult)
reconstructLastResult o = do
    rec_ <- lastProbeRecord o
    case rec_ of
        Just (A.Object obj) -> do
            let getStr k = case KM.lookup (Key.fromText k) obj of
                              Just (A.String s) -> s
                              _                 -> ""
                getInt k = case KM.lookup (Key.fromText k) obj of
                              Just (A.Number n) -> truncate n :: Int
                              _                 -> 0
                pid       = getStr "id"
                cmd_      = getStr "cmd"
                exitC     = getInt "exit"
                stdoutT   = getStr "stdout"
                stderrT   = getStr "stderr"
                soBytes   = getInt "stdout_bytes"
                seBytes   = getInt "stderr_bytes"
            pure $ Just LastResult
                { lrProbeId     = pid
                , lrCmd         = cmd_
                , lrExit        = exitC
                , lrStdoutSlice = T.take 2048 stdoutT
                , lrStderrSlice = T.take 1024 stderrT
                , lrStdoutBytes = if soBytes > 0 then soBytes else T.length stdoutT
                , lrStderrBytes = if seBytes > 0 then seBytes else T.length stderrT
                }
        _ -> pure Nothing


-- ---------------------------------------------------------------
-- Original full loop
-- ---------------------------------------------------------------

runLoop :: Oracle -> Text -> Text -> FilePath -> TraceHandle -> PromptOverrides -> IO ()
runLoop oracle apiKey model taskDir trace overrides = do
    startTime <- getCurrentTime
    phaseStart trace "loop"
    loop startTime 1 Nothing
    phaseEnd trace "loop"
  where
    loop :: UTCTime -> Int -> Maybe LastResult -> IO ()
    loop startT roundN lastResult = do
        elapsed <- elapsedSec startT
        if elapsed >= budgetSeconds
            then do
                putStrLn $ "[round " ++ show roundN ++ "] wall-clock 触发收敛 (" ++ show (round elapsed :: Int) ++ "s)"
                appendEvent trace "convergence" (A.object
                    [ "reason" A..= ("wall_clock" :: Text)
                    , "elapsed_sec" A..= (round elapsed :: Int)
                    ])
                pure ()
            else do
                let roundTag = T.pack ("round_" ++ pad3 roundN)
                    pad3 k = let s = show k in replicate (3 - length s) '0' ++ s
                putStrLn $ "[round " ++ show roundN ++ "] decision phase..."
                phaseStart trace (roundTag <> "_decision")
                action <- decisionPhase oracle apiKey model trace roundN lastResult overrides
                phaseEnd trace (roundTag <> "_decision")
                case action of
                    Nothing -> do
                        putStrLn $ "[round " ++ show roundN ++ "] no valid action, stopping."
                        pure ()
                    Just (ActStop reason) -> do
                        -- 决策阶段不该出 stop, 收到当 warning 处理, 继续往下走 Gate 来收敛
                        putStrLn $ "[round " ++ show roundN ++ "] WARN: decision returned stop ("
                                  ++ T.unpack reason ++ "), ignoring; gate will decide."
                        appendEvent trace "warn" (A.object
                            [ "where" A..= ("decision" :: Text)
                            , "msg"   A..= ("decision returned stop, ignored" :: Text)
                            , "why"   A..= reason
                            ])
                        loop startT (roundN + 1) lastResult
                    Just act -> do
                        putStrLn $ "[round " ++ show roundN ++ "] action: " ++ describeAction act
                        outcome <- executeAction taskDir act
                        case outcome of
                            Nothing -> loop startT (roundN + 1) lastResult
                            Just po -> do
                                pid <- mkProbeId roundN
                                let probeJson = probeToJsonWithAction pid roundN act po
                                appendProbe oracle probeJson
                                let lr = makeLastResult pid po
                                phaseStart trace (roundTag <> "_integration")
                                putStrLn $ "[round " ++ show roundN ++ "] integration phase..."
                                integrationPhase oracle apiKey model trace roundN act lr overrides
                                phaseEnd trace (roundTag <> "_integration")
                                -- Gate 判断收敛
                                phaseStart trace (roundTag <> "_gate")
                                putStrLn $ "[round " ++ show roundN ++ "] gate phase..."
                                cont <- gatePhase oracle apiKey model trace roundN overrides
                                phaseEnd trace (roundTag <> "_gate")
                                if cont
                                    then loop startT (roundN + 1) (Just lr)
                                    else do
                                        appendEvent trace "convergence" (A.object
                                            [ "reason" A..= ("gate_stop" :: Text) ])
                                        putStrLn $ "[round " ++ show roundN ++ "] gate 判 收敛"
                                        pure ()


elapsedSec :: UTCTime -> IO Double
elapsedSec startT = do
    now <- getCurrentTime
    pure (realToFrac (diffUTCTime now startT))


mkProbeId :: Int -> IO Text
mkProbeId n = pure (T.pack ("probe_" ++ pad3 n))
  where
    pad3 k = let s = show k in replicate (3 - length s) '0' ++ s


-- ---------------------------------------------------------------
-- Decision phase
-- ---------------------------------------------------------------

decisionPhase :: Oracle -> Text -> Text -> TraceHandle -> Int -> Maybe LastResult -> PromptOverrides -> IO (Maybe Action)
decisionPhase oracle apiKey model trace roundN lastResult overrides = do
    summaryTxt <- summary oracle
    dynamicTxt <- dynamicSection oracle roundN
    nProbes <- countProbes oracle
    pastCmds <- uniqueProbeCommands oracle
    history <- probeHistorySummary oracle
    refs <- referenceProbes oracle
    hints <- readNextRoundHints oracle
    let lrSection = maybe "(无)\n" renderLastResult lastResult
        hintsSection = if null hints
                       then ""
                       else "\n## 上发 integration 给本发的 hint (actionable, 一次性)\n"
                         <> T.unlines [ "- " <> h | h <- hints ]
                         <> "\n"
        probeStats = "\n## 探针计数\n本任务已发 probe 数: " <> T.pack (show nProbes)
                  <> "\n历史参考: 同类案例平均 ~70 发, 范围 10-200, 具体探多少自行判断。\n"
        refsSection = if null refs
                      then ""
                      else "\n## 参考文档 (常驻)\n"
                        <> T.unlines
                           [ "### " <> pid <> "\n$ " <> cmd <> "\n```\n"
                             <> T.take 8192 content <> "\n```"
                           | (pid, cmd, content) <- refs ]
        pastSection = if null pastCmds
                     then ""
                     else "\n## 已执行过的 probe (去重)\n"
                       <> T.unlines [ "- " <> c | c <- pastCmds ]
        historySection = if null history
                         then ""
                         else "\n## 探索历史 (最近 " <> T.pack (show (length history)) <> " 发, 含结果浓缩)\n"
                           <> T.unlines (map renderHistoryEntry history)
        sysPrompt = fromMaybe decisionSystemPrompt (poDecisionSystem overrides)
        userPrompt = summaryTxt <> "\n" <> dynamicTxt <> refsSection <> probeStats <> pastSection
                  <> historySection
                  <> "\n## 上轮回灌 (last_result)\n" <> lrSection
                  <> hintsSection
                  <> "\n## 你的任务\n基于以上, 决定下一步 action, 直接输出 action JSON。"
        msgs = [ SystemMsg sysPrompt, UserMsg (sanitizeDecisionPrompt userPrompt) ]

    result <- runChat apiKey model [] {- 决策阶段不暴露任何 tool -}
                msgs (dispatchTool oracle) (appendEvent trace) 2

    let firstAction = parseActionFromText (crContent result)
    -- 硬拦: 若 LLM 出 verbatim 已执行 cmd 且 why 没声明「重复 probe_xxx」, retry 一次喂 feedback.
    case firstAction of
        -- 拦截: probe action 必须使用 harness 提供的 `app` 占位符。
        -- harness 会在执行前把 shell token `app` 规范化成 ./probe；
        -- LLM 不再直接拼二进制名，避免 ./propr / ./prob 之类 typo。
        Just (ActProbe cmd why)
            | not (hasAppInvocation cmd) -> do
                putStrLn $ "[decision] WARN: cmd missing app token: " ++ T.unpack cmd
                appendEvent trace "decision_no_probe_rejected" (A.object
                    [ "cmd"        A..= cmd
                    , "why"        A..= why
                    ])
                let feedback = "harness 拒绝: probe action 必须使用 `app` 作为目标程序占位符, 不要写目标程序的真实路径或名字。示例: `echo /tmp/x | app -n -z echo ok`。"
                    retryMsgs = msgs ++ [ AssistantMsg (Just (crContent result)) []
                                        , UserMsg feedback ]
                retry <- runChat apiKey model [] retryMsgs
                            (dispatchTool oracle) (appendEvent trace) 2
                pure (parseActionFromText (crContent retry))
        Just (ActProbe cmd why)
            | cmd `elem` pastCmds && not (isExplicitRepeat why) -> do
                putStrLn $ "[decision] WARN: LLM emitted duplicate cmd: " ++ T.unpack cmd
                appendEvent trace "decision_duplicate_rejected" (A.object
                    [ "cmd"        A..= cmd
                    , "why"        A..= why
                    , "retry_with" A..= ("feedback" :: Text)
                    ])
                let feedback = "harness 拒绝: cmd `" <> cmd
                            <> "` 在「已执行过的 probe」段里已 verbatim 出现过, 重发等于浪费一发。"
                            <> "\n请换角度探。若确认要重复 (验证非确定性等), 在 why 字段写「重复 probe_xxx, 因为...」即可绕过本拦截。"
                    retryMsgs = msgs ++ [ AssistantMsg (Just (crContent result)) []
                                        , UserMsg feedback ]
                retry <- runChat apiKey model [] retryMsgs
                            (dispatchTool oracle) (appendEvent trace) 2
                pure (parseActionFromText (crContent retry))
        _ -> pure firstAction
  where
    isExplicitRepeat why = "重复 probe_" `T.isInfixOf` why


sanitizeDecisionPrompt :: Text -> Text
sanitizeDecisionPrompt =
    T.replace "./probe" "app"


parseActionFromText :: Text -> Maybe Action
parseActionFromText t =
    -- LLM often wraps JSON in prose ("Sure, here's...:\n\n{...}\nDone.")
    -- Extract substring between first { and matching closing }
    case extractJsonObject t of
        Nothing  -> Nothing
        Just obj -> case A.eitherDecodeStrict (TE.encodeUtf8 obj) of
            Right v -> parseAction v
            Left _  -> Nothing


-- Find the first balanced {...} object in the text.
extractJsonObject :: Text -> Maybe Text
extractJsonObject t =
    case T.findIndex (== '{') t of
        Nothing  -> Nothing
        Just i   ->
            let rest = T.drop i t
            in case findMatchingBrace 0 0 (T.unpack rest) of
                Nothing  -> Nothing
                Just end -> Just (T.take (end + 1) rest)
  where
    -- Walk chars, track depth, return index of closing brace.
    findMatchingBrace :: Int -> Int -> String -> Maybe Int
    findMatchingBrace _   _ []         = Nothing
    findMatchingBrace pos d ('{' : cs) = findMatchingBrace (pos + 1) (d + 1) cs
    findMatchingBrace pos 1 ('}' : _)  = Just pos
    findMatchingBrace pos d ('}' : cs) = findMatchingBrace (pos + 1) (d - 1) cs
    findMatchingBrace pos d (_ : cs)   = findMatchingBrace (pos + 1) d cs


renderHistoryEntry :: (Int, Text, Int, Text, Text, Int, Int, Text, [Text]) -> Text
renderHistoryEntry (rnd, cmd_, exit_, soSlice, seSlice, soBytes, seBytes, why, targets) =
    "- [r" <> T.pack (show rnd) <> "] " <> cmd_ <> " -> exit " <> T.pack (show exit_)
    <> targetPart
    <> whyPart
    <> " | stdout(" <> T.pack (show soBytes) <> "B): " <> flatOrEmpty soSlice
    <> " | stderr(" <> T.pack (show seBytes) <> "B): " <> flatOrEmpty seSlice
  where
    flatOrEmpty t = let s = T.strip t
                    in if T.null s then "(empty)" else T.replace "\n" " " s
    targetPart =
        if null targets
        then ""
        else " | targets: " <> T.intercalate "," targets
    whyPart =
        let w = T.strip why
        in if T.null w
           then ""
           else " | why: " <> T.take 160 (T.replace "\n" " " w)


-- ---------------------------------------------------------------
-- Integration phase
-- ---------------------------------------------------------------

integrationPhase :: Oracle -> Text -> Text -> TraceHandle -> Int -> Action -> LastResult -> PromptOverrides -> IO ()
integrationPhase oracle apiKey model trace roundN lastAction lr overrides = do
    setCurrentRound oracle roundN
    -- 清空上发 integration 给本发的 hint (本发 integration 会重新累加给下一发)
    resetNextRoundHints oracle
    summaryTxt <- fullSummary oracle
    let actJson = actionJson lastAction
        userPrompt = summaryTxt <> "\n\n## 上轮 action\n" <> actJson
                  <> "\n\n## 上轮回灌 (last_result)\n" <> renderLastResult lr
                  <> "\n\n## 你的任务\n" <> integrationTask
        msgs = [ SystemMsg (fromMaybe integrationSystemPrompt (poIntegrationSystem overrides))
              , UserMsg userPrompt ]

    -- 机械限制: 本次 integration 最多写 3 个槽 (高密度 probe 的多槽事实不浪费)
    writeSlotCounter <- newIORef (0 :: Int)
    let maxSlotsPerProbe = 3
        wrappedHandler name args =
            if name == "writeSlot"
                then do
                    n <- atomicModifyIORef' writeSlotCounter (\c -> (c + 1, c))
                    if n < maxSlotsPerProbe
                        then dispatchTool oracle name args
                        else pure "rejected: 本次 integration 已写 3 个槽, 后续 writeSlot 不生效"
                else dispatchTool oracle name args

    _ <- runChat apiKey model [writeSlotTool]
            msgs wrappedHandler (appendEvent trace) 4

    -- 记录本轮 LLM 尝试 writeSlot 的总次数, 供下一轮 dynamicSection 反馈
    totalAttempts <- readIORef writeSlotCounter
    setLastIntegrationAttempts oracle totalAttempts

    pure ()


-- ---------------------------------------------------------------
-- Gate phase
-- ---------------------------------------------------------------

gatePhase :: Oracle -> Text -> Text -> TraceHandle -> Int -> PromptOverrides -> IO Bool
gatePhase oracle apiKey model trace _roundN overrides =
    case poGateSystem overrides of
        Just _  -> gatePhaseLLM oracle apiKey model trace overrides
        Nothing -> gateHeuristic oracle trace


gateHeuristic :: Oracle -> TraceHandle -> IO Bool
gateHeuristic oracle trace = do
    confs <- slotConfidences oracle
    nProbes <- countProbes oracle
    nDecProbes <- countDecisionProbes oracle
    let mean = sum (map snd confs) / fromIntegral (length confs)
        emptySlots = [ sid | (sid, conf) <- confs, conf <= 0 ]
        continue = mean < 0.6 || not (null emptySlots)
        reason :: Text
        reason
            | not (null emptySlots) =
                "continue: universal slots still have no probe-backed facts: "
                <> T.intercalate ", " emptySlots
            | mean < 0.6 =
                "continue: confidence mean below threshold"
            | otherwise =
                "converge: confidence mean passed threshold and all universal slots touched"
    appendEvent trace "gate_heuristic" (A.object
        [ "mean" A..= mean
        , "confs" A..= confs
        , "n_probes" A..= nProbes
        , "n_decision_probes" A..= nDecProbes
        , "empty_slots" A..= emptySlots
        , "continue" A..= continue
        , "reason" A..= reason
        ])
    putStrLn $ "[gate] heuristic: mean=" ++ show (round (mean * 100) :: Int)
            ++ "%, empty_slots=" ++ show (map T.unpack emptySlots)
            ++ " -> " ++ (if continue then "continue" else "converge")
    pure continue


gatePhaseLLM :: Oracle -> Text -> Text -> TraceHandle -> PromptOverrides -> IO Bool
gatePhaseLLM oracle apiKey model trace overrides = do
    summaryTxt <- summary oracle
    nProbes <- countProbes oracle
    let probeStats = "\n## 探针计数\n本任务已发 probe 数: " <> T.pack (show nProbes)
                  <> "\n历史参考: 同类案例平均 ~70 发, 范围 10-200。\n"
        userPrompt = summaryTxt <> probeStats
                  <> "\n## 你的任务\n判断信息是否足够收敛。直接输出 JSON: "
                  <> "{\"continue\": true / false, \"why\": \"...\"}"
        msgs = [ SystemMsg (fromMaybe gateSystemPrompt (poGateSystem overrides))
               , UserMsg userPrompt ]

    result <- runChat apiKey model []
                msgs (dispatchTool oracle) (appendEvent trace) 2

    pure (parseGateVerdict (crContent result))


-- 默认 True (继续) 兜底 —— 解析失败也算继续, 避免无故收敛
parseGateVerdict :: Text -> Bool
parseGateVerdict t =
    case extractJsonObject t of
        Nothing  -> True
        Just obj -> case A.eitherDecodeStrict (TE.encodeUtf8 obj) of
            Right (A.Object o) -> case KM.lookup "continue" o of
                Just (A.Bool b) -> b
                _               -> True
            _ -> True


gateSystemPrompt :: Text
gateSystemPrompt = T.unlines
    [ "你是 Gate 节点 —— 唯一职责: 判断 oracle 信息够不够收敛, 不参与「探什么」。"
    , ""
    , "**判断规则** (基于摘要里每槽 confidence, 7 universal 槽全算入):"
    , "  - 7 槽均值 < 0.6  → continue (强制, 信息显然不够)"
    , "  - 7 槽均值 ≥ 0.8  → 可以 converge (信息达可收敛水平)"
    , "  - 0.6 ≤ 均值 < 0.8 → 斟酌区, 倾向 continue, 自己判"
    , ""
    , "参考: 12 个历史案例 7 槽均值范围 0.63-0.90, 平均 0.81。"
    , "  - identity / cli_flags / io_channels / exit_codes 普遍达 0.85+"
    , "  - error_buckets / impl_fingerprint / known_unknowns 通常 0.6-0.85"
    , ""
    , "回复 STRICT JSON: {\"continue\": true 或 false, \"why\": \"<简短理由, 含算出来的均值>\"}"
    ]


-- ---------------------------------------------------------------
-- Execute one action
-- ---------------------------------------------------------------

executeAction :: FilePath -> Action -> IO (Maybe ProbeOutcome)
executeAction taskDir (ActProbe cmd _) = do
    putStrLn $ "  $ " ++ T.unpack cmd
    outcome <- runShellInDir taskDir (normalizeAppCommand cmd)
    pure (fmap (\po -> po { poCmd = cmd }) outcome)
executeAction taskDir (ActGrep pattern files _) = do
    let cmd = "grep -nH -E " <> T.pack (show (T.unpack pattern)) <> " "
              <> T.unwords files
    putStrLn $ "  $ " ++ T.unpack cmd
    runShellInDir taskDir cmd
executeAction taskDir (ActOther _ cmd _) = do
    putStrLn $ "  $ " ++ T.unpack cmd
    runShellInDir taskDir cmd
executeAction _ (ActStop _) = pure Nothing


-- ---------------------------------------------------------------
-- Docker wrapper detection + cmd rewrite
-- ---------------------------------------------------------------
--
-- 背景: PB task wrapper 形如
--   timeout 6 docker exec -i <container> /workspace/executable "$@"
-- 直接跑 LLM cmd 会让 host shell 解析整条 cmd, 导致 `touch /tmp/F` 在 host /tmp,
-- container 内 entr 在 container /tmp 找不到 → fixture namespace 失配。
--
-- 改造: 检测 task dir 下 `probe` 是否 docker wrapper, 是则:
--   1. cmd 字符串里 `./probe` 替换为容器内 binary 路径
--   2. 整条 cmd 用 `docker exec <c> bash -c '<rewritten>'` 进容器跑
--   3. 容器内 `timeout 5` 包裹防 LLM 阻塞 cmd 卡死
--   4. host 侧 hsbb 再包 System.Timeout 30s 兜底 (防 docker client 自己卡)

-- 解析 wrapper 拿 (container_name, internal_binary_path)。
-- wrapper 行例: "timeout 6 docker exec -i pbref-real-entr /workspace/executable \"$@\""
parseDockerWrapper :: Text -> Maybe (Text, Text)
parseDockerWrapper body =
    let lns = T.lines body
        dockerLine = find ("docker exec" `T.isInfixOf`) lns
    in case dockerLine of
        Nothing -> Nothing
        Just l ->
            let toks       = T.words l
                afterExec  = drop 1 $ dropWhile (/= "exec") toks
                afterFlags = dropWhile ("-" `T.isPrefixOf`) afterExec
            in case afterFlags of
                (container : rest) ->
                    case dropWhile ("-" `T.isPrefixOf`) rest of
                        (binary : _) -> Just (container, binary)
                        _            -> Nothing
                _ -> Nothing

-- shell single-quote escape: ' → '\''
shSingleQuote :: Text -> Text
shSingleQuote t = "'" <> T.replace "'" "'\\''" t <> "'"


hasAppInvocation :: Text -> Bool
hasAppInvocation = containsShellToken "app"


normalizeAppCommand :: Text -> Text
normalizeAppCommand = replaceShellToken "app" "./probe"


containsShellToken :: Text -> Text -> Bool
containsShellToken token input = T.unpack token `elem` shellTokens (T.unpack input)


replaceShellToken :: Text -> Text -> Text -> Text
replaceShellToken token repl input =
    T.pack (go True Nothing (T.unpack input))
  where
    tokenS = T.unpack token
    replS  = T.unpack repl

    go _ _ [] = []
    go canStart quote s@(c:cs)
        | quote == Nothing
        , canStart
        , tokenS `isPrefixOfString` s
        , tokenBoundary (drop (length tokenS) s) =
            replS ++ go False Nothing (drop (length tokenS) s)
        | otherwise =
            let quote' = updateQuote quote c
                canStart' = quote' == Nothing && isShellBoundary c
            in c : go canStart' quote' cs


shellTokens :: String -> [String]
shellTokens = go True Nothing []
  where
    go _ _ cur [] = [reverse cur | not (null cur)]
    go canStart quote cur (c:cs)
        | quote == Nothing && isShellBoundary c =
            let rest = go True Nothing [] cs
            in if null cur then rest else reverse cur : rest
        | otherwise =
            let quote' = updateQuote quote c
            in go canStart quote' (c:cur) cs


updateQuote :: Maybe Char -> Char -> Maybe Char
updateQuote Nothing '\'' = Just '\''
updateQuote Nothing '"'  = Just '"'
updateQuote (Just '\'') '\'' = Nothing
updateQuote (Just '"') '"' = Nothing
updateQuote q _ = q


isShellBoundary :: Char -> Bool
isShellBoundary c = isSpace c || c `elem` ("|&;()<>" :: String)


tokenBoundary :: String -> Bool
tokenBoundary [] = True
tokenBoundary (c:_) = isShellBoundary c


isPrefixOfString :: String -> String -> Bool
isPrefixOfString pre s = take (length pre) s == pre

-- 给定 cmd 和 task dir, 决定真正要交给 host shell 跑的 cmd。
-- 若 task 是 docker wrapper 且 cmd 真的调用 ./probe, 重写为 docker exec 形态。
-- 不含 ./probe 的 cmd (grep / ls / file 等纯 host 操作) 留在 host shell 跑。
rewriteForDocker :: FilePath -> Text -> IO Text
rewriteForDocker dir cmd
    | not ("./probe" `T.isInfixOf` cmd) = pure cmd
    | otherwise = do
        let wrapperPath = dir </> "probe"
        exists <- doesFileExist wrapperPath
        if not exists
            then pure cmd
            else do
                body <- TIO.readFile wrapperPath
                case parseDockerWrapper body of
                    Nothing -> pure cmd
                    Just (container, binary) ->
                        let cmdRewritten = T.replace "./probe" binary cmd
                            innerWithTimeout = "timeout 5 bash -c " <> shSingleQuote cmdRewritten
                        in pure $ "docker exec -i " <> container <> " " <> innerWithTimeout


runShellInDir :: FilePath -> Text -> IO (Maybe ProbeOutcome)
runShellInDir dir cmd = do
    t0 <- getCurrentTime
    realCmd <- rewriteForDocker dir cmd
    let runIt = readCreateProcessWithExitCode
                  ((shell (T.unpack realCmd)) { cwd = Just dir }) ""
    -- host 侧 30s 兜底 (docker client 卡死 / network 卡死)
    mResult <- timeout (30 * 1000000) runIt
    t1 <- getCurrentTime
    let durMs = round (1000 * realToFrac (diffUTCTime t1 t0) :: Double) :: Int
    case mResult of
        Just (ec, out, err) -> pure $ Just ProbeOutcome
            { poCmd        = cmd
            , poExit       = case ec of
                                ExitSuccess   -> 0
                                ExitFailure n -> n
            , poStdout     = T.pack out
            , poStderr     = T.pack err
            , poDurationMs = durMs
            }
        Nothing -> pure $ Just ProbeOutcome
            { poCmd        = cmd
            , poExit       = 124
            , poStdout     = ""
            , poStderr     = "HSBB_TIMEOUT: cmd exceeded 30s host wall-clock budget"
            , poDurationMs = durMs
            }


-- ---------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------

renderLastResult :: LastResult -> Text
renderLastResult lr = T.unlines
    [ "cmd: " <> lrCmd lr
    , "exit: " <> T.pack (show (lrExit lr))
    , "stdout (" <> T.pack (show (lrStdoutBytes lr)) <> " B total, ≤2KB sliced):"
    , "```"
    , lrStdoutSlice lr
    , "```"
    , "stderr (" <> T.pack (show (lrStderrBytes lr)) <> " B total, ≤1KB sliced):"
    , "```"
    , lrStderrSlice lr
    , "```"
    , "probe_id: " <> lrProbeId lr <> " (lookupProbe for full)"
    ]


probeToJson :: Text -> Int -> ProbeOutcome -> A.Value
probeToJson pid roundN po = A.object (probeFields pid roundN po)


probeToJsonWithAction :: Text -> Int -> Action -> ProbeOutcome -> A.Value
probeToJsonWithAction pid roundN act po = A.object $
    probeFields pid roundN po ++
    [ "decision"       A..= actionValue act
    , "decision_why"   A..= actionWhy act
    , "decision_kind"  A..= actionKind act
    , "decision_targets" A..= actionTargets act
    ]


probeFields :: Text -> Int -> ProbeOutcome -> [(Key.Key, A.Value)]
probeFields pid roundN po =
    [ "id"           A..= pid
    , "round"        A..= roundN
    , "cmd"          A..= poCmd po
    , "exit"         A..= poExit po
    , "stdout_bytes" A..= T.length (poStdout po)
    , "stderr_bytes" A..= T.length (poStderr po)
    , "stdout"       A..= poStdout po
    , "stderr"       A..= poStderr po
    , "duration_ms"  A..= poDurationMs po
    ]


describeAction :: Action -> String
describeAction (ActProbe c _)     = "probe: " ++ T.unpack c
describeAction (ActGrep p _ _)    = "grep: " ++ T.unpack p
describeAction (ActOther k c _)   = "other(" ++ T.unpack k ++ "): " ++ T.unpack c
describeAction (ActStop r)        = "stop: " ++ T.unpack r


actionJson :: Action -> Text
actionJson = TE.decodeUtf8 . BL.toStrict . A.encode . actionValue


actionValue :: Action -> A.Value
actionValue (ActProbe c w) = A.object
    [ "action" A..= ("probe" :: Text)
    , "cmd" A..= c
    , "why" A..= w
    , "target_slots" A..= targetsFromWhy w
    ]
actionValue (ActGrep p fs w) = A.object
    [ "action" A..= ("grep" :: Text)
    , "pattern" A..= p
    , "files" A..= fs
    , "why" A..= w
    , "target_slots" A..= targetsFromWhy w
    ]
actionValue (ActOther k c w) = A.object
    [ "action" A..= ("other" :: Text)
    , "kind" A..= k
    , "cmd" A..= c
    , "why" A..= w
    , "target_slots" A..= targetsFromWhy w
    ]
actionValue (ActStop w) = A.object
    [ "action" A..= ("stop" :: Text)
    , "why" A..= w
    , "target_slots" A..= targetsFromWhy w
    ]


actionWhy :: Action -> Text
actionWhy (ActProbe _ w)   = w
actionWhy (ActGrep _ _ w) = w
actionWhy (ActOther _ _ w)= w
actionWhy (ActStop w)     = w


actionKind :: Action -> Text
actionKind (ActProbe _ _)    = "probe"
actionKind (ActGrep _ _ _)   = "grep"
actionKind (ActOther k _ _)  = "other:" <> k
actionKind (ActStop _)       = "stop"


actionTargets :: Action -> [Text]
actionTargets = targetsFromWhy . actionWhy


targetsFromWhy :: Text -> [Text]
targetsFromWhy why =
    [ sid | sid <- universalSlots, sid `T.isInfixOf` why ]




-- ---------------------------------------------------------------
-- System prompts
-- ---------------------------------------------------------------

decisionSystemPrompt :: Text
decisionSystemPrompt = T.unlines
    [ "拿到一个黑盒工具: 先看文档了解它能做什么, 然后实际尝试使用它, 观察结果并评测。"
    , "本步: 读 user prompt 各段, 输出下一发要做什么 (action JSON)。"
    , ""
    , "**执行环境**: 你写的整条 cmd 在 Linux container (debian-slim) 内跑, GNU coreutils, bash 5。"
    , "fixture (touch / echo > /tmp/X) 与 probe 同 namespace, 路径一致, 不必 docker exec。"
    , "cmd 被 timeout 5s 包裹, 超时 (exit=124) 仍会收到 stdout — 拿到信号就够。"
    , ""
    , "**探索策略 — 尝试使用优先**:"
    , "  用文档示例或你的理解做一次真实尝试 (创建文件 + 管道喂给 probe + 合理 flag),"
    , "  一次真实使用往往同时验证 flag 解析 / io 通道 / exit code / error 行为, 比逐个 flag 验证信息密度高得多。"
    , "  可以先准备 fixture (echo /tmp/test > /tmp/watched.txt), 再用它跑 probe。"
    , ""
    , "**广度优先**:"
    , "  未触槽 (conf=0) 优先于已触槽的继续深挖。"
    , "  identity / io_channels / exit_codes 通常比 flag 组合更有信息密度。"
    , "  如果动态栏提示「探索集中度」, 说明你在某个槽上花太多轮了 — 换一个维度。"
    , ""
    , "action 协议:"
    , "  探一发: {\"action\":\"probe\",\"cmd\":\"app <args>\",\"why\":\"<意图+目标槽>\"}"
    , "  搜源码: {\"action\":\"grep\",\"pattern\":\"<regex>\",\"files\":[\"<path>\"],\"why\":\"...\"}"
    , "  其他:   {\"action\":\"other\",\"kind\":\"shell/http/docker\",\"cmd\":\"<cmd>\",\"why\":\"...\"}"
    , ""
    , "`app` 是 harness 提供的目标程序占位符。不要写目标程序的真实路径或名字; 如果需要管道或重定向, 写 `echo /tmp/x | app -n -z echo ok`。"
    , ""
    , "why 字段 = 这一发的意图 + 预期 + 目标槽位。两块:"
    , "  1) 意图: 我想用它做 X (具体使用场景), 预期 Y"
    , "  2) 目标槽: 这发应影响哪个 slot (identity / cli_flags / io_channels / exit_codes / error_buckets / impl_fingerprint / known_unknowns / 自定义 other id)"
    , ""
    , "范例: \"意图: 用 -z 让工具在 utility 完成后退出, 管道喂一个文件触发执行. 预期: exit 0. 目标: exit_codes + io_channels.\""
    , ""
    , "**不要预设 last_result 长什么样**。结果空间是开放的, 实际看到啥就是啥, 整理阶段会读 why 的假设 + 实际 result 自由判定。"
    , "硬塞 \"符合 / 反例\" 二元分支等于剥夺整理阶段处理意外结果的能力。"
    ]


integrationSystemPrompt :: Text
integrationSystemPrompt = T.unlines
    [ "你是黑盒探测 agent 的整理阶段。"
    , "上一发探索刚执行完, 看 last_result 揭示了什么, 决定要不要 writeSlot。"
    , ""
    , "**重要约束**："
   , "  - 一发 probe 只能升 **1 个槽**——选 last_result 最直接揭示的那个写"
    , "  - 一发 probe 最多升 **3 个槽**——高密度 probe (如 --help) 可同时落多个槽"
    , "  - 即便给多个 writeSlot tool call, harness 最多采纳 3 个, 后续静默丢弃"
    , ""
    , "可用 tool："
    , "  - writeSlot(slot_id, title, content, confidence, evidence, [notes], [index])"
    , "      slot_id: identity / cli_flags / io_channels / exit_codes / error_buckets"
    , "               / impl_fingerprint / known_unknowns（universal） 或自定义 id（落 other）"
    , "      evidence 必填: 至少含本轮 probe_id"
    , "      evidence 必须保留已有条目 + 追加本轮新 probe_id (不要丢弃旧 evidence)"
    , ""
    , "**title is critical**: must be one info-dense sentence with concrete name/version/counts/key flags/quirks."
    , "  Good: 'yj 5.1.0 (Go binary, std flag parser, 4-format converter)' / '20 single-letter flags, -x[x] 4x4 conversion matrix'"
    , "          / 'stdin->stdout, usage on stderr, exit 1 on bad flag'"
    , "  Bad (forbidden): 'Tool identity' / 'CLI flags' / 'I/O channels' — these empty labels are not allowed."
    , "  In the integration phase, title should incorporate the **new facts revealed by last_result**, not just doc facts."
    , ""
    , "**content is critical**: bullet-list of high-density factual statements (probe-observed, not doc-paraphrased)."
    , "  Each bullet = one verified fact or precise behavior, ideally with ← probe_id evidence."
    , "  Good:"
    , "    - exit 2 on --foo (unknown flag) ← probe_007"
    , "    - stdout: HTTP body / stderr: progress + errors"
    , "    - -print=H/B/h/b/A: H=resp header, B=resp body, h=req header, b=req body, A=all ← probe_014"
    , "    - --version: exit 2, stdout='Version 0.1.0' (Go-flag style) ← probe_002"
    , "  Bad (forbidden):"
    , "    - 'This tool is a Go-based CLI for HTTP requests, similar to cURL...' (prose narrative)"
    , "    - 'Generally produces output to stdout' (vague, no specific behavior)"
    , "    - 'Supports authentication and proxy' (doc paraphrase, not observation)"
    , "    - '13 flags' (count alone, no flag specifics)"
    , ""
    , "oracle 全量信息已在 user prompt 给你（完整 title + content + confidence + evidence）。"
    , "决策阶段的 action.why 字段会指明本发的假设 + 目标槽。"
    , ""
    , "**merge 原则**: 回写 writeSlot 时必须 merge——保留已有 content 中的 bullet + 追加/修正新发现。"
    , "不要全量覆盖丢失旧事实。evidence 同理: 保留旧条目 + 追加新 probe_id。"
    , ""
   , "**自由判定 last_result 真实呈现的状态**, 按下面分类落 writeSlot:"
   , "  - 验证型: last_result 确认 why 假设 (init 推断被实测吻合)"
   , "    → writeSlot 同 slot_id, 复用或微调 title/content"
   , "  - 新事实型: last_result 揭示文档/init 没说的细节 (也包括: 假设确认但结果暴露了未覆盖的角度, 比如缺少前置条件)"
   , "    → writeSlot 落槽, 新事实写入 title/content"
   , "  - 冲突型: last_result 反驳目标槽或其他 slot 现有 title/content"
   , "    → writeSlot 修正"
   , "  - 完全无关: last_result 跟 why 声明的目标无关"
   , "    → 不发 tool call, 一句话总结"
   , ""
   , "**confidence = 该槽 content 的新增量, 不是 probe 成功率**。"
   , "打分前必做: 逐个比对 oracle 摘要中该槽的现有 content bullet, 判断这次 probe 揭示的事实是否已在其中。"
   , "  - 该槽 content 中无任何 probe 验证事实, 本次首次实测 → 0.3-0.5"
   , "  - 该槽 content 有部分事实, 本次新增了 content 中没有的 bullet → 0.2-0.4"
   , "  - probe 结果跟现有 content 已有事实相同, 只是换了 flag 组合再跑一遍 → 0.0-0.1"
   , "  - probe 失败 (exit≠0) 但 stderr 揭示了 content 中没有的新约束 → 0.2-0.4"
   , "  - probe 反驳了现有 content 中的某条事实 → 0.2-0.4"
   , "**关键: 新 flag 组合成功 ≠ 每个目标槽都有增量**。"
   , "  action.why 可能列多个目标槽, 但增量只给真正获得新事实的槽。"
   , "  对其他槽, 增量 ≤ 0.1 (重复确认) → 不要 writeSlot, 省 token + 避免噪声。"
   , "**反例 (实际发生过的错误)**:"
   , "  probe_004 用 -n -z -p 测试 -p (postpone), exit 0, stdout='changed'。"
   , "  why 声明目标: cli_flags + io_channels + exit_codes。"
   , "  正确打分: cli_flags=0.35 (-p 行为首次验证, content 中没有),"
   , "           io_channels 不写 (stdin 读列表 / stdout 透传 = probe_002 已验证, 无新事实),"
   , "           exit_codes 不写 (-z exit 0 = probe_002 已验证, 无新事实)。"
   , "  错误打法: 三个槽都给 0.3-0.5 → 虚假膨胀。"
  , ""
  , "**inconclusive 标记** (诚实标失败胜过外推):"
    , "  当 action.why 声明的目标槽是 X, 但 last_result 完全没给出能落到 X 的信号"
    , "  (比如 cmd 形态选错 / 工具拒收输入 / stdout 空 + stderr 无 actionable hint),"
    , "  调用 writeSlot 时除常规字段, 设 `inconclusive: true`。"
    , "  效果: confidence 不动, slot 的 inconclusive_count 累加。"
    , "  当某槽 inconclusive_count ≥ 2, oracle summary 自动标 [INCONCLUSIVE ×N], decision 阶段会避开。"
    , "  这是显式承认\"这个角度暂时探不出\"的合法路径——好过硬塞外推或反复试同一槽。"
    , ""
    , "**hint_for_next_round 字段** (传 actionable 信号给下一发):"
    , "  当 last_result.stderr/stdout 含**只对下一发 cmd 形态/方向有意义**但不是 slot fact 的信号"
    , "  (例: stderr 暗示 'use -n' / 工具要求真实文件路径 / 某 flag 是 single-shot 无需 trigger / 缺前置条件),"
    , "  调用 writeSlot 时附 `hint_for_next_round: \"<≤120 字的可执行一句话>\"`。"
    , "  hsbb 会把它显式塞进下一发 decision 的 user prompt, LLM 直接看到, 不用自己再 grep stderr。"
    , "  hint 只活一发 (下一发 integration 开始时清空)。"
    , "  反例 (不要写): 复述 slot title/content; 长段分析; 跟下一发 cmd 选择无关的解释。"
    ]


integrationTask :: Text
integrationTask = T.unlines
    [ "看 action.why 中声明的「目标槽 + 预期」, 比对 last_result:"
    , "  - 符合假设 (验证型) → writeSlot 同槽位, 提升 confidence (evidence 保留旧条目 + 追加本轮 probe_id)"
    , "  - 揭示新事实 → writeSlot 落槽 (新事实写入 title/content)"
    , "  - 反驳现有槽 (冲突型) → writeSlot 修正"
    , "  - 跟 why 声明完全无关 → 不发 tool call, 一句话总结"
    , ""
  , "**按信息增量给 confidence**: 首次发现高 (0.3-0.5), 重复确认低 (0.0-0.1)。probe 失败但揭示新约束也是高增量。"
  , ""
  , "**只写有增量的槽**: 如果某槽增量 ≤ 0.1 (跟现有 content 已有事实相同), 不要 writeSlot 该槽。"
  , "action.why 列了多个目标槽不代表每个都要写——只写真正获得新事实的。"
  , ""
  , "**回写 merge**: 保留已有 content bullet + 追加新发现; 不要全量覆盖。"
   ]
