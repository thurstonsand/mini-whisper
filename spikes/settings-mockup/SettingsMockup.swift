import AppKit
import SwiftUI

// Disposable mock-up for ticket 16. Real AppKit/SwiftUI so the window can be judged on its actual
// metrics, materials, and control sizes rather than a drawing. No MiniWhisper code is imported and
// nothing here ships: every value below is invented.
//
// Written against .agents/skills/native-macos-ui: system containers own the layout, text styles
// instead of point sizes, semantic colors only, and no control drawn by hand that AppKit provides.

// MARK: - Destination

/// Settings first and selected on open, then the features. `Model states` is a mock-up-only page
/// that shows every install state at once; the real Model page shows whichever one is true.
enum Destination: String, CaseIterable, Identifiable {
  case settings = "Settings"
  case history = "History"
  case model = "Model"
  case dictionary = "Dictionary"
  case cleanup = "Cleanup"
  case states = "Component states"
  case cursorLab1 = "Cursor lab 1"
  case cursorLab2 = "Cursor lab 2"
  case cursorLab3 = "Cursor lab 3"
  case playground = "Playground"

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .settings: "gearshape"
    case .history: "clock.arrow.circlepath"
    case .model: "waveform"
    case .dictionary: "character.book.closed"
    case .cleanup: "wand.and.sparkles"
    case .states: "square.stack.3d.up"
    case .cursorLab1,
         .cursorLab2,
         .cursorLab3,
         .playground: "keyboard"
    }
  }
}

// MARK: - Sample data

struct Entry: Identifiable, Hashable {
  let id = UUID()
  let day: String
  let time: String
  let app: String
  let text: String
  let length: String
  let hasAudio: Bool
}

let entries: [Entry] = [
  .init(day: "Today", time: "1:47 pm", app: "Ghostty",
        text: "I suspect there's a prefactor opportunity here to make this sort of issue not possible to produce in the future.",
        length: "11.8s", hasAudio: true),
  .init(day: "Today", time: "1:44 pm", app: "Safari",
        text: "In the event that a late package gets switched to out for delivery, we should leave the late label but then also enable it to be promoted to the hero.",
        length: "9.2s", hasAudio: true),
  .init(day: "Today", time: "1:31 pm", app: "Mail",
        text: "I could have sworn I saw something about the API now allowing for much more flexible layouts.",
        length: "6.4s", hasAudio: true),
  .init(day: "Yesterday", time: "4:08 pm", app: "Ghostty",
        text: "A quick thought to add to the ticket for adding custom words. I want a quick add option from the menu bar.",
        length: "22.9s", hasAudio: false),
  .init(day: "Yesterday", time: "11:52 am", app: "Notes",
        text: "I suppose if dates are missing then we can keep API order for those.",
        length: "4.1s", hasAudio: false),
  .init(day: "August 2, 2026", time: "9:04 am", app: "Xcode",
        text: "Wanted to make sure we could capture what that would mean for how we do layouts.",
        length: "7.7s", hasAudio: false),
]

var days: [String] { entries.map(\.day).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }

/// A vocabulary entry is either a term the engine should know, or a correction from what it hears
/// to what was meant. One list, two shapes.
struct Term: Identifiable, Hashable {
  let id = UUID()
  let word: String
  var heardAs: String?
  let added: String
}

let terms: [Term] = [
  .init(word: "Parakeet", added: "Today"),
  .init(word: "ghostty", heardAs: "ghosty", added: "Today"),
  .init(word: "FluidAudio", added: "Yesterday"),
  .init(word: "nvim", heardAs: "n vim", added: "Yesterday"),
  .init(word: "TCA", added: "Aug 2"),
  .init(word: "Renovate", added: "Aug 2"),
  .init(word: "npm", heardAs: "NPM", added: "Jul 30"),
  .init(word: "Silero", added: "Jul 28"),
]

/// Ordered shortest to longest so "reducing" is a comparison of indices.
let retentions = ["Never", "1 day", "7 days", "30 days", "90 days", "1 year", "Forever"]

let noAudioCue = "No audio"
let cues = [noAudioCue, "Tink", "Pop", "Glass", "Basso", "Submarine"]

// MARK: - Install state

enum InstallState: String, CaseIterable, Identifiable {
  case notInstalled = "Not installed"
  case downloading = "Downloading"
  case compiling = "Preparing"
  case failed = "Failed"
  case ready = "Ready"
  case readyInactive = "Ready, not in use"

  var id: String { rawValue }
}

// MARK: - Mock state

