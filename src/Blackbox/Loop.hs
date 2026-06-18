{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Main ReAct loop.
-- Each round: decision prompt → action → (if explore) execute + integration prompt.
-- Convergence: wall-clock > 20 min OR LLM emits stop action.
module Blackbox.Loop
    ( runLoop
    , runStep
    ) where

import           Control.Exception       (SomeException, try)
import           Control.Monad           (when)
import           Data.IORef              (atomicModifyIORef', newIORef,
                                          readIORef)
import qualified Data.Aeson              as A
import qualified Data.Aeson.Key          as Key
import qualified Data.Aeson.KeyMap       as KM
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

import           Blackbox.Deepseek       (Message (..), runChat,
                                          writeSlotTool,
                                          lookupProbeTool, ChatResult (..))
import           Blackbox.Oracle         (Oracle, summary, dynamicSection,
                                          appendProbe, countProbes,
                                          dispatchTool, lastProbeRecord,
                                          setCurrentRound,
                                          setLastIntegrationAttempts,
                                          uniqueProbeCommands,
                                          referenceProbes)
import           Blackbox.Trace          (TraceHandle, appendEvent,
                                          phaseStart, phaseEnd)
import           Blackbox.Types          (Action (..), LastResult (..),
                                          ProbeOutcome (..), makeLastResult,
                                          parseAction)


-- Wall-clock budget in seconds.
budgetSeconds :: Double
budgetSeconds = 20 * 60


-- ---------------------------------------------------------------
-- Single-round step (for parallel observable execution)
-- ---------------------------------------------------------------

-- runStep runs exactly one round (decision + optional explore + optional integration)
-- then exits. Round number derived from probes.jsonl; last_result reconstructed from
-- the latest probe if any.
runStep :: Oracle -> Text -> Text -> FilePath -> TraceHandle -> IO ()
runStep oracle apiKey model taskDir trace = do
    nProbes <- countProbes oracle
    let roundN = nProbes + 1
    lastResult <- reconstructLastResult oracle
    putStrLn $ "[step] round " ++ show roundN
                ++ (case lastResult of
                      Just lr -> " (last_result probe=" ++ T.unpack (lrProbeId lr) ++ ")"
                      Nothing -> " (no prior probe)")

    let roundTag = T.pack ("round_" ++ pad3 roundN)
        pad3 k = let s = show k in replicate (3 - length s) '0' ++ s

    phaseStart trace (roundTag <> "_decision")
    putStrLn "[step] decision phase..."
    action <- decisionPhase oracle apiKey model trace roundN lastResult
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
                    appendProbe oracle (probeToJson pid roundN po)
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
                    integrationPhase oracle apiKey model trace roundN act lr
                    phaseEnd trace (roundTag <> "_integration")
                    phaseStart trace (roundTag <> "_gate")
                    putStrLn "[step] gate phase..."
                    cont <- gatePhase oracle apiKey model trace roundN
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

runLoop :: Oracle -> Text -> Text -> FilePath -> TraceHandle -> IO ()
runLoop oracle apiKey model taskDir trace = do
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
                action <- decisionPhase oracle apiKey model trace roundN lastResult
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
                                let probeJson = probeToJson pid roundN po
                                appendProbe oracle probeJson
                                let lr = makeLastResult pid po
                                phaseStart trace (roundTag <> "_integration")
                                putStrLn $ "[round " ++ show roundN ++ "] integration phase..."
                                integrationPhase oracle apiKey model trace roundN act lr
                                phaseEnd trace (roundTag <> "_integration")
                                -- Gate 判断收敛
                                phaseStart trace (roundTag <> "_gate")
                                putStrLn $ "[round " ++ show roundN ++ "] gate phase..."
                                cont <- gatePhase oracle apiKey model trace roundN
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

decisionPhase :: Oracle -> Text -> Text -> TraceHandle -> Int -> Maybe LastResult -> IO (Maybe Action)
decisionPhase oracle apiKey model trace roundN lastResult = do
    summaryTxt <- summary oracle
    dynamicTxt <- dynamicSection oracle roundN
    nProbes <- countProbes oracle
    pastCmds <- uniqueProbeCommands oracle
    refs <- referenceProbes oracle
    let lrSection = maybe "(无)\n" renderLastResult lastResult
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
        sysPrompt = decisionSystemPrompt
        userPrompt = summaryTxt <> "\n" <> dynamicTxt <> refsSection <> probeStats <> pastSection
                  <> "\n## 上轮回灌 (last_result)\n" <> lrSection
                  <> "\n## 你的任务\n基于以上, 决定下一步 action, 直接输出 action JSON。"
        msgs = [ SystemMsg sysPrompt, UserMsg userPrompt ]

    result <- runChat apiKey model [] {- 决策阶段不暴露任何 tool -}
                msgs (dispatchTool oracle) (appendEvent trace) 2

    pure (parseActionFromText (crContent result))


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


-- ---------------------------------------------------------------
-- Integration phase
-- ---------------------------------------------------------------

integrationPhase :: Oracle -> Text -> Text -> TraceHandle -> Int -> Action -> LastResult -> IO ()
integrationPhase oracle apiKey model trace roundN lastAction lr = do
    setCurrentRound oracle roundN
    summaryTxt <- summary oracle
    let actJson = actionJson lastAction
        userPrompt = summaryTxt <> "\n\n## 上轮 action\n" <> actJson
                  <> "\n\n## 上轮回灌 (last_result)\n" <> renderLastResult lr
                  <> "\n\n## 你的任务\n" <> integrationTask
        msgs = [ SystemMsg integrationSystemPrompt, UserMsg userPrompt ]

    -- 机械限制: 本次 integration 只采纳第一个 writeSlot
    writeSlotCounter <- newIORef (0 :: Int)
    let wrappedHandler name args =
            if name == "writeSlot"
                then do
                    n <- atomicModifyIORef' writeSlotCounter (\c -> (c + 1, c))
                    if n == 0
                        then dispatchTool oracle name args
                        else pure "rejected: 本次 integration 已经写过 1 个槽, 后续 writeSlot 不生效 (一发 probe 只升 1 个槽)"
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

gatePhase :: Oracle -> Text -> Text -> TraceHandle -> Int -> IO Bool
gatePhase oracle apiKey model trace _roundN = do
    summaryTxt <- summary oracle
    nProbes <- countProbes oracle
    let probeStats = "\n## 探针计数\n本任务已发 probe 数: " <> T.pack (show nProbes)
                  <> "\n历史参考: 同类案例平均 ~70 发, 范围 10-200。\n"
        userPrompt = summaryTxt <> probeStats
                  <> "\n## 你的任务\n判断信息是否足够收敛。直接输出 JSON: "
                  <> "{\"continue\": true / false, \"why\": \"...\"}"
        msgs = [ SystemMsg gateSystemPrompt, UserMsg userPrompt ]

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
    runShellInDir taskDir cmd
executeAction taskDir (ActGrep pattern files _) = do
    let cmd = "grep -nH -E " <> T.pack (show (T.unpack pattern)) <> " "
              <> T.unwords files
    putStrLn $ "  $ " ++ T.unpack cmd
    runShellInDir taskDir cmd
executeAction taskDir (ActOther _ cmd _) = do
    putStrLn $ "  $ " ++ T.unpack cmd
    runShellInDir taskDir cmd
executeAction _ (ActStop _) = pure Nothing


runShellInDir :: FilePath -> Text -> IO (Maybe ProbeOutcome)
runShellInDir dir cmd = do
    t0 <- getCurrentTime
    (ec, out, err) <- readCreateProcessWithExitCode
        ((shell (T.unpack cmd)) { cwd = Just dir }) ""
    t1 <- getCurrentTime
    let durMs = round (1000 * realToFrac (diffUTCTime t1 t0) :: Double) :: Int
    pure $ Just ProbeOutcome
        { poCmd        = cmd
        , poExit       = case ec of
                            ExitSuccess     -> 0
                            ExitFailure n   -> n
        , poStdout     = T.pack out
        , poStderr     = T.pack err
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
probeToJson pid roundN po = A.object
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
actionJson (ActProbe c w) = "{\"action\":\"probe\",\"cmd\":\"" <> c <> "\",\"why\":\"" <> w <> "\"}"
actionJson (ActGrep p fs w) = "{\"action\":\"grep\",\"pattern\":\"" <> p <> "\",\"files\":["
    <> T.intercalate "," [ "\"" <> f <> "\"" | f <- fs ] <> "],\"why\":\"" <> w <> "\"}"
actionJson (ActOther k c w) = "{\"action\":\"other\",\"kind\":\"" <> k <> "\",\"cmd\":\"" <> c <> "\",\"why\":\"" <> w <> "\"}"
actionJson (ActStop w) = "{\"action\":\"stop\",\"why\":\"" <> w <> "\"}"




-- ---------------------------------------------------------------
-- System prompts
-- ---------------------------------------------------------------

decisionSystemPrompt :: Text
decisionSystemPrompt = T.unlines
    [ "你是黑盒探测 agent 的决策阶段。"
    , "看完 oracle 摘要（title + confidence）+ 上轮回灌, 决定下一步 action。"
    , ""
    , "oracle 摘要已是 harness 投影好的全部视图——**不需要任何 tool 去拉 oracle 槽位细节**。"
    , ""
    , "action 协议（**强制只用 ./probe**, 不要 ./pingu/./rg/./dsq 等真实工具名——probe 是 wrapper）："
    , "  探一发：{\"action\":\"probe\",\"cmd\":\"./probe <args>\",\"why\":\"...\"}"
    , "  搜源码：{\"action\":\"grep\",\"pattern\":\"...\",\"files\":[\"path\"],\"why\":\"...\"}"
    , "  其他：  {\"action\":\"other\",\"kind\":\"shell/http/docker\",\"cmd\":\"...\",\"why\":\"...\"}"
    , ""
    , "**收敛判断不归你管, 由独立 Gate 节点决定; 你**只**出探索 action**, 不要出 stop**。"
    , "**最后只输出 action JSON, 不要前置 prose。**"
    ]


integrationSystemPrompt :: Text
integrationSystemPrompt = T.unlines
    [ "你是黑盒探测 agent 的整理阶段。"
    , "上一发探索刚执行完, 看 last_result 揭示了什么, 决定要不要 writeSlot。"
    , ""
    , "**重要约束**："
    , "  - 一发 probe 只能升 **1 个槽**——选 last_result 最直接揭示的那个写"
    , "  - 即便给多个 writeSlot tool call, harness 只采纳第一个, 后续静默丢弃"
    , ""
    , "可用 tool："
    , "  - writeSlot(slot_id, title, content, confidence, evidence, [notes], [index])"
    , "      slot_id: identity / cli_flags / io_channels / exit_codes / error_buckets"
    , "               / impl_fingerprint / known_unknowns（universal） 或自定义 id（落 other）"
    , "      evidence 必填: 至少含本轮 probe_id"
    , ""
    , "**title is critical**: must be one info-dense sentence with concrete name/version/counts/key flags/quirks."
    , "  Good: 'yj 5.1.0 (Go binary, std flag parser, 4-format converter)' / '20 single-letter flags, -x[x] 4x4 conversion matrix'"
    , "          / 'stdin->stdout, usage on stderr, exit 1 on bad flag'"
    , "  Bad (forbidden): 'Tool identity' / 'CLI flags' / 'I/O channels' — these empty labels are not allowed."
    , "  In the integration phase, title should incorporate the **new facts revealed by last_result**, not just doc facts."
    , ""
    , "oracle 摘要已在 user prompt 给你（title + confidence）。要写哪个槽自己判断。"
    , ""
    , "若 last_result 揭示新事实 → 发 writeSlot tool calls 落槽（写新 / 整体替换旧的均可）。"
    , "若 last_result 无新意 → 不发 writeSlot, 直接简短总结。"
    ]


integrationTask :: Text
integrationTask = T.unlines
    [ "看 last_result, 比对 oracle 现有槽:"
    , "  - 有新事实 → writeSlot 落槽 (evidence 至少含 " <> "本轮 probe_id)"
    , "  - 有冲突 → readSlot 看详情后 writeSlot 修正"
    , "  - 无新意 → 不发 tool call, 一句话总结即可"
    ]
