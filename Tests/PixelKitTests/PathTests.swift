import Testing
@testable import PixelKit

/// A scene of `rows` of 8-pixel tiles, "#" solid, with an entity whose 8x8 hitbox is in cell `walker`: its entities[0].
@MainActor func place(_ rows: [String], walker: SIMD2<Int>) -> Scene {
    let scene = Scene()
    scene.tilemap = Tilemap("tiles", tileSize: 8, rows: rows, legend: ["#": 0])
    let entity = Entity()
    entity.hitbox = Rect(x: 0, y: 0, width: 8, height: 8)
    scene.add(entity, at: [Double(walker.x * 8), Double(walker.y * 8)])
    return scene
}

/// The middles of 8-pixel cells.
func middles(_ cells: [SIMD2<Int>]) -> [Vector] { cells.map { [Double($0.x * 8 + 4), Double($0.y * 8 + 4)] } }

@MainActor @Test func pathsGoAroundWallsTurningAsLittleAsTheyCanOrAreNilWithNoWay() {
    var scene = place(["..#..", "..#..", "....."], walker: [0, 0])
    #expect(scene.entities[0].path(to: [36, 4]) == middles([[0, 1], [0, 2], [1, 2], [2, 2], [3, 2], [4, 2], [4, 1], [4, 0]]))
    #expect(scene.entities[0].path(to: [4, 20]) == middles([[0, 1], [0, 2]]))
    #expect(scene.entities[0].path(to: [7, 7]) == []) // its own cell: it's there
    #expect(scene.entities[0].path(to: [20, 4]) == nil) // in the wall
    #expect(scene.entities[0].path(to: [44, 4]) == nil && scene.entities[0].path(to: [4, -1]) == nil) // off the map

    scene = place(["..#..", "..#..", "..#.."], walker: [0, 0])
    #expect(scene.entities[0].path(to: [36, 4]) == nil) // no way through
    scene.tilemap!.setTile(nil, at: [20, 12], layer: 0)
    #expect(scene.entities[0].path(to: [36, 4])?.count == 6) // through the gap
    #expect(Entity().path(to: [4, 4]) == nil) // in no scene
}

@MainActor @Test func diagonalPathsNeverCutACornerAndGoOnStraight() {
    var scene = place(["..", ".."], walker: [0, 0])
    #expect(scene.entities[0].path(to: [12, 12], diagonals: true) == middles([[1, 1]]))
    #expect(scene.entities[0].path(to: [12, 12])?.count == 2)
    scene = place(["..", "#."], walker: [0, 0])
    #expect(scene.entities[0].path(to: [12, 12], diagonals: true) == middles([[1, 0], [1, 1]])) // not past the wall's corner

    scene = place(["......", "......", "......"], walker: [0, 0])
    let path = scene.entities[0].path(to: [44, 20], diagonals: true) ?? []
    let steps = zip([[4, 4]] + path, path).map { $1 - $0 }
    #expect(path.count == 5 && path.last == [44, 20]) // 2 diagonal steps and 3 across
    #expect(zip(steps, steps.dropFirst()).filter { $0 != $1 }.count == 1) // in two straight runs
}

@MainActor @Test func pathsGoAroundSolidEntitiesButNotTheWalkerOrOneAtTheGoal() {
    let scene = place([".....", ".....", "#####"], walker: [0, 1])
    let (walker, rock) = (scene.entities[0], Entity())
    (walker.solid, rock.solid) = (true, true)
    rock.hitbox = Rect(x: 0, y: 0, width: 8, height: 8)
    scene.add(rock, at: [20, 8]) // in cells (2, 1) and (3, 1)
    #expect(walker.path(to: [36, 12]) == middles([[0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [4, 1]])) // over it
    rock.position = [32, 8] // at the goal, like a solid player being chased
    #expect(walker.path(to: [36, 12]) == middles([[1, 1], [2, 1], [3, 1], [4, 1]]))
    rock.solid = false
    rock.position = [20, 8]
    #expect(walker.path(to: [36, 12]) == middles([[1, 1], [2, 1], [3, 1], [4, 1]])) // not solid: walked through
}

@MainActor @Test func anEntityWalksAPathAroundAWallToItsEndWithoutTouchingIt() {
    let scene = Scene()
    scene.tilemap = Tilemap("tiles", tileSize: 8, rows: ["...#....", "...#....", "...#....", "........"], legend: ["#": 0])
    let walker = Entity()
    walker.hitbox = Rect(x: 1, y: 1, width: 6, height: 6) // a bit smaller than a tile
    scene.add(walker, at: [1, 2]) // its middle (5, 6), off its cell's
    var route = walker.path(to: [60, 4]) ?? []
    #expect(route.count == 13)
    var updates = 0
    while !route.isEmpty, updates < 200 {
        walker.walk(1.0 / 60, along: &route, speed: 90) // 1.5 pixels an update, which doesn't divide a tile
        #expect(!scene.tilemap!.isSolid(walker.box(at: walker.position)))
        updates += 1
    }
    #expect(walker.middle == [60, 4] && walker.velocity == .zero)
    #expect((68...72).contains(updates)) // 102 pixels at 1.5 an update
    walker.walk(1.0 / 60, along: &route, speed: 90)
    #expect(walker.middle == [60, 4]) // there, it stays
}
