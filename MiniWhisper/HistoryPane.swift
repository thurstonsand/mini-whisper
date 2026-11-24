import ComposableArchitecture
import History
import SwiftUI
import TipKit

// MARK: - HistoryPane

struct HistoryPane: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    let filtered = store.history.filteredEntries
    let effectiveLimit = resolvedVisibleLimit(in: filtered)
    let windowedEntries = filtered.count > effectiveLimit
      ? Array(filtered.prefix(effectiveLimit))
      : filtered
    let hasMore = filtered.count > windowedEntries.count
    let sections = Self.sections(from: windowedEntries)
    let tipEntry = tipsReady ? Self.tipEntry(in: windowedEntries) : nil
    let tipEntryID = tipEntry?.id
    let tip: any Tip? = tipEntry.flatMap { currentTip(for: $0) }
    List {
      ForEach(sections) { section in
        Section {
          ForEach(section.entries) { entry in
            HistoryRow(
              store: store, entry: entry, isCompact: isCompact,
              tip: entry.id == tipEntryID ? tip : nil,
            )
            .id(entry.id)
          }
        } header: {
          Text(section.title).padding(.leading, 6)
        }
      }
      if hasMore {
        Color.clear
          .frame(height: 1)
          .listRowSeparator(.hidden)
          .accessibilityHidden(true)
          .onAppear { visibleLimit += Self.pageSize }
      }
    }
    .listStyle(.plain)
    .onGeometryChange(for: Bool.self) { $0.size.width < 620 } action: { isCompact = $0 }
    .stableSettingsListRowHeight()
    .focusEffectDisabled()
    .keyboardCursorScroll(
      store: store, destination: .history, cursor: visibleCursor(in: filtered),
    )
    .task {
      guard !tipsReady else {
        return
      }
      _ = HistoryTips.group
      tipsReady = true
    }
    .onChange(of: store.history.cursor) { _, cursor in
      expandWindowIfNeeded(for: cursor, in: store.history.filteredEntries)
    }
    .onChange(of: store.history.search) { _, _ in
      visibleLimit = Self.initialLimit
    }
    .overlay {
      if store.history.log.entries.isEmpty, store.history.retention.transcripts == .never {
        ContentUnavailableView {
          Label("History Is Off", systemImage: "clock.badge.xmark")
        } actions: {
          Button("Keep Dictations…") { store.send(.history(.storagePresentationChanged(true))) }
        }
      } else if store.history.log.entries.isEmpty {
        ContentUnavailableView(
          "No History", systemImage: "clock.arrow.circlepath",
          description: Text("Your dictations will appear here."),
        )
      } else if filtered.isEmpty {
        ContentUnavailableView.search(text: store.history.search)
      }
    }
    .onChange(of: store.history.isRevealingRawText) { _, revealed in
      if revealed, store.history.filteredEntries.contains(where: { $0.revealedText != nil }) {
        HistoryRawTip().invalidate(reason: .actionPerformed)
      }
    }
    .onChange(of: store.history.copiedEntryID) { _, copied in
      if copied != nil {
        HistoryCopyTip().invalidate(reason: .actionPerformed)
      }
    }
  }

  // MARK: Private

  private static let initialLimit = 50
  private static let pageSize = 100
  private static let cursorLookahead = 20

  @State private var isCompact = false
  @State private var tipsReady = false
  @State private var visibleLimit = initialLimit

  private static func tipEntry(in entries: [HistoryEntry]) -> HistoryEntry? {
    entries.first { $0.revealedText != nil }
      ?? entries.first { $0.displayText != nil }
  }

  private static func sections(from entries: [HistoryEntry]) -> [HistoryDaySection] {
    let calendar = Calendar.autoupdatingCurrent
    let grouped = Dictionary(grouping: entries) {
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

  private static func dayTitle(_ date: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(date) {
      return "Today"
    }
    if calendar.isDateInYesterday(date) {
      return "Yesterday"
    }
    return date.formatted(.dateTime.month(.wide).day().year())
  }

  private func currentTip(for entry: HistoryEntry) -> any Tip? {
    let group = HistoryTips.group
    return entry.revealedText == nil ? HistoryCopyTip() : group.currentTip
  }

  private func resolvedVisibleLimit(in entries: [HistoryEntry]) -> Int {
    guard let cursor = store.history.cursor,
          let index = entries.firstIndex(where: { $0.id == cursor }),
          index + Self.cursorLookahead > visibleLimit
    else {
      return visibleLimit
    }
    return index + Self.cursorLookahead
  }

  private func expandWindowIfNeeded(for cursor: UUID?, in entries: [HistoryEntry]) {
    guard let cursor,
          let index = entries.firstIndex(where: { $0.id == cursor }),
          index + Self.cursorLookahead > visibleLimit
    else {
      return
    }
    visibleLimit = max(visibleLimit + Self.pageSize, index + Self.cursorLookahead)
  }

  /// A cursor filtered out by the search is not on screen to scroll to.
  private func visibleCursor(in entries: [HistoryEntry]) -> UUID? {
    guard let cursor = store.history.cursor,
          entries.contains(where: { $0.id == cursor })
    else {
      return nil
    }
    return cursor
  }
}

// MARK: - HistoryTips

private enum HistoryTips {
  /// Configure only when History opens; neither launch nor activation waits for the tip store.
  @MainActor static let group: TipGroup = {
    #if DEBUG
      if let scene = AgentDriveabilityScene.current {
        let location = AgentSceneFiles.command.appendingPathExtension("tips")
        if FileManager.default.fileExists(atPath: location.path) {
          try! FileManager.default.removeItem(at: location)
        }
        try! Tips.configure([
          .datastoreLocation(.url(location)),
          .displayFrequency(.immediate),
        ])
        if scene != .settingsHistoryTips {
          Tips.hideAllTipsForTesting()
        }
      } else {
        try! Tips.configure([.displayFrequency(.immediate)])
      }
    #else
      try! Tips.configure([.displayFrequency(.immediate)])
    #endif
    return TipGroup(.ordered) {
      HistoryRawTip()
      HistoryCopyTip()
    }
  }()
}

// MARK: - HistoryRawTip

private struct HistoryRawTip: Tip {
  var title: Text {
    Text("Hold ⌥ for the raw transcript")
  }

  var image: Image? {
    Image(systemName: "option")
  }

  var options: [any TipOption] {
    MaxDisplayCount(1)
  }
}

// MARK: - HistoryCopyTip

private struct HistoryCopyTip: Tip {
  var title: Text {
    Text("Click a dictation to copy it")
  }

  var image: Image? {
    Image(systemName: "doc.on.doc")
  }

  var options: [any TipOption] {
    MaxDisplayCount(1)
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
  let isCompact: Bool
  let tip: any Tip?

  var body: some View {
    let isCopied = store.history.copiedEntryID == entry.id
    let isPointed = store.interaction.mode == .mouse && store.interaction.focus == .detail
      && store.history.cursor == entry.id
    let showsKeyboardCursor = store.showsHistoryKeyboardCursor(entry.id)
    let showsGrey = !isCopied && (isPointed || showsKeyboardCursor)
    // A concrete unary container (not `Group`) keeps `List` statically aware that each row is
    // one cell so off-screen rows stay virtualized instead of evaluating eagerly during diffing.
    VStack(alignment: .leading, spacing: 0) {
      if isCompact {
        VStack(alignment: .leading, spacing: 6) {
          transcript
          HStack(spacing: 8) {
            metadata
            Spacer(minLength: 0)
            accessories(isPointed: isPointed, isCopied: isCopied)
          }
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          metadata
          transcript
          accessories(isPointed: isPointed, isCopied: isCopied)
        }
      }
    }
    .settingsListRowHeight(grows: true)
    .padding(.horizontal, 6)
    .settingsRowHighlight(showsGrey)
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(.tint)
        .opacity(isCopied ? 0.18 : 0)
        .animation(copyTintAnimation(isCopied: isCopied), value: isCopied)
    }
    .background {
      if let tip {
        Color.clear.popoverTip(tip, arrowEdge: .top)
      }
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
      if store.interaction.mode != .mouse {
        store.send(.pointerMoved)
      }
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

  private var isRevealed: Bool {
    store.history.isRevealingRawText && entry.revealedText != nil
  }

  private var isPlaying: Bool {
    store.history.playingEntryID == entry.id
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
      return AnyShapeStyle(.primary)
    }
    return isRevealed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
  }

  private var transcript: some View {
    Text(rowText)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .foregroundStyle(rowTextStyle)
  }

  private var metadata: some View {
    HStack(spacing: 8) {
      Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
        .monospacedDigit()
        .frame(width: 62, alignment: .leading)
      Text(entry.targetApp?.name ?? entry.targetApp?.bundleID ?? "Unknown")
        .lineLimit(1)
        .frame(width: 78, alignment: .leading)
    }
    .font(.callout)
    .foregroundStyle(.secondary)
  }

  @ViewBuilder private var menuItems: some View {
    Button("Copy", systemImage: "doc.on.doc") {
      store.send(.history(.copyEntry(entry.id, raw: false)))
    }
    .disabled(entry.displayText == nil)
    if entry.revealedText != nil {
      Button("Copy Raw Transcript") {
        store.send(.history(.copyEntry(entry.id, raw: true)))
      }
    }
    Button(
      isPlaying ? "Stop Audio" : "Play Audio",
      systemImage: isPlaying ? "stop.fill" : "play.fill",
    ) {
      store.send(.history(.playTapped(entry.id)))
    }
    .disabled(entry.audio == nil)
    Divider()
    Button("Re-transcribe", systemImage: "arrow.clockwise") {
      store.send(.history(.retranscribeTapped(entry.id)))
    }
    .disabled(entry.audio == nil || store.history.retranscribingEntryIDs.contains(entry.id))
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      store.send(.history(.deleteTapped(entry.id)))
    }
  }

  private func accessories(isPointed: Bool, isCopied: Bool) -> some View {
    HStack(spacing: 8) {
      if entry.revealedText != nil {
        Image(systemName: "wand.and.sparkles")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(width: 20)
          .opacity(isRevealed ? 0 : 1)
          .help("Cleaned up. Hold ⌥ to see the raw transcript.")
          .accessibilityLabel("Cleaned up")
          .accessibilityIdentifier(AccessibilityID.historyCleaned(entry.id))
      } else {
        Color.clear.frame(width: 20, height: 1).accessibilityHidden(true)
      }
      if entry.audio != nil {
        Button(isPlaying ? "Stop" : "Play", systemImage: playbackSymbol(isPointed: isPointed)) {
          store.send(.history(.playTapped(entry.id)))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(width: 20)
        .foregroundStyle(isPointed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .help(isPlaying ? "Stop the recording" : "Play the recording")
      } else {
        Color.clear.frame(width: 20, height: 1).accessibilityHidden(true)
      }
      accessory(isPointed: isPointed, isCopied: isCopied).frame(width: 70, alignment: .trailing)
    }
  }

  private func accessory(isPointed: Bool, isCopied: Bool) -> some View {
    ZStack(alignment: .trailing) {
      Label("Copied", systemImage: "checkmark")
        .font(.callout)
        .foregroundStyle(.tint)
        .fixedSize()
        .opacity(isCopied ? 1 : 0)
        .animation(copyTintAnimation(isCopied: isCopied), value: isCopied)
        .accessibilityIdentifier(AccessibilityID.historyCopied(entry.id))
        .accessibilityHidden(!isCopied)

      Group {
        if isPointed {
          HistoryMoreMenu { menuItems }
        } else if let duration = entry.audio?.durationSeconds {
          Text(duration.formattedDuration)
            .monospacedDigit()
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      .opacity(isCopied ? 0 : 1)
      .animation(durationAnimation(isCopied: isCopied), value: isCopied)
    }
  }

  /// The confirmation arrives at once and leaves slowly; the duration underneath waits out that
  /// exit before returning, so the two are never on screen together.
  private func copyTintAnimation(isCopied: Bool) -> Animation? {
    isCopied ? nil : .easeOut(duration: 0.5)
  }

  private func durationAnimation(isCopied: Bool) -> Animation {
    isCopied ? .easeOut(duration: 0.15) : .easeIn(duration: 0.25).delay(0.5)
  }

  private func playbackSymbol(isPointed: Bool) -> String {
    if isPlaying {
      return "stop.fill"
    }
    return isPointed ? "play.fill" : "waveform"
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

// MARK: - HistoryStorageToolbarButton

struct HistoryStorageToolbarButton: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    @Bindable var store = store
    Button("Keep Dictations…", systemImage: "clock.badge.xmark") {
      store.send(.history(.storagePresentationChanged(true)))
    }
    .labelStyle(.titleAndIcon)
    .help("Choose how long to keep transcripts and audio")
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
