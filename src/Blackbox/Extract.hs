{-# LANGUAGE OverloadedStrings #-}

-- Pure post-processing extractors for filling Belief fields.
-- Methodology §5 (library fingerprints) + §6.1 (bug-as-contract criteria).
module Blackbox.Extract
    ( extractCliFlags
    , classifyExitCode
    , bucketError
    , guessLibraries
    , detectBug
    , hexDump
    , detectMagicBytes
    , isMostlyBinary
    , detectDiagnosticFormat
    ) where

import qualified Data.Text as T
import           Data.Text (Text)
import           Data.Char (isAlpha, ord)
import           Data.List (nub)
import           Numeric (showHex)


-- ---------------------------------------------------------------
-- 2A: CLI surface extractor
-- ---------------------------------------------------------------

-- Parse `--help` output into a list of flag descriptors.
-- Conservative: keeps lines whose first non-space token starts with `-`,
-- and trims them to a single-line summary.
extractCliFlags :: Text -> [Text]
extractCliFlags helpText =
    let ls = T.lines helpText
    in nub [ T.strip l | l <- ls, isFlagLine l ]
  where
    isFlagLine line =
        let s = T.stripStart line
        in T.length s > 1
        && T.head s == '-'
        && (let c = T.index s 1 in c == '-' || isAlpha c)
        && not ("---" `T.isPrefixOf` s)


-- ---------------------------------------------------------------
-- 2B: Exit code classifier
-- ---------------------------------------------------------------

-- Map an observed exit code to its conventional meaning.
-- Notable: ≥ 128 = signal kill; ≥ 64 = sysexits.h reserved.
classifyExitCode :: Int -> Text
classifyExitCode n
    | n == 0     = "success"
    | n == 1     = "general error / usage error"
    | n == 2     = "shell builtin misuse / argv parse error"
    | n == 64    = "EX_USAGE (sysexits)"
    | n == 65    = "EX_DATAERR (sysexits)"
    | n == 66    = "EX_NOINPUT (sysexits)"
    | n == 69    = "EX_UNAVAILABLE (sysexits)"
    | n == 70    = "EX_SOFTWARE (sysexits)"
    | n == 77    = "EX_NOPERM (sysexits)"
    | n == 126   = "command found but not executable"
    | n == 127   = "command not found"
    | n == 130   = "killed by SIGINT (Ctrl-C)"
    | n == 134   = "killed by SIGABRT (abort)"
    | n == 137   = "killed by SIGKILL (oom or kill -9)"
    | n == 139   = "killed by SIGSEGV (segfault — likely BUG)"
    | n == 143   = "killed by SIGTERM"
    | n == -1    = "(synthetic: skipped by dedup)"
    | n >= 128 && n < 192 =
        "killed by signal " <> T.pack (show (n - 128)) <> " — likely BUG"
    | otherwise  = "exit " <> T.pack (show n) <> " (tool-specific)"


-- ---------------------------------------------------------------
-- 2C: Error bucket classifier
-- ---------------------------------------------------------------

-- Collapse one error message into a bucket label.
-- Returns Nothing for empty / non-error output.
bucketError :: Text -> Maybe Text
bucketError raw =
    let t = T.strip raw
        l = T.toLower t
    in if T.null t then Nothing
       else firstMatch l
            [ ("Usage:",                   "usage / help wall")
            , ("usage:",                   "usage / help wall")
            , ("error opening terminal",   "TUI: terminal init fail")
            , ("flag provided but not defined", "Go-flag: unknown flag")
            , ("flag needs an argument",   "Go-flag: missing arg")
            , ("invalid value",            "Go-flag: bad value")
            , ("unexpected argument",      "clap: unexpected arg")
            , ("no such file or directory","fs: missing file")
            , ("permission denied",        "fs: permission denied")
            , ("invalid argument",         "generic: invalid arg")
            , ("parse error",              "parser: input parse error")
            , ("unexpected end",           "parser: truncated input")
            , ("unexpected character",     "parser: bad token")
            , ("yaml:",                    "yaml.v2 error")
            , ("toml:",                    "toml parser error")
            , ("json:",                    "encoding/json error")
            , ("unable to open font",      "asset: font missing")
            , ("unable to open control",   "asset: control file missing")
            , ("read: connection reset",   "net: peer reset")
            , ("connection refused",       "net: connection refused")
            , ("no route to host",         "net: routing")
            , ("command not found",        "shell: not found")
            , ("incorrect parameter",      "zstd-style: bad parameter")
            , ("reflect: call of reflect", "BUG: yaml.v2 reflect crash")
            , ("segmentation fault",       "BUG: segfault")
            ]
  where
    firstMatch _    []           = Just (firstLine raw)  -- fall through: keep first line
    firstMatch txt ((k, v) : rs)
        | T.isInfixOf k txt = Just v
        | otherwise         = firstMatch txt rs
    firstLine = T.take 100 . T.strip . T.takeWhile (/= '\n')


-- ---------------------------------------------------------------
-- 2D: Library fingerprint matcher (methodology §5)
-- ---------------------------------------------------------------

-- Look at combined help+stderr+identity output and guess underlying libs.
guessLibraries :: Text -> [Text]
guessLibraries blob =
    let l = T.toLower blob
    in nub $ concat
        [ fingerprint l "json.exception.parse_error" "nlohmann/json (C++)"
        , fingerprint l "error parsing json"         "encoding/json (Go std)"
        , fingerprint l "toml:"                      "BurntSushi/toml (Go)"
        , fingerprint l "yaml:"                      "gopkg.in/yaml.v2 (Go)"
        , fingerprint l "error parsing hcl"          "HashiCorp hcl (Go)"
        , fingerprint l "reflect: call of reflect"   "yaml.v2 + reflect (Go) — reflect-misuse BUG"
        , fingerprint l "error opening terminal"     "ncurses"
        , fingerprint l "[?1003h"                    "FTXUI (mouse tracking)"
        , fingerprint l "[?1049h"                    "alt-buffer TUI"
        , fingerprint l "flag provided but not defined" "Go flag (std)"
        , fingerprint l "flag needs an argument"     "Go flag (std)"
        , fingerprint l "unexpected argument"        "Rust clap"
        , fingerprint l "incorrect parameter"        "zstd-style args parser"
        , fingerprint l "available commands:"        "cobra (Go)"
        , fingerprint l "check: xxh64"               "xxHash"
        , fingerprint l "user-agent: curl/"          "curl"
        , fingerprint l "server: basehttp/"          "Python http.server"
        ]
  where
    fingerprint t needle lib
        | T.isInfixOf needle t = [lib]
        | otherwise            = []


-- ---------------------------------------------------------------
-- 4A: Binary helpers — hex dump, magic byte detection (F8)
-- ---------------------------------------------------------------

-- Render the first n bytes of a Text as space-separated hex (xxd-style).
hexDump :: Int -> Text -> Text
hexDump n t =
    let bs = take n (T.unpack t)
    in T.pack $ unwords [pad (showHex (ord c) "") | c <- bs]
  where
    pad s = if length s < 2 then '0' : s else s


-- Magic-byte signature lookup — methodology §5.4.
detectMagicBytes :: Text -> Maybe Text
detectMagicBytes t = firstMatch (hexDump 8 t)
  where
    firstMatch hex
        | "28 b5 2f fd" `T.isPrefixOf` hex = Just "Zstandard frame (magic 28b52ffd)"
        | "1f 8b 08"    `T.isPrefixOf` hex = Just "gzip / zlib (magic 1f8b)"
        | "fd 37 7a 58 5a 00" `T.isPrefixOf` hex = Just "xz / liblzma (magic fd377a585a00)"
        | "04 22 4d 18" `T.isPrefixOf` hex = Just "LZ4 frame (magic 04224d18)"
        | "50 4b 03 04" `T.isPrefixOf` hex = Just "ZIP / jar (magic 504b0304)"
        | "89 50 4e 47" `T.isPrefixOf` hex = Just "PNG (magic 89504e47)"
        | "ff d8 ff"    `T.isPrefixOf` hex = Just "JPEG (magic ffd8ff)"
        | "7f 45 4c 46" `T.isPrefixOf` hex = Just "ELF binary (magic 7f454c46)"
        | otherwise                       = Nothing


-- Cheaper variant of Types.isBinary used internally.
isMostlyBinary :: Text -> Bool
isMostlyBinary t =
    let s          = T.unpack (T.take 1024 t)
        total      = length s
        nonPrint   = length (filter notPrintable s)
    in total > 16 && fromIntegral nonPrint / fromIntegral total > (0.3 :: Double)
  where
    notPrintable c =
        let o = ord c
        in not (o >= 32 && o < 127) && c /= '\n' && c /= '\t' && c /= '\r'


-- F11 structured-linter diagnostic shape recognizer.
-- Checks the first ~5 lines for canonical `file:line:col: msg` / dupl-style
-- range patterns. Returns the detected style name.
detectDiagnosticFormat :: Text -> Maybe Text
detectDiagnosticFormat t =
    let ls = filter (not . T.null) (take 5 (T.lines t))
    in case ls of
        []      -> Nothing
        (l : _)
          | isFileLineColMsg l -> Just "gcc/clang/Go-vet: <file>:<line>:<col>: <msg>"
          | isDuplRange l      -> Just "dupl/PMD-style: <file>:<startLine>,<endLine>: clone group"
          | otherwise          -> Nothing
  where
    -- "foo.go:42:5:" or "foo.cpp:42:5:"
    isFileLineColMsg line =
        let parts = T.splitOn ":" line
        in length parts >= 4
        && hasFileExt (head parts)
        && isNumText (parts !! 1)
        && isNumText (parts !! 2)
    -- "foo.go:42,67:" — comma-separated range
    isDuplRange line =
        let parts = T.splitOn ":" line
        in length parts >= 2
        && hasFileExt (head parts)
        && case T.splitOn "," (parts !! 1) of
            [a, b] -> isNumText a && isNumText b
            _      -> False
    hasFileExt s = T.isInfixOf "." s && T.length s < 80
    isNumText s  = not (T.null s) && T.all (\c -> c >= '0' && c <= '9') s


-- ---------------------------------------------------------------
-- 2E: Bug-as-contract detector (methodology §6.1)
-- ---------------------------------------------------------------

-- Given an exit code and stderr, decide if this looks like a bug.
detectBug :: Int -> Text -> Maybe Text
detectBug exitCode stderrTxt
    | exitCode >= 128 && exitCode < 192 =
        Just $ "exit " <> T.pack (show exitCode)
             <> " (signal " <> T.pack (show (exitCode - 128)) <> ") — segfault/abort"
    | "reflect: call of reflect" `T.isInfixOf` low =
        Just "yaml.v2 reflect-misuse crash (zero-Value)"
    | "sytactic" `T.isInfixOf` low =
        Just "typo in error message: 'sytactic' (sic)"
    | "<>" `T.isInfixOf` stderrTxt
      && ("entr" `T.isInfixOf` low
          || ("filename" `T.isInfixOf` low && T.isInfixOf "<>" stderrTxt) ) =
        Just "empty placeholder slot <> in error template"
    | otherwise = Nothing
  where
    low = T.toLower stderrTxt
