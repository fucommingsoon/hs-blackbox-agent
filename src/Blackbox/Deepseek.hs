{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Deepseek client + tool-calling loop.
-- Each call retries up to 3 times. Failing all retries throws.
module Blackbox.Deepseek
    ( -- API call
      runChat
      -- Tool definition helpers (for system prompt assembly)
    , readSlotTool
    , writeSlotTool
    , lookupProbeTool
      -- Message types
    , Message (..)
    , ToolCall (..)
    , ChatResult (..)
    ) where

import           Control.Exception       (SomeException, try)
import           Control.Monad           (forM, mfilter)
import qualified Data.Aeson              as A
import           Data.Aeson              ((.!=), (.:), (.:?), withObject)
import           Data.Aeson.Types        (Parser, parseEither)
import qualified Data.Aeson.Key          as Key
import qualified Data.Aeson.KeyMap       as KM
import           Data.Bifunctor          (first)
import qualified Data.ByteString.Lazy    as BL
import           Data.Maybe              (mapMaybe)
import qualified Data.Text               as T
import           Data.Text               (Text)
import qualified Data.Text.Encoding      as TE
import qualified Data.Vector             as V
import           Network.HTTP.Client     (Request (..), RequestBody (..),
                                          Response (..), httpLbs, newManager,
                                          parseRequest)
import           Network.HTTP.Client.TLS (tlsManagerSettings)


-- ---------------------------------------------------------------
-- Message types
-- ---------------------------------------------------------------

data Message
    = SystemMsg Text
    | UserMsg Text
    | AssistantMsg (Maybe Text) [ToolCall]  -- content + tool calls
    | ToolMsg Text Text                     -- tool_call_id + content
    deriving (Show)


data ToolCall = ToolCall
    { tcId       :: Text
    , tcName     :: Text
    , tcArgsJson :: Text   -- raw JSON string for arguments
    } deriving (Show)


-- The final result after the tool-calling loop finishes.
data ChatResult = ChatResult
    { crContent     :: Text         -- final assistant content (if any)
    , crToolCalls   :: [ToolCall]   -- final tool calls (if no content)
    , crAllMessages :: [Message]    -- full message history for trace
    } deriving (Show)


-- ---------------------------------------------------------------
-- Tool definitions (OpenAI-style function spec)
-- ---------------------------------------------------------------

readSlotTool :: A.Value
readSlotTool = A.object
    [ "type" A..= ("function" :: Text)
    , "function" A..= A.object
        [ "name" A..= ("readSlot" :: Text)
        , "description" A..= ("Read full content of one oracle slot. Use when summary isn't enough." :: Text)
        , "parameters" A..= A.object
            [ "type" A..= ("object" :: Text)
            , "properties" A..= A.object
                [ "slot_id" A..= A.object
                    [ "type" A..= ("string" :: Text)
                    , "description" A..= ("slot id: identity / cli_flags / ... or an 'other' entry id" :: Text)
                    ]
                ]
            , "required" A..= (["slot_id"] :: [Text])
            ]
        ]
    ]


writeSlotTool :: A.Value
writeSlotTool = A.object
    [ "type" A..= ("function" :: Text)
    , "function" A..= A.object
        [ "name" A..= ("writeSlot" :: Text)
        , "description" A..= ("Write or update an oracle slot (universal or 'other' entry)." :: Text)
        , "parameters" A..= A.object
            [ "type" A..= ("object" :: Text)
            , "properties" A..= A.object
                [ "slot_id"    A..= A.object [ "type" A..= ("string" :: Text) ]
                , "title"      A..= A.object [ "type" A..= ("string" :: Text)
                                             , "description" A..= ("One info-dense sentence. Must include concrete name/version/counts/key flags/quirks. **No empty labels like 'CLI flags' / 'Tool identity'.** Good: 'yj 5.1.0 (Go binary, std flag parser, 4-format converter)' / '20 single-letter flags, no long form, -x[x] 4x4 conversion matrix' / 'stdin->stdout, usage on stderr, exit 1 on bad flag'" :: Text) ]
                , "content"    A..= A.object [ "type" A..= ("string" :: Text)
                                             , "description" A..= ("High-density factual statements as bullet list. Each line = one probe-observed fact or precise behavior, ideally with ← probe_id evidence. NO prose narration, NO doc paraphrase. Good: 'exit 2 on --foo (unknown flag) ← probe_007' / 'stdout: HTTP body / stderr: progress' / '-print=H/B/h/b/A: H=resp header, B=body, h=req header...'. Bad (forbidden): 'This tool is a Go-based CLI...' (narrative) / 'Generally produces output to stdout' (vague) / 'Supports authentication' (doc paraphrase, not observation)" :: Text) ]
                , "confidence" A..= A.object [ "type" A..= ("number" :: Text)
                                            , "description" A..= ("0.0 to 1.0 — information increment vs this slot's existing content, NOT probe success. 0=no new facts in content, 0.3+=new behavior not yet in content. If slot already has this fact, give 0.0-0.1" :: Text) ]
                , "evidence"   A..= A.object [ "type" A..= ("array" :: Text)
                                             , "items" A..= A.object [ "type" A..= ("string" :: Text) ]
                                             , "description" A..= ("probe ids supporting this" :: Text) ]
                , "notes"      A..= A.object [ "type" A..= ("string" :: Text)
                                             , "description" A..= ("optional caveat" :: Text) ]
                , "index"      A..= A.object [ "type" A..= ("integer" :: Text)
                                             , "description" A..= ("optional, only for 'other' entries" :: Text) ]
                , "inconclusive" A..= A.object
                    [ "type" A..= ("boolean" :: Text)
                    , "description" A..= ("optional. Set true when this probe targeted this slot but failed to yield a conclusive signal (探了但 stdout/stderr 给不出明确事实). Slot 的 confidence 不被加, 但 inconclusive_count 累加. 当 inconclusive_count >= 2 后, oracle summary 会标 [INCONCLUSIVE], decision 阶段就不该再反复试同一槽。诚实标 inconclusive 比硬塞外推强。" :: Text)
                    ]
                , "hint_for_next_round" A..= A.object
                    [ "type" A..= ("string" :: Text)
                    , "description" A..= ("optional. 给下一发 decision LLM 的 actionable 一句话, 不是 slot fact。用于把 last_result 中只对‘下一发 cmd 形态/方向’有意义的信号显式传过去——例如 stderr 暗示 'use -n' / 工具要求真实文件路径 / 当前 fixture 用错路径 / 某 flag 是 single-shot 不需要 trigger。**只写跟下一发 cmd 选择直接相关的可执行建议**, 不要复述 slot 内容。一句话, 长度 ≤ 120 字符。" :: Text)
                    ]
                ]
            , "required" A..= (["slot_id", "title", "content", "confidence"] :: [Text])
            ]
        ]
    ]


lookupProbeTool :: A.Value
lookupProbeTool = A.object
    [ "type" A..= ("function" :: Text)
    , "function" A..= A.object
        [ "name" A..= ("lookupProbe" :: Text)
        , "description" A..= ("Fetch a probe's full record (full stdout/stderr) from probes.jsonl." :: Text)
        , "parameters" A..= A.object
            [ "type" A..= ("object" :: Text)
            , "properties" A..= A.object
                [ "probe_id" A..= A.object [ "type" A..= ("string" :: Text) ]
                ]
            , "required" A..= (["probe_id"] :: [Text])
            ]
        ]
    ]


-- ---------------------------------------------------------------
-- Tool-calling loop
-- ---------------------------------------------------------------

-- runChat sends messages, handles tool-call cycles, and returns when
-- the assistant produces a final content (no further tool calls).
--
-- The toolHandler is called for each tool invocation; its result becomes a
-- tool message that gets fed back to Deepseek.
--
-- The trace callback is invoked at: each llm_request, llm_response,
-- tool_dispatch_start, tool_dispatch_result. Use noTrace if you don't want
-- tracing.
runChat
    :: Text                                       -- apiKey
    -> Text                                       -- model
    -> [A.Value]                                  -- tools (function specs)
    -> [Message]                                  -- initial messages
    -> (Text -> A.Value -> IO Text)               -- toolHandler (name, args) → result
    -> (Text -> A.Value -> IO ())                 -- trace callback (eventType, payload)
    -> Int                                        -- max tool-call rounds (safety)
    -> IO ChatResult
runChat apiKey model tools msgs0 toolHandler trace maxRounds =
    go 0 msgs0
  where
    go n msgs
        | n >= maxRounds = pure (ChatResult "" [] msgs)
        | otherwise = do
            trace "llm_request" (A.object
                [ "round"       A..= n
                , "messages"    A..= map messageToJson msgs
                , "tools"       A..= tools
                  -- API 调用参数 (跟 postChat 里硬编码值保持一致, 便于审计)
                , "model"       A..= model
                , "temperature" A..= (0.3 :: Double)
                , "max_tokens"  A..= (2000 :: Int)
                ])
            resp <- callOnce apiKey model tools msgs
            case resp of
                Left e -> do
                    trace "error" (A.object [ "where" A..= ("llm_call" :: Text), "msg" A..= e ])
                    pure (ChatResult ("(api error: " <> e <> ")") [] msgs)
                Right (content, toolCalls) -> do
                    trace "llm_response" (A.object
                        [ "round"      A..= n
                        , "content"    A..= maybe A.Null A.String content
                        , "tool_calls" A..= map toolCallToJson toolCalls
                        ])
                    if null toolCalls
                        then
                            -- Final answer
                            pure (ChatResult (maybe "" id content) []
                                             (msgs ++ [AssistantMsg content []]))
                        else do
                            let assistantMsg = AssistantMsg content toolCalls
                            toolResults <- forM toolCalls $ \tc -> do
                                let argsVal = case A.eitherDecode (BL.fromStrict (TE.encodeUtf8 (tcArgsJson tc))) of
                                                Right v -> v
                                                Left _  -> A.Null
                                trace "tool_dispatch_start" (A.object
                                    [ "id"   A..= tcId tc
                                    , "name" A..= tcName tc
                                    , "args" A..= argsVal
                                    ])
                                r <- toolHandler (tcName tc) argsVal
                                trace "tool_dispatch_result" (A.object
                                    [ "id"     A..= tcId tc
                                    , "name"   A..= tcName tc
                                    , "result" A..= r
                                    ])
                                pure (ToolMsg (tcId tc) r)
                            go (n + 1) (msgs ++ [assistantMsg] ++ toolResults)


callOnce
    :: Text -> Text -> [A.Value] -> [Message]
    -> IO (Either Text (Maybe Text, [ToolCall]))
callOnce apiKey model tools msgs = goCall 3
  where
    goCall :: Int -> IO (Either Text (Maybe Text, [ToolCall]))
    goCall 0 = pure (Left "all retries failed")
    goCall n = do
        r <- try (postChat apiKey model tools msgs) :: IO (Either SomeException (Either Text (Maybe Text, [ToolCall])))
        case r of
            Right v@(Right _) -> pure v
            _ | n > 1 -> goCall (n - 1)
              | otherwise -> case r of
                    Left e -> pure (Left ("exception: " <> T.pack (show e)))
                    Right (Left e) -> pure (Left e)
                    Right v -> pure v


postChat
    :: Text -> Text -> [A.Value] -> [Message]
    -> IO (Either Text (Maybe Text, [ToolCall]))
postChat apiKey model tools msgs = do
    mgr <- newManager tlsManagerSettings
    let body = A.encode $ A.object $
            [ "model"       A..= model
            , "messages"    A..= map messageToJson msgs
            , "temperature" A..= (0.3 :: Double)
            , "max_tokens"  A..= (2000 :: Int)
            ] ++ if null tools then [] else
            [ "tools"      A..= tools
            , "tool_choice" A..= ("auto" :: Text)
            ]
    -- AUDIT: 每发请求体 append 到 /tmp/hsbb_bodies.jsonl, 一行一个
    BL.appendFile "/tmp/hsbb_bodies.jsonl" (body <> "\n")
    req0 <- parseRequest "https://api.deepseek.com/chat/completions"
    let req = req0
            { method         = "POST"
            , requestBody    = RequestBodyLBS body
            , requestHeaders =
                [ ("Authorization", "Bearer " <> TE.encodeUtf8 apiKey)
                , ("Content-Type", "application/json")
                ]
            }
    resp <- httpLbs req mgr
    case A.eitherDecode (responseBody resp) :: Either String A.Value of
        Left e  -> pure (Left ("json decode error: " <> T.pack e))
        Right v -> pure (parseResponse v)


-- parseResponse: 把 Deepseek 响应 JSON 抠成 (content, toolCalls)。
-- 【路 1 重写】改用 Aeson 自带的 Parser monad (withObject / .: / .:? / .!=)：
--   * do + <- 真正用上 monad 短路，原来的嵌套 case 金字塔塌成一条直线；
--   * key 缺失 / 类型不符会自动短路报错，不必手写 Left；
--   * 顺带消除旧版 `let A.Object choice = V.head arr` 的运行时崩溃隐患——
--     choice 非对象时这里只给正常的 Left，而不是抛 irrefutable-pattern 异常。
-- 注：Left/Right 语义与旧版一致；错误文案改由 withObject/.: 自动生成，措辞略有不同。
parseResponse :: A.Value -> Either Text (Maybe Text, [ToolCall])
parseResponse = first T.pack . parseEither parser
  where
    parser :: A.Value -> Parser (Maybe Text, [ToolCall])
    parser = withObject "response" $ \o -> do
        choices <- o .: "choices"
        case choices :: [A.Object] of
            (choice:_) -> do
                m        <- choice .: "message"
                content  <- m .:? "content"
                rawCalls <- m .:? "tool_calls" .!= []
                -- 空串 content 归一成 Nothing；解析失败的 tool_call 静默丢弃
                pure ( mfilter (not . T.null) content
                     , mapMaybe parseToolCall rawCalls )
            [] -> fail "no choices"


-- 【旧版 · 已停用，保留供参考】手写嵌套 case 版本。
-- 缺点：外层 do 是摆设(没用 monad)、case 层层嵌套、且 `let A.Object choice`
-- 在 choice 非对象时会运行时崩溃。已被上面的「路 1」版本取代。
{-
parseResponse :: A.Value -> Either Text (Maybe Text, [ToolCall])
parseResponse (A.Object o) = do
    case KM.lookup "choices" o of
        Just (A.Array arr) | not (V.null arr) -> do
            let A.Object choice = V.head arr
            case KM.lookup "message" choice of
                Just (A.Object m) -> do
                    let content = case KM.lookup "content" m of
                            Just (A.String s) | not (T.null s) -> Just s
                            _                                  -> Nothing
                        toolCalls = case KM.lookup "tool_calls" m of
                            Just (A.Array tcs) -> map parseToolCall (V.toList tcs)
                            _                  -> []
                    Right (content, [tc | Just tc <- toolCalls])
                _ -> Left "no message"
        _ -> Left "no choices"
parseResponse _ = Left "not an object"
-}


parseToolCall :: A.Value -> Maybe ToolCall
parseToolCall (A.Object o) = do
    A.String tid <- KM.lookup "id" o
    A.Object f   <- KM.lookup "function" o
    A.String n   <- KM.lookup "name" f
    A.String a   <- KM.lookup "arguments" f
    Just (ToolCall tid n a)
parseToolCall _ = Nothing


messageToJson :: Message -> A.Value
messageToJson (SystemMsg s)            = A.object [ "role" A..= ("system" :: Text), "content" A..= s ]
messageToJson (UserMsg s)              = A.object [ "role" A..= ("user" :: Text), "content" A..= s ]
messageToJson (AssistantMsg c tcs)     =
    let base = [ "role" A..= ("assistant" :: Text)
               , "content" A..= maybe A.Null A.String c
               ]
        withTools = if null tcs then base
                    else base ++ [ "tool_calls" A..= map toolCallToJson tcs ]
    in A.object withTools
messageToJson (ToolMsg tid c)          =
    A.object [ "role" A..= ("tool" :: Text)
             , "tool_call_id" A..= tid
             , "content" A..= c
             ]


toolCallToJson :: ToolCall -> A.Value
toolCallToJson tc = A.object
    [ "id"   A..= tcId tc
    , "type" A..= ("function" :: Text)
    , "function" A..= A.object
        [ "name"      A..= tcName tc
        , "arguments" A..= tcArgsJson tc
        ]
    ]
