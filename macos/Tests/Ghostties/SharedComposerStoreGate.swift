import Foundation

/// `SessionComposerStore.shared` is process-wide and Swift Testing runs suites
/// in parallel. Any test that opens or cancels it holds this gate for its
/// whole body, so two such tests never overlap.
actor SharedComposerStoreGate {
    static let shared = SharedComposerStoreGate()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

@MainActor
func withSharedComposerStore(_ body: @MainActor () async -> Void) async {
    await SharedComposerStoreGate.shared.acquire()
    await body()
    await SharedComposerStoreGate.shared.release()
}
