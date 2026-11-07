import AppSettings
import ComposableArchitecture
import ModelLibrary
import SwiftUI

// MARK: - ModelsPane

/// A patch bay when its two columns fit; an asset-first form in a narrow window. Both show which
/// profiles depend on each component, and share the same model actions.
struct ModelsPane: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    GeometryReader { geometry in
      if geometry.size.width < 600 {
        compact
      } else {
        patchBay
      }
    }
    .alert(
      "Delete \(models.pendingDeletion?.name ?? "")?", isPresented: deletionPending,
      presenting: models.pendingDeletion,
    ) { _ in
      Button("Cancel", role: .cancel) { store.send(.models(.deletionCancelled)) }
      Button("Delete", role: .destructive) { store.send(.models(.deletionConfirmed)) }
    } message: { _ in
      Text("\(models.settings.activeProfile.name) can’t transcribe until it’s downloaded again.")
    }
    .task { store.send(.models(.task)) }
  }

  // MARK: Private

  private var models: ModelsFeature.State {
    store.models
  }

  private var deletionPending: Binding<Bool> {
    Binding(
      get: { models.pendingDeletion != nil },
      set: { isPresented in
        guard !isPresented, models.pendingDeletion != nil else {
          return
        }
        store.send(.models(.deletionCancelled))
      },
    )
  }

  private var patchBay: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GateStrip(store: store)
        HStack(alignment: .top, spacing: 0) {
          VStack(spacing: 10) {
            ForEach(models.settings.profiles.lineup) { profile in
              PatchCard(store: store, profile: profile)
            }
          }
          .frame(minWidth: 180, maxWidth: 250)
          Spacer(minLength: 48)
          VStack(alignment: .leading, spacing: 8) {
            ColumnHeader("On this Mac")
            ComponentRow(store: store, component: .asset(.parakeet))
            ComponentRow(store: store, component: .asset(.s1Mini))
            ColumnHeader("Off this Mac")
              .padding(.top, 8)
            ComponentRow(store: store, component: .scribe)
            ForEach(models.settings.profiles.lineup.filter { $0.endpointLeg != nil }) { profile in
              ComponentRow(store: store, component: .endpoint(profile.id))
            }
          }
          .frame(minWidth: 200, maxWidth: 340)
        }
        .overlayPreferenceValue(PortKey.self) { ports in
          GeometryReader { proxy in
            Wires(store: store, ports: ports, proxy: proxy)
          }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
        if let failure = models.assetFailure {
          SemanticText(failure, identifier: AccessibilityID.modelsFailure, label: "Model failure")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .padding(20)
    }
    .keyboardCursorScroll(store: store, cursor: models.cursorRow)
  }

  private var compact: some View {
    Form {
      Section("On this Mac") {
        ForEach(ModelAsset.allCases, id: \.self) { asset in
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
              AssetStatus(store: store, asset: asset)
                .fixedSize()
            } label: {
              Text(asset.name)
                .fixedSize(horizontal: false, vertical: true)
            }
            if asset == .gate {
              Text("First stop in every profile")
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
              dependents(of: .asset(asset))
            }
          }
          .modifier(ModelsRow(store: store, row: .asset(asset)))
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier(AccessibilityID.modelsComponent(.asset(asset)))
        }
      }
      Section("Off this Mac") {
        hosted(.scribe, title: "ElevenLabs", model: "Scribe v2", sends: "Audio")
        ForEach(models.settings.profiles.lineup.filter { $0.endpointLeg != nil }) { profile in
          hosted(
            .endpoint(profile.id),
            title: profile.factory?.provider.displayName ?? "Your endpoint",
            model: profile.endpointLeg?.model ?? "Not set up",
            sends: "Transcript",
          )
        }
      }
      if let failure = models.assetFailure {
        Section {
          SemanticText(failure, identifier: AccessibilityID.modelsFailure, label: "Model failure")
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .keyboardCursorScroll(store: store, cursor: models.cursorRow)
  }

  private func hosted(
    _ component: ModelsFeature.Component, title: String, model: String, sends: String,
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      LabeledContent {
        Text(sends)
          .font(.callout)
          .foregroundStyle(.secondary)
      } label: {
        Text(title)
        Text(model)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      dependents(of: component)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.modelsComponent(component))
  }

  private func dependents(of component: ModelsFeature.Component) -> some View {
    ForEach(models.settings.profiles.lineup.filter { profile in
      [ModelsFeature.Leg.speech, .cleanup].contains {
        models.component($0, of: profile) == component
      }
    }) { profile in
      let speech = models.component(.speech, of: profile) == component
      let label = Text(
        "\(profile.name)\(models.settings.profiles.active == profile.id ? " · Active" : "")",
      )
      .font(.callout)
      .foregroundStyle(models.highlighted == profile.id ? Color.accentColor : Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
      if speech {
        label
          .modifier(ModelsRow(store: store, row: .profile(profile.id)))
          .accessibilityIdentifier(AccessibilityID.modelsCard(profile.id))
          .accessibilityValue(
            [
              models.settings.profiles.active == profile.id ? "Active" : nil,
              models.highlighted == profile.id ? "Highlighted" : nil,
            ]
            .compactMap(\.self)
            .joined(separator: "; "),
          )
      } else {
        label
      }
    }
  }
}

// MARK: - Port

private enum Port: Hashable {
  case card(ProfileID, ModelsFeature.Leg)
  case component(ModelsFeature.Component)
}

// MARK: - PortKey

private struct PortKey: PreferenceKey {
  static let defaultValue: [Port: Anchor<CGPoint>] = [:]

  static func reduce(
    value: inout [Port: Anchor<CGPoint>],
    nextValue: () -> [Port: Anchor<CGPoint>],
  ) {
    value.merge(nextValue()) { $1 }
  }
}

// MARK: - Wires

/// Drawn under nothing and hit by nothing: the cards and rows are the controls, the wires only say
/// which is plugged into which. The lit profile is drawn last so its wires cross over the rest.
private struct Wires: View {
  let store: StoreOf<SettingsWindowFeature>
  let ports: [Port: Anchor<CGPoint>]
  let proxy: GeometryProxy

  var body: some View {
    // Read here rather than inside the canvas: only a body's reads are observed, and a wire that
    // never hears the highlight move or a download fail would keep saying what used to be true.
    let models = store.models
    let assets = models.assets
    let highlighted = models.highlighted
    Canvas { context, _ in
      let lineup = models.settings.profiles.lineup
      let ordered = lineup.filter { $0.id != highlighted } + lineup.filter { $0.id == highlighted }
      for profile in ordered {
        let isLit = profile.id == highlighted
        for leg in [ModelsFeature.Leg.speech, .cleanup] {
          guard let component = models.component(leg, of: profile),
                let from = ports[.card(profile.id, leg)].map({ proxy[$0] }),
                let to = ports[.component(component)].map({ proxy[$0] })
          else {
            continue
          }
          var path = Path()
          path.move(to: from)
          let bend = (to.x - from.x) * 0.5
          path.addCurve(
            to: to, control1: CGPoint(x: from.x + bend, y: from.y),
            control2: CGPoint(x: to.x - bend, y: to.y),
          )
          let state = component.asset.flatMap { assets[$0] }
          let isBroken = state?.isInstalled == false
          let shading: GraphicsContext.Shading =
            if case .failed = state {
              .color(.red)
            } else if isLit {
              .color(.accentColor)
            } else {
              .style(.tertiary)
            }
          context.stroke(
            path, with: shading,
            style: StrokeStyle(
              lineWidth: isLit ? 2 : 1, lineCap: .round, dash: isBroken ? [4, 3] : [],
            ),
          )
        }
      }
    }
  }
}

// MARK: - GateStrip

/// Every profile runs the gate first, so five wires to it would say nothing: it is one strip
/// across the top instead.
private struct GateStrip: View {
  let store: StoreOf<SettingsWindowFeature>

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "internaldrive")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(ModelAsset.gate.name)
        Text("First stop in every profile")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      AssetStatus(store: store, asset: .gate)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.tint.quinary, in: .rect(cornerRadius: 8))
    .modifier(ModelsRow(store: store, row: .asset(.gate)))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.modelsComponent(.asset(.gate)))
  }
}

