port module Main exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode
import Json.Encode as Encode
import Pwa


port pwaIn : (Decode.Value -> msg) -> Sub msg


port pwaOut : Encode.Value -> Cmd msg



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
    }


init : Bool -> ( Model, Cmd Msg )
init isOnline =
    ( { isOnline = isOnline
      , updateAvailable = False
      , installAvailable = False
      , isInstalled = False
      , notes = [ "This note was created offline-ready" ]
      , draft = ""
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = GotPwaEvent (Result Decode.Error Pwa.Event)
    | AcceptUpdate
    | RequestInstall
    | SetDraft String
    | AddNote
    | RemoveNote Int


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
                ]
            ]
        ]


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
