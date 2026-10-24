import Foundation
import SpellcrestProtocol
import Testing

/// A kit of two-pixel parts: a body in skin and brown boots, a robe in cloth and a hat in cloth and hair.
private let kit = KitFile(frameWidth: 2, frameHeight: 1, animations: ["stand": .init(frames: [0], fps: 2)],
                          slots: [.init(name: "body"), .init(name: "robe", materials: ["cloth"]), .init(name: "hat", materials: ["cloth", "hair"])],
                          materials: [.init(name: "cloth", ramps: [.init(name: "blue", colors: ["#000010", "#000020"]),
                                                                   .init(name: "red", colors: ["#100000", "#200000"])]),
                                      .init(name: "hair", ramps: [.init(name: "brown", colors: ["#301000"]), .init(name: "purple", colors: ["#300030"])])])
private let parts: [String: [UInt32]] = [
    "body/plain": [0xF0C0A0FF, 0x301000FF], // skin, and a boot in the hair's brown
    "robe/long": [0x000020FF, 0], // the lit blue, and clear
    "hat/witch": [0x00001080, 0x301000FF], // the dark blue half see-through, and hair
    "hat/tiny": [0x000010FF],
]

private func compose(_ person: PersonFile) throws -> [UInt32] {
    try person.compose(kit) { slot, name in parts["\(slot)/\(name)"]! }
}

@Test func aPersonStacksItsPartsBackToFrontInTheShadesItWears() throws {
    #expect(try compose(PersonFile(parts: ["body": "plain", "robe": "long"])) == [0x000020FF, 0x301000FF]) // as drawn
    #expect(try compose(PersonFile(parts: ["body": "plain", "robe": "long"], wears: ["cloth": "red"])) == [0x200000FF, 0x301000FF])
    // The hat wears hair, the body doesn't, so its boot keeps its brown; half the hat's red shows over the robe's.
    let witch = try compose(PersonFile(parts: ["robe": "long", "body": "plain", "hat": "witch"], wears: ["cloth": "red", "hair": "purple"]))
    #expect(witch == [0x180000FF, 0x300030FF])
}

@Test func aPersonThatCantBeMadeSaysWhatToChange() {
    func message(_ person: PersonFile) -> String? {
        do {
            _ = try compose(person)
            return nil
        } catch {
            return (error as? PersonError)?.description
        }
    }
    #expect(message(PersonFile(parts: ["body": "plain"], wears: ["cloth": "green"])) == "the kit's cloth has no ramp called green, only blue, red")
    #expect(message(PersonFile(parts: ["cape": "short"])) == "the kit has no slot called cape")
    #expect(message(PersonFile(parts: ["body": "plain"], wears: ["skin": "tan"])) == "the kit has no material called skin")
    #expect(message(PersonFile(parts: [:])) == "a person wears a part in one slot at least")
    #expect(message(PersonFile(parts: ["body": "plain", "hat": "tiny"]))?.hasPrefix("hat/tiny has 1 pixels, and body/plain 2") == true)
}

@Test func kitsAndPeopleReadAsTheyWereWritten() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "people-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try kit.write(to: folder.appending(path: "kit.json"))
    #expect(try KitFile(contentsOf: folder.appending(path: "kit.json")) == kit)
    let witch = PersonFile(parts: ["body": "plain", "hat": "witch"], wears: ["cloth": "red"])
    try witch.write(to: folder.appending(path: "witch.person"))
    #expect(try PersonFile(contentsOf: folder.appending(path: "witch.person")) == witch)
    #expect(kit.sheet == SheetFile(frameWidth: 2, frameHeight: 1, animations: ["stand": .init(frames: [0], fps: 2)]))
}