@Observable final class Mock {
  var destination =
    Destination.allCases.first {
      $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "")
        .hasPrefix(CommandLine.arguments.dropFirst().first?.lowercased() ?? "set")
    } ?? .settings

  var selection: Entry.ID?
  var hovered: Entry.ID?
  var search = ""
  var copied: Entry.ID?
  var copiedIsLeaving = false
  var showingStorage = false

  var transcriptRetention = "Forever"
  var audioRetention = "7 days"
  var pendingReduction: (key: ReferenceWritableKeyPath<Mock, String>, value: String)?

  var launchAtLogin = true
  var microphone = "System default"
  var muteWhileActive = true
  var activeModel = "Parakeet TDT v2"
  var dictionarySearch = ""
  var dictionarySort = "Newest First"
  var editingTerm: Term?
  var addingTerm = false
  var cleanupEnabled = true
  var cleanupModel = "gpt-5.6-luna"
  var cleanupTimeout = 10
  var customModel = ""
  var modelListing = ModelListing.loaded(["gpt-5.6-luna", "gpt-5.4-mini", "llama-3.3-70b"])

  /// Alternates success and failure so both paths are reachable from the mock-up.
  func loadModels() {
    switch modelListing {
    case .loaded:
      modelListing = .failed("This endpoint doesn't list its models.")
      cleanupModel = customModelTag
    case .notLoaded,
         .failed:
      modelListing = .loaded(["gpt-5.6-luna", "gpt-5.4-mini", "llama-3.3-70b"])
    }
  }
  var endpointAddress = "https://gateway.internal/v1"
  let storedKey = "sk-proj-abcdefghijklmnopqrstuvwx"
  var keyState = KeyState.stored
  var customPrompt = ""

  /// Whether an endpoint fact changed since the last confirm — what arms variant C's Save.
  var endpointDirty = false

  func commitSave() {
    if endpointAddress.hasPrefix("https") {
      saveResult = .saved
      keyState = .stored
      endpointDirty = false
    } else {
      saveResult = .failed("Couldn't reach that address.")
    }
  }

  /// Where the Save button lives — the question this round of the mock exists to answer.
  /// Chosen by a `save-a` … `save-d` launch argument; A is today's shape, right-aligned.
  var saveVariant: SaveVariant = {
    for argument in CommandLine.arguments {
      switch argument.lowercased() {
      case "save-a": return .ownRowTrailing
      case "save-b": return .paneBottom
      case "save-c": return .modelRow
      case "save-d": return .sectionHeader
      default: continue
      }
    }
    return .ownRowTrailing
  }()

  /// Seeds variant C's tri-state for capture: `pristine`, `dirty`, `saved`, or `error`.
  func seedStage() {
    for argument in CommandLine.arguments {
      switch argument.lowercased() {
      case "pristine":
        endpointDirty = false
        saveResult = .none
      case "dirty":
        endpointDirty = true
        saveResult = .none
      case "saved":
        endpointDirty = false
        saveResult = .saved
      case "error":
        endpointDirty = true
        saveResult = .failed("Couldn't reach that address.")
      default:
        continue
      }
    }
  }
  /// Nothing is reported until Save is pressed, so the resting state says nothing at all.
  var saveResult = SaveResult.none

  /// A capability problem pins itself to the top of Settings; when everything is granted there is
  /// nothing to show, so the section does not exist.
  var accessibilityGranted = true
  var microphoneGranted = false

  var hasProblem: Bool { !accessibilityGranted || !microphoneGranted }

  var cueStart = "Tink"
  var cueDelivered = "Glass"
  var cueCancelled = noAudioCue
  var cueFailed = "Basso"

  func copy(_ id: Entry.ID) {
    copied = id
    copiedIsLeaving = false
  }

  /// The confirmation is a flash, not a state, and it leaves in two steps so it never shares pixels
  /// with the duration it replaced: the badge and tint fade out first, and only once they are gone
  /// does the metadata fade back in. Crossfading both at once superimposes two texts in one slot.
  ///
  /// Both mutations animate at the mutation site rather than through a modifier on the row: these
  /// resume after suspension, and a `List` only honours an exit animation that is already in the
  /// update transaction when it reaches its hosted rows.
  func clearCopied(_ id: Entry.ID) async {
    try? await Task.sleep(for: .seconds(1.2))
    guard copied == id else { return }
    withAnimation(.easeOut(duration: 0.5)) { copiedIsLeaving = true }

    try? await Task.sleep(for: .seconds(0.5))
    guard copied == id else { return }
    withAnimation(.easeIn(duration: 0.25)) {
      copied = nil
      copiedIsLeaving = false
    }
  }
}

// MARK: - History

struct HistoryPane: View {
  @Bindable var mock: Mock

  var body: some View {
    List(selection: $mock.selection) {
      ForEach(days, id: \.self) { day in
        Section(day) {
          ForEach(entries.filter { $0.day == day }) { entry in
            Row(mock: mock, entry: entry)
              .tag(entry.id)
          }
        }
      }
    }
    // The row is the copy target and nothing about a row says so, so one line does. `safeAreaBar`
    // is macOS 26's own bar treatment: it brings the material and the separator, so neither is
    // drawn by hand.
    .safeAreaBar(edge: .top) {
      Text("Click a transcript to copy it.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
    .searchable(text: $mock.search, prompt: "Search transcripts")
    .toolbar {
      Button("Storage", systemImage: "internaldrive") { mock.showingStorage.toggle() }
        .popover(isPresented: $mock.showingStorage, arrowEdge: .bottom) {
          StorageForm(mock: mock)
        }
    }
    .onKeyPress(.return) { if let id = mock.selection { mock.copy(id) }; return .handled }
    .onKeyPress(characters: .init(charactersIn: "jk")) { press in
      move(by: press.characters == "j" ? 1 : -1)
      return .handled
    }
  }

  private func move(by offset: Int) {
    guard let current = entries.firstIndex(where: { $0.id == mock.selection }) else {
      mock.selection = entries.first?.id
      return
    }
    mock.selection = entries[min(max(current + offset, 0), entries.count - 1)].id
  }
}

/// One dictation. Time and app sit together on the left as the entry's identity; the trailing slot
/// holds a fixed-height accessory so swapping metadata for buttons on hover cannot resize the row.
struct Row: View {
  @Bindable var mock: Mock
  let entry: Entry

  private var isHovered: Bool { mock.hovered == entry.id }
  /// Holding the row's tint: true for the whole confirmation, including while it fades.
  private var wasCopied: Bool { mock.copied == entry.id }
  /// Showing the badge: false as soon as the confirmation starts leaving.
  private var showsConfirmation: Bool { wasCopied && !mock.copiedIsLeaving }

  var body: some View {
    HStack(spacing: 8) {
      Text(entry.time)
        .monospacedDigit()
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 62, alignment: .leading)

      Text(entry.app)
        .lineLimit(1)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 68, alignment: .leading)

      Text(entry.text)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 8)

      // Its own column so every waveform lines up, and it is the play control rather than a label
      // beside one: the mark that says audio exists is the thing that plays it.
      Group {
        if entry.hasAudio {
          Button("Play", systemImage: isHovered ? "play.fill" : "waveform") {}
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .help("Play the recording")
        }
      }
      .frame(width: 18)

      // Fixed width as well as height: metadata and buttons occupy the same slot, or the transcript
      // reflows and reveals a different amount of text on hover.
      accessory
        .frame(width: 66, height: 18, alignment: .trailing)
    }
    // A fixed row height is the only reliable way to stop a swapped control from resizing the row.
    .frame(height: 22)
    .padding(.vertical, 3)
    .padding(.horizontal, 6)
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quaternary)
        .opacity(isHovered && !wasCopied ? 1 : 0)
      RoundedRectangle(cornerRadius: 8)
        .fill(.tint)
        .opacity(showsConfirmation ? 0.18 : 0)
    }
    .contentShape(.rect)
    .onTapGesture { mock.copy(entry.id) }
    .onHover { mock.hovered = $0 ? entry.id : nil }
    .contextMenu { menuItems }
  }

  @ViewBuilder private var menuItems: some View {
    Button("Rerun Transcription", systemImage: "arrow.clockwise") {}
    Button("Save Audio…", systemImage: "square.and.arrow.down") {}
      .disabled(!entry.hasAudio)
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {}
  }

  @ViewBuilder private var accessory: some View {
    ZStack(alignment: .trailing) {
      Label("Copied", systemImage: "checkmark")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize()
        .opacity(showsConfirmation ? 1 : 0)
        .task(id: wasCopied) { if wasCopied { await mock.clearCopied(entry.id) } }

      Group {
        if isHovered {
          MoreMenu { menuItems }
        } else {
          Text(entry.length)
            .monospacedDigit()
            .font(.callout)
            .foregroundStyle(.tertiary)
        }
      }
      .opacity(wasCopied ? 0 : 1)
    }
  }
}

