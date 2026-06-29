// BluffWords.swift — Word bank for Bluff! (Balderdash-style game)

struct BluffWord: Codable {
    let id: Int
    let word: String
    let realDefinition: String
    let category: String   // "word", "acronym", "law", "person"
}

enum BluffWordBank {
    static var all: [BluffWord] { words }
    static func byID(_ id: Int) -> BluffWord? { all.first { $0.id == id } }

    private static let words: [BluffWord] = [
        // Obscure words
        BluffWord(id: 1,  word: "Petrichor",       realDefinition: "The pleasant, earthy smell after rain falls on dry ground", category: "word"),
        BluffWord(id: 2,  word: "Sonder",           realDefinition: "The realization that each passerby has a life as vivid and complex as your own", category: "word"),
        BluffWord(id: 3,  word: "Borborygmus",      realDefinition: "A rumbling sound made by gas moving through the intestines", category: "word"),
        BluffWord(id: 4,  word: "Widdershins",      realDefinition: "In a direction contrary to the sun's course; counterclockwise", category: "word"),
        BluffWord(id: 5,  word: "Ullage",           realDefinition: "The amount by which a container falls short of being full", category: "word"),
        BluffWord(id: 6,  word: "Flibbertigibbet",  realDefinition: "A frivolous, flighty, or excessively talkative person", category: "word"),
        BluffWord(id: 7,  word: "Oxter",            realDefinition: "An armpit, or the arm itself when used to carry something", category: "word"),
        BluffWord(id: 8,  word: "Snollygoster",     realDefinition: "A dishonest or unscrupulous person, especially a politician", category: "word"),
        BluffWord(id: 9,  word: "Lollygag",         realDefinition: "To spend time aimlessly; to dawdle or fool around", category: "word"),
        BluffWord(id: 10, word: "Defenestration",   realDefinition: "The action of throwing someone or something out of a window", category: "word"),
        BluffWord(id: 11, word: "Vellichor",        realDefinition: "The strange wistfulness of used bookshops", category: "word"),
        BluffWord(id: 12, word: "Hiraeth",          realDefinition: "A deep longing for a home you cannot return to, or that never was", category: "word"),
        BluffWord(id: 13, word: "Bumfuzzle",        realDefinition: "To confuse or perplex someone", category: "word"),
        BluffWord(id: 14, word: "Gardyloo",         realDefinition: "A warning cry formerly used in Edinburgh before throwing slops out a window", category: "word"),
        BluffWord(id: 15, word: "Pettifog",         realDefinition: "To argue about trivial or petty details", category: "word"),
        BluffWord(id: 16, word: "Callipygian",      realDefinition: "Having well-shaped buttocks", category: "word"),
        BluffWord(id: 17, word: "Bloviate",         realDefinition: "To talk at length in a pompous or boastful manner", category: "word"),
        BluffWord(id: 18, word: "Absquatulate",     realDefinition: "To leave somewhere abruptly", category: "word"),
        BluffWord(id: 19, word: "Kerfuffle",        realDefinition: "A commotion or fuss caused by a conflict or controversy", category: "word"),
        BluffWord(id: 20, word: "Cattywampus",      realDefinition: "In disarray; askew; not aligned correctly", category: "word"),
        BluffWord(id: 21, word: "Frowsy",           realDefinition: "Scruffy and neglected in appearance; having an unpleasant smell", category: "word"),
        BluffWord(id: 22, word: "Zwodder",          realDefinition: "A drowsy, half-asleep state of mind", category: "word"),
        BluffWord(id: 23, word: "Groak",            realDefinition: "To silently watch someone eating in hopes they will offer you some food", category: "word"),
        BluffWord(id: 24, word: "Malarkey",         realDefinition: "Meaningless talk; nonsense", category: "word"),
        BluffWord(id: 25, word: "Slubberdegullion", realDefinition: "A slovenly, slobbering person", category: "word"),
        // Acronyms
        BluffWord(id: 26, word: "FUBAR",            realDefinition: "Fouled Up Beyond All Recognition — military slang for something hopelessly broken", category: "acronym"),
        BluffWord(id: 27, word: "NIMBY",            realDefinition: "Not In My Back Yard — objecting to development near one's home", category: "acronym"),
        BluffWord(id: 28, word: "FLOTUS",           realDefinition: "First Lady Of The United States", category: "acronym"),
        BluffWord(id: 29, word: "BOGO",             realDefinition: "Buy One Get One — a retail promotion", category: "acronym"),
        BluffWord(id: 30, word: "CAPTCHA",          realDefinition: "Completely Automated Public Turing test to tell Computers and Humans Apart", category: "acronym"),
        // Laws & concepts
        BluffWord(id: 31, word: "Murphy's Law",     realDefinition: "Anything that can go wrong will go wrong", category: "law"),
        BluffWord(id: 32, word: "Occam's Razor",    realDefinition: "The simplest explanation is usually the correct one", category: "law"),
        BluffWord(id: 33, word: "Dunning-Kruger",   realDefinition: "People with low ability overestimate their competence while experts underestimate theirs", category: "law"),
        BluffWord(id: 34, word: "Parkinson's Law",  realDefinition: "Work expands to fill the time available for its completion", category: "law"),
        BluffWord(id: 35, word: "Peter Principle",  realDefinition: "People are promoted until they reach their level of incompetence", category: "law"),
        // Historical oddities
        BluffWord(id: 36, word: "Jackalope",        realDefinition: "A fictional creature, a jackrabbit with antelope horns, from American folklore", category: "word"),
        BluffWord(id: 37, word: "Frobisher",        realDefinition: "A worker who cleans and polishes things, especially metals — or a proper name", category: "word"),
        BluffWord(id: 38, word: "Gonzo",            realDefinition: "Bizarre or crazy, often relating to journalism with personal involvement", category: "word"),
        BluffWord(id: 39, word: "Perseverate",      realDefinition: "To repeat or prolong an action, thought, or utterance after the stimulus has ceased", category: "word"),
        BluffWord(id: 40, word: "Snicker-snack",    realDefinition: "The sound of sharp cutting, from Lewis Carroll's Jabberwocky — now means brisk sharp cutting", category: "word"),
    ]
}
