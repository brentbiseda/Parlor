// QuiplashPrompts.swift — Prompt bank for Prompt Party

struct QuiplashPrompt: Codable {
    let id: Int
    let text: String
}

enum QuiplashPromptBank {
    static var all: [QuiplashPrompt] { prompts }
    static func byID(_ id: Int) -> QuiplashPrompt? { all.first { $0.id == id } }

    private static let prompts: [QuiplashPrompt] = [
        // 1–30: Worst things
        QuiplashPrompt(id: 1,  text: "The worst superpower to wake up with"),
        QuiplashPrompt(id: 2,  text: "The worst thing to hear your pilot say"),
        QuiplashPrompt(id: 3,  text: "The worst thing to put on a birthday cake"),
        QuiplashPrompt(id: 4,  text: "The worst name for a hospital"),
        QuiplashPrompt(id: 5,  text: "The worst career advice you could give a child"),
        QuiplashPrompt(id: 6,  text: "A terrible idea for a theme park ride"),
        QuiplashPrompt(id: 7,  text: "The worst thing a fortune cookie could say"),
        QuiplashPrompt(id: 8,  text: "The worst way to end a first date"),
        QuiplashPrompt(id: 9,  text: "The last thing you want to hear from your dentist"),
        QuiplashPrompt(id: 10, text: "The world's worst dating profile opening line"),
        QuiplashPrompt(id: 11, text: "The worst thing to name your new baby"),
        QuiplashPrompt(id: 12, text: "A terrible idea for a new breakfast cereal"),
        QuiplashPrompt(id: 13, text: "The worst person to get stuck in an elevator with"),
        QuiplashPrompt(id: 14, text: "The worst thing to tweet from a company account"),
        QuiplashPrompt(id: 15, text: "The worst gift to give at a baby shower"),
        // 16–40: What/if
        QuiplashPrompt(id: 16, text: "What your dog is actually thinking"),
        QuiplashPrompt(id: 17, text: "What the mannequins in stores are secretly plotting"),
        QuiplashPrompt(id: 18, text: "What's really written in the terms and conditions"),
        QuiplashPrompt(id: 19, text: "What GPS says when it's in a bad mood"),
        QuiplashPrompt(id: 20, text: "What pigeons actually talk about"),
        QuiplashPrompt(id: 21, text: "The secret ingredient in grandma's famous recipe"),
        QuiplashPrompt(id: 22, text: "If clouds had feelings, what would they be right now?"),
        QuiplashPrompt(id: 23, text: "What your search history says about you"),
        QuiplashPrompt(id: 24, text: "If laziness was an Olympic sport, how would you train?"),
        QuiplashPrompt(id: 25, text: "What dinosaurs were really like before scientists ruined everything"),
        QuiplashPrompt(id: 26, text: "The most unrealistic thing about action movies"),
        QuiplashPrompt(id: 27, text: "What AI secretly wants to be when it grows up"),
        QuiplashPrompt(id: 28, text: "The text your phone autocorrects to that causes the most chaos"),
        QuiplashPrompt(id: 29, text: "Why the last person to use the microwave is evil"),
        QuiplashPrompt(id: 30, text: "The real reason cats knock things off tables"),
        // 31–55: Fill in the blank
        QuiplashPrompt(id: 31, text: "My workout routine: ___"),
        QuiplashPrompt(id: 32, text: "The thing I definitely didn't eat at 2am: ___"),
        QuiplashPrompt(id: 33, text: "The rejected slogan for coffee: ___"),
        QuiplashPrompt(id: 34, text: "What's on the secret menu at McDonald's: ___"),
        QuiplashPrompt(id: 35, text: "A class nobody wants but everyone needs: ___"),
        QuiplashPrompt(id: 36, text: "My villain origin story: ___"),
        QuiplashPrompt(id: 37, text: "The rejected bumper sticker: ___"),
        QuiplashPrompt(id: 38, text: "My spirit animal would be ___ because ___"),
        QuiplashPrompt(id: 39, text: "The thing I said to my plants: ___"),
        QuiplashPrompt(id: 40, text: "An apology letter to my refrigerator: ___"),
        QuiplashPrompt(id: 41, text: "The product that shouldn't exist but someone would buy: ___"),
        QuiplashPrompt(id: 42, text: "The motto for my imaginary country: ___"),
        QuiplashPrompt(id: 43, text: "The thing aliens will judge us most harshly for: ___"),
        QuiplashPrompt(id: 44, text: "My autobiography title: ___"),
        QuiplashPrompt(id: 45, text: "The historical event that was actually kind of awkward: ___"),
        // 56–70: More creative
        QuiplashPrompt(id: 46, text: "The thing that should be an Olympic sport but isn't"),
        QuiplashPrompt(id: 47, text: "A rejected name for a new country"),
        QuiplashPrompt(id: 48, text: "What ghosts are actually doing in haunted houses"),
        QuiplashPrompt(id: 49, text: "The reason Mondays were invented"),
        QuiplashPrompt(id: 50, text: "What the Statue of Liberty is really thinking"),
        QuiplashPrompt(id: 51, text: "The review that would get you banned from Yelp"),
        QuiplashPrompt(id: 52, text: "What goes through a squirrel's mind when it sees a car"),
        QuiplashPrompt(id: 53, text: "The funniest possible job title"),
        QuiplashPrompt(id: 54, text: "The worst superhero name that is still technically heroic"),
        QuiplashPrompt(id: 55, text: "The thing time travelers would be most disappointed about"),
        QuiplashPrompt(id: 56, text: "The most suspicious thing to say at customs"),
        QuiplashPrompt(id: 57, text: "How to ruin a dinner party in one sentence"),
        QuiplashPrompt(id: 58, text: "The worst thing the moon could announce"),
        QuiplashPrompt(id: 59, text: "What bears actually think of camping"),
        QuiplashPrompt(id: 60, text: "A new law that would immediately improve society"),
    ]
}