/// Retention lives with the data it governs rather than in Settings, and reducing either value
/// confirms first, because the deletion is immediate and silent otherwise.
struct StorageForm: View {
  @Bindable var mock: Mock

  var body: some View {
    Form {
      Section {
        RetentionPicker("Keep transcripts for", mock: mock, keyPath: \.transcriptRetention)
        RetentionPicker("Keep audio for", mock: mock, keyPath: \.audioRetention)
        LabeledContent("Stored", value: "42 transcripts · 18 recordings · 61 MB")
      } header: {
        Text("Storage")
      }
    }
    .formStyle(.grouped)
    .frame(width: 380)
    .alert(
      "Delete older recordings?",
      isPresented: .init(get: { mock.pendingReduction != nil }, set: { if !$0 { mock.pendingReduction = nil } }),
    ) {
      Button("Cancel", role: .cancel) { mock.pendingReduction = nil }
      Button("Delete", role: .destructive) {
        if let pending = mock.pendingReduction { mock[keyPath: pending.key] = pending.value }
        mock.pendingReduction = nil
      }
    } message: {
      Text("Anything older than the new limit is deleted right away. This cannot be undone.")
    }
  }
}

struct RetentionPicker: View {
  let label: String
  @Bindable var mock: Mock
  let keyPath: ReferenceWritableKeyPath<Mock, String>

  init(_ label: String, mock: Mock, keyPath: ReferenceWritableKeyPath<Mock, String>) {
    self.label = label
    self.mock = mock
    self.keyPath = keyPath
  }

  var body: some View {
    Picker(
      label,
      selection: .init(
        get: { mock[keyPath: keyPath] },
        set: { proposed in
          let current = retentions.firstIndex(of: mock[keyPath: keyPath]) ?? 0
          let next = retentions.firstIndex(of: proposed) ?? 0
          if next < current {
            mock.pendingReduction = (keyPath, proposed)
          } else {
            mock[keyPath: keyPath] = proposed
          }
        },
      ),
    ) {
      ForEach(retentions, id: \.self, content: Text.init)
    }
  }
}

// MARK: - Vocabulary

struct DictionaryPane: View {
  @Bindable var mock: Mock
  @State private var hovered: Term.ID?

  var body: some View {
    // No selection: a row is not a thing you hold, it is a thing you open. Clicking edits it.
    List {
      ForEach(sorted) { term in
        TermRow(term: term, isHovered: hovered == term.id) { mock.editingTerm = term }
          .onHover { hovered = $0 ? term.id : nil }
      }
    }
    .searchable(text: $mock.dictionarySearch, prompt: "Search dictionary")
    .toolbar {
      Menu("Sort", systemImage: "arrow.up.arrow.down") {
        Picker("Sort", selection: $mock.dictionarySort) {
          Text("Newest First").tag("Newest First")
          Text("Alphabetical").tag("Alphabetical")
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
      Button("Add Word", systemImage: "plus") { mock.addingTerm = true }
    }
    .sheet(isPresented: $mock.addingTerm) { TermSheet(mock: mock, existing: nil) }
    .sheet(item: $mock.editingTerm) { TermSheet(mock: mock, existing: $0) }
  }

  private var sorted: [Term] {
    mock.dictionarySort == "Alphabetical" ? terms.sorted { $0.word.lowercased() < $1.word.lowercased() } : terms
  }
}

/// Rows match History's rhythm deliberately: same row height, same hover highlight, same trailing
/// actions. Two lists that behave differently for no reason is what made the first draft feel off.
struct TermRow: View {
  let term: Term
  let isHovered: Bool
  let edit: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if let heardAs = term.heardAs {
        HStack(spacing: 6) {
          Text(heardAs).foregroundStyle(.secondary)
          Image(systemName: "arrow.right").foregroundStyle(.tertiary).font(.caption)
          Text(term.word)
        }
      } else {
        Text(term.word)
      }

      Spacer(minLength: 8)

      Group {
        if isHovered {
          Button("Delete", systemImage: "trash", role: .destructive) {}
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
      }
      .frame(width: 18, height: 18, alignment: .trailing)
    }
    .frame(height: 22)
    .padding(.vertical, 3)
    .padding(.horizontal, 6)
    .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
    .contentShape(.rect)
    .onTapGesture(perform: edit)
  }
}

/// One sheet for adding and editing, and for both shapes an entry can take. Editing opens the same
/// form already filled in, so there is one layout to learn rather than two.
struct TermSheet: View {
  @Bindable var mock: Mock
  let existing: Term?