// MARK: - ColumnHeader

private struct ColumnHeader: View {
  // MARK: Lifecycle

  init(_ title: String) {
    self.title = title
  }

  // MARK: Internal

  let title: String

  var body: some View {
    Text(title)
      .font(.callout)
      .foregroundStyle(.secondary)
      .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - PatchCard

/// A profile and its two legs, each ending in the port its wire leaves from. The lit card wears
/// the accent stroke; the active one says so in words, because lit and active are different facts.
private struct PatchCard: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let profile: Profile

  var body: some View {
    let isLit = store.models.highlighted == profile.id
    let isActive = store.models.settings.profiles.active == profile.id
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: profile.symbol)
          .foregroundStyle(isLit ? Color.accentColor : Color.secondary)
        Text(profile.name)
          .fontWeight(.medium)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        if isActive {
          Text("Active")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      leg(.speech, "Speech", profile.engine.name)
      leg(.cleanup, "Cleanup", cleanup)
    }
    .padding(10)
    .background(.quinary, in: .rect(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          isLit ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isLit ? 2 : 1,
        )
    }
    .contentShape(.rect(cornerRadius: 8))
    .modifier(ModelsRow(store: store, row: .profile(profile.id)))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(AccessibilityID.modelsCard(profile.id))
    .accessibilityValue(
      [isActive ? "Active" : nil, isLit ? "Highlighted" : nil]
        .compactMap(\.self)
        .joined(separator: "; "),
    )
  }

