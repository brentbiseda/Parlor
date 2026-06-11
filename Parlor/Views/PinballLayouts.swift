import SpriteKit

/// One themed pinball table. The scene is parameterized entirely by this
/// struct: colors, gravity, bumper field, target bank, decorative skyline,
/// extra rails (bridges/slopes), an optional spinner, and an optional
/// tunnel that swallows the ball and fires it out somewhere else.
/// The playfield is 390×700; the launch lane sits right of x = 352.
struct PinballTheme: Identifiable {
    struct Bumper {
        var x: CGFloat
        var y: CGFloat
        var radius: CGFloat = 21
        var color: SKColor
        var points = 100
    }

    struct Decal {
        var text: String
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat = 40
        var alpha: CGFloat = 0.45
    }

    struct Tunnel {
        var entry: CGPoint
        var exit: CGPoint
        var label: String
    }

    let id: String
    let name: String
    let blurb: String
    var background = SKColor(red: 0.05, green: 0.07, blue: 0.16, alpha: 1)
    var wall = SKColor(white: 1, alpha: 0.28)
    var flipper = SKColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1)
    var gravity: CGFloat = -7.2
    var bumpers: [Bumper]
    var targetColor = SKColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 1)
    /// X positions of the drop-target bank (y fixed near the arch).
    var targetXs: [CGFloat] = [137, 195, 253]
    /// Extra wall polylines — bridges, slopes, rails.
    var rails: [[CGPoint]] = []
    var decals: [Decal] = []
    var tunnel: Tunnel? = nil
    var spinner: CGPoint? = nil
    var watermark: String

    static func theme(id: String) -> PinballTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [PinballTheme] = [
        PinballTheme(
            id: "classic", name: "Classic Parlor", blurb: "The house table — pure flow.",
            bumpers: [Bumper(x: 110, y: 470, color: SKColor(hue: 0.0, saturation: 0.75, brightness: 0.9, alpha: 1)),
                      Bumper(x: 280, y: 470, color: SKColor(hue: 0.55, saturation: 0.75, brightness: 0.9, alpha: 1)),
                      Bumper(x: 195, y: 545, color: SKColor(hue: 0.83, saturation: 0.75, brightness: 0.9, alpha: 1))],
            decals: [Decal(text: "♠", x: 70, y: 330, size: 34, alpha: 0.15),
                     Decal(text: "♥", x: 310, y: 330, size: 34, alpha: 0.15)],
            watermark: "PARLOR"
        ),

        PinballTheme(
            id: "pittsburgh", name: "Pittsburgh, PA", blurb: "Black & gold, three rivers, 446 bridges.",
            background: SKColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1),
            wall: SKColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 0.55),
            flipper: SKColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 1),
            bumpers: [Bumper(x: 100, y: 480, color: SKColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 1)),
                      Bumper(x: 290, y: 480, color: SKColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 1)),
                      Bumper(x: 195, y: 555, radius: 24, color: SKColor(white: 0.15, alpha: 1), points: 150)],
            targetColor: SKColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 1),
            // The two rivers meeting at the Point, plus an incline rail.
            rails: [[CGPoint(x: 8, y: 420), CGPoint(x: 150, y: 330)],
                    [CGPoint(x: 352, y: 420), CGPoint(x: 240, y: 330)],
                    [CGPoint(x: 60, y: 250), CGPoint(x: 130, y: 215)]],
            decals: [Decal(text: "🌉", x: 100, y: 380, size: 40),
                     Decal(text: "🌉", x: 290, y: 380, size: 40),
                     Decal(text: "412", x: 195, y: 250, size: 26, alpha: 0.3),
                     Decal(text: "🏗", x: 60, y: 590, size: 30, alpha: 0.4)],
            watermark: "STEEL CITY"
        ),

        PinballTheme(
            id: "chicago", name: "Chicago Hotdog", blurb: "Drag it through the garden. No ketchup.",
            background: SKColor(red: 0.2, green: 0.13, blue: 0.04, alpha: 1),
            wall: SKColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.5),
            flipper: SKColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1),
            bumpers: [Bumper(x: 105, y: 470, color: SKColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 1)),    // tomato
                      Bumper(x: 285, y: 470, color: SKColor(red: 0.35, green: 0.65, blue: 0.2, alpha: 1)),    // pickle
                      Bumper(x: 195, y: 545, color: SKColor(red: 0.95, green: 0.8, blue: 0.15, alpha: 1))],   // mustard
            targetColor: SKColor(red: 0.45, green: 0.8, blue: 0.3, alpha: 1),
            decals: [Decal(text: "🌭", x: 70, y: 350, size: 44),
                     Decal(text: "🌭", x: 320, y: 350, size: 44),
                     Decal(text: "🧅", x: 60, y: 590, size: 26, alpha: 0.4),
                     Decal(text: "🌶", x: 330, y: 250, size: 26, alpha: 0.4)],
            spinner: CGPoint(x: 195, y: 400),
            watermark: "NO KETCHUP"
        ),

        PinballTheme(
            id: "london", name: "London", blurb: "Take the Tube — mind the gap.",
            background: SKColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1),
            wall: SKColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 0.55),
            flipper: SKColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 1),
            bumpers: [Bumper(x: 110, y: 480, color: SKColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 1)),
                      Bumper(x: 280, y: 480, color: SKColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1)),
                      Bumper(x: 195, y: 550, color: SKColor(white: 0.9, alpha: 1))],
            targetColor: SKColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 1),
            decals: [Decal(text: "🕰", x: 90, y: 360, size: 46),
                     Decal(text: "🎡", x: 300, y: 360, size: 44),
                     Decal(text: "☂️", x: 60, y: 250, size: 28, alpha: 0.4),
                     Decal(text: "🚇", x: 56, y: 285, size: 24, alpha: 0.8)],
            tunnel: Tunnel(entry: CGPoint(x: 55, y: 260), exit: CGPoint(x: 280, y: 620), label: "TUBE"),
            watermark: "MIND THE GAP"
        ),

        PinballTheme(
            id: "paris", name: "Paris", blurb: "La ville lumière — ride the Métro.",
            background: SKColor(red: 0.14, green: 0.09, blue: 0.18, alpha: 1),
            wall: SKColor(red: 0.95, green: 0.75, blue: 0.55, alpha: 0.5),
            flipper: SKColor(red: 0.93, green: 0.6, blue: 0.65, alpha: 1),
            bumpers: [Bumper(x: 110, y: 470, color: SKColor(red: 0.93, green: 0.6, blue: 0.65, alpha: 1)),
                      Bumper(x: 280, y: 470, color: SKColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1)),
                      Bumper(x: 195, y: 545, radius: 23, color: SKColor(red: 0.95, green: 0.83, blue: 0.4, alpha: 1), points: 125)],
            targetColor: SKColor(red: 0.95, green: 0.83, blue: 0.4, alpha: 1),
            decals: [Decal(text: "🗼", x: 195, y: 420, size: 90, alpha: 0.3),
                     Decal(text: "🥐", x: 70, y: 330, size: 30, alpha: 0.45),
                     Decal(text: "☕️", x: 320, y: 330, size: 28, alpha: 0.45),
                     Decal(text: "🚇", x: 56, y: 285, size: 24, alpha: 0.8)],
            tunnel: Tunnel(entry: CGPoint(x: 55, y: 260), exit: CGPoint(x: 195, y: 630), label: "MÉTRO"),
            watermark: "VILLE LUMIÈRE"
        ),

        PinballTheme(
            id: "switzerland", name: "Switzerland", blurb: "Steep slopes, heavy gravity, fine cheese.",
            background: SKColor(red: 0.09, green: 0.13, blue: 0.17, alpha: 1),
            wall: SKColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 0.45),
            flipper: SKColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1),
            gravity: -8.6,
            bumpers: [Bumper(x: 105, y: 475, color: SKColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1)),     // emmental
                      Bumper(x: 285, y: 475, color: SKColor(red: 0.45, green: 0.3, blue: 0.2, alpha: 1)),     // chocolate
                      Bumper(x: 195, y: 550, color: SKColor(white: 0.95, alpha: 1))],                          // snow
            targetColor: SKColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1),
            // Ski slopes the ball can ride.
            rails: [[CGPoint(x: 8, y: 460), CGPoint(x: 120, y: 380), CGPoint(x: 160, y: 372)],
                    [CGPoint(x: 352, y: 500), CGPoint(x: 250, y: 410), CGPoint(x: 215, y: 404)]],
            decals: [Decal(text: "🏔", x: 100, y: 600, size: 46),
                     Decal(text: "🏔", x: 280, y: 600, size: 52),
                     Decal(text: "🧀", x: 70, y: 330, size: 30, alpha: 0.45),
                     Decal(text: "⛷", x: 320, y: 300, size: 28, alpha: 0.45)],
            watermark: "THE ALPS"
        ),

        PinballTheme(
            id: "space", name: "Deep Space", blurb: "Low gravity. The ball just floats.",
            background: SKColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 1),
            wall: SKColor(red: 0.5, green: 0.4, blue: 1.0, alpha: 0.5),
            flipper: SKColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1),
            gravity: -4.6,
            bumpers: [Bumper(x: 110, y: 470, color: SKColor(red: 0.9, green: 0.3, blue: 0.9, alpha: 1)),
                      Bumper(x: 280, y: 470, color: SKColor(red: 0.3, green: 0.9, blue: 0.9, alpha: 1)),
                      Bumper(x: 195, y: 550, radius: 26, color: SKColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1), points: 150)],
            targetColor: SKColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1),
            decals: [Decal(text: "🪐", x: 90, y: 360, size: 44),
                     Decal(text: "🚀", x: 300, y: 340, size: 34),
                     Decal(text: "✦", x: 60, y: 620, size: 18, alpha: 0.6),
                     Decal(text: "✦", x: 320, y: 580, size: 14, alpha: 0.5),
                     Decal(text: "✦", x: 150, y: 300, size: 12, alpha: 0.5)],
            spinner: CGPoint(x: 195, y: 390),
            watermark: "ZERO G"
        ),

        PinballTheme(
            id: "tokyo", name: "Neon Tokyo", blurb: "Fast, bright, electric.",
            background: SKColor(red: 0.1, green: 0.03, blue: 0.1, alpha: 1),
            wall: SKColor(red: 0.2, green: 0.95, blue: 0.9, alpha: 0.55),
            flipper: SKColor(red: 1.0, green: 0.3, blue: 0.65, alpha: 1),
            gravity: -8.0,
            bumpers: [Bumper(x: 105, y: 475, color: SKColor(red: 1.0, green: 0.3, blue: 0.65, alpha: 1)),
                      Bumper(x: 285, y: 475, color: SKColor(red: 0.2, green: 0.95, blue: 0.9, alpha: 1)),
                      Bumper(x: 195, y: 548, color: SKColor(red: 0.95, green: 0.9, blue: 0.2, alpha: 1))],
            targetColor: SKColor(red: 1.0, green: 0.3, blue: 0.65, alpha: 1),
            decals: [Decal(text: "🗼", x: 90, y: 380, size: 50, alpha: 0.4),
                     Decal(text: "⛩", x: 300, y: 360, size: 40),
                     Decal(text: "🍣", x: 60, y: 280, size: 26, alpha: 0.45)],
            spinner: CGPoint(x: 240, y: 400),
            watermark: "NEON TOKYO"
        ),

        PinballTheme(
            id: "pirate", name: "Pirate Cove", blurb: "Fire the cannon, keep the gold.",
            background: SKColor(red: 0.02, green: 0.12, blue: 0.14, alpha: 1),
            wall: SKColor(red: 0.85, green: 0.7, blue: 0.4, alpha: 0.5),
            flipper: SKColor(red: 0.85, green: 0.7, blue: 0.4, alpha: 1),
            bumpers: [Bumper(x: 110, y: 475, color: SKColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1)),
                      Bumper(x: 280, y: 475, color: SKColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1)),
                      Bumper(x: 195, y: 548, radius: 24, color: SKColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1), points: 150)],
            targetColor: SKColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1),
            decals: [Decal(text: "🏴‍☠️", x: 90, y: 370, size: 40),
                     Decal(text: "⚓️", x: 300, y: 350, size: 34),
                     Decal(text: "🦜", x: 320, y: 600, size: 28, alpha: 0.5),
                     Decal(text: "💣", x: 56, y: 285, size: 24, alpha: 0.8)],
            tunnel: Tunnel(entry: CGPoint(x: 55, y: 260), exit: CGPoint(x: 240, y: 640), label: "CANNON"),
            watermark: "PIRATE COVE"
        ),

        PinballTheme(
            id: "vegas", name: "Vegas", blurb: "Double bumpers. The house still wins.",
            background: SKColor(red: 0.08, green: 0.05, blue: 0.02, alpha: 1),
            wall: SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.55),
            flipper: SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1),
            bumpers: [Bumper(x: 105, y: 475, color: SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1), points: 200),
                      Bumper(x: 285, y: 475, color: SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1), points: 200),
                      Bumper(x: 195, y: 548, color: SKColor(white: 0.15, alpha: 1), points: 200)],
            targetColor: SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1),
            decals: [Decal(text: "🎰", x: 90, y: 360, size: 40),
                     Decal(text: "🎲", x: 300, y: 350, size: 34),
                     Decal(text: "♠", x: 60, y: 600, size: 24, alpha: 0.4),
                     Decal(text: "♦", x: 330, y: 600, size: 24, alpha: 0.4)],
            spinner: CGPoint(x: 195, y: 395),
            watermark: "JACKPOT"
        ),
    ]
}
