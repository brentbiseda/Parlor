# Parlor

A SwiftUI iOS app for playing card and board games with people nearby, with
friends over FaceTime, on one shared phone, or solo against bots — plus
leagues, knockout tournaments, Elo rankings, leaderboards, player profiles,
suspend-and-resume play, synthesized sound effects, and an arcade corner.

**Games:** Hearts · Spades · Euchre · Bridge · Klondike · FreeCell ·
Mahjongg (tile-matching solitaire) · Chess · Checkers · Go ·
Pinball (10 themed tables) · Breakout · Blocks (falling tetrominoes)

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
| **Solo / bots** | Any empty seat is filled by a bot, so you can play 4-player games alone. Klondike, FreeCell, Mahjongg, Pinball, Breakout, and Blocks are single-player. |
| **Asynchronous** | Leaving a local table (or backgrounding the app) suspends the game to disk. The home screen's **Continue playing** row resumes any table — including mid-league matches — whenever you like. |

A `parlor://join` link opens the app straight into the nearby-table browser —
handy to text someone in the room who already has the app. (True
internet-link matchmaking would need a relay server; remote play here goes
through SharePlay instead.)

## Profiles, rankings & leaderboards

- **Profiles** — multiple local identities with a name, symbol, and color.
  The active profile (switchable from the home-screen chip) is your name at
  every table. Pass-and-play guests, league entrants, and bots get directory
  entries automatically, so everyone shows up in the rankings.
- **Rankings** — per-game Elo ratings (start 1200, K=24, split pairwise
  across opponents so a 4-player table moves ratings like a head-to-head
  game). Every finished competitive game updates ratings — humans and bots,
  live or simulated. Zero-sum, upset wins pay more.
- **Leaderboards** — local record tables: pinball/breakout/blocks high
  scores, fastest Klondike/FreeCell solves (fewest moves), Mahjongg clears
  with fewest shuffles. Top 20 per game, with a toast when you set a new #1.

## Bots, sound & feel

- **Bot difficulty** — every setup sheet (and league/tournament creation)
  offers Easy / Normal / Hard. Easy is random-but-legal; Normal bids and
  calls sensibly; Hard ducks points in Hearts, passes the Q♠ on, wins tricks
  as cheaply as possible, takes and protects material in chess and checkers,
  and grabs captures in Go. A smoke test pits Hard against Easy to keep it
  honest.
- **Sound effects** — synthesized at runtime (enveloped tones, chords,
  noise bursts — no audio assets): card plays, tile matches, bumpers,
  slingshots, jackpots, drains, flippers, brick breaks, line clears, win
  fanfares. Toggle with the speaker button on the home screen; respects the
  silent switch. Big moments also tap the haptics engine.
- **Visual effects** — confetti on every result banner, spark bursts on
  pinball bumpers, floating score popups, ghost-piece preview in Blocks,
  felt vignette and themed arcade backgrounds.

## Leagues & tournaments

Both live on the home screen under **Compete**. Rosters mix humans (who play
pass-and-play on this device) and named bots; matches with no humans at the
table can be **simulated instantly**. Results are recorded automatically when
you leave a finished table, and every game contributes to per-game lifetime
stats shown on the home screen tiles.

- **Leagues** — a fixed roster plays a generated season. 2-player games get a
  circle-method round robin (single or double, byes for odd rosters);
  4-player games seat rotating tables of four so partners and opponents vary
  each round. Placement points (4-player: 3/2/1/0 · 2-player: 1/0, ties split)
  feed a live standings table with P/W/D/L/Pts.
- **Tournaments** — single-elimination knockouts for 4, 8, or 16 entrants
  with a random draw. 2-player games advance each winner; 4-player games
  advance the top two finishers per table (the winning pair stays partnered
  in Spades/Euchre/Bridge). Drawn knockout matches are replayed. The bracket
  builds round by round to a champion banner.

## Rules implemented

- **Hearts** — passing rotation (left/right/across/hold), 2♣ leads, hearts must
  be broken, no points on the first trick, Q♠ = 13, shooting the moon, game to 100.
- **Spades** — partnerships, nil bids (±100), bags with the 10-bag penalty,
  spades must be broken, game to 500.
- **Euchre** — 24-card deck, bowers, two bidding rounds with stick-the-dealer,
  going alone, march/euchre scoring, game to 10.
- **Bridge** — Chicago (four-deal) format: full auction with doubles/redoubles,
  declarer plays dummy, rotating vulnerability, standard duplicate scoring.
- **Klondike** — draw-1 or draw-3 (your choice persists), configurable
  passes through the deck (unlimited/1/2/3/5), drag & drop or tap-to-move,
  seven card-back designs (including two fish), undo. Dropping on any
  foundation slot routes the card to its suit's pile automatically.
- **FreeCell** — all 52 cards face up across 8 cascades, 4 free cells,
  supermoves up to (1 + free cells) × 2^(empty cascades), undo.
