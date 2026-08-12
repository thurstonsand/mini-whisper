// MARK: - HotkeyMatchOutput

public enum HotkeyMatchOutput<Action: Equatable & Sendable>: Equatable, Sendable {
  case gesture(GestureInput)
  case global(GestureInput)
  case action(Action)
}

// MARK: - RoutedChordMatch

public struct RoutedChordMatch<Action: Equatable & Sendable>: Equatable, Sendable {
  // MARK: Lifecycle

  public init(output: HotkeyMatchOutput<Action>?, disposition: EventDisposition) {
    self.output = output
    self.disposition = disposition
  }

  // MARK: Public

  public let output: HotkeyMatchOutput<Action>?
  public let disposition: EventDisposition
}

// MARK: - MultipleChordMatcher

/// Treats configured bindings as alternatives. Once one activates, only that binding sees input
/// until its primary chord releases; another binding cannot interfere with an active gesture.
public struct MultipleChordMatcher<Action: Equatable & Sendable>: Equatable, Sendable {
  // MARK: Lifecycle

  public init(bindings: [HotkeyBinding<Action>]) {
    entries = bindings.map(Entry.init(binding:))
  }

  // MARK: Public

  public mutating func receive(_ transition: KeyTransition) -> RoutedChordMatch<Action> {
    if let activeIndex {
      return forward(transition, to: activeIndex)
    }

    let matches = entries.indices.map { index in
      (index: index, match: entries[index].matcher.receive(transition))
    }
    if let winner = matches.first(where: { $0.match.input?.isActivation == true }) {
      activate(winner.index)
      return routed(winner.match, for: winner.index)
    }

    // Every binding judged the same transition, so one that has nothing to say about it speaks
    // for all of them: only an input none of them can explain is a real conflict. Building the
    // first half of one binding is therefore never the other binding's conflict.
    let inputs = matches.compactMap(\.match.input)
    let input = inputs.count == matches.count ? inputs.first : nil
    return RoutedChordMatch(
      output: input.map(HotkeyMatchOutput.global),
      disposition: matches.contains { $0.match.disposition == .suppress }
        ? .suppress : .passThrough,
    )
  }

  public mutating func interrupt() {
    activeIndex = nil
    for index in entries.indices {
      entries[index].matcher.interrupt()
    }
  }

  // MARK: Private

  private struct Entry: Equatable {
    // MARK: Lifecycle

    init(binding: HotkeyBinding<Action>) {
      matcher = PhysicalChordMatcher(hotkey: binding.hotkey)
      physicalKeys = binding.hotkey.physicalKeys
      route = binding.route
    }

    // MARK: Internal

    var matcher: PhysicalChordMatcher
    let physicalKeys: Set<PhysicalKey>
    let route: HotkeyBindingRoute<Action>
  }

  private var entries: [Entry]
  private var activeIndex: Int?

  private mutating func forward(
    _ transition: KeyTransition, to index: Int,
  ) -> RoutedChordMatch<Action> {
    guard entries[index].physicalKeys.contains(transition.key)
      || !entries.indices.contains(where: {
        $0 != index && entries[$0].physicalKeys.contains(transition.key)
      })
    else {
      return RoutedChordMatch(output: nil, disposition: .passThrough)
    }
    let match = entries[index].matcher.receive(transition)
    if match.input?.isRelease == true {
      activeIndex = nil
    }
    return routed(match, for: index)
  }

  private func routed(_ match: ChordMatch, for index: Int) -> RoutedChordMatch<Action> {
    let output: HotkeyMatchOutput<Action>? =
      switch entries[index].route {
      case .gesture:
        match.input.map(HotkeyMatchOutput.gesture)
      case let .action(action):
        match.input?.isActivation == true ? .action(action) : nil
      }
    return RoutedChordMatch(output: output, disposition: match.disposition)
  }

  private mutating func activate(_ index: Int) {
    activeIndex = index
    for other in entries.indices where other != index {
      entries[other].matcher.interrupt()
    }
  }
}

private extension Hotkey {
  var physicalKeys: Set<PhysicalKey> {
    var keys = Set(modifiers.map(PhysicalKey.modifier))
    if let keyCode {
      keys.insert(.keyCode(keyCode))
    }
    return keys
  }
}
