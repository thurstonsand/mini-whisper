import AppSettings
import ComposableArchitecture
import HotkeyListener

// MARK: - HotkeyAction

enum HotkeyAction: Equatable {
  case pasteLastTranscript
}

// MARK: - Listener configuration

extension HotkeyBindingsSettings {
  var listenerBindings: [HotkeyBinding<HotkeyAction>] {
    HotkeyCommand.allCases.flatMap { command in
      hotkeys(for: command).map {
        HotkeyBinding(hotkey: $0, route: command.listenerRoute)
      }
    }
  }
}

private extension HotkeyCommand {
  var listenerRoute: HotkeyBindingRoute<HotkeyAction> {
    switch self {
    case .activate:
      .gesture
    case .pasteLastTranscript:
      .action(.pasteLastTranscript)
    }
  }
}

// MARK: - AppFeature

extension AppFeature {
  /// The single place the Accessibility grant is turned into hotkey-listening state: every
  /// observation of it — startup, onboarding, activation, the menu — lands here so a grant made
  /// after setup starts the listener and a revocation stops it, without a relaunch either way.
  func reconcileAccessibility(_ granted: Bool, _ state: inout State) -> Effect<Action> {
    state.$health.withLock { $0.accessibilityGranted = granted }
    guard granted else {
      state.$health.withLock { $0.hotkeyTap = .idle }
      return .cancel(id: CancelID.hotkeyEvents)
    }
    guard state.health.hotkeyTap != .active, state.health.hotkeyTap != .starting else {
      return .none
    }
    return restartHotkeyListener(&state)
  }

  func beginHotkeyRecording(
    _ state: inout State, recorderReady: Action,
  ) -> Effect<Action> {
    // Stop the activation tap before the recorder installs its owning tap. This ordering makes
    // recording the activation shortcut race-free: no physical event can reach both consumers.
    state.$health.withLock { $0.hotkeyTap = .idle }
    return .concatenate(.cancel(id: CancelID.hotkeyEvents), .send(recorderReady))
  }

  /// Not listening is not a failure by itself: a missing grant and no configured bindings both
  /// end here, and `health` tells the menu bar why the tap is idle.
  func restartHotkeyListener(_ state: inout State) -> Effect<Action> {
    let bindings = state.settings.bindings.listenerBindings
    guard state.health.accessibilityGranted, !bindings.isEmpty else {
      state.$health.withLock { $0.hotkeyTap = .idle }
      return .cancel(id: CancelID.hotkeyEvents)
    }
    state.$health.withLock { $0.hotkeyTap = .starting }
    return listenForHotkeyEvents(bindings: bindings)
  }

  /// A revoked grant kills the tap exactly the way a genuine failure does. Only a live read tells
  /// them apart, and only one of the two has a repair that can work.
  func diagnoseTapLoss(_ state: inout State) -> Effect<Action> {
    let granted = accessibilityPermission.hasPermission()
    state.$health.withLock { $0.accessibilityGranted = granted }
    guard granted else {
      state.$health.withLock { $0.hotkeyTap = .idle }
      return .cancel(id: CancelID.hotkeyEvents)
    }
    state.$health.withLock { $0.hotkeyTap = .dead }
    return .none
  }

  private func listenForHotkeyEvents(
    bindings: [HotkeyBinding<HotkeyAction>],
  ) -> Effect<Action> {
    .run { send in
      do {
        let events = try await hotkeyListener.events(bindings)
        for await event in events {
          await send(.hotkeyListenerEvent(event))
        }
        await send(.hotkeyListenerFinished)
      } catch {
        await send(.hotkeyListenerFailed(String(describing: error)))
      }
    }.cancellable(id: CancelID.hotkeyEvents, cancelInFlight: true)
  }
}
