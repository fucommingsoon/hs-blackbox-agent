{-# LANGUAGE OverloadedStrings #-}

-- Detection rules: from the first 1-3 probes + filesystem inspection,
-- classify the black box into one of the 12 forms.
--
-- See methodology.md §2.
module Blackbox.Classifier
    ( classifyByForm
    , chooseStrategy
    , countDocLines
    ) where

import           Control.Monad (filterM)
import qualified Data.Text as T
import           Data.Text (Text)
import qualified Data.Text.IO as TIO
import           System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import           System.FilePath ((</>), takeExtension)

import           Blackbox.Types


-- Pick the right form based on observed signals.
--
-- Inputs:
--   helpOut : output of `./probe --help` (or -h if --help fails)
--   defOut  : output of `./probe` no-args
--   helpErr : stderr of the above
--   docDirContents : list of files/dirs in task dir
classifyByForm
    :: Text             -- helpOut (stdout)
    -> Text             -- defOut (stdout)
    -> Text             -- defErr (stderr)
    -> [FilePath]       -- contents of task dir
    -> Int              -- doc total lines
    -> BlackBoxType
classifyByForm helpOut defOut defErr taskDirFiles docLines
    -- Rule order matters. Strongest / most specific signals first.

    -- Rule 2.2: TUI ncurses-locked (error path) — most specific
    | T.isInfixOf "Error opening terminal" defErr
        || T.isInfixOf "unable to get terminal" defErr
        || T.isInfixOf "TIOCGWINSZ" defErr
        = F3_TuiNcursesLocked

    -- Rule 2.2: TUI stdout-emitting (control bytes in stdout) — runtime signal
    | hasControlBytes defOut = F4_TuiStdoutEmitting

    -- Rule 2.3: Binary byte-exact. Two signals:
    --   (a) default probe output is itself non-printable, OR
    --   (b) help text describes compression/encoding/serialization (binary intent)
    -- (b) needed because tools like zstd dump usage text on no-args; we can't
    -- *see* the binary nature until something is actually compressed.
    | binaryRatio defOut > 0.3 || hasBinaryToolVocab helpOut = F8_BinaryByteExact

    -- Rule 2.1: Asset-dependent. Require an *asset-style* subdir name; the
    -- previous heuristic flagged any task with `data/` (e.g. cmatrix) as F12.
    -- Also try to detect "needs font/asset path" via default probe error.
    | hasAssetDir taskDirFiles
        && (assetErrorInDefault defErr || hasAssetDir taskDirFiles)
        = F12_AssetDependent

    -- Rule 2.5: HTTP client (strict — require URL/HTTPie noun phrases, not verbs)
    | hasHttpKeywords helpOut = F5_HttpClient

    -- Rule 2.6: Multi-stage pipeline
    | countSelectionFlags helpOut >= 3 = F9_MultiStagePipeline

    -- Rule 2.7: Large flag space + 厚文档
    | countFlags helpOut >= 20 && docLines >= 1000 = F10_LargeFlagSpace

    -- Rule 2.8: Format converter
    | hasFormatKeywords helpOut = F7_FormatConverter

    -- Rule 2.10: Stateful daemon (rough — keywords)
    | hasDaemonKeywords helpOut = F2_StatefulDaemon

    -- Rule 2.4: Silent linter detection.
    -- Decision: if no-args is silent AND help does NOT mention stdin/filter/convert
    -- behavior, classify as F6. Linter-vocab keywords boost confidence but aren't
    -- strictly required (errcheck's Go-flag help has neither stdin nor 'linter'
    -- words). The negative test on hasFilterVocab is the key discriminator.
    | T.null (T.strip defOut) && T.null (T.strip defErr) && not (hasFilterVocab helpOut)
        = F6_SilentLinter

    -- Rule 2.9: Structured linter (file:line:col output pattern)
    -- We can't see this from just help; this needs a follow-up probe with input.
    -- Default to F1 here; agent can re-classify later.
    | otherwise = F1_PureFunction


-- Strategy = function of total doc volume (methodology §0.1).
chooseStrategy :: Int -> ProbeStrategy
chooseStrategy docLines
    | docLines >= 1000 = StrategyLandscape
    | docLines >= 200  = StrategyHybrid
    | otherwise        = StrategyDiscovery


-- Count lines across all *.md / README* / GUIDE* / FAQ* / *.6 / *.1 in task dir.
countDocLines :: FilePath -> IO Int
countDocLines taskDir = do
    items <- listDirectory taskDir
    let docs = filter isDoc items
    sums <- mapM countFile docs
    pure (sum sums)
  where
    countFile f = do
        let p = taskDir </> f
        exists <- doesFileExist p
        if exists
            then do
                t <- TIO.readFile p
                pure (length (T.lines t))
            else pure 0
    isDoc f =
        takeExtension f `elem` [".md", ".markdown", ".rst", ".txt", ".6", ".1", ".5"]
        || takeWhile (/= '.') f `elem` ["README", "Readme", "readme", "GUIDE", "FAQ"]


-- ---------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------

-- Methodology §2.1: asset-style subdir in task dir.
-- DROPPED "data" — too generic; many tasks have data/ for unrelated reasons
-- (e.g. cmatrix's data/img/ has demo screenshots).
hasAssetDir :: [FilePath] -> Bool
hasAssetDir files =
    any (`elem` files) ["assets", "fonts", "templates", "dict", "samples"]


-- Does the default-probe stderr look like "couldn't open font/asset"?
-- (Currently a placeholder — actual detection requires probe content.)
assetErrorInDefault :: Text -> Bool
assetErrorInDefault defErr =
    any (`T.isInfixOf` defErr)
        [ "Unable to open font", "no such file or directory"
        , "Unable to open control", "default font"
        ]


-- Help vocab indicating a binary-byte-exact tool (compressor / encoder /
-- serializer / image processor). These tools produce non-printable output
-- by design.
hasBinaryToolVocab :: Text -> Bool
hasBinaryToolVocab t =
    let l = T.toLower t
    in any (`T.isInfixOf` l)
        [ "compress", "decompress", "encode", "decode"
        , "encrypt", "decrypt", "checksum", "hash"
        , "encoding", "encoded as", "byte-level"
        , ".zst", ".gz", ".xz", ".lz4", ".tar"
        ]


-- Methodology §2.2: control bytes in output suggest TUI.
hasControlBytes :: Text -> Bool
hasControlBytes t =
    T.length (T.take 4096 t) > 0
    && T.any (\c -> let o = fromEnum c in o < 32 && c /= '\n' && c /= '\t' && c /= '\r') t


-- Heuristic for binary output (methodology §2.3, isBinary in Types).
binaryRatio :: Text -> Double
binaryRatio t =
    let s          = T.unpack (T.take 4096 t)
        total      = length s
        nonPrint   = length (filter (\c -> let o = fromEnum c in not (o >= 32 && o < 127) && c /= '\n' && c /= '\t' && c /= '\r') s)
    in if total == 0 then 0 else fromIntegral nonPrint / fromIntegral total


-- Strict HTTP-client detection. Earlier looser variants false-matched
-- `https://github.com/...` URLs and HTTP-verb-like substrings (PUT in
-- "put the output" etc). Now require an explicit URL-as-argument signal
-- AND a curl/HTTPie-style blurb in the help — both. zstd / dupl / etc.
-- have neither.
hasHttpKeywords :: Text -> Bool
hasHttpKeywords t =
    let l            = T.toLower t
        hasUrlArg    = any (`T.isInfixOf` l)
                        ["<url>", "[url]", " url ", " url:", "url ...", "[url ...]"]
        hasCurlBlurb = any (`T.isInfixOf` l)
                        [ "curl-like", "httpie", "http client", "http request"
                        , "http method", "request body", "request header"
                        ]
    in hasUrlArg && hasCurlBlurb


countSelectionFlags :: Text -> Int
countSelectionFlags helpOut =
    length $ filter isSelectionFlag (T.lines helpOut)
  where
    isSelectionFlag line =
        let stripped = T.strip line
            lower    = T.toLower stripped
        in (T.isInfixOf "-l, " stripped && T.isInfixOf "lexer" lower)
        || (T.isInfixOf "-s, " stripped && T.isInfixOf "style" lower)
        || (T.isInfixOf "-f, " stripped && (T.isInfixOf "format" lower || T.isInfixOf "font" lower))
        || T.isInfixOf "--lexer" stripped
        || T.isInfixOf "--style" stripped
        || T.isInfixOf "--formatter" stripped


countFlags :: Text -> Int
countFlags helpOut =
    length $ filter isFlagLine (T.lines helpOut)
  where
    isFlagLine line =
        let stripped = T.dropWhile (== ' ') line
        in T.length stripped > 1 && T.head stripped == '-'


hasFormatKeywords :: Text -> Bool
hasFormatKeywords t =
    let l = T.toLower t
        formats = ["yaml", "json", "toml", "hcl", "xml", "csv"]
        hits    = length [f | f <- formats, T.isInfixOf f l]
    in hits >= 3 && (T.isInfixOf "convert" l || T.isInfixOf "to " l)


hasDaemonKeywords :: Text -> Bool
hasDaemonKeywords t =
    let l = T.toLower t
    in any (`T.isInfixOf` l) ["watch", "listen", "event", "trigger", "monitor", "notify"]


-- F6 silent linter / static analyzer indicators in help text.
hasLinterVocab :: Text -> Bool
hasLinterVocab t =
    let l = T.toLower t
    in any (`T.isInfixOf` l)
        [ "linter", "static analysis", "static analyser", "static analyzer"
        , "checker", "lint ", "analyz", "scanner", "auditor"
        , "checks for", "detect ", "find ignored", "find issues"
        , "vet", "errcheck", "ripsecrets", "find secrets", "find clones"
        , "find dupl"
        ]


-- Indicators that a tool is a stdin → stdout filter / formatter (F1, not F6).
hasFilterVocab :: Text -> Bool
hasFilterVocab t =
    let l = T.toLower t
    in any (`T.isInfixOf` l)
        [ "syntax highlight", "highlighter", "formatter", "convert"
        , "rewrite", "transform", "replace", "filter"
        , "read from stdin", "from standard input", "stdin if no"
        , "shellcheck", "shellharden", "pretty-print", "beautif"
        ]
