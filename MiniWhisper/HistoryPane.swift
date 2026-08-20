import ComposableArchitecture
import History
import SwiftUI

// MARK: - HistoryPane

struct HistoryPane: View {
  // MARK: Internal

  @Bindable var store: StoreOf<SettingsWindowFeature>

  var searchFocus: FocusState<Bool>.Binding

  var body: some View {
    List {
      ForEach(sections) { section in
        Section(section.title) {
          ForEach(section.entries) { entry in
            HistoryRow(store: store, entry: entry).id(entry.id)
          }
        }
      }
    }
    .stableSettingsListRowHeight()
    .focusEffectDisabled()
    .keyboardCursorScroll(store: store, cursor: visibleCursor)
    .overlay {
      if store.history.log.entries.isEmpty {
        ContentUnavailableView(
          "No History", systemImage: "clock.arrow.circlepath",
          description: Text("Your dictations will appear here."),
        )
      } else if store.history.filteredEntries.isEmpty {
        ContentUnavailableView.search(text: store.history.search)
      }
    }
    .modifier(HistoryCaptionBar(mentionsHold: hasRevealableEntry))
    .searchable(
      text: $store.history.search.sending(\.history.searchChanged), prompt: "Search transcripts",
    )
    .searchFocused(searchFocus)
    .toolbar {
      Button("Storage", systemImage: "internaldrive") {
        store.send(.history(.storagePresentationChanged(true)))
      }
      .accessibilityIdentifier(AccessibilityID.historyStorage)
      .popover(
        isPresented: $store.history
          .isStoragePresented
          .sending(\.history.storagePresentationChanged),
        arrowEdge: .bottom,
      ) {
        HistoryStorageForm(store: store)
      }
    }
  }

  // MARK: Private

  private var sections: [HistoryDaySection] {
    let calendar = Calendar.autoupdatingCurrent
    let grouped = Dictionary(grouping: store.history.filteredEntries) {
      calendar.startOfDay(for: $0.createdAt)
    }
    return grouped.keys.sorted(by: >).map { day in
      HistoryDaySection(
        day: day,
        title: dayTitle(day, calendar: calendar),
        entries: grouped[day, default: []].sorted { $0.createdAt > $1.createdAt },
      )
    }
  }

  private var hasRevealableEntry: Bool {
    store.history.log.entries.contains { $0.revealedText != nil }
  }

  /// A cursor filtered out by the search is not on screen to scroll to.
  private var visibleCursor: UUID? {
    guard let cursor = store.history.cursor,
          store.history.filteredEntries.contains(where: { $0.id == cursor })
    else {
      return nil
    }
    return cursor
  }

  private func dayTitle(_ date: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(date) {
      return "Today"
    }
    if calendar.isDateInYesterday(date) {
      return "Yesterday"
    }
    return date.formatted(.dateTime.month(.wide).day().year())
  }
}

// MARK: - HistorySearchFocus

/// Search is the one place in the window where typing means letters rather than commands, so it
/// gets two ways out: Return keeps the filter, Escape abandons it, and either hands the rows back
/// their keys. The field lives in the toolbar rather than the pane, so its focus binding is the
/// only handle on it — key presses never reach here. The way in is `/`, routed with every other
/// key by the window.
struct HistorySearchFocus: ViewModifier {
  let store: StoreOf<SettingsWindowFeature>
  var isSearchFocused: FocusState<Bool>.Binding
  var focusedColumn: FocusState<SettingsWindowFocus?>.Binding

  func body(content: Content) -> some View {
    content
      // Focus moves to the rows rather than dismissing the search, because dismissing it is
      // what clears the field, and Return is the exit that keeps the filter.
      .onSubmit(of: .search) {
        store.send(.keyboardModeEntered)
        focusedColumn.wrappedValue = .detail
      }
      .onChange(of: isSearchFocused.wrappedValue) { _, isFocused in
        // Escape dismisses the search itself, clearing the query and leaving no column focused.
        // Anywhere the user aimed focus deliberately has already claimed a column by now.
        guard !isFocused, focusedColumn.wrappedValue == nil else {
          return
        }
        store.send(.keyboardModeEntered)
        focusedColumn.wrappedValue = .detail
      }
  }
}

// MARK: - HistoryCaptionBar