- **Mahjongg** — classic 144-tile turtle, free-tile rule, flowers/seasons match
  within their group, hints, reshuffle when stuck, undo. Tiles use bold,
  color-coded faces (numbers + suit marks, serif winds, CJK dragons) instead
  of the hard-to-read Unicode mahjong glyphs.
- **Chess** — full legality: castling, en passant, promotion, check/checkmate,
  stalemate, 50-move rule, basic insufficient-material draws.
- **Checkers** — American rules: forced captures, multi-jumps, kings,
  crowning ends a jump sequence.
- **Go** — 9×9/13×13/19×19, suicide and simple-ko rules, area scoring with
  komi 6.5 after two passes (capture dead stones before passing).
- **Pinball** — a SpriteKit physics table: hold either half of the screen to
  work that flipper, hold the launch lane to charge the plunger. Pop bumpers,
  slingshots, a drop-target bank (1000 for clearing it), three balls per
  game, best score remembered. **Ten themed tables**: Classic Parlor ·
  Pittsburgh, PA (black & gold, three-rivers rails) · Chicago Hotdog (garden
  bumpers, hotdog spinner, no ketchup) · London (ride the Tube tunnel) ·
  Paris (Métro tunnel under the Eiffel Tower) · Switzerland (steeper gravity,
  ski-slope rails) · Deep Space (low gravity) · Neon Tokyo · Pirate Cove
  (cannon tunnel) · Vegas (double-value bumpers). Tables add spinners,
  teleport tunnels, extra rails, spark bursts, and themed sounds.
- **Breakout** — drag to steer, tap to launch; aim with the paddle (the
  bounce angle follows the hit point), armored bricks and checkerboard gaps
  on later levels, speed climbs per level, three lives.
- **Blocks** — 10×20 well, 7-bag randomizer, wall kicks, ghost landing
  preview, soft/hard drops, line scores ×100/300/500/800 by level; gravity
  speeds up every 10 lines. Swipe to move, tap to rotate, swipe down to
  slam — or use the buttons.

## Architecture

```
Parlor/
  Model/    Card, GameKind, Move       — shared value types; one Codable Move
            Competition, Player,         enum covers every game; League &
            SavedGame                    Tournament scheduling, Elo math,
                                         profiles, suspended-game snapshots
  Engine/   13 game engines + Bot      — pure Swift state machines, no UI/network;
                                         ranking() reports final standings for
                                         leagues, tournaments, and Elo; Bot has
                                         three difficulty levels
  Net/      Multipeer + SharePlay      — transports behind one GameTransport
            GameSession                  protocol; host-authoritative sync;
                                         solo-game undo; save/resume snapshots;
                                         table-wide sound hooks
  Views/    SwiftUI (+ SKScenes)       — one shared trick-taking table (with an
                                         always-visible scoreboard) for the four
                                         card games, board views, league/
                                         tournament/profile/ranking screens,
                                         pinball (PinballLayouts = 10 themes),
                                         breakout, falling blocks, confetti
  App/      ParlorApp, AppModel,       — session lifecycle, result recording
            CompetitionStore,            (stats, Elo, leaderboards, standings),
            ProfileStore,                JSON persistence, background auto-save
            LeaderboardStore,            for async play; SoundFX synthesizes
            SavedGamesStore,             every effect into PCM buffers at
            StatsStore, SoundFX          runtime (no assets)
```

Multiplayer is host-authoritative: clients send proposed moves, the host
validates them against the engine and pushes back per-seat **redacted** state,
so other players' hands never leave the host. If a player disconnects
mid-game, their seat is taken over by a bot so the game can finish.

Leagues and tournaments are local to the device: human entrants play
pass-and-play at the same table, bots fill the rest, and `GameEngine.ranking()`
(seats grouped by finishing rank) is mapped back to entrants to award points
or advance the bracket. Pinball's physics live in the SpriteKit scene; the
engine only keeps score, so results flow through the same pipeline as every
other game.

### Engine tests

`Package.swift` at the repo root builds the engines **and the competition
models** as a plain Swift package for fast iteration on macOS:

```sh
swift test    # plays every game to completion with bots at every difficulty,
              # checks rankings, round-robin/bracket scheduling, standings math,
              # Elo properties, Tetris/Klondike rules, coding round-trips —
              # and makes the hard bot defend its title against random play
```

### Notes & known simplifications

- Bots are casual opponents: light heuristics for bidding, otherwise random
  legal moves (with a move cap in Go so random capture cycles always end).
- Bridge plays one Chicago cycle (4 deals); rubber scoring isn't modeled.
- Go scoring counts all stones as alive; threefold repetition isn't tracked in
  chess; Mahjongg deals are random (a reshuffle button rescues stuck boards).
- Drawn knockout matches simply ask for a replay; bot-vs-bot simulations
  retry automatically until someone wins.
- SharePlay requires the Group Activities capability (already in
  `Support/Parlor.entitlements`) and a paid/free Apple developer account that
  permits it; nearby play needs the Local Network permission (prompted on
  first use).
- The `PARLOR_AUTOSTART=<game>` environment variable jumps straight into a
  solo game at launch — used for development screenshots.
