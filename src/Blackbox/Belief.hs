{-# LANGUAGE OverloadedStrings #-}

-- belief.md synthesis — single Deepseek call after convergence.
module Blackbox.Belief
    ( synthesize
    ) where

import qualified Data.Aeson              as A
import qualified Data.Text               as T
import           Data.Text               (Text)
import qualified Data.Text.IO            as TIO
import qualified Data.Text.Encoding      as TE
import qualified Data.Yaml               as Y
import           System.FilePath         ((</>))

import           Blackbox.Deepseek       (Message (..), runChat,
                                          lookupProbeTool, ChatResult (..))
import           Blackbox.Oracle         (Oracle, loadOracle, dispatchTool)
import           Blackbox.Trace          (TraceHandle, appendEvent,
                                          phaseStart, phaseEnd)


synthesize :: Oracle -> Text -> Text -> FilePath -> TraceHandle -> IO ()
synthesize oracle apiKey model taskDir trace = do
    putStrLn "[belief] synthesizing..."
    phaseStart trace "belief"
    oracleVal <- loadOracle oracle
    let oracleYaml = TE.decodeUtf8 (Y.encode oracleVal)
        sysPrompt = "你是一名黑盒目标分析师。基于 oracle.yaml 内的全部事实, 给消费者（人或上游 agent）写一份 belief.md。"
                  <> "\n格式自由 markdown, 你认为重要的全写。需要某个 probe 全量可调 lookupProbe(probe_id)。"
        userPrompt = "## oracle.yaml 全文\n```yaml\n" <> oracleYaml
                  <> "\n```\n\n请写 belief.md（直接输出 markdown 正文, 无围栏）。"
        msgs = [ SystemMsg sysPrompt, UserMsg userPrompt ]

    result <- runChat apiKey model [] {- belief 阶段不暴露任何 tool -}
                msgs (dispatchTool oracle) (appendEvent trace) 2

    let beliefPath = taskDir </> ".hsbb" </> "belief.md"
    TIO.writeFile beliefPath (crContent result)
    appendEvent trace "belief_written" (A.object
        [ "path" A..= beliefPath
        , "bytes" A..= T.length (crContent result)
        ])
    phaseEnd trace "belief"
    putStrLn $ "[belief] wrote " ++ beliefPath
