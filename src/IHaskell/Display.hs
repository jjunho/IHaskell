{-# LANGUAGE NoImplicitPrelude, OverloadedStrings, FlexibleInstances #-}

-- | If you are interested in the IHaskell library for the purpose of augmenting the IHaskell
-- notebook or writing your own display mechanisms and widgets, this module contains all functions
-- you need.
--
-- In order to create a display mechanism for a particular data type, write a module named (for
-- example) @IHaskell.Display.YourThing@ in a package named @ihaskell-yourThing@. (Note the
-- capitalization - it's important!) Then, in that module, add an instance of @IHaskellDisplay@ for
-- your data type. Similarly, to create a widget, add an instance of @IHaskellWidget@.
--
-- An example of creating a display is provided in the
-- <http://gibiansky.github.io/IHaskell/demo.html demo notebook>.
--
module IHaskell.Display (
    -- * Rich display and interactive display typeclasses and types
    IHaskellDisplay(..),
    Display(..),
    DisplayData(..),
    IHaskellWidget(..),

    -- ** Interactive use functions
    printDisplay,

    -- * Constructors for displays
    plain,
    html,
    html',
    bmp,
    png,
    jpg,
    gif,
    svg,
    latex,
    markdown,
    javascript,
    json,
    vega,
    vegalite,
    vdom,
    widgetdisplay,
    custom,
    many,

    -- ** Image and data encoding functions
    Width,
    Height,
    Base64,
    encode64,
    base64,

    -- * Internal only use
    displayFromChan,
    serializeDisplay,
    Widget(..),

    -- ** Channel management (for kernel use)
    getDisplayChan,
    setDisplayChan,
    resetDisplayChan,
    ) where

import           IHaskellPrelude
import qualified Data.Text as T
import qualified Data.ByteString.Char8 as CBS
import qualified Data.ByteString.Lazy as LBS

import           Data.Binary as Binary
import qualified Data.ByteString.Base64 as Base64

import           Control.Concurrent.STM (atomically)
import           Control.Concurrent.STM.TChan
import           Data.IORef (IORef, newIORef, readIORef, atomicWriteIORef)
import           System.IO.Unsafe (unsafePerformIO)

import qualified Data.Text.Encoding as E

import           IHaskell.Eval.Util (unfoldM)
import           IHaskell.Types
import           StringUtils (rstrip)

type Base64 = Text

-- | Encode many displays into a single one. All will be output.
many :: [Display] -> Display
many = ManyDisplay

-- | Generate a plain text display.
plain :: String -> DisplayData
plain = DisplayData PlainText . T.pack . rstrip

-- | Generate an HTML display.
html :: String -> DisplayData
html = html' Nothing

-- | Generate an HTML display with optional styles.
html' :: Maybe Text -> String -> DisplayData
html' maybeStyles s = DisplayData MimeHtml $ case maybeStyles of
  Just css -> mconcat ["<style>", css, "</style>", T.pack s]
  Nothing -> T.pack s

-- | Generate an SVG display.
svg :: T.Text -> DisplayData
svg = DisplayData MimeSvg

-- | Generate a LaTeX display.
latex :: String -> DisplayData
latex = DisplayData MimeLatex . T.pack

-- | Generate a Javascript display.
javascript :: String -> DisplayData
javascript = DisplayData MimeJavascript . T.pack

-- | Generate a Json display.
json :: String -> DisplayData
json = DisplayData MimeJson . T.pack

-- | Generate a Vega display.
vega :: String -> DisplayData
vega = DisplayData MimeVega . T.pack

-- | Generate a Vegalite display.
vegalite :: String -> DisplayData
vegalite = DisplayData MimeVegalite . T.pack

-- | Generate a Vdom display.
vdom :: String -> DisplayData
vdom = DisplayData MimeVdom . T.pack

-- | Generate a custom display. The first argument is the mimetype and the second argument is the
-- payload.
custom :: T.Text -> String -> DisplayData
custom mimetype = DisplayData (MimeCustom mimetype) . T.pack

-- | Generate a Markdown display.
markdown :: String -> DisplayData
markdown = DisplayData MimeMarkdown . T.pack

-- | Generate a GIF display of the given width and height. Data must be provided in a Base64 encoded
-- manner, suitable for embedding into HTML. The @base64@ function may be used to encode data into
-- this format.
gif :: Width -> Height -> Base64 -> DisplayData
gif width height = DisplayData (MimeGif width height)

-- | Generate a BMP display of the given width and height. Data must be provided in a Base64 encoded
-- manner, suitable for embedding into HTML. The @base64@ function may be used to encode data into
-- this format.
bmp :: Width -> Height -> Base64 -> DisplayData
bmp width height = DisplayData (MimeBmp width height)

-- | Generate a PNG display of the given width and height. Data must be provided in a Base64 encoded
-- manner, suitable for embedding into HTML. The @base64@ function may be used to encode data into
-- this format.
png :: Width -> Height -> Base64 -> DisplayData
png width height = DisplayData (MimePng width height)

-- | Generate a JPG display of the given width and height. Data must be provided in a Base64 encoded
-- manner, suitable for embedding into HTML. The @base64@ function may be used to encode data into
-- this format.
jpg :: Width -> Height -> Base64 -> DisplayData
jpg width height = DisplayData (MimeJpg width height)

-- | Generate a Widget display given the uuid and the view version
widgetdisplay :: String -> DisplayData
widgetdisplay = DisplayData MimeWidget .T.pack

-- | Convert from a string into base 64 encoded data.
encode64 :: String -> Base64
encode64 str = base64 $ CBS.pack str

-- | Convert from a ByteString into base 64 encoded data.
base64 :: ByteString -> Base64
base64 = E.decodeUtf8 . Base64.encode

-- | For internal use within IHaskell. Serialize displays to a ByteString.
serializeDisplay :: Display -> LBS.ByteString
serializeDisplay = Binary.encode

-- | Items written to this chan will be included in the output sent to the frontend (ultimately the
-- browser), the next time IHaskell has an item to display.
--
-- The channel is stored in an 'IORef' so that the kernel can replace it for
-- testing or re-initialization without relying on 'unsafePerformIO' semantics.
{-# NOINLINE displayChanRef #-}
displayChanRef :: IORef (TChan Display)
displayChanRef = unsafePerformIO $ newIORef =<< newTChanIO

-- | Get the current display channel.
getDisplayChan :: IO (TChan Display)
getDisplayChan = readIORef displayChanRef

-- | Replace the display channel (for testing or kernel re-initialization).
setDisplayChan :: TChan Display -> IO ()
setDisplayChan = atomicWriteIORef displayChanRef

-- | Create a fresh display channel and use it (for kernel re-initialization).
resetDisplayChan :: IO ()
resetDisplayChan =
  newTChanIO >>= atomicWriteIORef displayChanRef

-- | Take everything that was put into the display channel at that point out,
-- and return the accumulated 'Display'.
displayFromChan :: IO Display
displayFromChan = do
  chan <- readIORef displayChanRef
  many <$> unfoldM (atomically $ tryReadTChan chan)

-- | Write to the display channel. The contents will be displayed in the notebook once the current
-- execution call ends.
printDisplay :: IHaskellDisplay a => a -> IO ()
printDisplay disp = do
  chan <- readIORef displayChanRef
  display disp >>= atomically . writeTChan chan