private struct HistoryCaptionBar: ViewModifier {
  // MARK: Internal

  /// A pane whose transcripts were never cleaned has nothing to reveal, so it never teaches a
  /// gesture that would do nothing.
  let mentionsHold: Bool

  func body(content: Content) -> some View {
    content.safeAreaBar(edge: .top) { caption }
  }

  // MARK: Private

  private var caption: some View {
    Text(
      mentionsHold
        ? "Click a transcript to copy it. Hold \u{2325} to see raw transcript."
        : "Click a transcript to copy it.",
    )
    .font(.callout)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.bottom, 6)
    .accessibilityIdentifier(AccessibilityID.historyCaption)
  }
}

// MARK: - HistoryDaySection

private struct HistoryDaySection: Identifiable {
  var day: Date
  var title: String
  var entries: [HistoryEntry]

  var id: Date {
    day
  }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let entry: HistoryEntry

  var body: some View {
    // A wrapped transcript makes the row as tall as it needs to be; everything beside it sits on
    // the transcript's first line, which is the line the row began on.
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
        .monospacedDigit()
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 62, alignment: .leading)

      Text(entry.targetApp?.name ?? entry.targetApp?.bundleID ?? "Unknown")
        .lineLimit(1)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 78, alignment: .leading)

      Text(rowText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(rowTextStyle)

      if entry.revealedText != nil {
        Image(systemName: "wand.and.sparkles")
          .font(.callout)
          .foregroundStyle(.tertiary)
          .opacity(isRevealed ? 0 : 1)
          .accessibilityIdentifier(AccessibilityID.historyCleaned(entry.id))
      }

      if entry.audio != nil {
        Button(isPlaying ? "Stop" : "Play", systemImage: playbackSymbol) {
          store.send(.history(.playTapped(entry.id)))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(isPointed ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .help(isPlaying ? "Stop the recording" : "Play the recording")
      }

      accessory
        .frame(width: 70, alignment: .trailing)
    }
    .settingsListRowHeight(grows: true)
    .padding(.horizontal, 6)
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quaternary)
        .opacity(showsGrey ? 1 : 0)
      RoundedRectangle(cornerRadius: 8)
        .fill(.tint)
        .opacity(isCopied ? 0.18 : 0)
        .animation(copyTintAnimation, value: isCopied)
    }
    // A row whose content is a custom layout leaves the separator to guess where the text
    // begins, and it guesses from the trailing accessory — which is what leaves stubs beside
    // the durations. Naming both edges gives the list back the full-width rule it draws
    // everywhere else.
    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
    .contentShape(.rect)
    .onTapGesture {
      guard entry.displayText != nil else {
        return
      }
      store.send(.pointerMoved)
      store.send(.history(.rowTapped(entry.id)))
    }
    .windowPointerMovement(store: store) {
      store.send(.history(.cursorHovered(entry.id)))
    }
    .contextMenu { menuItems }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.historyRow(entry.id))
    .accessibilityLabel(rowText)
    .accessibilityPaintState(
      AccessibilityID.historyRowState(entry.id), label: "History row highlight",
      value:
      "Grey \(showsGrey ? "on" : "off"); Cursor \(showsKeyboardCursor ? "on" : "off"); Copied \(isCopied ? "on" : "off")",
    )
  }

  // MARK: Private

  private var isPointed: Bool {
    store.interaction.mode == .mouse && store.interaction.focus == .detail
      && store.history.cursor == entry.id
  }

  private var showsGrey: Bool {
    !isCopied && (isPointed || showsKeyboardCursor)
  }

  private var showsKeyboardCursor: Bool {
    store.state.showsHistoryKeyboardCursor(entry.id)
  }

  private var isCopied: Bool {
    store.history.copiedEntryID == entry.id
  }

  private var isRevealed: Bool {
    store.history.isRevealingRawText && entry.revealedText != nil
  }

  private var isPlaying: Bool {
    store.history.playingEntryID == entry.id
  }

  /// The confirmation arrives at once and leaves slowly; the duration underneath waits out that
  /// exit before returning, so the two are never on screen together.
  private var copyTintAnimation: Animation? {
    isCopied ? nil : .easeOut(duration: 0.5)
  }

  private var durationAnimation: Animation {
    isCopied ? .easeOut(duration: 0.15) : .easeIn(duration: 0.25).delay(0.5)
  }

  private var failure: String? {
    store.history.retranscriptionFailures[entry.id]
  }

  private var rowText: String {
    if store.history.retranscribingEntryIDs.contains(entry.id) {
      return "Re-transcribing…"
    }
    if let failure {
      return failure
    }
    if isRevealed, let revealedText = entry.revealedText {
      return revealedText
    }
    return entry.displayText ?? "Transcription unavailable"
  }

  /// The revealed transcript is not the entry's text, and reads as the supporting fact it is.
  private var rowTextStyle: AnyShapeStyle {
    if failure != nil {
      return AnyShapeStyle(.orange)
    }
    return isRevealed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
  }

  private var playbackSymbol: String {
    if isPlaying {
      return "stop.fill"
    }
    return isPointed ? "play.fill" : "waveform"
  }

  @ViewBuilder private var menuItems: some View {
    Button("Re-transcribe", systemImage: "arrow.clockwise") {
      store.send(.history(.retranscribeTapped(entry.id)))
    }
    .disabled(entry.audio == nil || store.history.retranscribingEntryIDs.contains(entry.id))
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      store.send(.history(.deleteTapped(entry.id)))
    }
  }

  private var accessory: some View {
    ZStack(alignment: .trailing) {
      Label("Copied", systemImage: "checkmark")
        .font(.callout)
        .foregroundStyle(.tint)
        .fixedSize()
        .opacity(isCopied ? 1 : 0)
        .animation(copyTintAnimation, value: isCopied)
        .accessibilityIdentifier(AccessibilityID.historyCopied(entry.id))
        .accessibilityHidden(!isCopied)

      Group {
        if isPointed {
          HistoryMoreMenu { menuItems }
        } else if let duration = entry.audio?.durationSeconds {
          Text(duration.formattedDuration)
            .monospacedDigit()
            .font(.callout)
            .foregroundStyle(.tertiary)
        }
      }
      .opacity(isCopied ? 0 : 1)
      .animation(durationAnimation, value: isCopied)
    }
  }
}

