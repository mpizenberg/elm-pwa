port module Main exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Pwa


port pwaIn : (Decode.Value -> msg) -> Sub msg


port pwaOut : Encode.Value -> Cmd msg


pushServerUrl : String
pushServerUrl =
    "https://push.dokploy.zidev.ovh"



-- MAIN


main : Program { isOnline : Bool, topic : String, isStandalone : Bool, platform : String } Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    pwaIn (Pwa.decodeEvent >> GotPwaEvent)



-- MODEL


type Platform
    = IOS
    | Android
    | Desktop


type alias Model =
    { isOnline : Bool
    , updateAvailable : Bool
    , installAvailable : Bool
    , isInstalled : Bool
    , justInstalled : Bool
    , installedInBrowser : Bool
    , platform : Platform
    , notificationPermission : Maybe Pwa.NotificationPermission
    , pushSubscription : Maybe Encode.Value
    , lastNotificationUrl : Maybe String
    , notificationClickCount : Int
    , vapidPublicKey : Maybe String
    , pushError : Maybe String
    , topic : String
    , notifyTitle : String
    , notifyBody : String
    , notifySent : Maybe Bool
    }


parsePlatform : String -> Platform
parsePlatform str =
    case str of
        "ios" ->
            IOS

        "android" ->
            Android

        _ ->
            Desktop


init : { isOnline : Bool, topic : String, isStandalone : Bool, platform : String } -> ( Model, Cmd Msg )
init flags =
    ( { isOnline = flags.isOnline
      , updateAvailable = False
      , installAvailable = False
      , isInstalled = flags.isStandalone
      , justInstalled = False
      , installedInBrowser = False
      , platform = parsePlatform flags.platform
      , notificationPermission = Nothing
      , pushSubscription = Nothing
      , lastNotificationUrl = Nothing
      , notificationClickCount = 0
      , vapidPublicKey = Nothing
      , pushError = Nothing
      , topic = flags.topic
      , notifyTitle = ""
      , notifyBody = ""
      , notifySent = Nothing
      }
    , fetchVapidKey
    )



-- UPDATE


type Msg
    = GotPwaEvent (Result Decode.Error Pwa.Event)
    | AcceptUpdate
    | RequestInstall
    | RequestNotificationPermission
    | SubscribePush
    | UnsubscribePush
    | GotVapidKey (Result Http.Error String)
    | SubscriptionRegistered (Result Http.Error ())
    | SubscriptionUnregistered (Result Http.Error ())
    | SetNotifyTitle String
    | SetNotifyBody String
    | SendTestNotification
    | DismissInstallBanner
    | NotificationSent (Result Http.Error ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotPwaEvent (Ok event) ->
            case event of
                Pwa.ConnectionChanged online ->
                    ( { model | isOnline = online }, Cmd.none )

                Pwa.UpdateAvailable ->
                    ( { model | updateAvailable = True }, Cmd.none )

                Pwa.InstallAvailable ->
                    ( { model | installAvailable = True }, Cmd.none )

                Pwa.Installed ->
                    ( { model | installAvailable = False, isInstalled = True, justInstalled = True }, Cmd.none )

                Pwa.InstalledInBrowser ->
                    ( { model | installedInBrowser = True }, Cmd.none )

                Pwa.NotificationPermissionChanged permission ->
                    ( { model | notificationPermission = Just permission }, Cmd.none )

                Pwa.PushSubscription subscription ->
                    ( { model | pushSubscription = Just subscription, pushError = Nothing }
                    , registerSubscription model.topic subscription
                    )

                Pwa.PushSubscriptionError error ->
                    ( { model | pushError = Just error }, Cmd.none )

                Pwa.PushUnsubscribed ->
                    let
                        endpoint =
                            model.pushSubscription
                                |> Maybe.andThen
                                    (\sub ->
                                        Decode.decodeValue (Decode.field "endpoint" Decode.string) sub
                                            |> Result.toMaybe
                                    )
                    in
                    ( { model | pushSubscription = Nothing }
                    , case endpoint of
                        Just ep ->
                            unregisterSubscription ep

                        Nothing ->
                            Cmd.none
                    )

                Pwa.NotificationClicked url ->
                    ( { model | lastNotificationUrl = Just url, notificationClickCount = model.notificationClickCount + 1 }, Cmd.none )

        GotPwaEvent (Err _) ->
            ( model, Cmd.none )

        AcceptUpdate ->
            ( model, Pwa.acceptUpdate pwaOut )

        DismissInstallBanner ->
            ( { model | justInstalled = False }, Cmd.none )

        RequestInstall ->
            ( model, Pwa.requestInstall pwaOut )

        RequestNotificationPermission ->
            ( model, Pwa.requestNotificationPermission pwaOut )

        SubscribePush ->
            case model.vapidPublicKey of
                Just key ->
                    ( model, Pwa.subscribePush pwaOut key )

                Nothing ->
                    ( { model | pushError = Just "VAPID key not loaded yet" }, Cmd.none )

        UnsubscribePush ->
            ( model, Pwa.unsubscribePush pwaOut )

        GotVapidKey (Ok key) ->
            ( { model | vapidPublicKey = Just key }, Cmd.none )

        GotVapidKey (Err _) ->
            ( { model | pushError = Just "Failed to fetch VAPID key" }, Cmd.none )

        SubscriptionRegistered (Ok _) ->
            ( model, Cmd.none )

        SubscriptionRegistered (Err _) ->
            ( { model | pushError = Just "Failed to register subscription with server" }, Cmd.none )

        SubscriptionUnregistered _ ->
            ( model, Cmd.none )

        SetNotifyTitle title ->
            ( { model | notifyTitle = title, notifySent = Nothing }, Cmd.none )

        SetNotifyBody body ->
            ( { model | notifyBody = body, notifySent = Nothing }, Cmd.none )

        SendTestNotification ->
            ( model, sendTestNotification model.topic model.notifyTitle model.notifyBody )

        NotificationSent (Ok _) ->
            ( { model | notifySent = Just True }, Cmd.none )

        NotificationSent (Err _) ->
            ( { model | notifySent = Just False }, Cmd.none )



-- HTTP


fetchVapidKey : Cmd Msg
fetchVapidKey =
    Http.get
        { url = pushServerUrl ++ "/vapid-public-key"
        , expect =
            Http.expectJson GotVapidKey
                (Decode.field "vapidPublicKey" Decode.string)
        }


registerSubscription : String -> Encode.Value -> Cmd Msg
registerSubscription topic subscription =
    Http.post
        { url = pushServerUrl ++ "/subscriptions"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "subscription", subscription )
                    , ( "topic", Encode.string topic )
                    ]
                )
        , expect = Http.expectWhatever SubscriptionRegistered
        }


