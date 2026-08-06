// MARK: - MultipleChordMatcher

/// Treats configured bindings as alternatives. Once one activates, only that binding sees input
/// until its primary chord releases; another binding cannot interfere with an active gesture.
public struct MultipleChordMatcher: Equatable, Sendable {
  // MARK: Lifecycle

  public init(hotkeys: [Hotkey]) {
    matchers = hotkeys.map(PhysicalChordMatcher.init(hotkey:))
    bindingKeys = hotkeys.map(\.physicalKeys)
  }

  // MARK: Public

  public mutating func receive(_ transition: KeyTransition) -> ChordMatch {
    if let activeIndex {
      return forward(transition, to: activeIndex)
    }

    let matches = matchers.indices.map { index in
      (index: index, match: matchers[index].receive(transition))
    }
    if let winner = matches.first(where: { $0.match.input?.isActivation == true }) {
      activate(winner.index)
      return winner.match
    }

    // Every binding judged the same transition, so one that has nothing to say about it speaks
    // for all of them: only an input none of them can explain is a real conflict. Building the
    // first half of one binding is therefore never the other binding's conflict.
    let inputs = matches.compactMap(\.match.input)
    return ChordMatch(
      input: inputs.count == matches.count ? inputs.first : nil,
      disposition: matches.contains { $0.match.disposition == .suppress }
        ? .suppress : .passThrough,
    )
  }

  public mutating func interrupt() {
    activeIndex = nil
    for index in matchers.indices {
      matchers[index].interrupt()
    }
  }

  // MARK: Private

  private var matchers: [PhysicalChordMatcher]
  private let bindingKeys: [Set<PhysicalKey>]
  private var activeIndex: Int?

  private mutating func forward(_ transition: KeyTransition, to index: Int) -> ChordMatch {
    guard bindingKeys[index].contains(transition.key)
      || !bindingKeys.indices.contains(where: {
        $0 != index && bindingKeys[$0].contains(transition.key)
      })
    else {
      return ChordMatch(input: nil, disposition: .passThrough)
    }
    let match = matchers[index].receive(transition)
    if match.input?.isRelease == true {
      activeIndex = nil
    }
    return match
  }

  private mutating func activate(_ index: Int) {
    activeIndex = index
    for other in matchers.indices where other != index {
      matchers[other].interrupt()
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