  @State private var isCorrection: Bool
  @State private var word: String
  @State private var heardAs: String

  init(mock: Mock, existing: Term?) {
    self.mock = mock
    self.existing = existing
    _isCorrection = State(initialValue: existing?.heardAs != nil)
    _word = State(initialValue: existing?.word ?? "")
    _heardAs = State(initialValue: existing?.heardAs ?? "")
  }

  var body: some View {
    Form {
      // The toggle is the first row of its own section and nothing above it ever changes size, so
      // it stays put when flipped. A control that moves when you use it is a control you misclick.
      Section {
        Toggle("Correct a misspelling", isOn: $isCorrection.animation(.easeOut(duration: 0.15)))
      }

      Section {
        if isCorrection {
          // Wispr's arrow reads as a rule: what was heard becomes what was meant. The placeholders
          // name each side's role, which is the only label these fields need.
          HStack(spacing: 10) {
            TextField("", text: $heardAs, prompt: Text("Misspelling"))
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            TextField("", text: $word, prompt: Text("Correct spelling"))
          }
        } else {
          TextField("", text: $word, prompt: Text("Add a new word"))
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .safeAreaInset(edge: .bottom) {
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
        Button(existing == nil ? "Add" : "Save") { dismiss() }
          .buttonStyle(.borderedProminent)
          .disabled(word.isEmpty || (isCorrection && heardAs.isEmpty))
      }
      .padding(12)
    }
  }

  private func dismiss() {
    mock.addingTerm = false
    mock.editingTerm = nil
  }
}

// MARK: - Cleanup

struct CleanupPane: View {
  @Bindable var mock: Mock

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          Toggle("Clean up transcripts", isOn: $mock.cleanupEnabled)
          Picker("Give up after", selection: $mock.cleanupTimeout) {
            ForEach([5, 10, 20, 30], id: \.self) { seconds in
              Text("\(seconds) seconds").tag(seconds)
            }
          }
          .disabled(!mock.cleanupEnabled)
        }

        Section {
          TextField("Address", text: endpointField($mock.endpointAddress))
          APIKeyField(mock: mock)
          // Loading is best effort. Plenty of gateways never implement /v1/models, so a failed
          // listing falls through to Custom with the field already open rather than leaving an
          // empty dropdown that reads as "you may not enter a model".
          LabeledContent("Model") {
            HStack {
              if case let .failed(reason) = mock.modelListing {
                Text(reason)
                  .foregroundStyle(.secondary)
                Spacer()
              }
              Picker("", selection: modelField($mock.cleanupModel)) {
                if case let .loaded(names) = mock.modelListing {
                  ForEach(names, id: \.self, content: Text.init)
                  Divider()
                }
                Text("Custom…").tag(customModelTag)
              }
              .labelsHidden()
              Button("Load Models") { mock.loadModels() }
              // C: one button, one place, three states — grey Save (nothing pending), blue Save
              // (edits pending), grey Saved (confirmed). Nothing moves; only meaning changes.
              if mock.saveVariant == .modelRow {
                Button(mock.saveResult == .saved && !mock.endpointDirty ? "Saved" : "Save") {
                  mock.commitSave()
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 56)
                .disabled(!mock.endpointDirty)
              }
            }
          }
          if mock.cleanupModel == customModelTag {
            TextField("", text: $mock.customModel, prompt: Text("Model ID"))
          }
          // A: the row Save keeps its own row, pushed to the trailing edge.
          if mock.saveVariant == .ownRowTrailing {
            HStack {
              Spacer()
              SaveResultLabel(result: mock.saveResult)
              saveButton
            }
          }

        } header: {
          // D: Save rides the section header's trailing edge, the Dictionary quick-add grammar.
          if mock.saveVariant == .sectionHeader {
            HStack {
              Text("Endpoint")
              Spacer()
              SaveResultLabel(result: mock.saveResult)
              saveButton
                .controlSize(.small)
            }
          } else {
            Text("Endpoint")
          }
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            // C's failure lives under the table, in red, above the promises.
            if mock.saveVariant == .modelRow, case let .failed(reason) = mock.saveResult {
              Text(reason)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if mock.saveVariant != .paneBottom {
              Text(privacyFooter)
            }
          }
        }
        .disabled(!mock.cleanupEnabled)

        Section {
          TextEditor(text: $mock.customPrompt)
            .frame(height: 64)
            .overlay(alignment: .topLeading) {
              if mock.customPrompt.isEmpty {
                Text("Keep it casual — lowercase is fine, and don’t touch my contractions.")
                  .foregroundStyle(.tertiary)
                  .padding(.top, 1)
                  .allowsHitTesting(false)
              }
            }
        } header: {
          Text("Custom prompt")
        }
        .disabled(!mock.cleanupEnabled)
      }
      .formStyle(.grouped)

      // B: Save leaves the form entirely — a pane-scoped bar under the scroll, bottom-right,
      // with the privacy promise beneath the button that enacts it.
      if mock.saveVariant == .paneBottom {
        VStack(alignment: .trailing, spacing: 6) {
          HStack {
            Spacer()
            SaveResultLabel(result: mock.saveResult)
            saveButton
          }
          Text(privacyFooter)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .disabled(!mock.cleanupEnabled)
      }
    }
    .animation(.easeOut(duration: 0.2), value: mock.saveResult)
  }

  // MARK: Private

  private var privacyFooter: String {
    "Transcripts are sent to this endpoint. Recorded audio never leaves this Mac. If cleanup fails or runs past the limit, the transcript is delivered as heard."
  }

  private var saveButton: some View {
    Button("Save") {
      if mock.endpointAddress.hasPrefix("https") {
        mock.saveResult = .saved
        // Storing the key is what saving means; until then it is only typed.
        mock.keyState = .stored
      } else {
        mock.saveResult = .failed("Couldn't reach that address.")
      }
    }
    .buttonStyle(.borderedProminent)
  }

