// StrokeHistory: undo stops at the strokes the card opened with, redo replays what was undone,
// and a new stroke clears redo.

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct StrokeHistoryTests {
    private enum Step { case undo, redo }

    /// `#expect` can't take a mutating call, so the step runs here and its result is checked.
    private static func step(_ history: inout StrokeHistory, _ step: Step) -> Bool {
        switch step {
        case .undo: history.undo()
        case .redo: history.redo()
        }
    }

    private static func stroke(_ x: Double) -> Stroke {
        Stroke(tool: .pen, points: [AnnotationPoint(x: x, y: 0), AnnotationPoint(x: x, y: 10)])
    }

    @Test("a new drawing can't undo the stroke that made it")
    func firstStrokeIsTheFloor() {
        var history = StrokeHistory(opening: [Self.stroke(1)])
        #expect(!history.canUndo)
        #expect(!history.canRedo)
        #expect(!Self.step(&history, .undo))
        #expect(history.strokes == [Self.stroke(1)])
    }

    @Test("a pin opened with no strokes has nothing to undo or redo")
    func emptyOpening() {
        var history = StrokeHistory()
        #expect(!history.canUndo)
        #expect(!history.canRedo)
        #expect(!Self.step(&history, .redo))
        #expect(history.strokes.isEmpty)
    }

    @Test("undo walks back to the opening state, redo walks forward to the latest")
    func undoRedoWalk() {
        var history = StrokeHistory(opening: [Self.stroke(1)])
        history.add(Self.stroke(2))
        history.add(Self.stroke(3))
        #expect(history.canUndo)
        #expect(!history.canRedo)

        #expect(Self.step(&history, .undo))
        #expect(Self.step(&history, .undo))
        #expect(history.strokes == [Self.stroke(1)])
        #expect(!history.canUndo)
        #expect(history.canRedo)

        #expect(Self.step(&history, .redo))
        #expect(history.strokes == [Self.stroke(1), Self.stroke(2)])
        #expect(Self.step(&history, .redo))
        #expect(history.strokes == [Self.stroke(1), Self.stroke(2), Self.stroke(3)])
        #expect(!history.canRedo)
        #expect(!Self.step(&history, .redo))
    }

    @Test("a new stroke after an undo clears redo")
    func newStrokeClearsRedo() {
        var history = StrokeHistory()
        history.add(Self.stroke(1))
        history.add(Self.stroke(2))
        history.undo()
        history.add(Self.stroke(9))
        #expect(!history.canRedo)
        #expect(history.strokes == [Self.stroke(1), Self.stroke(9)])
    }

    @Test("a reopened pin keeps the strokes it was saved with")
    func reopenedFloor() {
        var history = StrokeHistory(opening: [Self.stroke(1), Self.stroke(2)])
        history.add(Self.stroke(3))
        history.undo()
        #expect(!Self.step(&history, .undo))
        #expect(history.strokes == [Self.stroke(1), Self.stroke(2)])
    }
}
