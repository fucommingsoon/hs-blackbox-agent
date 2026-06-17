{-# LANGUAGE OverloadedStrings #-}

-- Init phase: read task docs, call Deepseek once to digest them into oracle slots.
module Blackbox.Init
    ( runInit
    ) where

import           Control.Exception       (SomeException, try)
import qualified Data.Aeson              as A
import qualified Data.Text               as T
import           Data.Text               (Text)
import qualified Data.Text.IO            as TIO
import           System.Directory        (doesFileExist, listDirectory)
import           System.FilePath         ((</>), takeExtension)

import           Blackbox.Deepseek       (Message (..), runChat, writeSlotTool)
import           Blackbox.Oracle         (Oracle, dispatchTool)
import           Blackbox.Trace          (TraceHandle, appendEvent,
                                          phaseStart, phaseEnd)


runInit :: Oracle -> Text -> Text -> FilePath -> TraceHandle -> IO ()
runInit oracle apiKey model taskDir trace = do
    putStrLn "[init] reading docs..."
    docs <- collectDocs taskDir
    let docsBlob = renderDocs docs

    phaseStart trace "init"
    appendEvent trace "meta" (A.object
        [ "phase" A..= ("init" :: Text)
        , "docs_files" A..= map fst docs
        , "docs_total_chars" A..= sum (map (T.length . snd) docs)
        ])

    let sysPrompt = initSystemPrompt
        userPrompt = "## 任务文档\n" <> docsBlob <> "\n\n## 你的任务\n" <> initUserPrompt
        msgs = [ SystemMsg sysPrompt, UserMsg userPrompt ]

    putStrLn "[init] calling Deepseek to digest docs..."
    _ <- runChat apiKey model [writeSlotTool]
            msgs (dispatchTool oracle) (appendEvent trace) 6

    phaseEnd trace "init"
    putStrLn "[init] done."


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
