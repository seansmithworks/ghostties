// StatusIndicator.swift
// Six-state indicator (inactive/idle/processing/longRunning/waiting/error)
// rendered as a small ghost glyph next to each session row.

import SwiftUI

enum IndicatorState {
    case inactive, idle, processing, longRunning, waiting, error
}

struct StatusIndicator: View {
    let state: IndicatorState

    var body: some View {
        // Pixel-glyph rendering lives in GhostCharacterView
        EmptyView()
    }
}
