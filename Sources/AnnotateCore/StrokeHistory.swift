// Undo / redo for the strokes on an open pin: the composer's undo and redo buttons, ⌘Z and ⇧⌘Z.
// History starts at the strokes the card opened with, so undo stops there: a new drawing's first
// stroke is what made the pin, and a reopened pin keeps what it was saved with. Redo holds what was
// undone until a new stroke goes down, which clears it.

import Foundation

public struct StrokeHistory: Equatable, Sendable {
    public private(set) var strokes: [Stroke]
    /// Undone strokes, most recent last.
    private var undone: [Stroke] = []
    /// How many strokes the card opened with; undo never goes below it.
    private let floor: Int

    public init(opening strokes: [Stroke] = []) {
        self.strokes = strokes
        floor = strokes.count
    }

    public var canUndo: Bool { strokes.count > floor }
    public var canRedo: Bool { !undone.isEmpty }

    public mutating func add(_ stroke: Stroke) {
        strokes.append(stroke)
        undone.removeAll()
    }

    /// Returns false (and changes nothing) at the opening state.
    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo, let last = strokes.popLast() else { return false }
        undone.append(last)
        return true
    }

    /// Returns false (and changes nothing) when nothing was undone.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = undone.popLast() else { return false }
        strokes.append(next)
        return true
    }
}
