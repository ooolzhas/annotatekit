// ScreenMatch: re-entering annotate mode on a screen that already has pins picks that screen;
// a different screen, or a sample of another size, picks none.

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct ScreenMatchTests {
    let home = [UInt8](repeating: 200, count: 64)
    let settings = [UInt8](repeating: 60, count: 64)

    @Test("the same screen matches, a ticking clock included; a real change doesn't")
    func sameScreenMatches() {
        var changed = home
        changed[0...7] = ArraySlice(repeating: 0, count: 8)  // mean difference 25: a real change
        var clock = home
        clock[0] = 100  // mean difference ~1.6: a ticking clock
        #expect(ScreenMatch.match(home, among: [(1, settings), (2, home)]) == 2)
        #expect(ScreenMatch.match(clock, among: [(1, home)]) == 1)
        #expect(ScreenMatch.match(changed, among: [(1, home)]) == nil)
    }

    @Test("a different screen, a size mismatch or no candidates match nothing")
    func noMatch() {
        #expect(ScreenMatch.match(settings, among: [(1, home)]) == nil)
        #expect(ScreenMatch.match([UInt8](repeating: 200, count: 32), among: [(1, home)]) == nil)
        #expect(ScreenMatch.match(home, among: []) == nil)
    }

    @Test("the closest of several matching screens wins")
    func closestWins() {
        let near = [UInt8](repeating: 201, count: 64)
        let farther = [UInt8](repeating: 203, count: 64)
        #expect(ScreenMatch.match(home, among: [(1, farther), (2, near)]) == 2)
    }
}
