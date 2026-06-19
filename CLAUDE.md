# Parlor — Architecture Reference

iOS SwiftUI card & arcade game collection. Deployment target: iOS 17.0. Swift 5.0.

## Project Layout

```
Parlor/
  Engine/         Game logic (pure structs, no UIKit/SwiftUI imports)
  Model/          Shared data types: Card, Move, GameKind, Competition, Player, SavedGame
  Net/            GameSession, MultipeerTransport, SharePlay
  Views/          SwiftUI views (one file per game or concern)
  EngineCheck/    XCTest smoke-tests for game engines
```

## Core Protocol: GameEngine

```swift
protocol GameEngine: Codable {
    static var kind: GameKind { get }
    var currentPlayer: Int { get }
    var isOver: Bool { get }
    var statusText: String { get }
    var resultText: String? { get }
    func legalMoves() -> [Move]
    func isLegal(_ move: Move) -> Bool
    mutating func apply(_ move: Move) throws
    func redacted(for seat: Int) -> Self      // blank other players' hidden cards
    func controller(of seat: Int) -> Int      // bridge declarer plays dummy
    func ranking() -> [[Int]]                 // grouped by finish rank, best first
}
```

Default implementations (in `GameEngine` extension):
- `isLegal` — `legalMoves().contains(move)`
- `applyValidated` — guards `isOver` and `isLegal` before calling `apply`
- `verify(_:)` — returns `Result<Self, GameError>` without mutating the receiver
- `redacted` — returns `self` (only override for hidden-information games)
- `controller` — returns `seat` (bridge overrides for dummy)
- `ranking` — `[[0, 1, …, n-1]]` (override for meaningful standings)

## AnyGame

`AnyGame` is a type-erased `Codable` wrapper around `any GameEngine`. It is used everywhere a game must cross a boundary (Multipeer, SharePlay, saved games). The `init(from:)` and `encode(to:)` dispatch manually by `GameKind`. **When adding a new game, add a case to both.**

## Move

`Move` is a flat enum with associated values covering every game. Pattern: `session.submit(.playCard(card))`, `session.submit(.klondike(.draw))`, `session.submit(.tetris(.hardDrop))`, `session.submit(.bomberman(.placeBomb))`. `BreakoutPowerUp` enum (widePaddle/multiball/shield/fireball/scoreDouble/extraLife) is used in `BreakoutEvent.powerUp(_:)`. `BombermanMove` (move/placeBomb/kick/detonate/tick) drives Bomberman — `.kick` propels a bomb in `playerDir` until hitting a wall, `.detonate` triggers all remote-tagged bombs immediately.

## GameSession

`ObservableObject` in `Net/GameSession.swift`. Owns the live `AnyGame?`. Call `session.submit(_:Move)` from views; it validates, applies, broadcasts (Multipeer/SharePlay), and enqueues bot moves. `session.undo()` pops `undoStack` (solo and multiplayer-aware). `session.canUndo: Bool` guards the undo UI.

## Networking

- **MultipeerTransport** — MCSession peer discovery + moves serialized as JSON `Data`. Works on LAN/Bluetooth, no internet needed.
- **SharePlay** — `GroupActivity` for FaceTime. Moves flow through `GroupSession` synchronization.
- Both transports call back into `GameSession` which applies moves and publishes changes.

## Game Engines

### Trick-Taking (Hearts, Spades, Euchre, Bridge)
All share `TrickTaking.swift` utilities: `deal`, `followLegal`, `winner`, `trumpValue`, `plainValue`.
`TrickPlay = (seat: Int, card: Card)`. Views adapt via `TrickGameAdapter` protocol in `TrickGameViews.swift`.