// MARK: - HistoryMoreMenu

private struct HistoryMoreMenu<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    Menu { content } label: {
      Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

// MARK: - HistoryStorageForm

private struct HistoryStorageForm: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    Form {
      Section("Storage") {
        Picker("Keep transcripts for", selection: retention(.transcripts)) {
          ForEach(RetentionTTL.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Picker("Keep audio for", selection: retention(.audio)) {
          ForEach(RetentionTTL.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        LabeledContent("Stored", value: storedSummary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 380)
    .accessibilityIdentifier(AccessibilityID.historyStoragePopover)
    .alert("Delete older history?", isPresented: reductionPending) {
      Button("Cancel", role: .cancel) { store.send(.history(.retentionReductionCancelled)) }
      Button("Delete", role: .destructive) { store.send(.history(.retentionReductionConfirmed)) }
    } message: {
      Text("Anything older than the new limit is deleted right away. This cannot be undone.")
    }
  }

  // MARK: Private

  private var storedSummary: String {
    let entries = store.history.log.entries
    let recordings = entries.filter { $0.audio != nil }
    let bytes = recordings.compactMap(\.audio?.byteCount).reduce(0, +)
    let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    return "\(entries.count) transcripts · \(recordings.count) recordings · \(size)"
  }

  private var reductionPending: Binding<Bool> {
    Binding(
      get: { store.history.pendingRetentionReduction != nil },
      set: { isPresented in
        guard !isPresented else {
          return
        }
        store.send(.history(.retentionReductionCancelled))
      },
    )
  }

  private func retention(_ field: RetentionPolicy.Key) -> Binding<RetentionTTL> {
    Binding(
      get: { store.history.retention[field] },
      set: { store.send(.history(.retentionProposed(field, $0))) },
    )
  }
}

private extension RetentionTTL {
  var label: String {
    switch self {
    case .never:
      "Never"
    case .oneDay:
      "1 day"
    case .sevenDays:
      "7 days"
    case .thirtyDays:
      "30 days"
    case .ninetyDays:
      "90 days"
    case .oneYear:
      "1 year"
    case .forever:
      "Forever"
    }
  }
}

private extension Double {
  var formattedDuration: String {
    let seconds = Int(rounded())
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}
