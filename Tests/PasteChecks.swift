import AppKit

final class FakePasteEnvironment: PasteEnvironment {
    var trusted = true
    var mayPostEvents = true
    var ownPID: pid_t = 10
    var frontmostPID: pid_t? = 10
    var modifiersHeld = false
    var running = true
    var activationWorks = true
    var activateImmediately = true
    var menu: PasteMenuResult = .performed
    var postWorks = true
    var activations = 0
    var restores = 0
    var menuActions = 0
    var keyActions = 0
    var onRestore: (() -> Void)?
    func isRunning(_ target: PasteDestination) -> Bool { running }
    func activate(_ target: PasteDestination) -> Bool { activations += 1; if activateImmediately && activationWorks { frontmostPID = target.pid }; return activationWorks }
    func restoreFocus(_ target: PasteDestination) { restores += 1; onRestore?() }
    func pressPasteMenu(_ target: PasteDestination) -> PasteMenuResult { menuActions += 1; return menu }
    func postPaste(_ target: PasteDestination) -> Bool { keyActions += 1; return postWorks }
}

final class TestClock {
    var time: TimeInterval = 0
    var queue: [(TimeInterval, () -> Void)] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) { queue.append((time + delay, action)) }
    func advance(to end: TimeInterval) {
        var limit = 1000
        while let index = queue.indices.min(by: { queue[$0].0 < queue[$1].0 }), queue[index].0 <= end, limit > 0 {
            let next = queue.remove(at: index); time = next.0; next.1(); limit -= 1
        }
        precondition(limit > 0, "Unexpected unbounded scheduling")
        time = end
    }
}