sendTestNotification : String -> String -> String -> Cmd Msg
sendTestNotification topic title body =
    Http.post
        { url = pushServerUrl ++ "/topics/" ++ topic ++ "/notify"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "title", Encode.string title )
                    , ( "body", Encode.string body )
                    ]
                )
        , expect = Http.expectWhatever NotificationSent
        }


unregisterSubscription : String -> Cmd Msg
unregisterSubscription endpoint =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = pushServerUrl ++ "/subscriptions"
        , body = Http.jsonBody (Encode.object [ ( "endpoint", Encode.string endpoint ) ])
        , expect = Http.expectWhatever SubscriptionUnregistered
        , timeout = Nothing
        , tracker = Nothing
        }



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "app" ]
        [ viewUpdateBanner model.updateAvailable
        , viewInstallBanner model.justInstalled
        , viewHeader model
        , viewMain model
        , viewFooter
        ]


viewUpdateBanner : Bool -> Html Msg
viewUpdateBanner visible =
    if visible then
        div [ class "banner" ]
            [ text "A new version is available. "
            , button [ onClick AcceptUpdate ] [ text "Update now" ]
            ]

    else
        text ""


viewInstallBanner : Bool -> Html Msg
viewInstallBanner visible =
    if visible then
        div [ class "banner banner-success" ]
            [ text "App installed! You can now close this tab and open Elm PWA from your home screen. "
            , button [ onClick DismissInstallBanner ] [ text "Dismiss" ]
            ]

    else
        text ""


viewHeader : Model -> Html Msg
viewHeader model =
    header []
        [ h1 [] [ text "Elm PWA" ]
        , div [ class "status-bar" ]
            [ viewConnectionStatus model.isOnline
            , viewInstallButton model
            ]
        ]


viewConnectionStatus : Bool -> Html Msg
viewConnectionStatus isOnline =
    span
        [ class "status-badge"
        , class
            (if isOnline then
                "online"

             else
                "offline"
            )
        ]
        [ text
            (if isOnline then
                "Online"

             else
                "Offline"
            )
        ]


viewInstallButton : Model -> Html Msg
viewInstallButton model =
    if model.isInstalled then
        span [ class "status-badge installed" ] [ text "Installed" ]

    else if model.installAvailable then
        button [ class "install-btn", onClick RequestInstall ] [ text "Install App" ]

    else if model.installedInBrowser then
        span [ class "install-hint" ]
            [ text "App is installed — open it from your home screen" ]

    else
        case model.platform of
            IOS ->
                span [ class "install-hint" ]
                    [ text "To install: tap "
                    , span [ class "share-icon" ] [ text "Share" ]
                    , text " then \"Add to Home Screen\""
                    ]

            _ ->
                text ""


