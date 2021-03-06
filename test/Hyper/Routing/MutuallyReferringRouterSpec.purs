module Hyper.Routing.MutuallyReferringRouterSpec where

import Prelude
import Control.Alt ((<|>))
import Control.Monad.Eff.Console (CONSOLE)
import Data.MediaType.Common (textHTML)
import Data.Tuple (Tuple(..))
import Hyper.Core (statusOK, StatusLineOpen, closeHeaders, writeStatus, class ResponseWriter, Conn, Middleware, ResponseEnded)
import Hyper.HTML (text)
import Hyper.Method (Method(GET))
import Hyper.Node.Assertions (bodyShouldEqual)
import Hyper.Response (class Response, respond, contentType)
import Hyper.Routing.ResourceRouter (defaultRouterFallbacks, router, linkTo, Unsupported, Supported, ResourceRecord, runRouter, handler, resource)
import Hyper.Test.TestServer (StringBody(StringBody), testStringBody, TestResponse, testResponseWriter, testBody, testHeaders, testServer)
import Test.Spec (Spec, it, describe)
import Test.Spec.Assertions (shouldEqual)


-- To have `app` and its routes be polymorphic, and still compile, we need to provide
-- some type annotations. The following alias is a handy shortcut for the resources
-- used in this test suite.

type TestResource m rw gr pr =
  forall req res c b.
  (Monad m, ResponseWriter rw m b) =>
  ResourceRecord
  m
  gr
  pr
  (Conn { url :: String, method :: Method | req } { writer :: rw StatusLineOpen | res } c)
  (Conn { url :: String, method :: Method | req } { writer :: rw ResponseEnded | res } c)


app :: forall m req res rw b c.
  (Monad m, ResponseWriter rw m b, Response m String b) =>
  Middleware
  m
  (Conn { url :: String, method :: Method | req }
        { writer :: rw StatusLineOpen | res }
        c)
  (Conn { url :: String, method :: Method | req }
        { writer :: rw ResponseEnded | res }
        c)
app = runRouter defaultRouterFallbacks (router about <|> router contact)
  where
    about :: TestResource m rw Supported Unsupported
    about =
      resource
      { path = ["about"]
      , "GET" = handler (\conn ->
                         writeStatus statusOK conn
                         >>= contentType textHTML
                         >>= closeHeaders
                         >>= respond (linkTo (contact ∷ TestResource m rw Supported Unsupported) [text "Contact Me!"]))
      }

    contact :: TestResource m rw Supported Unsupported
    contact =
      resource
      { path = ["contact"]
      , "GET" = handler (\conn ->
                          writeStatus statusOK conn
                          >>= contentType textHTML
                          >>= closeHeaders
                          >>= respond (linkTo (about ∷ TestResource m rw Supported Unsupported) [text "About Me"]))
      }


getResponse
  :: forall m.
     (Monad m, Response m String StringBody) =>
     Method ->
     String ->
     m (TestResponse StringBody)
getResponse method url =
  let conn = { request: { method: method
                        , url: url
                        }
             , response: { writer: testResponseWriter }
             , components: {}
             }
  in testServer (app conn)


spec :: forall e. Spec (console :: CONSOLE | e) Unit
spec = do
  describe "Hyper.HTML.DSL" do
    it "can linkTo an existing route" do
      response <- getResponse GET "about"
      testHeaders response `shouldEqual` [Tuple "Content-Type" "text/html"]
      testStringBody response `shouldEqual` "<a href=\"/contact\">Contact Me!</a>"

    it "can linkTo another existing route" do
      response <- getResponse GET "contact"
      testHeaders response `shouldEqual` [Tuple "Content-Type" "text/html"]
      testStringBody response `shouldEqual` "<a href=\"/about\">About Me</a>"