  /// Editing any endpoint fact marks the section dirty, which is what arms the Save button.
  private func endpointField(_ binding: Binding<String>) -> Binding<String> {
    Binding(
      get: { binding.wrappedValue },
      set: { binding.wrappedValue = $0; mock.endpointDirty = true },
    )
  }

  private func modelField(_ binding: Binding<String>) -> Binding<String> {
    Binding(
      get: { binding.wrappedValue },
      set: { binding.wrappedValue = $0; mock.endpointDirty = true },
    )
  }
}

// MARK: - Save variant

enum SaveVariant {
  case ownRowTrailing
  case paneBottom
  case modelRow
  case sectionHeader
}

// MARK: - Save result

enum SaveResult: Equatable {
  case none
  case saved
  case failed(String)
}

// MARK: - Model listing

let customModelTag = "Custom…"

enum ModelListing: Equatable {
  case notLoaded
  case loaded([String])
  /// The endpoint answered but cannot enumerate models. Not an error the user has to fix.
  case failed(String)
}

// MARK: - Key state

enum KeyState: Equatable {
  /// A key exists on disk. Shown as a prefix and dots, never editable in place.
  case stored
  /// Being typed or pasted right now, in the clear.
  case editing(String)
}

/// A stored key is evidence, not content: it says which key is installed, and it cannot be edited
/// in place because a half-edited secret is a secret that no longer works. Touching it replaces it
/// outright. A key being typed is an ordinary text field, so selection, ⌘A, and paste all behave.
struct APIKeyField: View {
  @Bindable var mock: Mock

  var body: some View {
    LabeledContent("API key") {
      switch mock.keyState {
      case .stored:
        HStack {
          Text(masked)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("Replace") { mock.keyState = .editing("") }
        }
        .contentShape(.rect)
        .onTapGesture { mock.keyState = .editing("") }
      case let .editing(text):
        TextField(
          "", text: .init(get: { text }, set: { mock.keyState = .editing($0) }),
          prompt: Text("Paste your key"),
        )
      }
    }
  }

  private var masked: String {
    mock.storedKey.prefix(6) + String(repeating: "•", count: max(mock.storedKey.count - 6, 0))
  }
}

/// Says nothing until Save is pressed. Success is one word; failure is the specific reason.
struct SaveResultLabel: View {
  let result: SaveResult

  var body: some View {
    switch result {
    case .none:
      EmptyView()
    case .saved:
      Label("Saved", systemImage: "checkmark.circle.fill")
        .font(.callout)
        .foregroundStyle(.green)
    case let .failed(reason):
      Label(reason, systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.orange)
    }
  }
}

// MARK: - Model

/// The page as it should look in normal use: what is installed, what else could be, nothing more.
struct ModelPane: View {
  @Bindable var mock: Mock

  var body: some View {
    Form {
      // Installed models are a single choice, so the whole row selects: the checkmark marks the one
      // in use rather than a button asking to make it so.
      Section("Installed") {
        ForEach(["Parakeet TDT v2", "Parakeet TDT v3"], id: \.self) { name in
          InstalledModelRow(name: name, size: "474 MB", inUse: mock.activeModel == name)
            .contentShape(.rect)
            .onTapGesture { mock.activeModel = name }
        }
      }

      Section("Available") {
        LabeledContent("Whisper Medium.en") {
          HStack {
            Text("769 MB").foregroundStyle(.secondary)
            Button("Download") {}
          }
        }
      }

      Section {
        LabeledContent("Total on disk", value: "948 MB")
      }
    }
    .formStyle(.grouped)
  }
}

/// An installed model: in use or merely present, its size, and the things you can do to the file.
struct InstalledModelRow: View {
  let name: String
  let size: String
  let inUse: Bool