viewMain : Model -> Html Msg
viewMain model =
    main_ []
        [ viewPushNotifications model
        , section []
            [ h2 [] [ text "How This Works" ]
            , dl []
                [ dt [] [ text "Service Worker" ]
                , dd [] [ text "Caches the app shell (HTML, JS, CSS) for offline use. Updates are detected and offered via an in-app banner." ]
                , dt [] [ text "Web App Manifest" ]
                , dd [] [ text "Makes the app installable. Provides icons, name, and display mode for the installed experience." ]
                , dt [] [ text "Online/Offline Detection" ]
                , dd [] [ text "JS listens for online/offline events and sends status to Elm via ports." ]
                , dt [] [ text "Install Prompt" ]
                , dd [] [ text "The beforeinstallprompt event is captured in JS and forwarded to Elm, which shows an install button." ]
                , dt [] [ text "Push Notifications" ]
                , dd [] [ text "Request permission, subscribe via the Push API, and handle notification clicks — all through the same ports." ]
                ]
            ]
        ]


viewPushNotifications : Model -> Html Msg
viewPushNotifications model =
    section []
        [ h2 [] [ text "Push Notifications" ]
        , if model.platform == IOS && not model.isInstalled then
            p []
                [ text "Push notifications on iOS require the app to be installed. Tap "
                , span [ class "share-icon" ] [ text "Share" ]
                , text " then \"Add to Home Screen\" first."
                ]

          else
            div []
                [ dl []
                    [ dt [] [ text "Permission" ]
                    , dd []
                        [ text (permissionToString model.notificationPermission)
                        , case model.notificationPermission of
                            Just Pwa.Default ->
                                button [ onClick RequestNotificationPermission, style "margin-left" "8px" ]
                                    [ text "Enable Notifications" ]

                            Nothing ->
                                button [ onClick RequestNotificationPermission, style "margin-left" "8px" ]
                                    [ text "Enable Notifications" ]

                            _ ->
                                text ""
                        ]
                    , dt [] [ text "Push Subscription" ]
                    , dd []
                        [ case model.pushSubscription of
                            Just _ ->
                                span []
                                    [ text "Active "
                                    , button [ onClick UnsubscribePush ] [ text "Unsubscribe" ]
                                    ]

                            Nothing ->
                                case model.notificationPermission of
                                    Just Pwa.Granted ->
                                        button [ onClick SubscribePush ] [ text "Subscribe to Push" ]

                                    _ ->
                                        text "Not subscribed (grant notification permission first)"
                        ]
                    , dt [] [ text "Last Notification Click" ]
                    , dd []
                        [ case model.lastNotificationUrl of
                            Just url ->
                                div []
                                    [ div [] [ text ("URL: " ++ url) ]
                                    , div [] [ text ("Count: " ++ String.fromInt model.notificationClickCount) ]
                                    ]

                            Nothing ->
                                text "None"
                        ]
                    ]
                , viewSendTestNotification model
                , case model.pushError of
                    Just err ->
                        p [ style "color" "red" ] [ text err ]

                    Nothing ->
                        text ""
                ]
        ]


viewSendTestNotification : Model -> Html Msg
viewSendTestNotification model =
    case model.pushSubscription of
        Nothing ->
            text ""

        Just _ ->
            div []
                [ h3 [] [ text "Send Test Notification" ]
                , div [ class "note-input" ]
                    [ div [] [ input [ type_ "text", placeholder "Title", value model.notifyTitle, onInput SetNotifyTitle ] [] ]
                    , div [] [ input [ type_ "text", placeholder "Body", value model.notifyBody, onInput SetNotifyBody, onEnter SendTestNotification ] [] ]
                    , div [] [ button [ onClick SendTestNotification ] [ text "Send" ] ]
                    ]
                , case model.notifySent of
                    Just True ->
                        p [ style "color" "green" ] [ text "Sent!" ]

                    Just False ->
                        p [ style "color" "red" ] [ text "Failed to send" ]

                    Nothing ->
                        text ""
                ]


permissionToString : Maybe Pwa.NotificationPermission -> String
permissionToString maybePerm =
    case maybePerm of
        Nothing ->
            "Unknown"

        Just Pwa.Granted ->
            "Granted"

        Just Pwa.Denied ->
            "Denied"

        Just Pwa.Default ->
            "Default (not asked)"

        Just Pwa.Unsupported ->
            "Unsupported"


onEnter : msg -> Attribute msg
onEnter msg =
    Html.Events.on "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Enter" then
                        Decode.succeed msg

                    else
                        Decode.fail ""
                )
        )


viewFooter : Html Msg
viewFooter =
    footer []
        [ text "Elm PWA Example — See "
        , a [ href "https://github.com/mpizenberg/elm-pwa" ] [ text "README" ]
        , text " for the full guide."
        ]
