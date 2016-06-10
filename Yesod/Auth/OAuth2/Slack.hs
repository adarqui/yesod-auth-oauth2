{-# LANGUAGE OverloadedStrings #-}
--
-- OAuth2 plugin for Slack
module Yesod.Auth.OAuth2.Slack
    ( SlackScope(..)
    , oauth2Slack
    , oauth2SlackScoped
    ) where

import Data.Aeson
import Yesod.Auth
import Yesod.Auth.OAuth2

import Control.Exception.Lifted (throwIO)
import Data.Maybe (catMaybes)
import Data.Monoid ((<>))
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Network.HTTP.Conduit (Manager)

import qualified Data.Text as Text
import qualified Network.HTTP.Conduit as HTTP

data SlackScope
    = SlackEmailScope
    | SlackTeamScope
    | SlackAvatarScope

data SlackUser = SlackUser
    { slackUserId :: Text
    , slackUserName :: Text
    , slackUserEmail :: Maybe Text
    , slackUserAvatar :: Maybe Text
    }

instance FromJSON SlackUser where
    parseJSON = withObject "root" $ \root ->
        root .: "user" >>= withObject "user"
            ( \user ->
                SlackUser
                    <$> user .: "id"
                    <*> user .: "name"
                    <*> user .:? "email"
                    <*> user .:? "image_512"
            )

oauth2Slack :: YesodAuth m
             => Text -- ^ Client ID
             -> Text -- ^ Client Secret
             -> AuthPlugin m
oauth2Slack clientId clientSecret = oauth2SlackScoped clientId clientSecret []

oauth2SlackScoped :: YesodAuth m
             => Text -- ^ Client ID
             -> Text -- ^ Client Secret
             -> [SlackScope]
             -> AuthPlugin m
oauth2SlackScoped clientId clientSecret scopes =
    authOAuth2 "slack" oauth fetchSlackProfile
  where
    oauth = OAuth2
        { oauthClientId = encodeUtf8 clientId
        , oauthClientSecret = encodeUtf8 clientSecret
        , oauthOAuthorizeEndpoint =
            encodeUtf8
            $ "https://slack.com/oauth/authorize?scope="
            <> Text.intercalate "," scopeTexts
        , oauthAccessTokenEndpoint = "https://slack.com/api/oauth.access"
        , oauthCallback = Nothing
        }
    scopeTexts = "identity.basic":map scopeText scopes

scopeText :: SlackScope -> Text
scopeText SlackEmailScope = "identity.email"
scopeText SlackTeamScope = "identity.team"
scopeText SlackAvatarScope = "identity.avatar"

fetchSlackProfile :: Manager -> AccessToken -> IO (Creds m)
fetchSlackProfile manager token = do
    request
        <- HTTP.setQueryString [("token", Just $ accessToken token)]
        <$> HTTP.parseUrl "https://slack.com/api/users.identity"
    body <- HTTP.responseBody <$> HTTP.httpLbs request manager
    case eitherDecode body of
        Left _ -> throwIO $ InvalidProfileResponse "slack" body
        Right u -> return $ toCreds u token

toCreds :: SlackUser -> AccessToken -> Creds m
toCreds user token = Creds
    { credsPlugin = "slack"
    , credsIdent = slackUserId user
    , credsExtra = catMaybes
        [ Just ("name", slackUserName user)
        , Just ("access_token", decodeUtf8 $ accessToken token)
        , (,) <$> pure "email" <*> slackUserEmail user
        , (,) <$> pure "avatar" <*> slackUserAvatar user
        ]
    }
