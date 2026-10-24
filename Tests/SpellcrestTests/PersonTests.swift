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
    "hat/wide": [0x000010FF, 0x000010FF, 0x000010FF],
]

private func compose(_ person: PersonFile) throws -> [UInt32] {
    try person.compose(kit) { path in (parts[path]!, parts[path]!.count) }.pixels // a row each
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
    #expect(message(PersonFile(parts: ["body": "plain", "hat": "wide"])) == "hat/wide is 3 pixels wide and a person 2: a part has every frame, laid out as theirs")
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

@Test func aPartDrawnOnceFollowsItsAnchorAndLeavesTheBodyInFrontOfIt() throws {
    // Four frames of two pixels: a body, and a cap drawn once that follows the head, which moves a pixel right in
    // frame 2 and is gone in frame 3; in frame 1 an arm is in front of the head's second pixel.
    let kit = KitFile(frameWidth: 2, frameHeight: 1, frames: 4, columns: 4, slots: [.init(name: "body"), .init(name: "hat", follows: "head")],
                      materials: [], anchors: ["head": [.init(0, 0), .init(0, 0), .init(1, 0), nil]], front: "front")
    let (b, c): (UInt32, UInt32) = (0x8040_20FF, 0x2040_A0FF)
    let images: [String: [UInt32]] = ["body/plain": [b, b, b, b, b, b, b, b], "hat/cap": [c, c], "hat/big": [c, c, c], "front": [0, 0, 0, 0xFF, 0, 0, 0, 0]]
    func person(_ parts: [String: String]) throws -> (pixels: [UInt32], width: Int) {
        try PersonFile(parts: parts).compose(kit) { path in (images[path]!, path == "hat/big" ? 3 : path == "hat/cap" ? 2 : 8) }
    }
    #expect(try person(["body": "plain", "hat": "cap"]) == ([c, c, c, b, b, c, b, b], 8))
    #expect(try person(["hat": "cap"]) == ([c, c, c, 0, 0, c, 0, 0], 8)) // laid out as the kit says, with no part of every frame
    #expect(throws: PersonError("hat/big is 3 pixels wide and a person 8: a part has every frame, laid out as theirs, or one frame to follow the head")) {
        try person(["body": "plain", "hat": "big"])
    }
    let file = FileManager.default.temporaryDirectory.appending(path: "kit-\(UUID()).json")
    try kit.write(to: file)
    #expect(try KitFile(contentsOf: file) == kit && String(decoding: try Data(contentsOf: file), as: UTF8.self).contains(#""head":[[0,0],[0,0],[1,0],null]"#))
}