  var body: some View {
    LabeledContent {
      HStack {
        Text(size).foregroundStyle(.secondary)
        MoreMenu {
          Button("Reveal in Finder", systemImage: "folder") {}
          Button("Reinstall", systemImage: "arrow.clockwise") {}
          Divider()
          Button("Delete", systemImage: "trash", role: .destructive) {}
            .disabled(inUse)
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(inUse ? AnyShapeStyle(.green) : AnyShapeStyle(.quaternary))
        Text(name)
      }
    }
  }
}

/// Mock-up only. Every state the stateful rows can be in, side by side, so they can be compared.
/// The app only ever shows one of each.
struct ComponentStatesPane: View {
  var body: some View {
    Form {
      Section("Model") {
        EmptyView()
      }
      ForEach(InstallState.allCases) { state in
        Section(state.rawValue) {
          ModelRow(state: state)
        }
      }

      Section("Endpoint · after pressing Save") {
        LabeledContent("Untouched") { SaveResultLabel(result: .none) }
        LabeledContent("Success") { SaveResultLabel(result: .saved) }
        LabeledContent("Unreachable") { SaveResultLabel(result: .failed("Couldn't reach that address.")) }
        LabeledContent("Rejected") { SaveResultLabel(result: .failed("The key was refused.")) }
        LabeledContent("Missing model") { SaveResultLabel(result: .failed("That model isn't on this endpoint.")) }
        LabeledContent("No listing") { SaveResultLabel(result: .saved) }
      }

      Section("API key") {
        LabeledContent("Never set") { Text("").frame(maxWidth: .infinity, alignment: .leading) }
        LabeledContent("Stored") {
          Text("sk-pro••••••••••••••••••••").foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        LabeledContent("Being replaced") {
          Text("sk-proj-new-key-being-typed").frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .formStyle(.grouped)
  }
}

struct ModelRow: View {
  let state: InstallState

  var body: some View {
    switch state {
    case .notInstalled:
      LabeledContent("Parakeet TDT v3") {
        HStack {
          Text("474 MB").foregroundStyle(.secondary)
          Button("Download") {}
        }
      }
    case .downloading:
      progressRow(caption: "Downloading · 294 of 474 MB", value: 0.62)
    case .compiling:
      progressRow(caption: "Preparing · about 2 minutes left", value: nil)
    case .failed:
      LabeledContent {
        HStack {
          Button("Retry") {}
          Button("Cancel", role: .destructive) {}
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          VStack(alignment: .leading) {
            Text("Parakeet TDT v3")
            Text("The connection dropped").font(.callout).foregroundStyle(.secondary)
          }
        }
      }
    case .ready:
      InstalledModelRow(name: "Parakeet TDT v2", size: "474 MB", inUse: true)
    case .readyInactive:
      InstalledModelRow(name: "Parakeet TDT v3", size: "474 MB", inUse: false)
    }
  }

  private func progressRow(caption: String, value: Double?) -> some View {
    LabeledContent("Parakeet TDT v3") {
      HStack {
        Group {
          if let value {
            ProgressView(value: value) { Text(caption).font(.callout).foregroundStyle(.secondary) }
          } else {
            ProgressView { Text(caption).font(.callout).foregroundStyle(.secondary) }
          }
        }
        .frame(width: 220)
        Button("Cancel", role: .destructive) {}
      }
    }
  }
}

// MARK: - Cursor lab

/// Six treatments for the settings pane's keyboard cursor, judged against the grouped form's own
/// row background rather than History's plain list. In every section the Activate row wears the
/// cursor and the Microphone row does not, so each option is seen against its resting neighbour.
struct CursorLabPane: View {
  let page: Int

  var body: some View {
    Form {
      if page == 1 { pageOne } else { pageTwo }
    }
    .formStyle(.grouped)
  }

  // MARK: Private

  @ViewBuilder private var pageOne: some View {
    section(
        "A \u{00b7} Row fill \u{00b7} quaternary",
        "History's exact treatment: 8pt rounded quaternary fill behind the whole row.",
      ) { treated { RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)) } }
      section(
        "B \u{00b7} Row fill \u{00b7} quinary, inset",
        "A quieter fill floated 4pt inside the row so it never touches the section's own edges.",
      ) { treated { RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quinarySystemFill)).padding(3) } }
      section(
        "C \u{00b7} Accent wash",
        "The row keeps its shape; the cursor is an 8% accent tint across it.",
      ) { treated { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)) } }
  }

  @ViewBuilder private var pageTwo: some View {
    section(
        "D \u{00b7} Focus ring",
        "No fill at all: the system keyboard-focus colour strokes the row, the way macOS marks focus.",
      ) {
        treated {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
            .padding(2)
        }
      }
      section(
        "E \u{00b7} Accent bar",
        "A 3pt accent capsule at the leading edge names the row without repainting it.",
      ) {
        treated {
          HStack {
            Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 4)
            Spacer()
          }.padding(.leading, 4)
        }
      }
      section(
        "F \u{00b7} Control focus",
        "The row stays untouched; the cursor rings the control the key would press.",
      ) { controlFocusRow }
  }

  private var controlFocusRow: some View { shortcutRow(ringFirstChord: true) }

  private func section(
    _ title: String, _ note: String, @ViewBuilder cursorTreatment: () -> some View,
  ) -> some View {
    Section {
      cursorTreatment()
      Picker("Microphone", selection: .constant("System default")) {
        Text("System default").tag("System default")
      }
    } header: {
      Text(title)
    } footer: {
      Text(note)
    }
  }

  /// The grouped form paints its own opaque row above `listRowBackground`, so a cursor treatment
  /// has to live inside the row: insets zeroed, the row's spacing recreated inside the shape.
  private func treated(@ViewBuilder _ background: () -> some View) -> some View {
    shortcutRow(ringFirstChord: false)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background { background() }
      .listRowInsets(EdgeInsets())
  }

  private func shortcutRow(ringFirstChord: Bool) -> some View {
    LabeledContent("Activate") {
      HStack(spacing: 8) {
        KeycapChord(caps: ["\u{2325} Opt \u{2192}"], ringed: ringFirstChord)
        KeycapChord(caps: ["\u{2303} Ctrl \u{2192}", "R"], ringed: false)
        Image(systemName: "ellipsis").foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Playground: the composed cursor, live

/// The E+F design as something to feel, not look at. Mouse hover moves the accent bar exactly as
/// the keyboard cursor does, so the two inputs share one visual language; the focus ring exists
/// only while the keyboard is driving. j/k rows \u{00b7} h/l targets \u{00b7} Return presses \u{00b7}
/// h past the left edge "ascends".
@Observable final class PlaygroundState {
  enum Mode { case mouse, keyboard }

  static let targets: [[String]] = [
    ["rerecord \u{2325} Opt \u{2192}", "rerecord \u{2303} Ctrl \u{2192} R", "open the \u{22ef} menu"],
    ["open the Microphone picker"],
    ["toggle Open at login"],
  ]

  var mode = Mode.mouse
  var hovered: Int?
  var row = 0
  var target = 0
  var inSidebar = false
  var flash = "Move the mouse over rows, or press j / k / h / l / Return."

  var barRow: Int? {
    if inSidebar { return nil }
    return mode == .mouse ? hovered : row
  }

  func ringTarget(row index: Int) -> Int? {
    guard mode == .keyboard, !inSidebar, index == row else { return nil }
    return target
  }

  func key(_ character: String) -> Bool {
    switch character {
    case "j", "k":
      enterKeyboard()
      if inSidebar {
        flash = "(sidebar) j/k would walk destinations \u{2014} l returns to the pane"
        return true
      }
      row = min(max(row + (character == "j" ? 1 : -1), 0), Self.targets.count - 1)
      target = 0
      flash = "row \(row + 1)"
    case "l":
      enterKeyboard()
      if inSidebar {
        inSidebar = false
        flash = "back in the pane"
        return true
      }
      guard target < Self.targets[row].count - 1 else {
        flash = "(right edge \u{2014} nothing further)"
        return true
      }
      target += 1
      flash = "target: \(Self.targets[row][target])"
    case "h":
      enterKeyboard()
      guard !inSidebar else { return true }
      if target > 0 {
        target -= 1
        flash = "target: \(Self.targets[row][target])"
      } else {
        inSidebar = true
        flash = "ascended to the sidebar \u{2014} l comes back"
      }
    case "\r":
      enterKeyboard()
      guard !inSidebar else { return true }
      flash = "Return \u{2192} \(Self.targets[row][target])"
    default:
      return false
    }
    return true
  }

  private func enterKeyboard() {
    mode = .keyboard
    hovered = nil
  }
}

struct PlaygroundPane: View {
  @State private var state = PlaygroundState()
  @State private var monitor: Any?

  var body: some View {
    Form {
      Section {
        playRow(0) {
          LabeledContent("Activate") {
            HStack(spacing: 8) {
              KeycapChord(caps: ["\u{2325} Opt \u{2192}"], ringed: state.ringTarget(row: 0) == 0)
              KeycapChord(
                caps: ["\u{2303} Ctrl \u{2192}", "R"], ringed: state.ringTarget(row: 0) == 1,
              )
              Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .padding(4)
                .overlay {
                  if state.ringTarget(row: 0) == 2 {
                    RoundedRectangle(cornerRadius: 6)
                      .strokeBorder(
                        Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2,
                      )
                  }
                }
            }
          }
        }
        playRow(1) {
          LabeledContent("Microphone") {
            Picker("", selection: .constant("System default")) {
              Text("System default").tag("System default")
            }
            .labelsHidden()
            .fixedSize()
            .overlay {
              if state.ringTarget(row: 1) == 0 {
                RoundedRectangle(cornerRadius: 6)
                  .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                  .padding(-1)
              }
            }
          }
        }
        playRow(2) {
          LabeledContent("Open at login") {
            Toggle("", isOn: .constant(true))
              .labelsHidden()
              .toggleStyle(.switch)
              .overlay {
                if state.ringTarget(row: 2) == 0 {
                  RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                    .padding(-3)
                }
              }
          }
        }
      } header: {
        Text("Playground \u{00b7} j/k rows \u{00b7} h/l targets \u{00b7} Return presses")
      } footer: {
        Label(state.flash, systemImage: state.inSidebar ? "sidebar.left" : "keyboard")
          .font(.callout)
          .foregroundStyle(.secondary)
          .animation(.easeOut(duration: 0.15), value: state.flash)
      }
    }
    .formStyle(.grouped)
    .onAppear {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        guard let characters = event.charactersIgnoringModifiers,
              state.key(characters) else { return event }
        return nil
      }
    }
    .onDisappear {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }

  // MARK: Private

  private func playRow(_ index: Int, @ViewBuilder content: () -> some View) -> some View {
    content()
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background {
        if state.barRow == index {
          HStack {
            Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 4)
            Spacer()
          }
          .padding(.leading, 4)
        }
      }
      .animation(.easeOut(duration: 0.12), value: state.barRow)
      .listRowInsets(EdgeInsets())
      .contentShape(Rectangle())
      // The bar only ever moves to a row; it never clears between them. Leaving a row without
      // entering another (the separator, the form margin) keeps the last row lit, so a sweep
      // across the section reads as one continuous motion instead of a blink per gap.
      .onHover { inside in
        guard inside else { return }
        state.mode = .mouse
        state.inSidebar = false
        state.hovered = index
      }
  }
}

// MARK: - Composed lab: accent bar + control focus

/// E and F together: the accent bar is the row cursor, and within the row a focus ring marks the
/// one target a key press would hit. Each section freezes one moment of the walk.
struct ComposedLabPane: View {
  var body: some View {
    Form {
      moment(
        "1 \u{00b7} Cursor enters the row",
        "The bar marks the row; the ring starts on the first binding.",
        ring: 0,
      )
      moment(
        "2 \u{00b7} One step right",
        "The bar holds the row; the ring moves to the second binding.",
        ring: 1,
      )
      moment(
        "3 \u{00b7} The menu is a target too",
        "Add and Remove stay reachable without a pointer: the ring lands on the \u{22ef} last.",
        ring: 2,
      )
      Section {
        barRow {
          LabeledContent("Microphone") {
            Picker("", selection: .constant("System default")) {
              Text("System default").tag("System default")
            }
            .labelsHidden()
            .fixedSize()
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                .padding(-1)
            }
          }
        }
      } header: {
        Text("4 \u{00b7} The same grammar on any row")
      } footer: {
        Text("A one-control row is just a one-stop walk: the ring sits on the picker.")
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Private

  private func moment(_ title: String, _ note: String, ring: Int) -> some View {
    Section {
      barRow {
        LabeledContent("Activate") {
          HStack(spacing: 8) {
            KeycapChord(caps: ["\u{2325} Opt \u{2192}"], ringed: ring == 0)
            KeycapChord(caps: ["\u{2303} Ctrl \u{2192}", "R"], ringed: ring == 1)
            Image(systemName: "ellipsis")
              .foregroundStyle(.secondary)
              .padding(4)
              .overlay {
                if ring == 2 {
                  RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                }
              }
          }
        }
      }
    } header: {
      Text(title)
    } footer: {
      Text(note)
    }
  }

  private func barRow(@ViewBuilder content: () -> some View) -> some View {
    content()
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background {
        HStack {
          Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 4)
          Spacer()
        }
        .padding(.leading, 4)
      }
      .listRowInsets(EdgeInsets())
  }
}

/// The shipped binding anatomy: each chord component is its own keycap box, the boxes grouped
/// into one click target.
struct KeycapChord: View {
  let caps: [String]
  let ringed: Bool

  var body: some View {
    HStack(spacing: 3) {
      ForEach(caps, id: \.self) { cap in
        Text(cap)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(
            RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .quaternarySystemFill)),
          )
      }
    }
    .padding(3)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .quinarySystemFill)))
    .overlay {
      if ringed {
        RoundedRectangle(cornerRadius: 7)
          .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
      }
    }
  }
}

