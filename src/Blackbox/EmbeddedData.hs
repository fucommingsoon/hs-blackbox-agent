{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- Embeds the distilled methodology document into the binary at compile time.
-- The methodology is the agent's only reference — see anti-cheating manifest in README.
module Blackbox.EmbeddedData
    ( embeddedMethodology
    ) where

import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import           Data.FileEmbed (embedFile)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import           Data.Text (Text)


-- The full distill v1 document, decoded as Text.
-- ~32 KB, ~920 lines.
embeddedMethodology :: Text
embeddedMethodology = TE.decodeUtf8 embeddedMethodologyBytes


embeddedMethodologyBytes :: ByteString
embeddedMethodologyBytes = $(embedFile "data/methodology.md")
