{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Minimal Deepseek client. Single-call request/response.
module Blackbox.LLM
    ( Message (..)
    , LLMRequest (..)
    , defaultRequest
    , callChat
    ) where

import           Control.Exception (try, SomeException)
import qualified Data.Aeson as A
import           Data.Aeson ((.=))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import           Data.Text (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import           Network.HTTP.Client
                    ( Manager, Request, parseRequest, requestBody, requestHeaders
                    , method, RequestBody (..), httpLbs, responseBody, newManager
                    )
import           Network.HTTP.Client.TLS (tlsManagerSettings)
import           Network.HTTP.Types.Header (hContentType)


data Message = Message
    { msgRole    :: Text   -- "system" | "user" | "assistant"
    , msgContent :: Text
    }
    deriving (Eq, Show)


instance A.ToJSON Message where
    toJSON m = A.object
        [ "role"    .= msgRole m
        , "content" .= msgContent m
        ]


data LLMRequest = LLMRequest
    { reqMessages    :: [Message]
    , reqModel       :: Text
    , reqMaxTokens   :: Int
    , reqTemperature :: Double
    }
    deriving (Eq, Show)


defaultRequest :: [Message] -> LLMRequest
defaultRequest msgs = LLMRequest
    { reqMessages    = msgs
    , reqModel       = "deepseek-chat"
    , reqMaxTokens   = 2000
    , reqTemperature = 0.0
    }


-- Call Deepseek's OpenAI-compatible chat completions endpoint.
-- Returns the assistant's content. On any error returns "" — caller decides.
callChat :: Text -> LLMRequest -> IO Text
callChat apiKey req = do
    mgrR <- try (newManager tlsManagerSettings) :: IO (Either SomeException Manager)
    case mgrR of
        Left _    -> pure ""
        Right mgr -> doCall mgr
  where
    doCall mgr = do
        let body = A.object
                [ "model"       .= reqModel req
                , "messages"    .= reqMessages req
                , "max_tokens"  .= reqMaxTokens req
                , "temperature" .= reqTemperature req
                , "stream"      .= False
                ]
            bodyBs = A.encode body
        initReqE <- try (parseRequest "https://api.deepseek.com/chat/completions")
                 :: IO (Either SomeException Request)
        case initReqE of
            Left _ -> pure ""
            Right initReq -> do
                let r = initReq
                        { method         = "POST"
                        , requestHeaders =
                            [ (hContentType, "application/json")
                            , ("Authorization", TE.encodeUtf8 ("Bearer " <> apiKey))
                            ]
                        , requestBody    = RequestBodyLBS bodyBs
                        }
                respE <- try (httpLbs r mgr)
                case respE of
                    Left (_ :: SomeException) -> pure ""
                    Right resp -> case A.decode (responseBody resp) of
                        Just (A.Object o) -> pure (extractContent o)
                        _                 -> pure ""


-- Extract assistant content from a parsed response object.
extractContent :: A.Object -> Text
extractContent o =
    case KM.lookup "choices" o of
        Just (A.Array v) | not (V.null v) ->
            case V.head v of
                A.Object choice ->
                    case KM.lookup "message" choice of
                        Just (A.Object msg) ->
                            case KM.lookup "content" msg of
                                Just (A.String s) -> s
                                _ -> ""
                        _ -> ""
                _ -> ""
        _ -> ""