| Game    | Players | File               | Key notes |
|---------|---------|-------------------|-----------|
| Hearts  | 4       | HeartsGame.swift  | Pass left/right/across/hold; shoot the moon; ends at 100 pts. `queenPlayed: Bool` tracks Q♠ appearance mid-trick (shown in `statusText`). `roundHistory: [[Int]]` keeps per-round point deltas (newest first); moon shots set `lastTrickSummary = "🌙 Seat X shot the moon! +26 to others"`. `resultText` appends a `[scoreDetail]` bracket with all 4 final scores. `isShootingMoon: Bool` and `moonShooterSeat: Int` computed properties. `lowestPositiveRoundScore`/`lowestPositiveRoundSeat` track best defensive round (shown in resultText). Pass phase `statusText` shows directional symbols (←/→/↕/⟳) and `seat0PassSummary`. |
| Spades  | 4       | SpadesGame.swift  | Nil bids; bag penalty at 10 bags; ends at 500/−200. `teamLabel()` returns "N/S"/"E/W". `teamContract(_:)` sums a team's bids. `lastRoundSummary` ends with running score `"T1 N vs T2 N"`. `statusText` shows partial bids with "?" placeholders during bidding, then tricks-vs-contract + bags while playing. `resultText` handles ties: `"Draw — 120 each"`. `sandbagsWarning: Bool` computed property. |
| Euchre  | 4       | EuchreGame.swift  | Order up or call trump; alone; sitting-out seat. `lastRoundResult` shows "March alone! +4" / "Made it (+1)" / "euchred!". `teamRoundStreak`/`teamBestStreak` track consecutive round wins (shown in resultText at ≥ 3). Bot goes alone when it holds both bowers + ≥ 4 trump. `trumpCallsBySuit: [Int]` tracks frequency per suit; `resultText` shows full trump-split breakdown when ≥2 suits were called. |
| Bridge  | 4       | BridgeGame.swift  | Auction → contract → play; dummy exposed; Rubber scoring. `currentBidLabel` appends "X"/"XX" for doubled/redoubled. `statusText` in play shows "Dbl"/"Rdbl" and "need N more"/"making+N" progress. Auction `statusText` shows `"🔴 N/S vul"` / `"🔴 both vul"` / `"none vul"` based on live `isVulnerable(side:)` calls. |

### Shedding / Draw Games
UnoGame, EightsGame: color/rank matching, draw mechanics.
GoFishGame: rank-collection, 4-of-a-kind books.
UnoGame: `calledUno: Set<Int>` tracks who declared UNO. `Move.uno(.callUno)` is only legal when holding 1 card; failing to call removes the UNO mark on next play/draw. View shows yellow "UNO!" badge on affected hands and a call button when the local player is at 1–2 cards.

`EightsGame`: `pendingDraw: Int` accumulates draw-two debt — when a 2 is played `pendingDraw += 2`; `canPlay()` restricts plays to only 2s while `pendingDraw > 0` (stacking), and `legalMoves()` offers `.draw` as the relief valve that absorbs the full accumulated total. Queens skip the next seat (`wasSkipped: Bool`, `currentPlayer += 2`). `statusText` adds `"· DRAW 4!"` / `"· SKIP"` warnings. `EightsView` shows the suit nomination as an inline overlay picker (4 large suit buttons over a dimmed scrim) instead of a system `confirmationDialog`, plus a draw-two warning banner above the hand when it's your turn and a penalty is pending.

`GoFishGame`: `lastBookEvent: String?` is set (and shown via a flash banner in `GoFishView`) when a book completes, e.g. `"S1 books Ks! (3 books)"`; cleared at the top of the next `apply()`. `lastEvent` is a richer per-ask description: `"S1 asked S2 for Ks — got 2 cards"`. `statusText` shows `"Books 8/13 · pond 12 · hands S1:3🃏 S2:2🃏 … · 🎣 N%"` (per-seat hand counts + live ask accuracy).

### Solitaire
- **KlondikeGame** — tableau + stock/waste + foundations. Undo history (capped at 50 via internal `Snapshot` stack separate from the session-level undo). `drawThree: Bool`, `maxPasses: Int` (0 = unlimited). `KlondikeView` has a 4-tier hint system (`showHint`) that highlights the best move with a mint border, plus an always-on foundation auto-hint: any foundation whose suit has a playable waste/tableau top pulses a green ring (`autoFoundationSuits(_:)`), and a brief green flash plays on a successful foundation landing (`flashFoundation(suit:)`). `autoFoundationCount: Int` counts how many cards (waste top + tableau tops) can immediately be placed on a foundation; shown in `statusText` as `"✨N ready"`. `foundationProgress: Int` and `foundationProgressFraction: Double` track dealt-to-foundation ratio.
- **FreeCellGame** — 8 cascades, 4 free cells. Auto-finish condition when all cascades are ordered. `deadlocked: Bool` is set when `legalMoves().isEmpty` after a move with the game not already over; `isOver` honors it; overlay banner shows `"Stuck after N moves · M cards unplaced"`. `autoFinishAvailable: Bool` and `foundationCount: Int` support the auto-finish UI.
- **MahjongGame** — tile-matching patience.

