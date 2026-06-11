# Parlor

A SwiftUI iOS app for playing card and board games with people nearby, with
friends over FaceTime, on one shared phone, or solo against bots.

**Games:** Hearts · Spades · Euchre · Bridge · Solitaire (Klondike) ·
Mahjongg (tile-matching solitaire) · Chess · Checkers · Go

## Running the app

1. Open `Parlor.xcodeproj` in Xcode 16 or newer.
2. To run on a real device, select the Parlor target → Signing & Capabilities
   and pick your team (the bundle ID is `com.brentbiseda.Parlor`).
3. Build & run on an iPhone or iPad (iOS 17+).

No dependencies, no server — everything is on-device.

## Ways to play

| Mode | How it works |
|---|---|
| **Nearby** | One player hosts a table; everyone else taps **Join a nearby game**. Uses MultipeerConnectivity over local Wi-Fi/Bluetooth — no internet needed. |
| **Friends anywhere** | Start a FaceTime call (or share a FaceTime link from the FaceTime app), then pick **Play over SharePlay** in the game setup. Friends with the app join right from the call. |
| **Pass & play** | Several people share one device. For card games a curtain screen hides each hand during handoffs. |
| **Solo / bots** | Any empty seat is filled by a bot, so you can play 4-player games alone. Solitaire and Mahjongg are single-player. |

A `parlor://join` link opens the app straight into the nearby-table browser —
handy to text someone in the room who already has the app. (True
internet-link matchmaking would need a relay server; remote play here goes
through SharePlay instead.)

## Rules implemented

- **Hearts** — passing rotation (left/right/across/hold), 2♣ leads, hearts must
  be broken, no points on the first trick, Q♠ = 13, shooting the moon, game to 100.
- **Spades** — partnerships, nil bids (±100), bags with the 10-bag penalty,
  spades must be broken, game to 500.
- **Euchre** — 24-card deck, bowers, two bidding rounds with stick-the-dealer,
  going alone, march/euchre scoring, game to 10.
- **Bridge** — Chicago (four-deal) format: full auction with doubles/redoubles,
  declarer plays dummy, rotating vulnerability, standard duplicate scoring.
- **Solitaire** — Klondike, draw-1 or draw-3, unlimited redeals.
- **Mahjongg** — classic 144-tile turtle, free-tile rule, flowers/seasons match
  within their group, hints, reshuffle when stuck.
- **Chess** — full legality: castling, en passant, promotion, check/checkmate,
  stalemate, 50-move rule, basic insufficient-material draws.
- **Checkers** — American rules: forced captures, multi-jumps, kings,
  crowning ends a jump sequence.
- **Go** — 9×9/13×13/19×19, suicide and simple-ko rules, area scoring with
  komi 6.5 after two passes (capture dead stones before passing).

## Architecture

```
Parlor/
  Model/    Card, GameKind, Move      — shared value types; one Codable Move
                                        enum covers every game
  Engine/   9 game engines + Bot      — pure Swift state machines, no UI/network
  Net/      Multipeer + SharePlay     — transports behind one GameTransport
            GameSession                 protocol; host-authoritative sync
  Views/    SwiftUI                   — one shared trick-taking table for the
                                        four card games, board views, etc.
  App/      ParlorApp, AppModel
```

Multiplayer is host-authoritative: clients send proposed moves, the host
validates them against the engine and pushes back per-seat **redacted** state,
so other players' hands never leave the host. If a player disconnects
mid-game, their seat is taken over by a bot so the game can finish.

### Engine tests

`Package.swift` at the repo root builds the engines as a plain Swift package
for fast iteration on macOS:

```sh
swift test    # plays every game to completion with bots + coding round-trips
```

### Notes & known simplifications

- Bots are casual opponents: light heuristics for bidding, otherwise random
  legal moves.
- Bridge plays one Chicago cycle (4 deals); rubber scoring isn't modeled.
- Go scoring counts all stones as alive; threefold repetition isn't tracked in
  chess; Mahjongg deals are random (a reshuffle button rescues stuck boards).
- SharePlay requires the Group Activities capability (already in
  `Support/Parlor.entitlements`) and a paid/free Apple developer account that
  permits it; nearby play needs the Local Network permission (prompted on
  first use).
- The `PARLOR_AUTOSTART=<game>` environment variable jumps straight into a
  solo game at launch — used for development screenshots.