// MARK: - Settings

struct SettingsPane: View {
  @Bindable var mock: Mock

  var body: some View {
    Form {
      // Only exists when something is wrong, and then it is the first thing on the page.
      if mock.hasProblem {
        Section {
          if !mock.microphoneGranted {
            ProblemRow("Microphone access is off, so nothing can be recorded", action: "Open Settings…")
          }
          if !mock.accessibilityGranted {
            ProblemRow("Accessibility is off, so the shortcut and pasting can't work", action: "Open Settings…")
          }
        }
      }

      Section {
        ShortcutRow("Activate", keys: ["⌥ Right Opt", "⌃ Ctrl ⌥ Opt R"])
        ShortcutRow("Copy last transcript", keys: [])
      } header: {
        Text("Shortcuts")
      } footer: {
        Text("Hold to dictate, or double-tap to keep recording hands free.")
      }

      Section("Microphone") {
        Picker("Input", selection: $mock.microphone) {
          Text("System default").tag("System default")
          Divider()
          Text("AirPods Pro").tag("AirPods Pro")
          Text("MacBook Pro Microphone").tag("MacBook Pro Microphone")
        }
      }

      Section("Sounds") {
        CueRow("Recording started", selection: $mock.cueStart)
        CueRow("Transcription completed", selection: $mock.cueDelivered)
        CueRow("Recording cancelled", selection: $mock.cueCancelled)
        CueRow("Problem while transcribing", selection: $mock.cueFailed)
      }

      Section {
        Toggle("Mute other audio while active", isOn: $mock.muteWhileActive)
      }

      Section {
        Toggle("Open at login", isOn: $mock.launchAtLogin)
        LabeledContent("Version", value: "0.2.0")
        Button("Open Settings File…") {}
      }
    }
    .formStyle(.grouped)
  }
}

