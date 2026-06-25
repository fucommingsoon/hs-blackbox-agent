{-# LANGUAGE OverloadedStrings #-}

-- Init phase:
--   1) mechanically run `./probe --help` and `./probe --version`, write to probes.jsonl (round=0)
--   2) call Deepseek once with docs + the mechanical probe outputs, to digest into oracle slots
module Blackbox.Init
    ( runInit
    ) where

import           Control.Exception       (SomeException, try)
import qualified Data.Aeson              as A
import           Data.Maybe              (catMaybes, fromMaybe)
import qualified Data.Text               as T
import           Data.Text               (Text)
import qualified Data.Text.IO            as TIO
import           System.Directory        (doesFileExist, listDirectory)
import           System.FilePath         ((</>), takeExtension)

import           Blackbox.Deepseek       (Message (..), runChat, writeSlotTool)
import           Blackbox.Loop           (runShellInDir, probeToJson,
                                          PromptOverrides (..))
import           Blackbox.Oracle         (Oracle, dispatchTool, appendProbe,
                                          resetNextRoundHints)
import           Blackbox.Trace          (TraceHandle, appendEvent,
                                          phaseStart, phaseEnd)
import           Blackbox.Types          (ProbeOutcome (..))


runInit :: Oracle -> Text -> Text -> FilePath -> TraceHandle -> PromptOverrides -> IO ()
runInit oracle apiKey model taskDir trace overrides = do
    putStrLn "[init] reading docs..."
    docs <- collectDocs taskDir
    let docsBlob = renderDocs docs

    phaseStart trace "init"
    appendEvent trace "meta" (A.object
        [ "phase" A..= ("init" :: Text)
        , "docs_files" A..= map fst docs
        , "docs_total_chars" A..= sum (map (T.length . snd) docs)
        ])

   -- 1) fs context probes — 看 task 目录 / binary 类型 / 环境
   --    (跑在 host shell, 不进 docker container; rewriteForDocker 会自动 skip)
    putStrLn "[init] running fs context probe: ls -la"
    fsLs   <- runShellInDir taskDir "ls -la ."

    -- 2) 一发 --help 当 canonical 自我介绍 (跨 task 几乎都支持; 去掉之前 -h/-?/-V/-v/--version 5 个重复 alias)
    -- 2) 找到 canonical help: 依次试 --help / -h，取第一个有有效 help 内容的。
    --    有些工具 (如 entr) 不认 --help，只认 -h。
    putStrLn "[init] running mechanical help probes (--help, -h)"
    helpOutcome <- findValidHelp taskDir

    let recordInitProbe pid po = do
            appendProbe oracle (probeToJson pid 0 po)
            appendEvent trace "probe_appended" (A.object
                [ "round"        A..= (0 :: Int)
                , "probe_id"     A..= pid
                , "init_probe"   A..= True
                , "exit"         A..= poExit po
                , "stdout_bytes" A..= T.length (poStdout po)
                , "stderr_bytes" A..= T.length (poStderr po)
                ])
    case fsLs of
        Just po -> recordInitProbe "probe_init_fs_ls" po
        Nothing -> pure ()
    case helpOutcome of
        Just (pid, po) -> do
            recordInitProbe pid po
            putStrLn $ "[init] canonical help: " ++ T.unpack pid
        Nothing -> pure ()

    let fsContext = renderInitProbes
           [ ("ls -la .", fsLs)
           ]
        preProbesSection = case helpOutcome of
            Just (pid, po) -> renderInitProbes [ (pid, Just po) ]
            Nothing        -> ""
        sysPrompt = fromMaybe initSystemPrompt (poInitSystem overrides)
        userPrompt = "## 任务文档\n" <> docsBlob
                  <> "\n\n## fs 上下文 (init 阶段看到的环境)\n" <> fsContext
                  <> "\n\n## 实测自我介绍 (init 阶段已机械执行 help probe)\n" <> preProbesSection
                  <> "\n\n## 你的任务\n" <> initUserPrompt
        msgs = [ SystemMsg sysPrompt, UserMsg userPrompt ]

    putStrLn "[init] calling Deepseek to digest docs + fs context + --help ..."
    _ <- runChat apiKey model [writeSlotTool]
            msgs (dispatchTool oracle) (appendEvent trace) 6

    -- defensive: 清掉 init phase LLM 顺手在 writeSlot 里写的 hint
    -- (init 阶段不该有"上发 cmd 给本发的 hint", 因为本发就是第一发)
    resetNextRoundHints oracle

    phaseEnd trace "init"
    putStrLn "[init] done."


-- 渲染 init phase 跑过的 cmd 结果。
-- label 是完整 cmd 字符串 (例: "./probe --help" / "ls -la .")。
renderInitProbes :: [(Text, Maybe ProbeOutcome)] -> Text
renderInitProbes labelOutcomes = T.unlines $ catMaybes (map render1 labelOutcomes)
  where
    render1 (_,     Nothing) = Nothing
    render1 (label, Just po) = Just $ T.unlines
        [ "### $ " <> label
        , "exit: " <> T.pack (show (poExit po))
        , "stdout:"
        , "```"
        , T.take 8000 (poStdout po)
        , "```"
        , "stderr:"
        , "```"
        , T.take 4000 (poStderr po)
        , "```"
        ]


