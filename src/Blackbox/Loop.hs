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
import           Blackbox.Oracle         (Oracle, summary, appendProbe,
                                          countProbes, dispatchTool,
                                          lastProbeRecord)
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
                        putStrLn $ "[round " ++ show roundN ++ "] LLM stop: " ++ T.unpack reason
                        appendEvent trace "convergence" (A.object
                            [ "reason" A..= ("llm_stop" :: Text)
                            , "why" A..= reason
                            ])
                        pure ()
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
                                loop startT (roundN + 1) (Just lr)


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
    nProbes <- countProbes oracle
    let lrSection = maybe "(无)\n" renderLastResult lastResult
        sysPrompt = decisionSystemPrompt
        userPrompt = summaryTxt <> "\n## 上轮回灌 (last_result)\n" <> lrSection
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
    summaryTxt <- summary oracle
    let actJson = actionJson lastAction
        userPrompt = summaryTxt <> "\n\n## 上轮 action\n" <> actJson
                  <> "\n\n## 上轮回灌 (last_result)\n" <> renderLastResult lr
                  <> "\n\n## 你的任务\n" <> integrationTask
        msgs = [ SystemMsg integrationSystemPrompt, UserMsg userPrompt ]

    _ <- runChat apiKey model [writeSlotTool]
            msgs (dispatchTool oracle) (appendEvent trace) 4

    pure ()


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
    , "  收工：  {\"action\":\"stop\",\"why\":\"...\"}"
    , ""
    , "若信息已足或继续无新意 → stop。"
    , "若未列出的槽位是关键 → 选 probe 把它探出来。"
    , "**最后只输出 action JSON, 不要前置 prose。**"
    ]


integrationSystemPrompt :: Text
integrationSystemPrompt = T.unlines
    [ "你是黑盒探测 agent 的整理阶段。"
    , "上一发探索刚执行完, 看 last_result 揭示了什么, 决定要不要 writeSlot。"
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