  // MARK: Private

  private var cleanup: String {
    switch profile.cleanup {
    case .none:
      "None"
    case .local:
      ModelAsset.s1Mini.name
    case let .endpoint(leg):
      leg.model ?? "Not set up"
    }
  }

  private func leg(_ leg: ModelsFeature.Leg, _ label: String, _ value: String) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 58, alignment: .leading)
      Text(value)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
      PortDot(isLit: store.models.highlighted == profile.id, isPlugged: isPlugged(leg))
        .anchorPreference(key: PortKey.self, value: .center) { [.card(profile.id, leg): $0] }
    }
    .font(.callout)
  }

  private func isPlugged(_ leg: ModelsFeature.Leg) -> Bool {
    store.models.component(leg, of: profile) != nil
  }
}

// MARK: - ComponentRow

/// One thing a leg can plug into. A model on this Mac carries its size and the way to get the
/// space back; a service off it carries what it is sent.
private struct ComponentRow: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let component: ModelsFeature.Component

  var body: some View {
    let isLit = litComponents.contains(component)
    let row = HStack(spacing: 8) {
      PortDot(isLit: isLit, isPlugged: true)
        .anchorPreference(key: PortKey.self, value: .center) { [.component(component): $0] }
      Image(systemName: component.asset == nil ? "cloud" : "internaldrive")
        .foregroundStyle(.secondary)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          identity.fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 0)
          status
        }
        VStack(alignment: .leading, spacing: 8) {
          identity
          status
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      isLit ? AnyShapeStyle(.tint.quinary) : AnyShapeStyle(.quinary), in: .rect(cornerRadius: 8),
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          .separator, style: StrokeStyle(lineWidth: 1, dash: component.asset == nil ? [4, 3] : []),
        )
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.modelsComponent(component))
    .accessibilityLabel(title)
    if let asset = component.asset {
      row.modifier(ModelsRow(store: store, row: .asset(asset)))
    } else {
      row
    }
  }

  // MARK: Private

  private var litComponents: Set<ModelsFeature.Component> {
    let profile = store.models.settings.profiles.profile(store.models.highlighted)
    return Set([ModelsFeature.Leg.speech, .cleanup].compactMap {
      store.models.component($0, of: profile)
    })
  }

  private var title: String {
    switch component {
    case let .asset(asset):
      asset.name
    case .scribe:
      "ElevenLabs"
    case let .endpoint(id):
      store.models.settings.profiles.profile(id).factory?.provider.displayName ?? "Your endpoint"
    }
  }

  private var subtitle: String {
    switch component {
    case let .asset(asset):
      store.models.users(of: asset)
    case .scribe:
      "Scribe v2"
    case let .endpoint(id):
      store.models.settings.profiles.profile(id).endpointLeg?.model ?? "Not set up"
    }
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .fixedSize(horizontal: false, vertical: true)
      Text(subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder private var status: some View {
    if let asset = component.asset {
      AssetStatus(store: store, asset: asset)
        .fixedSize()
    } else {
      Image(systemName: component == .scribe ? "waveform" : "text.quote")
        .foregroundStyle(.secondary)
        .help(component == .scribe ? "Sent your audio" : "Sent your transcript")
    }
  }
}

// MARK: - AssetStatus

/// The one slot a model's state lives in: its size and Delete, its progress, its failure and
/// Retry, or Download. Delete asks first only when the active profile runs on the model, and only
/// then wears the ellipsis that promises a question.
private struct AssetStatus: View {
  // MARK: Internal

  let store: StoreOf<SettingsWindowFeature>
  let asset: ModelAsset

  var body: some View {
    let isRinged = store.state.showsModelsRing(asset)
    HStack(spacing: 8) {
      switch store.models.assets[asset] {
      case let .installed(bytes):
        state(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        if store.models.isDeletable(asset) {
          Button(store.models.asksBeforeDeleting(asset) ? "Delete…" : "Delete") {
            store.send(.models(.deleteTapped(asset)))
          }
          .focusRing(isRinged)
          .accessibilityIdentifier(AccessibilityID.modelsAssetDelete(asset))
        }
      case let .downloading(fraction):
        ProgressView(value: fraction)
          .frame(width: 60)
        state("\(Int(fraction * 100))%")
      case .failed:
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        state("Failed")
        Button("Retry") { store.send(.models(.downloadTapped(asset))) }
          .focusRing(isRinged)
          .accessibilityIdentifier(AccessibilityID.modelsAssetDownload(asset))
      case .missing:
        state(ByteCountFormatter.string(fromByteCount: Int64(asset.pinnedBytes), countStyle: .file))
        Button("Download") { store.send(.models(.downloadTapped(asset))) }
          .focusRing(isRinged)
          .accessibilityIdentifier(AccessibilityID.modelsAssetDownload(asset))
      case nil:
        EmptyView()
      }
    }
  }

  // MARK: Private

  private func state(_ text: String) -> some View {
    SemanticText(
      text, identifier: AccessibilityID.modelsAssetState(asset), label: "\(asset.name) state",
    )
    .font(.callout)
    .foregroundStyle(.secondary)
    .monospacedDigit()
  }
}

// MARK: - PortDot

private struct PortDot: View {
  let isLit: Bool
  let isPlugged: Bool

  var body: some View {
    Circle()
      .fill(isLit && isPlugged ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
      .frame(width: 7, height: 7)
      .opacity(isPlugged ? 1 : 0)
  }
}

// MARK: - ModelsRow

/// The pane's half of the cursor grammar: pointing at a row is standing on it.
private struct ModelsRow: ViewModifier {
  let store: StoreOf<SettingsWindowFeature>
  let row: ModelsFeature.Row

  func body(content: Content) -> some View {
    content
      .id(row)
      .windowPointerMovement(store: store) {
        store.send(.models(.cursorHovered(row)))
      }
  }
}

private extension ModelsFeature.Component {
  var asset: ModelAsset? {
    if case let .asset(asset) = self {
      return asset
    }
    return nil
  }
}