-- 依次试 ./probe --help / ./probe -h，取第一个 stdout+stderr 有有效 help 内容的。
-- 返回 (probe_id, outcome)，probe_id 为 "probe_init_help" 或 "probe_init_h"。
-- 全部无效时返回 Nothing。
findValidHelp :: FilePath -> IO (Maybe (Text, ProbeOutcome))
findValidHelp taskDir = go candidates
  where
    candidates =
        [ ("probe_init_help", "./probe --help")
        , ("probe_init_h",    "./probe -h")
        ]
    go [] = pure Nothing
    go ((pid, cmd) : rest) = do
        mPo <- runShellInDir taskDir (T.pack cmd)
        case mPo of
            Just po | isHelpContent po ->
                pure (Just (pid, po))
            _ -> go rest

    -- 判定是否真正有效的 help 输出:
    --   1. stderr 含 "invalid option" / "unrecognized" / "unknown" → 明确拒绝, 不是 help
    --   2. stdout+stderr 合并后含 help 关键词 (usage:/options:/flags: 等)
    --   3. 且 stdout 非空 (真正的 help 通常把内容打到 stdout, 即使是 BSD 风格)
    --      例外: Go std flag 的 --help 把 usage 打到 stderr, 但不含 "invalid option"
    isHelpContent po =
        let combined = poStdout po <> "\n" <> poStderr po
            lower    = T.toLower combined
            isRejected = any (`T.isInfixOf` lower)
                [ "invalid option", "unrecognized", "unknown option", "illegal option" ]
            hasKeyword = any (`T.isInfixOf` lower)
                [ "usage:", "usage of", "options:", "flags:"
                , "arguments:", "command:", "summary:", "synopsis:"
                , "commands:", "subcommands:", "examples:"
                ]
            hasFlagLine = any (`T.isInfixOf` combined) ["\n  -", "\n    -", "\n\t-"]
            hasStdout = not (T.null (T.strip (poStdout po)))
        in not isRejected && (hasKeyword || hasFlagLine) && hasStdout


initSystemPrompt :: Text
initSystemPrompt = T.unlines
    [ "你是黑盒探测 agent 的 init 阶段。"
    , "通读任务文档（README/SPEC.md/man pages 等），把能推断的事实落到 oracle 槽里。"
    , ""
    , "可用 tool：writeSlot"
    , "  - slot_id：identity / cli_flags / io_channels / exit_codes / error_buckets / impl_fingerprint / known_unknowns（universal）"
    , "  - 或自定义 id 写到 other"
    , ""
    , "**title is critical**: must be one info-dense sentence with concrete name/version/counts/key flags/quirks."
    , "  Good: 'yj 5.1.0 (Go binary, std flag parser, 4-format converter)' / '20 single-letter flags, no long form, -x[x] 4x4 conversion matrix'"
    , "  Bad (forbidden): 'Tool identity' / 'CLI flags' / 'I/O channels' — these empty labels are not allowed."
    , ""
    , "**置信度统一填 0**（init 阶段所有内容都是未经 probe 验证的文档推断, 一律 0 = 不可置信）"
    , "title / content 可以照常从文档推断写, 但 confidence 必须 = 0"
    , "不确定的角度放 known_unknowns 槽"
    , "evidence 字段写 'source: README' 之类（暂无 probe id）"
    , ""
    , "通过若干个 writeSlot tool call 完成。完成后给一句简短总结即可。"
    ]


initUserPrompt :: Text
initUserPrompt = T.unlines
    [ "通读以上文档，推断能填的事实，发起 writeSlot tool calls 落到 oracle。"
    , "完成后回复一句简短总结。"
    ]


-- Collect non-binary docs from task dir.
collectDocs :: FilePath -> IO [(FilePath, Text)]
collectDocs taskDir = do
    files <- listDirectory taskDir
    let docFiles = filter isDocFile files
    pairs <- mapM (\f -> do
                      t <- tryRead (taskDir </> f)
                      pure (f, t)) docFiles
    pure (filter (not . T.null . snd) pairs)
  where
    isDocFile f =
        let lower = map toLowerChar f
            ext   = map toLowerChar (takeExtension f)
        in lower `elem` ["readme", "readme.md", "readme.txt", "spec.md", "guide.md", "faq", "faq.md"]
           || ext `elem` [".md", ".rst", ".txt", ".1", ".5", ".6", ".7", ".8"]
    toLowerChar c
        | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
        | otherwise = c


renderDocs :: [(FilePath, Text)] -> Text
renderDocs = T.unlines . map render1
  where
    render1 (name, content) = T.unlines
        [ "### " <> T.pack name
        , T.take 8000 content
        , ""
        ]


tryRead :: FilePath -> IO Text
tryRead p = do
    ex <- doesFileExist p
    if not ex then pure ""
    else do
        r <- try (TIO.readFile p) :: IO (Either SomeException Text)
        pure (either (const "") id r)
