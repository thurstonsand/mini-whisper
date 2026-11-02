import AppKit
import ApplicationServices
import Carbon
import ComposableArchitecture
import Foundation

// MARK: - ClipboardRestoration

enum ClipboardRestoration: Equatable {
  case restored
  case skipped
  case failed
  /// The delivery never touched the clipboard: it was written into a pane, a terminal, or a
  /// field the user had looked away from.
  case untouched
}

// MARK: - DeliveryFallback

enum DeliveryFallback: Equatable {
  case accessibilityPermissionMissing
  case secureInput
  case eventCreationFailed
  /// The pane closed or the app quit since the dictation started.
  case targetGone
  /// The pane's foreground command changed under a submit.
  case targetChanged
  /// The target could not be given its app's focus back, or would not take the text.
  case targetUnreachable
  /// The user is in the target app, away from the field, and their focus is not moved.
  case targetInUse
  /// Focus left the field while it was being typed into, or the user acted while an Electron
  /// target was brought forward.
  case interrupted
  /// Keys were still held when a paste was due; ⌘V would have chorded with them.
  case keysHeld
  /// The field changed in a way the write does not explain, so whether it landed is unknown.
  case unconfirmed
}

// MARK: - NoReceiverReason

enum NoReceiverReason: Equatable {
  case noFocusedElement
  case nonTextElement(role: String?)
}

// MARK: - DeliveryOutcome

enum DeliveryOutcome: Equatable {
  case pasted(ClipboardRestoration)
  case copied(DeliveryFallback)
  case noReceiver(NoReceiverReason)
}

// MARK: - DeliveryError

enum DeliveryError: Error, Equatable { case pasteboardWriteFailed }

// MARK: - DeliveryClient

@DependencyClient struct DeliveryClient {
  /// Writes the text into the target, then Return when it `submits`.
  var deliver: @Sendable (_ text: String, _ target: DeliveryTarget, _ submits: Bool) async throws
    -> DeliveryOutcome
  var copy: @Sendable (String) async throws -> Void
}

// MARK: DependencyKey

extension DeliveryClient: DependencyKey {
  static let liveValue = Self(
    deliver: { text, target, submits in
      let fallback: DeliveryFallback
      if let pane = target.pane {
        switch TmuxPanes.deliver(text, submit: submits, to: pane) {
        case .delivered:
          return .pasted(.untouched)
        case .gone:
          fallback = .targetGone
        case .changed:
          fallback = .targetChanged
        }
      } else if let terminal = target.terminal {
        switch GhosttyTerminals.deliver(text, submit: submits, to: terminal) {
        case .delivered:
          return .pasted(.untouched)
        case .gone:
          fallback = .targetGone
        case .changed:
          fallback = .targetChanged
        case .refused:
          fallback = .targetUnreachable
        }
      } else {
        return try await TranscriptDelivery.deliver(text, to: target, submits: submits)
      }
      try await ClipboardPaste.copy(text)
      return .copied(fallback)
    },
    copy: { transcript in try await ClipboardPaste.copy(transcript) },
  )
}

extension DependencyValues {
  var delivery: DeliveryClient {
    get { self[DeliveryClient.self] }
    set { self[DeliveryClient.self] = newValue }
  }
}

// MARK: - TranscriptDelivery

@MainActor private enum TranscriptDelivery {
  /// A GUI target the user is still in takes a paste, the way a person would paste. One they have
  /// looked away from is delivered in the background, leaving their focus where it is — except in
  /// Electron, which takes input only in front and so gets a round trip. Anything that cannot be
  /// delivered for sure keeps the transcript on the clipboard instead.
  static func deliver(
    _ transcript: String, to target: DeliveryTarget, submits: Bool,
  ) async throws -> DeliveryOutcome {
    guard AXIsProcessTrusted() else {
      try ClipboardPaste.copy(transcript)
      return .copied(.accessibilityPermissionMissing)
    }
    guard !IsSecureEventInputEnabled() else {
      try ClipboardPaste.copy(transcript)
      return .copied(.secureInput)
    }
    guard let processID = target.processID,
          let application = NSRunningApplication(processIdentifier: processID),
          !application.isTerminated
    else {
      try ClipboardPaste.copy(transcript)
      return .copied(.targetGone)
    }

    let fallback: DeliveryFallback
    if let here = FocusSpot.frontmost()?.finds(target) {
      switch try await ClipboardPaste.paste(transcript, submits: submits, ready: {
        FocusSpot.frontmost()?.holds(here) == true
      }) {
      case let .pasted(restoration):
        return .pasted(restoration)
      case .keysHeld:
        fallback = .keysHeld
      case .focusMoved:
        fallback = .interrupted
      case .eventCreationFailed:
        fallback = .eventCreationFailed
      }
    } else if ChromiumAccessibility.isElectron(application) {
      // The user is in the app, away from the field; bringing it forward would move their focus.
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier != processID else {
        try ClipboardPaste.copy(transcript)
        return .copied(.targetInUse)
      }
      switch try await RoundTripDelivery.deliver(transcript, to: target, submits: submits) {
      case let .delivered(restoration):
        return .pasted(restoration)
      case .keysHeld:
        fallback = .keysHeld
      case .targetInUse:
        fallback = .targetInUse
      case .unreachable:
        fallback = .targetUnreachable
      case .interrupted:
        fallback = .interrupted
      case .eventCreationFailed:
        fallback = .eventCreationFailed
      }
    } else {
      switch await BackgroundDelivery.deliver(transcript, to: target, submits: submits) {
      case .delivered:
        return .pasted(.untouched)
      case .targetInUse:
        fallback = .targetInUse
      case .unreachable:
        fallback = .targetUnreachable
      case .interrupted:
        fallback = .interrupted
      case .unconfirmed:
        fallback = .unconfirmed
      }
    }
    try ClipboardPaste.copy(transcript)
    return .copied(fallback)
  }
}