### Puzzles
- **MinesweeperGame** — 3 difficulty presets (Easy 9×11/14, Medium 12×16/40, Hard 16×22/99). Instance methods `index(_:_:)` and `neighbors(_:)` (NOT static). First click is always safe. Chording supported. `flagCount: Int` and `timerString: String` (`"1:23"`/`"42s"`) back the `statusText`/`resultText`; `MinesweeperView`'s header is a 3-section pill: difficulty | 💣 remaining | ⏱ timer, with the border turning green on win / red on loss. `mineDensityLabel: String` returns `"Low (14%)"` / `"Medium (21%)"` / `"High (28%)"` based on mine density; shown in win `resultText`. Chord-ready cells pulse with cyan border animation.
- **TetrisGame** — 10×20 well, 7-bag randomizer, wall kicks, ghost piece. Scoring constants: `lineClearScore`, `softDropScore`, `hardDropScore`. Hard-drop score clamped with `max(0, …)`. `combo: Int`, `backToBack: Bool`, and `lastClearLabel: String?` ("TETRIS B2B", "TRIPLE", …) drive bonus scoring (`backToBackBonus`, `comboBase`) and `statusText`. `TetrisView` shows the clear label as a spring-animated yellow sidebar badge (`clearBadge`, auto-clears after 1.5s) and a `COMBO ×N` stat block when `combo > 1`. `stackHeight` stat block is color-coded white/yellow/orange/red. Ghost piece opacity scales with distance from active piece (0.55 close → 0.18 far). `TetrisMove` includes `.rotate180` (180° rotation). Lock-delay progress bar overlaid on board. Survival time tracked via `gameStartDate` and shown in `resultText`.
- **CapsulesGame** — Dr. Mario-style. `advanceLevel()` called externally after clear animation. `levelsCleared` tracks sessions. Cell `linkDY -1` = bottom half (partner above); `linkDY +1` = top half (skip in settle loop). `maxChain` and `totalVirusesCleared` stats in `resultText`. Sidebar shows a `VIRUSES N/total` progress bar (red fill → green on clear).
- **SnakeGame** — Grid 15×22. `bitesPerLevel=6`, `growthPerBite=3`, 6-pattern wall cycle (open/bar/pillars/cross/corners/diagonal). `pendingDirection` is buffered and applied at next tick; view uses `pendingDirection ?? direction` for eye rendering. Every 3rd bite spawns `bonusFood: Int?` (gold star, 3× points, `bonusTicks` TTL with end-of-life blink); `comboCount` tracks consecutive same-tick gains. `SnakeView` shows a floating score popup (`scorePopup`, level-up/combo/bonus text), a bottom-left speed chip (bars proportional to level), and a top-left "Next: <pattern>" chip 2 bites before a level change. Arrow buttons show `.yellow` tint + `scaleEffect(0.92)` press state (via `pressedDirection: GridDirection?`, cleared after 120ms). `speedLabel: String` (`"slow"`/`"medium"`/`"fast"`/`"very fast"`/`"blazing"`). Bonus food ring transitions green→orange→red based on `bonusTicks` fraction.

### Arcade / Sports
`ArcadeGames.swift` holds thin scorekeeping engines: Centipede, Football, Baseball, Soccer, Hockey.
SpriteKit scenes live in `SportsViews.swift` (FieldGoalScene, DerbyScene, ShootoutScene, HockeyScene).
Scenes push `ArcadeEvent` callbacks into `session.submit(.arcade(event))`.

`SoccerGame` has an explicit `Phase` enum: `.shooting` → `.keeping` → `.done`. Early-finish detection via `isDecided` when the trailing team can no longer tie. `saves: Int` tracks keeper saves; `goldenBoot`/`cleanSheet` achievements appear in `resultText` ("⚽ Golden Boot" / "🧤 Clean Sheet").