struct ProblemRow: View {
  let message: String
  let action: String

  init(_ message: String, action: String) {
    self.message = message
    self.action = action
  }

  var body: some View {
    LabeledContent {
      Button(action) {}
    } label: {
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }
}

/// A shortcut may be bound more than once, or not at all. Clicking a binding rerecords it, so the
/// menu holds only what clicking cannot do.
struct ShortcutRow: View {
  let label: String
  let keys: [String]

  init(_ label: String, keys: [String]) {
    self.label = label
    self.keys = keys
  }

  var body: some View {
    LabeledContent(label) {
      HStack {
        if keys.isEmpty {
          Text("Not set").foregroundStyle(.secondary)
          Button("Set…") {}
        } else {
          ForEach(keys, id: \.self) { key in
            Button(key) {}
          }
        }
        MoreMenu {
          Button("Add Another…", systemImage: "plus") {}
          Divider()
          ForEach(keys, id: \.self) { key in
            Button("Remove \(key)", systemImage: "xmark", role: .destructive) {}
          }
        }
      }
    }
  }
}

/// Choosing a cue plays it, and the button replays it without reopening the menu. "No audio" is
/// dimmed so silence reads as the absence of a choice rather than one more sound.
struct CueRow: View {
  let label: String
  @Binding var selection: String

  init(_ label: String, selection: Binding<String>) {
    self.label = label
    _selection = selection
  }

  var body: some View {
    LabeledContent(label) {
      HStack {
        Picker("", selection: $selection) {
          Text(noAudioCue).foregroundStyle(.secondary).tag(noAudioCue)
          Divider()
          ForEach(cues.dropFirst(), id: \.self, content: Text.init)
        }
        .labelsHidden()
        Button("Play", systemImage: "play.circle") {}
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .disabled(selection == noAudioCue)
      }
    }
  }
}

// MARK: - Shared

/// One ellipsis menu, used everywhere. Getting `.iconOnly` and the indicator right once beats
/// getting it subtly wrong in four places.
struct MoreMenu<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    Menu {
      content
    } label: {
      Label("More", systemImage: "ellipsis")
        .labelStyle(.iconOnly)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

// MARK: - Window

struct Root: View {
  @Bindable var mock: Mock

  var body: some View {
    NavigationSplitView {
      List(selection: $mock.destination) {
        row(.settings)
        Section {
          ForEach([Destination.history, .model, .dictionary, .cleanup], content: row)
        }
        Section("Mock-up only") {
          row(.states)
        }
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 220)
    } detail: {
      pane(mock.destination)
        .navigationTitle(mock.destination.rawValue)
    }
  }

  private func row(_ destination: Destination) -> some View {
    Label(destination.rawValue, systemImage: destination.symbol).tag(destination)
  }

  @ViewBuilder private func pane(_ destination: Destination) -> some View {
    switch destination {
    case .settings: SettingsPane(mock: mock)
    case .history: HistoryPane(mock: mock)
    case .model: ModelPane(mock: mock)
    case .dictionary: DictionaryPane(mock: mock)
    case .cleanup: CleanupPane(mock: mock)
    case .states: ComponentStatesPane()
    case .cursorLab1: CursorLabPane(page: 1)
    case .cursorLab2: CursorLabPane(page: 2)
    case .cursorLab3: ComposedLabPane()
    case .playground: PlaygroundPane()
    }
  }
}

// MARK: - Host

final class Delegate: NSObject, NSApplicationDelegate {
  let mock = Mock()
  var window: NSWindow!

  func applicationDidFinishLaunching(_: Notification) {
    mock.seedStage()
    if CommandLine.arguments.contains("light") {
      NSApp.appearance = NSAppearance(named: .aqua)
    } else if CommandLine.arguments.contains("dark") {
      NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false,
    )
    window.title = "MiniWhisper"
    window.toolbarStyle = .unified
    window.contentView = NSHostingView(rootView: Root(mock: mock))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // `screencapture -l` wants the CGWindowID, which is exactly this. Reporting it beats
    // screen-scraping coordinates that go stale the moment anything else takes the front.
    print(window.windowNumber)
    fflush(stdout)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
