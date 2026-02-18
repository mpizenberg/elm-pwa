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


main : Program Bool Model Msg
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


type alias Model =
    { isOnline : Bool
    , updateAvailable : Bool
    , installAvailable : Bool
    , isInstalled : Bool
    , notes : List String
    , draft : String
    , notificationPermission : Maybe Pwa.NotificationPermission
    , pushSubscription : Maybe Encode.Value
    , lastNotificationUrl : Maybe String
    , vapidPublicKey : Maybe String
    , pushError : Maybe String
    }


init : Bool -> ( Model, Cmd Msg )
init isOnline =
    ( { isOnline = isOnline
      , updateAvailable = False
      , installAvailable = False
      , isInstalled = False
      , notes = [ "This note was created offline-ready" ]
      , draft = ""
      , notificationPermission = Nothing
      , pushSubscription = Nothing
      , lastNotificationUrl = Nothing
      , vapidPublicKey = Nothing
      , pushError = Nothing
      }
    , fetchVapidKey
    )



-- UPDATE


type Msg
    = GotPwaEvent (Result Decode.Error Pwa.Event)
    | AcceptUpdate
    | RequestInstall
    | SetDraft String
    | AddNote
    | RemoveNote Int
    | RequestNotificationPermission
    | SubscribePush
    | UnsubscribePush
    | GotVapidKey (Result Http.Error String)
    | SubscriptionRegistered (Result Http.Error ())
    | SubscriptionUnregistered (Result Http.Error ())


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
                    ( { model | installAvailable = False, isInstalled = True }, Cmd.none )

                Pwa.NotificationPermissionChanged permission ->
                    ( { model | notificationPermission = Just permission }, Cmd.none )

                Pwa.PushSubscription subscription ->
                    ( { model | pushSubscription = Just subscription, pushError = Nothing }
                    , registerSubscription subscription
                    )

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
                    ( { model | lastNotificationUrl = Just url }, Cmd.none )

        GotPwaEvent (Err _) ->
            ( model, Cmd.none )

        AcceptUpdate ->
            ( model, Pwa.acceptUpdate pwaOut )

        RequestInstall ->
            ( model, Pwa.requestInstall pwaOut )

        SetDraft draft ->
            ( { model | draft = draft }, Cmd.none )

        AddNote ->
            if String.isEmpty (String.trim model.draft) then
                ( model, Cmd.none )

            else
                ( { model
                    | notes = model.notes ++ [ String.trim model.draft ]
                    , draft = ""
                  }
                , Cmd.none
                )

        RemoveNote index ->
            ( { model | notes = removeAt index model.notes }, Cmd.none )

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



-- HTTP


fetchVapidKey : Cmd Msg
fetchVapidKey =
    Http.get
        { url = pushServerUrl ++ "/vapid-public-key"
        , expect =
            Http.expectJson GotVapidKey
                (Decode.field "vapidPublicKey" Decode.string)
        }


registerSubscription : Encode.Value -> Cmd Msg
registerSubscription subscription =
    Http.post
        { url = pushServerUrl ++ "/subscriptions"
        , body = Http.jsonBody (Encode.object [ ( "subscription", subscription ) ])
        , expect = Http.expectWhatever SubscriptionRegistered
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



-- HELPERS


removeAt : Int -> List a -> List a
removeAt index list =
    List.indexedMap Tuple.pair list
        |> List.filterMap
            (\( i, item ) ->
                if i == index then
                    Nothing

                else
                    Just item
            )



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "app" ]
        [ viewUpdateBanner model.updateAvailable
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

    else
        text ""


viewMain : Model -> Html Msg
viewMain model =
    main_ []
        [ section []
            [ h2 [] [ text "Notes" ]
            , p [ class "hint" ]
                [ text "Add notes below. The app works offline thanks to the service worker cache." ]
            , div [ class "note-input" ]
                [ input
                    [ type_ "text"
                    , placeholder "Write a note..."
                    , value model.draft
                    , onInput SetDraft
                    , onEnter AddNote
                    ]
                    []
                , button [ onClick AddNote ] [ text "Add" ]
                ]
            , viewNotes model.notes
            ]
        , viewPushNotifications model
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
        , dl []
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
                [ text
                    (case model.lastNotificationUrl of
                        Just url ->
                            url

                        Nothing ->
                            "None"
                    )
                ]
            ]
        , case model.pushError of
            Just err ->
                p [ style "color" "red" ] [ text err ]

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


viewNotes : List String -> Html Msg
viewNotes notes =
    if List.isEmpty notes then
        p [ class "empty" ] [ text "No notes yet." ]

    else
        ul [ class "notes" ]
            (List.indexedMap viewNote notes)


viewNote : Int -> String -> Html Msg
viewNote index note =
    li []
        [ span [] [ text note ]
        , button [ class "remove-btn", onClick (RemoveNote index) ] [ text "x" ]
        ]


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
        , a [ href "../../pwa.md" ] [ text "pwa.md" ]
        , text " for the full guide."
        ]