`FootballGame`: `currentStreak`/`bestStreak` fields; `🔥N` in statusText.
`BaseballGame`: `longestHomer` field; shown in statusText/resultText.
`HockeyGame`: `maxDeficit: Int` tracks the largest comeback gap; `shutout: Bool { won && botGoals == 0 }`; `statusText` shows lead/trail as `"↑2"`/`"↓1"`; `resultText` adds "🥅 Shutout!" and comeback callouts.

- **HopperGame** — `crossingTicks` resets on `respawn()`; `timeBonusBudget=200` gives time-pressure bonus. `perfectCrossings: Int` increments when a crossing earns time bonus AND the player hasn't lost a life since the last `respawn()`. View has a green/yellow/red timer bar and `+N` score popup. `zoneLabel: String` shows `"🌊 river"` / `"🚗 road"` / `"🟩 safe"` / `"🏁 home"` based on `frogY`; shown in `statusText`.
- **BombermanGame** — 15×13 grid with indestructible pillar walls and soft destructible blocks. `BomberBomb` (fuse 120 ticks, `radius`, ID, `remote: Bool`), `BomberExplosion` (flat cell index list, `ticksLeft=25`, `killCount`), `BomberEnemy` (3 kinds: balloon=slow random, ghost=medium open-space preference, demon=fast player-pursuit within 7 cells). Chain explosions: bomb in active explosion fires immediately; `currentChain`/`maxChain` track depth. 6 power-ups in soft blocks (30% chance, weighted): `.powerBomb` (+1 max bombs, cap 8), `.powerBlast` (+1 blast radius, cap 8), `.powerSpeed` (+1 speed boost, cap 3), `.powerRemote` (remote detonator: next bomb tagged `remote=true`, triggered by `.detonate`), `.powerShield` (180 ticks invincibility, stackable), `.powerSkull` (penalty: `skullTicks=120`, caps effectiveMaxBombs=1 and effectiveBlastRadius=1). `dangerCells: Set<Int>` computed from all active bomb blast paths — pulsing red overlay in view (alpha alternates every 4 ticks). `invincibleTicks=90` on player hit + `shieldTicks` from power-up, both combined in `isInvincible`. `playerDir: GridDirection` tracks facing for kick mechanic + view chevron. Kick: `.bomberman(.kick)` slides the bomb in `playerDir` until hitting a wall. Bonus cherry 🍒: spawns every ~250 ticks (65% chance), worth 500 pts, blinks when expiring (`bonusItemTicks < 35`). Multi-kill combo: `score += 200 × kills × max(kills, chain)`, `maxKillCombo` stat. Enemy speed scales per level (balloon floor 3, ghost floor 2, demon floor 1). Level clear: all enemies dead → `levelClearCountdown = 80` (2.5s banner) → `populateLevel(level+1)`, continuous arcade play. `deathsThisLevel == 0` grants +500 perfect-level bonus. `levelsCleared`/`survivalTicks`/`totalExplosionCells`/`maxKillCombo` stats in `resultText`. `isOver = livesLeft <= 0` (no `gameWon` flag — levels advance indefinitely). View: D-pad + BOMB + KICK + DETONATE buttons; level-clear overlay with countdown bar; score/chain/power-up floating popups from clock loop; distinct enemy shapes (balloon=oval+string, ghost=8-pt wavy polygon, demon=body+horns+yellow eyes); player direction chevron + shield glow ring + skull red tint; danger zone pulse animation; bonus cherry rendering with expiry blink.
- **BreakoutGame (updated)** — 6 power-up types (`BreakoutPowerUp`: widePaddle/multiball/shield/fireball/scoreDouble/extraLife), 3 new brick types (explosive = chain-destroys neighbours within 72px, steel = indestructible from Lv4, moving = SKAction oscillation from Lv3). `shieldHits`, `powerUpsCaught`, `extraLivesGained` stats in `resultText`. `bricksRemaining`/`totalBricks` tracked via `.brickCount(remaining:total:)` event → header progress bar. Fireball mode removes brick `collisionBitMask` (ball passes through) while keeping `contactTestBitMask` for destruction callbacks. Multi-ball: `balls: [SKShapeNode]` array; losing all balls triggers `.ballLost`. Score-double: scene applies `scoreMultiplier` to points before sending `.score(n)` event. Wall contacts fire `.wallBounce` (ball `contactTestBitMask` now includes `Category.wall`). Shield: horizontal bar at y=24 with `Category.shield`; breaks on first ball contact.
- **MuncherGame** — Ghosts have `GhostType` (.blinky/.pinky/.inky/.clyde) with distinct chase targeting. Scatter/chase phase cycle via `scatterChaseCycle` array (even=scatter, odd=chase). `isScatterPhase: Bool` computed property. `fruitsEaten: Int` tracks bonus fruit pickups (shown in resultText 🍒). View shows a power-pellet timer bar that displays the ghost combo multiplier (`×200`, `×400`, `×800`, `×1600`) when ghosts have been eaten this power-up. "SCATTER" hint label also shown.

