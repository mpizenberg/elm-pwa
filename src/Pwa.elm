module Pwa exposing
    ( Event(..), decodeEvent
    , acceptUpdate, requestInstall
    )

{-| PWA integration for Elm apps.

The app defines two ports:

    port pwaIn : (Decode.Value -> msg) -> Sub msg

    port pwaOut : Encode.Value -> Cmd msg

Then wires them as follows:

    subscriptions _ =
        pwaIn (Pwa.decodeEvent >> GotPwaEvent)

    update msg model =
        case msg of
            AcceptUpdate ->
                ( model, Pwa.acceptUpdate pwaOut )

The JS side calls `init({ ports: { pwaIn, pwaOut } })` from the companion
npm package to connect browser events to these ports.


# Events

@docs Event, decodeEvent


# Commands

@docs acceptUpdate, requestInstall

-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| Events sent from the JS runtime to Elm via the `pwaIn` port.

  - `ConnectionChanged True` — device went online
  - `ConnectionChanged False` — device went offline
  - `UpdateAvailable` — a new service worker is installed and waiting to activate
  - `InstallAvailable` — the browser's install prompt can be triggered (Chromium only)
  - `Installed` — the app was installed to the home screen / desktop

-}
type Event
    = ConnectionChanged Bool
    | UpdateAvailable
    | InstallAvailable
    | Installed


{-| Decode a JSON value from the `pwaIn` port into an `Event`.

    subscriptions _ =
        pwaIn (Pwa.decodeEvent >> GotPwaEvent)

-}
decodeEvent : Decode.Value -> Result Decode.Error Event
decodeEvent value =
    Decode.decodeValue eventDecoder value


eventDecoder : Decode.Decoder Event
eventDecoder =
    Decode.field "tag" Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "connectionChanged" ->
                        Decode.field "online" Decode.bool
                            |> Decode.map ConnectionChanged

                    "updateAvailable" ->
                        Decode.succeed UpdateAvailable

                    "installAvailable" ->
                        Decode.succeed InstallAvailable

                    "installed" ->
                        Decode.succeed Installed

                    _ ->
                        Decode.fail ("Unknown PWA event tag: " ++ tag)
            )


{-| Tell the waiting service worker to activate, which triggers a page reload.

    update msg model =
        case msg of
            AcceptUpdate ->
                ( model, Pwa.acceptUpdate pwaOut )

-}
acceptUpdate : (Encode.Value -> Cmd msg) -> Cmd msg
acceptUpdate pwaOut =
    pwaOut (Encode.object [ ( "tag", Encode.string "acceptUpdate" ) ])


{-| Trigger the browser's install prompt (Chromium only).

    update msg model =
        case msg of
            RequestInstall ->
                ( model, Pwa.requestInstall pwaOut )

-}
requestInstall : (Encode.Value -> Cmd msg) -> Cmd msg
requestInstall pwaOut =
    pwaOut (Encode.object [ ( "tag", Encode.string "requestInstall" ) ])
