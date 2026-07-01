{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Fixture
    ( FixtureState (..)
    , setupFixtures
    ) where

import           Control.Concurrent (threadDelay)
import           Control.Exception  (IOException, catch)
import           Control.Monad      (foldM, when)
import qualified Data.Text          as T
import           Data.Text          (Text)
import qualified Data.Text.IO       as TIO
import           System.Directory   (createDirectoryIfMissing)
import           System.FilePath    ((</>), takeDirectory)
import           System.IO          (BufferMode (..), Handle, hGetLine,
                                      hSetBuffering)
import           System.Process     (CreateProcess (..), StdStream (..),
                                      proc, createProcess, terminateProcess)
import           System.Timeout     (timeout)

import           Blackbox.DTC
import           Blackbox.DTC.Env


data FixtureState = FixtureState
    { fsEnv         :: DtcEnv
    , fsUnsupported :: [Text]
    , fsCleanup     :: IO ()
    }


setupFixtures :: DtcEnv -> [FixtureAction] -> IO FixtureState
setupFixtures env actions =
    foldM apply initial actions
  where
    initial = FixtureState env [] (pure ())

    apply state action =
        case action of
            TouchFile path -> do
                let env' = fsEnv state
                    expanded = expandPath env' path
                ensureParent expanded
                TIO.writeFile expanded ""
                pure state
            WriteFileText path txt -> do
                let env' = fsEnv state
                    expanded = expandPath env' path
                ensureParent expanded
                TIO.writeFile expanded (expandText env' txt)
                pure state
            AppendFileText path txt -> do
                let env' = fsEnv state
                    expanded = expandPath env' path
                ensureParent expanded
                TIO.appendFile expanded (expandText env' txt)
                pure state
            SleepMs ms -> do
                threadDelay (ms * 1000)
                pure state
            StartHttpFixture routes -> do
                httpState <- startHttpFixture (fsEnv state) routes
                pure state
                    { fsEnv = fsEnv httpState
                    , fsUnsupported = fsUnsupported state <> fsUnsupported httpState
                    , fsCleanup = fsCleanup state >> fsCleanup httpState
                    }


startHttpFixture :: DtcEnv -> [HttpRoute] -> IO FixtureState
startHttpFixture env routes =
    case dePort env of
        Just _ ->
            pure FixtureState
                { fsEnv = env
                , fsUnsupported = ["fixture backend unsupported: multiple http fixtures"]
                , fsCleanup = pure ()
                }
        Nothing -> do
            let scriptPath = deWorkDir env </> "http_fixture.py"
            TIO.writeFile scriptPath (fixtureScript routes)
            (_mIn, mOut, _mErr, ph) <- createProcess (proc "python3" [scriptPath])
                { std_in = NoStream
                , std_out = CreatePipe
                , std_err = Inherit
                }
            mapM_ (`hSetBuffering` LineBuffering) mOut
            mLine <- case mOut of
                Nothing -> pure Nothing
                Just h  -> timeout 2000000 (safeGetLine h)
            case mLine >>= parsePort of
                Nothing -> do
                    terminateProcess ph
                    pure FixtureState
                        { fsEnv = env
                        , fsUnsupported = ["fixture backend failed: http port unavailable"]
                        , fsCleanup = pure ()
                        }
                Just port ->
                    pure FixtureState
                        { fsEnv = env { dePort = Just port }
                        , fsUnsupported = []
                        , fsCleanup = terminateProcess ph
                        }

fixtureScript :: [HttpRoute] -> Text
fixtureScript routes = T.unlines
    [ "import http.server"
    , "import socketserver"
    , ""
    , "ROUTES = ["
    , T.concat (map routeLine routes)
    , "]"
    , ""
    , "class Handler(http.server.BaseHTTPRequestHandler):"
    , "    def log_message(self, fmt, *args):"
    , "        pass"
    , ""
    , "    def _handle(self):"
    , "        full_path = self.path"
    , "        request_path = full_path.split('?', 1)[0]"
    , "        length = int(self.headers.get('Content-Length', '0'))"
    , "        request_body = b''"
    , "        if length:"
    , "            request_body = self.rfile.read(length)"
    , "        request_body_text = request_body.decode('utf-8', errors='ignore')"
    , "        headers_text = '\\n'.join(f'{k}: {v}' for k, v in self.headers.items()).lower()"
    , "        for method, path, status, body, content_type, path_needles, header_needles, body_needles in ROUTES:"
    , "            if self.command == method and request_path == path and all(needle in full_path for needle in path_needles) and all(needle.lower() in headers_text for needle in header_needles) and all(needle in request_body_text for needle in body_needles):"
    , "                payload = body.encode('utf-8')"
    , "                self.send_response(status)"
    , "                self.send_header('Content-Type', content_type)"
    , "                self.send_header('Content-Length', str(len(payload)))"
    , "                self.end_headers()"
    , "                self.wfile.write(payload)"
    , "                return"
    , "        payload = b'{\"error\":\"not found\"}\\n'"
    , "        self.send_response(404)"
    , "        self.send_header('Content-Type', 'application/json')"
    , "        self.send_header('Content-Length', str(len(payload)))"
    , "        self.end_headers()"
    , "        self.wfile.write(payload)"
    , ""
    , "    def do_GET(self):"
    , "        self._handle()"
    , "    def do_POST(self):"
    , "        self._handle()"
    , "    def do_PUT(self):"
    , "        self._handle()"
    , "    def do_PATCH(self):"
    , "        self._handle()"
    , "    def do_DELETE(self):"
    , "        self._handle()"
    , "    def do_OPTIONS(self):"
    , "        self._handle()"
    , ""
    , "with socketserver.TCPServer(('127.0.0.1', 0), Handler) as httpd:"
    , "    print(httpd.server_address[1], flush=True)"
    , "    httpd.serve_forever()"
    ]
  where
    routeLine route =
        T.concat
            [ "    ("
            , pyString (hrMethod route)
            , ", "
            , pyString (hrPath route)
            , ", "
            , T.pack (show (hrStatus route))
            , ", "
            , pyString (hrBody route)
            , ", "
            , pyString (hrResponseContentType route)
            , ", "
            , pyList (hrRequestPathNeedles route)
            , ", "
            , pyList (hrRequestHeaderNeedles route)
            , ", "
            , pyList (hrRequestBodyNeedles route)
            , "),\n"
            ]


pyString :: Text -> Text
pyString =
    T.pack . show . T.unpack


pyList :: [Text] -> Text
pyList values =
    "[" <> T.intercalate ", " (map pyString values) <> "]"


parsePort :: String -> Maybe Int
parsePort s =
    case reads s of
        [(n, "")] -> Just n
        _         -> Nothing


safeGetLine :: Handle -> IO String
safeGetLine h =
    hGetLine h `catch` onIo
  where
    onIo :: IOException -> IO String
    onIo _ = pure ""


ensureParent :: FilePath -> IO ()
ensureParent path =
    when (not (null dir) && dir /= ".") $
        createDirectoryIfMissing True dir
  where
    dir = takeDirectory path