### Board Games
Chess, Checkers, Go — in `BoardGameViews.swift`. Bot logic in `Bots.swift`.
`BoardGameViews` shows a `capturedBar` beneath the board: chess shows missing pieces grouped by type; checkers shows piece-loss counts, moves-without-capture counter ("no-cap"), and the `lastMoveDesc` text underneath. Checkers board highlights pieces one step from promotion with a hollow crown icon + gold glow ring.

`ChessGame`: `isOpeningPhase: Bool` (`moveNumber <= 8`) shown in `statusText` as `"📖 opening"`. `materialBalance: Int` (signed from White's perspective). `resultText` shows per-side capture balance.
`CheckersGame`: `pieceCount(color:)` and `kingCount(color:)` helpers; `statusText` shows `"R:9(K:2) B:8(K:1)"` plus a trailing `lastMoveDesc` (e.g. `"· Red a3–b4"`, `"· Red c3×e5 ♛"` for crowned captures) built from `colLabel(_:)`/`cellLabel(_:)` (`"a"`–`"h"` / `"a1"`–`"h8"`). `resultText` adds `" · loser has no moves"` when applicable. `positionHashes: [Int: Int]` tracks position frequency for 3-fold repetition; `isThreefoldRepetition: Bool`; `statusText` shows `"⚠️ repeat×2"` when any position has appeared twice (warning before draw). Pieces one row from promotion show a hollow crown icon + gold glow ring in the board view. Bot eval adds center control bonus (inner 4×4 squares +0.07, outer ring +0.03).

`GoGame`: `statusText` shows move number (`#N`), stone counts (●B ○W), captures, live atari count (`"⚠️ atari(N)"` when any groups are in atari), and estimated area score with leader margin. Coordinate labels rendered along board edges: letters A–T (skipping I) along bottom, numbers 1–N along left.

## Bots

`Bot.chooseMove(for:difficulty:)` in `Bots.swift`. Three difficulty levels:
- **easy** — random legal moves
- **normal** — sensible bids, casual card play
- **hard** — `hardHeartsPlay`, `hardTrickPlay`, chess/checkers greedy search, Go territory capture

Hearts pass bot uses `g.passDirection` to decide which cards to unload (direction-aware danger rankings). Hard bot uses `TrickTaking.safeLead` for opening leads. Hearts hard bot proactively initiates moon-shoot when holding 7+ hearts + Q♠ before any points land (`attemptingMoonShoot`), in addition to the reactive trigger (≥8 pts with none escaped). **Moon-defense mode**: when an opponent is detected as attempting a moon shoot, the hard bot actively steals a point trick (leads a high heart if broken, or plays cheapest winning card when a point trick is live).
Euchre bot threshold: `Bot.euchreTrumpThreshold = 8` (sum of bower/trump-card weights).
Checkers hard bot: recursive 4-half-ply alpha-beta (`checkersAlphaBeta`) with material + advancement + king-safety + **center control** eval. King-crowning bonus (+0.6), back-rank safety (+0.1), inner-4×4 center bonus (+0.07), outer ring (+0.03).
Chess hard bot: 2-ply alpha-beta with enriched eval: centrality (up to 0.245), pawn advancement, **passed-pawn bonus (+0.35)**, **doubled-pawn penalty (−0.2)**, **rook-on-open-file bonus (+0.15/+0.25)**, **bishop-pair bonus (+0.1)**. Early-queen penalty (−0.4 before move 8). King safety: pawn shield (+0.10), castled position (+0.3), uncastled center penalty (−0.4), open file penalty (−0.15).
Uno bot: when self has ≤2 cards (near-win), immediately plays highest-point colored card. When opponent has ≤3 cards, calls the color the threat is least likely to have. `wildDrawFour` preferred over plain wild when opponent has ≤ 2 cards.
Go hard bot: self-atari avoidance filter; prefers moves adjacent to own stones; 19×19 uses hoshi star points as early-game bias and extended 80-move opening threshold.
Bridge bot (`bridgeBotCall`): opens with 13+ HCP only when `game.lastBid == nil`. Balanced hands (no void, no singleton) with 15–17 HCP open 1NT; otherwise opens longest suit at 1-level. When any bid has been made, the bot passes (safe over sophisticated). **Never bid without checking auction legality.**

`TrickTaking` helpers: `highCardPoints(hand:)` (A=4, K=3, Q=2, J=1), `suitCounts(hand:suitOf:)`, `trickEstimate(hand:suit:)` — used by bidding bots. `safeLead(from:trump:suitOf:)` — picks a good opening lead (avoids bare K-Q tenace, leads fourth-best from longest suit).
`Bot.estimateSpadesBid(hand:)` is `internal` — accessible from views for displaying a recommended bid chip in the Spades bidding panel.

## Views

### Key Patterns
- `session.game?.engine as? SpecificGame` — typed access to the live engine
- `session.submit(.someMove)` — all user actions go through this
- `.task(id: session.sessionID) { await gravityLoop() }` — gravity/clock loops restart when game restarts
- Gravity loops use `do { try await Task.sleep(…) } catch { break }` for clean cancellation — never use `try?` (silently swallows cancellation)
- `HandView(cards:legal:enabled:selected:onTap:)` — shared hand renderer in `CardViews.swift`. Legal cards get a yellow border + subtle yellow glow shadow. When `!enabled`, applies `.saturation(0.55)` + `.brightness(-0.08)` with `easeInOut` animation.
- `PressableTileStyle` — ButtonStyle with scale/brightness/shadow on press (in `RootView.swift`)
- `FaceDownCardView` — uses `Canvas`-drawn diagonal pinstripe pattern (not a club grid). `CardBack` enum drives the style: 9 styles (classic/crimson/forest/royal/midnight/fish/koi/coral/dusk). `coral` shows 🪸 motif; `dusk` shows 🌆 motif.
- `OpponentHandView` — fans up to 8 cards with dynamic `spreadFactor`; shows "+N" badge when count > 8.
- `CardSlotView` — empty pile slot with radial gradient inner glow and dashed border (topLeading-to-bottomTrailing gradient).

### TableView
- **Player avatar strip** — shown above the status line for multiplayer games; each seat gets a small circle icon (green ring = active turn, teal dot = local human, person/cpu icon = human/bot). Accessibility: `.accessibilityLabel` on each seat badge ("Seat N, current turn, you").
- **Result banner** — `resultBanner(_:)` shows a per-player finish table (🥇🥈🥉 rows) for multiplayer games, sourced from `game.ranking()`. Solo games show only the text result. Includes a `ShareLink` to share result text and slides in with `.spring` transition.
- `statusLine(_:)` appends "— your move" or "— PlayerName" to `game.statusText`. Status bar uses `lineLimit(2)` + `minimumScaleFactor(0.78)` to accommodate long Chess/Go status strings.

### TrickGameViews
`TrickGameAdapter` protocol bridges the 4 engines to `TrickTableView`. During Hearts passing, `legal: []` (not `Set(cards)`) so only selected cards get the yellow highlight — avoids painting all 13 with selection styling. `lastTrickSummary` renders as a styled capsule pill (green checkmark icon, translucent background, scale+opacity transition) rather than plain text.

### Tetris Colors (colorblind palette)
S = lime `(0.55, 0.95, 0.22)`, Z = magenta `(0.95, 0.25, 0.65)` — distinguishable under deuteranopia/protanopia.

`TetrisView` sidebar now shows a `→LVL N` stat block for lines remaining to the next level (`10 - (game.lines % 10)`). T-spin clear badge is purple `(0.72, 0.38, 0.92)`, PERFECT CLEAR is `.mint`, otherwise `.yellow`.

### CentipedeView
Stats header above the sprite view: life dots (green/empty), score, wave chip, 🎯N segments-shot badge, ⭐N best-life badge. Backed by `CentipedeGame.segmentsShot`, `livesLeft`, `bestLifeScore`.

### BoardGameViews (Go)
Go `captureBar` now shows stone counts per player (`game.board.filter { $0 == 1 }.count`) alongside capture counts, plus a move number label. The territory split bar and B/W margin remain unchanged. Coordinate labels rendered as `Text` overlays: column letters A–T (skipping I) along the bottom edge, row numbers 1–N along the left edge, scaled to `step * 0.32`.

### KlondikeView
Foundation slots show two distinct highlight states, layered in `topRow(_:cardWidth:)`: a yellow border while a card is actively selected/dragged and can land on that suit (`foundationHintSuit(_:)`), and — when nothing is selected — a slow-pulsing green ring on any suit with an available auto-play candidate (`autoFoundationSuits(_:)`, driven by `foundationPulse` via a repeating `easeInOut` animation). A brief solid-green flash (`foundationLandFlash`, `flashFoundation(suit:)`) confirms a successful drop.

Elapsed-time timer: `@State private var elapsedSeconds: Int` backed by `Timer.publish(every:1)`. Stops incrementing when `game.isOver`; resets via `.task(id: session.sessionID)`. Shown as `⏱N:NN` in the foundation progress bar.

### GoFishView
Books render as mini playing-card tiles (rank + small suit glyphs, gold gradient) via `bookRow(_:)` rather than plain text chips. Completing a book triggers a 2-second gold flash banner (`bookFlash`, driven by `onChange(of: game.lastBookEvent)`) plus a `.jackpot` sound. The pond header shows a running `Books: N/13` total alongside stock count. Stat chips shown below the event line: 🎣 `N%` hit (ask accuracy from `game.totalAsks`/`game.successfulAsks`), 💰 `N haul` badge when `game.biggestHaul ≥ 3`, 🌊×N lucky-pond-books count.

### ShedGameViews (EightsView / UnoView)
Naming a suit after playing an 8 uses an inline overlay (dimmed scrim + 4 large suit buttons in a centered card) instead of `confirmationDialog`, matching the rest of the app's visual language. The draw-two warning banner color-codes by severity: orange/yellow for small penalties, orange-red for ≥4, deep red + white text + `flame.fill` icon for ≥8. Banner pulses with `easeInOut` animation.

`UnoView`: draw pile button turns red and shows "LOW!" label when `game.drawPile.count ≤ 5`. `handSizeStrip` now shows color-distribution pips (colored circles with counts) below the bar for the local player's hand. `currentColorEmoji: String` (🔴/🟡/🟢/🔵) shown on active color chip. `UnoGame.resultText` appends `"🃏 draws: S1:N S2:N …"` per-seat draw tally when total ≥4 draws occurred.

### RootView / GameTile
`GameTile` shows win/loss record (`statsLine`, format `"8W 4L"`, plus a `🔥N` streak suffix at streak ≥ 3 via `GameStats.summary`) and best-score (`bestLine`, with a star icon, gold tint) as two stacked pills rather than picking only one. Games with no `played` history show a green "NEW" badge in the top-right corner instead.

Win-rate is now displayed as a `%` badge (top-right of icon circle) and a colored dot: green ≥ 56%, yellow 35–55%, red < 35%. Computed from `GameStats.winRate: Double?` (not string-based). `GameTile` accepts `winRate: Double?`; supplied by `gameSection(_:)` from `stats.stats(for: kind).winRate`.

`PressableTileStyle` fires a `.soft` `UIImpactFeedbackGenerator` on press. `HomeBackground` now also drifts 12 suit symbols (up from 10) with slow independent rotation (90 s period) in addition to the vertical float.

### TableView
`PlayerAvatarCell` (in `CardViews.swift`) replaces the inline avatar code in the turn-indicator strip. It animates a pulsing green ring around the active player's circle and resets cleanly when `isCurrent` changes.

`resultBanner` now delegates text rendering to `resultTextView(_:)`, which splits `resultText` at ` · ` into a bold headline (first segment) plus scrollable stat pills (remaining segments up to 5). This surfaces the richer `resultText` content added in the engine passes.

`LobbyWaitView` now uses a `ScrollView` container with an animated scan-ring around the game icon. Empty seats show "Will become a bot" subtitle; the start button has a drop shadow and larger corner radius.

### CardViews
`HandView` card taps now fire `.light` haptic feedback when the tapped card is legal. `OpponentHandView` shows a dashed empty-slot outline when `count == 0`, and the `+N` overflow badge is styled with a black pill background. `FeltBackground` renders a subtle canvas noise grain (with `.overlay` blend mode) to simulate felt fiber texture. `PlayerAvatarCell` is a new reusable component extracted from `TableView`.

### ProfilesView
- Shows per-game ELO + W/L/D record for the active profile's played games (sorted by games played), with a win-rate progress bar under each row and the ELO number color-tiered (`eloColor(_:)`: green ≥1200, yellow 1000–1199, red <1000).
- ELO delta vs starting rating (1200) shown as green `+N` / red `-N` next to each ELO number. The starting baseline is 1200 (`Elo.initial`), not 1000.
- Total games played shown as a small pill badge next to each game title (e.g. `"15"`).
- `PlayerProfile.symbols` has 28 entries (was 16); includes chess, gamecontroller, brain, atom, etc.
- `Avatar.colors` array drives both the avatar gradient and the color picker swatch row.

### TrickGameViews
- **Spades bidding panel**: now shows a per-suit hand-strength strip (card count + high-card labels per suit) and a cyan "Rec. N" chip from `Bot.estimateSpadesBid(hand:)`. Recommended bid is highlighted in cyan in the bid picker row.
- **Bridge auction panel**: replaced 4-chip history with a full dealer-aligned grid (4-column, one column per seat) with colored bid chips and pass labels.
- **Bridge score strip**: vulnerability shown via "VUL" detail on `scoreChip` with orange bagWarning styling.
- **Euchre tricks bar**: shows ⚡ALONE badge, N/3 fraction. Score strip shows 🔥N streak from `teamRoundStreak`. `resultText` shows full trump-split breakdown when ≥2 suits called (e.g. `"♠×4 ♥×2"`).
- **Spades tricks bar**: shows projected bag delta (+N🎒) and ✓/N/contract progress during playing. Nil bid chips show `shield.fill` icon (green) or `xmark.circle.fill` (red), count of tricks taken if busted.
- **Hearts moon pulse**: TrickTableView animates a pulsing effect on the moon-candidate chip when a potential moon-shooter is detected.

## Adding a New Game

1. Create `Engine/MyGame.swift` conforming to `GameEngine` with a unique `GameKind` case.
2. Add `case .myGame` to `GameKind` enum in `Model/GameKind.swift`.
3. Add decode and encode cases in `AnyGame` (`GameEngine.swift`).
4. Add `case .myGame(MyGameMove)` to `Move` enum (`Model/Move.swift`).
5. Create `Views/MyGameView.swift` with `@ObservedObject var session: GameSession`.
6. Wire the view into `TableView.swift`'s game-kind dispatch.
7. Add a smoke test in `EngineCheck/Tests/SmokeTests.swift`.
8. If the game has hidden cards, implement `redacted(for:)`.

## Testing

`EngineCheck/` target (XCTest). Run with `Cmd+U` or `xcodebuild test`.
Tests call `game.applyValidated(_:)` which enforces `isLegal` before applying.
`game.verify(_:)` returns `Result<Self, GameError>` for non-mutating legality checks.

Note: as of the current `Parlor.xcodeproj`, only the `Parlor` app target/scheme is configured — `EngineCheck/Tests/SmokeTests.swift` exists on disk but isn't wired into a test target, so `xcodebuild test` has nothing to run until that target is added in Xcode. Until then, verify engine changes with `swiftc -typecheck` against `Engine/*.swift` + `Model/*.swift`, and confirm the app target with `xcodebuild build`.
