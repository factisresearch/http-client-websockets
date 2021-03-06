{-# LANGUAGE LambdaCase #-}

-- | Glue code for [http-client](https://hackage.haskell.org/package/http-client)
--   and [websockets](https://hackage.haskell.org/package/websockets).
--
--   This module is intended to be imported @qualified@.
--
--   If you want to use TLS-secured WebSockets (via the @wss@ scheme)
--   you need to supply a 'Manager' which supports TLS, for example
--   from [http-client-tls](https://hackage.haskell.org/package/http-client-tls)
--   or [http-client-openssl](https://hackage.haskell.org/package/http-client-openssl).
--
--   == Example
--   >>> :set -XOverloadedStrings
--   >>> :set -XQuasiQuotes
--   >>>
--   >>> import Network.HTTP.Client (Manager, newManager, defaultManagerSettings)
--   >>> import qualified Network.WebSockets as WS
--   >>> import qualified Network.HTTP.Client.WebSockets as HCWS
--   >>> import Network.URI.Static
--   >>> import Data.ByteString (ByteString)
--   >>>
--   >>> :{
--       runEchoExample :: Manager -> IO ByteString
--       runEchoExample mgr = HCWS.runClient mgr echoUri $ \conn -> do
--           WS.sendTextData conn ("hello there" :: ByteString)
--           msg <- WS.receiveData conn
--           pure (msg :: ByteString)
--         where
--           echoUri = [uri|ws://echo.websocket.org|]
--   :}
--
--   >>> -- this Manager does not support TLS, so we can't use the wss scheme above
--   >>> newManager defaultManagerSettings >>= runEchoExample
--   "hello there"
module Network.HTTP.Client.WebSockets
  ( runClient,
    runClientWith,
  )
where

import qualified Codec.Binary.UTF8.Generic as UTF8
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.Internal as HTTP
import Network.URI (URI (..))
import qualified Network.WebSockets as WS
import qualified Network.WebSockets.Stream as WS

runClient ::
  -- | 'HTTP.Manager' to use to establish the connection
  HTTP.Manager ->
  -- | 'URI' to connect to. Only the schemes @ws@ and @wss@ are valid.
  URI ->
  -- | Client application
  WS.ClientApp a ->
  IO a
runClient mgr uri = runClientWith mgr uri WS.defaultConnectionOptions []

runClientWith ::
  -- | 'HTTP.Manager' to use to establish the connection
  HTTP.Manager ->
  -- | 'URI' to connect to. Only the schemes @ws@ and @wss@ are valid.
  URI ->
  -- | Options
  WS.ConnectionOptions ->
  -- | Custom headers to send
  WS.Headers ->
  -- | Client application
  WS.ClientApp a ->
  IO a
runClientWith mgr uri connOpts headers app = do
  httpScheme <- case uriScheme uri of
    "ws:" -> pure "http:"
    "wss:" -> pure "https:"
    s -> fail $ "invalid WebSockets scheme: " <> s
  req <- HTTP.requestFromURI uri {uriScheme = httpScheme}
  HTTP.withConnection req mgr $ \conn -> do
    let read = do
          bs <- HTTP.connectionRead conn
          pure $ if B.null bs then Nothing else Just bs
        write = \case
          Nothing -> HTTP.connectionClose conn
          Just bs -> HTTP.connectionWrite conn $ LB.toStrict bs
    stream <- WS.makeStream read write
    WS.runClientWithStream
      stream
      (UTF8.toString $ HTTP.host req)
      (UTF8.toString $ HTTP.path req <> HTTP.queryString req)
      connOpts
      headers
      app