@main struct PasteChecks {
    static var count = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        count += 1; print("PASS: \(message)")
    }
    static func main() {
        let target = PasteDestination(pid: 20, name: "Test editor")
        func scenario(_ test: (FakePasteEnvironment, TestClock, PasteCoordinator) -> Void) {
            let env = FakePasteEnvironment(); let clock = TestClock()
            let coordinator = PasteCoordinator(environment: env, schedule: { clock.schedule($0, $1) }, now: { clock.time })
            test(env, clock, coordinator)
        }
        scenario { env, clock, paste in
            var success = false; paste.paste(to: target) { if case .success = $0 { success = true } }; clock.advance(to: 2)
            expect(success && env.menuActions == 1 && env.keyActions == 0 && env.restores == 1, "Standard paste menu sends one paste and restores focus")
        }
        scenario { env, clock, paste in
            env.trusted = false; var error: DirectPasteError?
            paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .permission && env.activations == 0 && env.menuActions == 0 && env.keyActions == 0, "Untrusted build cannot switch apps or inject input")
        }
        scenario { env, _, paste in
            var error: DirectPasteError?; paste.paste(to: nil) { if case .failure(let value) = $0 { error = value } }
            expect(error == .noTarget && env.activations == 0, "Missing target has a distinct error")
        }
        scenario { env, _, paste in
            var error: DirectPasteError?; paste.paste(to: PasteDestination(pid: env.ownPID, name: "Self")) { if case .failure(let value) = $0 { error = value } }
            expect(error == .noTarget, "Clipboard panel is never its own paste target")
        }
        scenario { env, _, paste in
            env.running = false; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }
            expect(error == .targetClosed && env.activations == 0, "Closed target is rejected before activation")
        }
        scenario { env, _, paste in
            env.activationWorks = false; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }
            expect(error == .activation && env.keyActions == 0, "Failed activation does not send keys")
        }
        scenario { env, clock, paste in
            env.activateImmediately = false; var success = false; paste.paste(to: target) { if case .success = $0 { success = true } }
            clock.advance(to: 1.1)
            expect(env.menuActions == 0 && env.keyActions == 0, "Slow target does not receive paste before becoming active")
            env.frontmostPID = target.pid; clock.advance(to: 1.4)
            expect(success && env.menuActions == 1, "Activation slower than old 250ms delay still pastes")
        }
        scenario { env, clock, paste in
            env.activateImmediately = false; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .activation && env.menuActions == 0, "Activation timeout leaves content copied without sending input")
        }
        scenario { env, clock, paste in
            var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; env.frontmostPID = 30; clock.advance(to: 2)
            expect(error == .focusChanged && env.keyActions == 0 && env.menuActions == 0, "Switching to another app cancels delayed paste")
        }
        scenario { env, clock, paste in
            env.modifiersHeld = true; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .modifiers && env.menuActions == 0, "Held shortcut modifiers cannot alter the outgoing paste")
        }
        scenario { env, clock, paste in
            env.modifiersHeld = true; var success = false; paste.paste(to: target) { if case .success = $0 { success = true } }; clock.advance(to: 0.4)
            env.modifiersHeld = false; clock.advance(to: 0.7)
            expect(success && env.menuActions == 1, "Releasing modifiers completes exactly one paste")
        }
        scenario { env, clock, paste in
            env.menu = .disabled; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .disabled && env.keyActions == 0, "Disabled Paste menu reports a noneditable destination")
        }
        scenario { env, clock, paste in
            env.menu = .unavailable; var success = false; paste.paste(to: target) { if case .success = $0 { success = true } }; clock.advance(to: 2)
            expect(success && env.keyActions == 1 && env.menuActions == 1, "Missing app menu falls back to one targeted key command")
        }
        scenario { env, clock, paste in
            var success = false; paste.paste(to: target, preferKeyboard: true) { if case .success = $0 { success = true } }; clock.advance(to: 2)
            expect(success && env.keyActions == 1 && env.menuActions == 0, "Custom image editor uses Cmd-V without also invoking a text-only menu action")
        }
        scenario { env, clock, paste in
            env.mayPostEvents = false; var success = false; paste.paste(to: target, preferKeyboard: true) { if case .success = $0 { success = true } }; clock.advance(to: 2)
            expect(success && env.menuActions == 1 && env.keyActions == 0, "Image editor can still use authorized menu when key posting is restricted")
        }
        scenario { env, clock, paste in
            env.postWorks = false; var error: DirectPasteError?; paste.paste(to: target, preferKeyboard: true) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .events && env.keyActions == 1 && env.menuActions == 0, "Custom image route does not retry and accidentally paste twice")
        }
        scenario { env, clock, paste in
            env.menu = .unavailable; env.mayPostEvents = false; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .events && env.keyActions == 0, "Restricted input posting is reported without silently dropping events")
        }
        scenario { env, clock, paste in
            env.menu = .failed; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .command && env.keyActions == 0, "Unconfirmed menu action never retries with keys and duplicates content")
        }
        scenario { env, clock, paste in
            env.menu = .unavailable; env.postWorks = false; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .events && env.keyActions == 1, "Keyboard event creation failure is surfaced")
        }
        scenario { env, clock, paste in
            env.mayPostEvents = false; var success = false; paste.paste(to: target) { if case .success = $0 { success = true } }; clock.advance(to: 2)
            expect(success && env.menuActions == 1 && env.keyActions == 0, "Authorized menu action works without simulated-key permission")
        }
        scenario { env, clock, paste in
            var completions = 0; paste.paste(to: target) { _ in completions += 1 }; paste.cancel(); clock.advance(to: 2)
            expect(completions == 0 && env.menuActions == 0 && !paste.isBusy, "Reopening panel cancels pending paste")
        }
        scenario { env, clock, paste in
            var completions = 0; paste.paste(to: target) { _ in completions += 1 }; paste.paste(to: target) { _ in completions += 1 }; clock.advance(to: 2)
            expect(completions == 1 && env.menuActions == 1, "New request cancels older request without duplicate paste")
        }
        scenario { env, clock, paste in
            var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; env.trusted = false; clock.advance(to: 2)
            expect(error == .permission && env.menuActions == 0, "Permission is checked again after activation")
        }
        scenario { env, clock, paste in
            var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; env.running = false; clock.advance(to: 2)
            expect(error == .targetClosed && env.menuActions == 0, "Target closing during activation cancels paste")
        }
        scenario { env, clock, paste in
            env.onRestore = { env.frontmostPID = 30 }; var error: DirectPasteError?; paste.paste(to: target) { if case .failure(let value) = $0 { error = value } }; clock.advance(to: 2)
            expect(error == .focusChanged && env.menuActions == 0, "Focus change while restoring input cannot paste into another app")
        }
        print("\(count) direct-paste checks passed. No real apps, keyboard events, permissions, or clipboard data were changed.")
    }
}
