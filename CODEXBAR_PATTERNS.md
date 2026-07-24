# CodexBar Architectural Patterns

A detailed reference for advanced macOS app patterns used in CodexBar. These patterns apply to menu bar apps, especially those mixing AppKit and SwiftUI with complex state management.

## 1. Enum Singleton Registry Pattern

### Why Enums Over Structs for Namespaces

CodexBar uses enum-based registries rather than structs as static namespaces. This provides:

- **Stronger type safety**: Enums cannot be instantiated, preventing accidental instance creation
- **Clearer intent**: Declares a namespace/registry explicitly, not a type you'd instantiate
- **Pattern enforcement**: Lock-based synchronization at the type level
- **Cleaner API**: No awkward `static let shared` patterns

### The Provider Registry Pattern

**File**: `Providers/ProviderDescriptor.swift`

```swift
public enum ProviderDescriptorRegistry {
    private final class Store: @unchecked Sendable {
        var ordered: [ProviderDescriptor] = []
        var byID: [UsageProvider: ProviderDescriptor] = [:]
    }

    private static let lock = NSLock()
    private static let store = Store()
    
    // Lazy bootstrap ensures initialization only when first accessed
    private static let bootstrap: Void = {
        _ = ProviderDescriptorRegistry.register(CodexProviderDescriptor.descriptor)
        _ = ProviderDescriptorRegistry.register(ClaudeProviderDescriptor.descriptor)
        // ... register all providers
    }()

    private static func ensureBootstrapped() {
        _ = self.bootstrap
    }

    @discardableResult
    public static func register(_ descriptor: ProviderDescriptor) -> ProviderDescriptor {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.store.byID[descriptor.id] == nil {
            self.store.ordered.append(descriptor)
        }
        self.store.byID[descriptor.id] = descriptor
        return descriptor
    }

    public static var all: [ProviderDescriptor] {
        self.ensureBootstrapped()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.store.ordered
    }

    public static func descriptor(for id: UsageProvider) -> ProviderDescriptor {
        self.ensureBootstrapped()
        if let found = self.store.byID[id] { return found }
        if let found = self.all.first(where: { $0.id == id }) { return found }
        fatalError("Missing ProviderDescriptor for \(id.rawValue)")
    }
}
```

**Key patterns**:

1. **Thread-safe lazy initialization**: `bootstrap` property uses static initialization guarantee
2. **Private inner store class**: Keeps mutable state encapsulated with `@unchecked Sendable`
3. **Dual lookups**: O(1) by ID and ordered iteration available simultaneously
4. **Registration returns value**: Allows use in static properties for compile-time registration
5. **Lock discipline**: Every public method locks/unlocks symmetrically using `defer`

**Usage**:

```swift
// Providers register themselves at module import time
let descriptor = ProviderDescriptorRegistry.descriptor(for: .codex)

// Iterate all descriptors (maintains order)
for descriptor in ProviderDescriptorRegistry.all {
    // ...
}

// Get metadata dictionary
let metadata = ProviderDescriptorRegistry.metadata  // [UsageProvider: ProviderMetadata]
```

---

## 2. Hybrid AppKit + SwiftUI Menu Bar Architecture

### Design Philosophy

CodexBar maintains the menu bar UI in AppKit (NSStatusBar, NSMenu, NSMenuItem) while using SwiftUI for settings/preferences. This hybrid approach provides:

- **Fast animations**: Direct NSImage updates avoid SwiftUI rendering overhead
- **Native feel**: AppKit menus work exactly as users expect
- **Settings in SwiftUI**: Modern, clean preferences UI
- **Contained complexity**: Clear boundary between AppKit state and SwiftUI state

### The Three-Layer Architecture

```text
┌─────────────────────────────────────┐
│  AppKit NSStatusBar + NSMenu        │
│  (Direct icon updates, fast)        │
│  StatusItemController               │
└────────────┬────────────────────────┘
             │ (reads from)
┌────────────▼────────────────────────┐
│  State Stores (@Observable)         │
│  UsageStore, SettingsStore          │
│  (Single source of truth)           │
└────────────┬────────────────────────┘
             │ (reads from)
┌────────────▼────────────────────────┐
│  SwiftUI Settings UI                │
│  PreferencesView, MenuContent       │
│  (UI mirrors state)                 │
└─────────────────────────────────────┘
```

### StatusItemController: AppKit Host

**File**: `StatusItemController.swift`

```swift
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, StatusItemControlling {
    typealias Factory = (UsageStore, SettingsStore, AccountInfo, UpdaterProviding, 
                        PreferencesSelection) -> StatusItemControlling
    static var factory: Factory = StatusItemController.defaultFactory

    let store: UsageStore
    let settings: SettingsStore
    var statusItem: NSStatusItem
    var statusItems: [UsageProvider: NSStatusItem] = [:]
    var mergedMenu: NSMenu?
    var providerMenus: [UsageProvider: NSMenu] = [:]
    var fallbackMenu: NSMenu?
    
    // Track open menus for refresh during animation
    var openMenus: [ObjectIdentifier: NSMenu] = [:]

    init(
        store: UsageStore,
        settings: SettingsStore,
        account: AccountInfo,
        updater: UpdaterProviding,
        preferencesSelection: PreferencesSelection)
    {
        let bar = NSStatusBar.system
        let item = bar.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imageScaling = .scaleNone  // Crisp rendering for template images
        self.statusItem = item
        
        // One status item per provider
        for provider in UsageProvider.allCases {
            let providerItem = bar.statusItem(withLength: NSStatusItem.variableLength)
            providerItem.button?.imageScaling = .scaleNone
            self.statusItems[provider] = providerItem
        }
        
        super.init()
        self.wireBindings()
        self.updateIcons()
        self.updateVisibility()
    }
}
```

**Key decisions**:

1. **Factory pattern**: Enables dependency injection and testing
2. **@MainActor**: All UI updates happen on main thread
3. **NSStatusItem per provider**: Allows independent visibility/menu attachment
4. **Template image scaling**: Ensures crisp rendering at 1:1

### Menu Attachment Pattern

Menus are lazily created and attached based on provider state:

```swift
private func attachMenus() {
    if self.mergedMenu == nil {
        self.mergedMenu = self.makeMenu()
    }
    if self.statusItem.menu !== self.mergedMenu {
        self.statusItem.menu = self.mergedMenu
    }
}

private func attachMenus(fallback: UsageProvider? = nil) {
    for provider in UsageProvider.allCases {
        guard let item = self.statusItems[provider] else { continue }
        if self.isEnabled(provider) {
            if self.providerMenus[provider] == nil {
                self.providerMenus[provider] = self.makeMenu(for: provider)
            }
            let menu = self.providerMenus[provider]
            if item.menu !== menu {
                item.menu = menu
            }
        } else if fallback == provider {
            if self.fallbackMenu == nil {
                self.fallbackMenu = self.makeMenu(for: nil)
            }
            if item.menu !== self.fallbackMenu {
                item.menu = self.fallbackMenu
            }
        } else {
            if item.menu != nil {
                item.menu = nil
            }
        }
    }
}
```

### NSMenuDelegate for Dynamic Updates

```swift
@MainActor
protocol StatusItemControlling: AnyObject {
    func openMenuFromShortcut()
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Track which menu opened
        self.openMenus[ObjectIdentifier(menu)] = menu
        
        // Populate with current data
        if self.menuNeedsRefresh(menu) {
            self.populateMenu(menu, provider: provider)
            self.markMenuFresh(menu)
        }
        
        // Schedule refresh if data updates while menu is open
        self.scheduleOpenMenuRefresh(for: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        self.openMenus.removeValue(forKey: ObjectIdentifier(menu))
        self.menuRefreshTasks.removeValue(forKey: ObjectIdentifier(menu))?.cancel()
        
        // Clear highlights
        for menuItem in menu.items {
            (menuItem.view as? MenuCardHighlighting)?.setHighlighted(false)
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            let highlighted = menuItem == item && menuItem.isEnabled
            (menuItem.view as? MenuCardHighlighting)?.setHighlighted(highlighted)
        }
    }
}
```

### SwiftUI-in-AppKit Menu Content

Menus are populated with SwiftUI views hosted in NSMenu items:

```swift
private func populateMenu(_ menu: NSMenu, provider: UsageProvider?) {
    menu.removeAllItems()

    let descriptor = MenuDescriptor.build(
        provider: provider,
        store: self.store,
        settings: self.settings,
        account: self.account,
        updateReady: self.updater.updateStatus.isUpdateReady)

    for section in descriptor.sections {
        var menuItems: [NSMenuItem] = []
        
        for entry in section.entries {
            let item = NSMenuItem()
            
            // Host SwiftUI view in NSMenuItem
            let view = MenuCardView(
                store: self.store,
                settings: self.settings,
                entry: entry)
            item.view = NSHostingView(rootView: view)
            menuItems.append(item)
        }
        
        if !menuItems.isEmpty {
            menu.addItems(menuItems)
            if section != descriptor.sections.last {
                menu.addItem(NSMenuItem.separator())
            }
        }
    }
}
```

---

## 3. Dependency Injection via Protocols

### Protocol-Based Testability

CodexBar uses protocols to abstract concrete implementations, enabling comprehensive testing.

#### The Updater Protocol

**File**: `CodexbarApp.swift`

```swift
@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    var updateStatus: UpdateStatus { get }
    func checkForUpdates(_ sender: Any?)
}

// Production implementation (Sparkle)
#if canImport(Sparkle) && ENABLE_SPARKLE
import Sparkle

@MainActor
final class SparkleUpdaterController: NSObject, UpdaterProviding, SPUUpdaterDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil)
    let updateStatus = UpdateStatus()

    var isAvailable: Bool { true }
    
    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateStatus.isUpdateReady = true
        }
    }
}
#endif

// Test double (no-op implementation)
final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    let isAvailable: Bool = false
    let updateStatus = UpdateStatus()

    func checkForUpdates(_ sender: Any?) {}
}
```

**Benefits**:

1. **Tests use `DisabledUpdaterController`**: No Sparkle framework needed
2. **Production uses `SparkleUpdaterController`**: Full functionality
3. **Same interface**: Type-safe, no casts or mocking frameworks needed

#### Cookie Store Protocol

**File**: `SettingsStore.swift`

```swift
@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let codexCookieStore: any CookieHeaderStoring
    @ObservationIgnored private let claudeCookieStore: any CookieHeaderStoring
    @ObservationIgnored private let cursorCookieStore: any CookieHeaderStoring
    
    // ...cookie header properties...

    init(
        userDefaults: UserDefaults = .standard,
        codexCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "codex-cookie",
            promptKind: .codexCookie),
        claudeCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "claude-cookie",
            promptKind: .claudeCookie),
        cursorCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(
            account: "cursor-cookie",
            promptKind: .cursorCookie))
    {
        self.codexCookieStore = codexCookieStore
        self.claudeCookieStore = claudeCookieStore
        self.cursorCookieStore = cursorCookieStore
    }
}
```

Tests provide mock stores:

```swift
// In tests:
let mockCodexStore = MockCookieHeaderStore()
let settings = SettingsStore(
    codexCookieStore: mockCodexStore,
    claudeCookieStore: MockCookieHeaderStore(),
    cursorCookieStore: MockCookieHeaderStore())
```

#### Token Store Abstraction

```swift
protocol ZaiTokenStoring {
    func load() async throws -> String
    func save(_ token: String) async throws
    func delete() async throws
}

protocol CopilotTokenStoring {
    func load() async throws -> String
    func save(_ token: String) async throws
    func delete() async throws
}

// Keychain implementation
final class KeychainZaiTokenStore: ZaiTokenStoring {
    func load() async throws -> String {
        // Keychain access...
    }
}

// In-memory test implementation
final class InMemoryZaiTokenStore: ZaiTokenStoring {
    var token: String?
    
    func load() async throws -> String {
        guard let token else { throw TestError.notFound }
        return token
    }
}
```

### StatusItemController Factory

The controller uses the factory pattern for dependency injection:

```swift
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    typealias Factory = (UsageStore, SettingsStore, AccountInfo, UpdaterProviding, 
                        PreferencesSelection) -> StatusItemControlling
    
    static let defaultFactory: Factory = { store, settings, account, updater, selection in
        StatusItemController(
            store: store,
            settings: settings,
            account: account,
            updater: updater,
            preferencesSelection: selection)
    }

    static var factory: Factory = StatusItemController.defaultFactory
}

// In AppDelegate:
self.statusController = StatusItemController.factory(
    store,
    settings,
    account,
    self.updaterController,
    selection)

// In tests:
StatusItemController.factory = { store, settings, account, updater, selection in
    MockStatusItemController(store: store, settings: settings)
}
```

---

## 4. State Management with @Observable

### The Store Pattern

CodexBar uses Swift 5.9's `@Observable` macro for reactive state. Two main stores handle all state:

#### UsageStore: Fetched Data

**File**: `UsageStore.swift`

```swift
@MainActor
@Observable
final class UsageStore {
    // MARK: - Observable State (triggers UI updates)
    
    private(set) var snapshots: [UsageProvider: UsageSnapshot] = [:]
    private(set) var errors: [UsageProvider: String] = [:]
    private(set) var lastSourceLabels: [UsageProvider: String] = [:]
    private(set) var tokenSnapshots: [UsageProvider: CostUsageTokenSnapshot] = [:]
    private(set) var tokenErrors: [UsageProvider: String] = [:]
    private(set) var refreshingProviders: Set<UsageProvider> = []
    
    var credits: CreditsSnapshot?
    var lastCreditsError: String?
    var openAIDashboard: OpenAIDashboardSnapshot?
    var codexVersion: String?
    var claudeVersion: String?
    var isRefreshing = false
    
    // MARK: - Non-Observable State (@ObservationIgnored)
    
    @ObservationIgnored private let codexFetcher: UsageFetcher
    @ObservationIgnored private let claudeFetcher: any ClaudeUsageFetching
    @ObservationIgnored private let costUsageFetcher: CostUsageFetcher
    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private let settings: SettingsStore
    
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var tokenTimerTask: Task<Void, Never>?
    @ObservationIgnored private var failureGates: [UsageProvider: ConsecutiveFailureGate] = [:]

    init(
        fetcher: UsageFetcher,
        browserDetection: BrowserDetection,
        claudeFetcher: (any ClaudeUsageFetching)? = nil,
        costUsageFetcher: CostUsageFetcher = CostUsageFetcher(),
        settings: SettingsStore,
        registry: ProviderRegistry = .shared,
        sessionQuotaNotifier: SessionQuotaNotifier = SessionQuotaNotifier())
    {
        self.codexFetcher = fetcher
        self.claudeFetcher = claudeFetcher ?? ClaudeUsageFetcher(browserDetection: browserDetection)
        self.costUsageFetcher = costUsageFetcher
        self.settings = settings
        self.registry = registry
        
        self.failureGates = Dictionary(
            uniqueKeysWithValues: UsageProvider.allCases
                .map { ($0, ConsecutiveFailureGate()) })
        
        // Set up initial data
        self.detectVersions()
        Task { await self.refresh() }
        self.startTimer()
    }

    deinit {
        self.timerTask?.cancel()
        self.tokenTimerTask?.cancel()
    }
}
```

**Key design**:

1. **Observable properties**: Core data that triggers UI updates
2. **@ObservationIgnored**: Dependencies and internal state excluded from observation
3. **private(set)**: Observable collection state is read-only publicly
4. **Deferred initialization**: Heavy work in `init` vs. `Task { await self.refresh() }`

#### SettingsStore: User Preferences

```swift
@MainActor
@Observable
final class SettingsStore {
    // MARK: - Observable Properties
    
    var refreshFrequency: RefreshFrequency {
        didSet { self.userDefaults.set(self.refreshFrequency.rawValue, forKey: "refreshFrequency") }
    }

    var launchAtLogin: Bool {
        didSet {
            self.userDefaults.set(self.launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginManager.setEnabled(self.launchAtLogin)
        }
    }

    var statusChecksEnabled: Bool {
        didSet { self.userDefaults.set(self.statusChecksEnabled, forKey: "statusChecksEnabled") }
    }

    var usageBarsShowUsed: Bool {
        didSet { self.userDefaults.set(self.usageBarsShowUsed, forKey: "usageBarsShowUsed") }
    }

    var costUsageEnabled: Bool {
        didSet { self.userDefaults.set(self.costUsageEnabled, forKey: "tokenCostUsageEnabled") }
    }

    // MARK: - Non-Observable Dependencies
    
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let codexCookieStore: any CookieHeaderStoring
    @ObservationIgnored private let claudeCookieStore: any CookieHeaderStoring
    @ObservationIgnored private var codexCookiePersistTask: Task<Void, Never>?
    
    // Cache enablement to avoid UserDefaults lookups in animation ticks
    @ObservationIgnored private var cachedProviderEnablement: [UsageProvider: Bool] = [:]
    @ObservationIgnored private var cachedProviderEnablementRevision: Int = -1

    init(
        userDefaults: UserDefaults = .standard,
        codexCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(...),
        claudeCookieStore: any CookieHeaderStoring = KeychainCookieHeaderStore(...))
    {
        self.userDefaults = userDefaults
        self.codexCookieStore = codexCookieStore
        
        // Load persisted values
        self.refreshFrequency = RefreshFrequency(rawValue: 
            userDefaults.string(forKey: "refreshFrequency") ?? "") ?? .fiveMinutes
        self.statusChecksEnabled = userDefaults.bool(forKey: "statusChecksEnabled")
    }
}
```

**Pattern**:

- **Computed properties with setters**: Automatically persist to UserDefaults
- **@ObservationIgnored protocol deps**: Can't be observed (intentional)
- **Caching non-observable lookups**: `cachedProviderEnablement` avoids repeated UserDefaults calls during animation

### Observation Tracking Pattern

CodexBar uses `withObservationTracking` to manually subscribe to changes:

```swift
private func observeStoreChanges() {
    withObservationTracking {
        // Access properties you want to track
        _ = self.store.menuObservationToken
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            // Re-establish tracking (recursive)
            self.observeStoreChanges()
            
            // React to changes
            self.invalidateMenus()
            self.updateIcons()
            self.updateBlinkingState()
        }
    }
}

private func observeDebugForceAnimation() {
    withObservationTracking {
        _ = self.store.debugForceAnimation
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.observeDebugForceAnimation()
            self.updateVisibility()
            self.updateBlinkingState()
        }
    }
}

private func observeSettingsChanges() {
    withObservationTracking {
        _ = self.settings.refreshFrequency
        _ = self.settings.statusChecksEnabled
        _ = self.settings.usageBarsShowUsed
        // ... access all properties you care about
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.observeSettingsChanges()
            self.invalidateMenus()
            self.updateVisibility()
        }
    }
}
```

**Why `withObservationTracking` instead of `@State`?**

1. **NSObject-based**: `StatusItemController` extends `NSObject`, not `View`
2. **Manual lifecycle**: Can call multiple times to re-establish tracking
3. **Closure-based**: Naturally avoids reference cycles with `[weak self]`
4. **AppKit-friendly**: Works with NSMenuItem, NSStatusBar directly

### Observation Token Pattern

Both stores provide a "token" property that accesses all observable state:

```swift
// UsageStore
var menuObservationToken: Int {
    _ = self.snapshots
    _ = self.errors
    _ = self.lastSourceLabels
    _ = self.lastFetchAttempts
    _ = self.tokenSnapshots
    _ = self.tokenErrors
    _ = self.tokenRefreshInFlight
    _ = self.credits
    _ = self.lastCreditsError
    _ = self.openAIDashboard
    _ = self.codexVersion
    _ = self.claudeVersion
    // ... all observable properties
    return 0
}

// SettingsStore
var menuObservationToken: Int {
    _ = self.providerOrderRaw
    _ = self.refreshFrequency
    _ = self.launchAtLogin
    _ = self.statusChecksEnabled
    _ = self.sessionQuotaNotificationsEnabled
    // ... all observable properties
    return 0
}
```

**Purpose**: A single access point that automatically invalidates when *any* observable property changes. Used in `withObservationTracking` to track broad categories of changes.

---

## 5. Powerful & Ergonomic Patterns

### ObjectIdentifier for Tracking Instances

**Use case**: Menu instances need unique tracking keys in AppKit.

```swift
var openMenus: [ObjectIdentifier: NSMenu] = [:]
var menuProviders: [ObjectIdentifier: UsageProvider] = [:]
var menuRefreshTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

func menuWillOpen(_ menu: NSMenu) {
    self.openMenus[ObjectIdentifier(menu)] = menu
    // ...
}

func menuDidClose(_ menu: NSMenu) {
    self.openMenus.removeValue(forKey: ObjectIdentifier(menu))
    self.menuRefreshTasks.removeValue(forKey: ObjectIdentifier(menu))?.cancel()
}
```

**Why ObjectIdentifier?**

- `NSMenu` is not `Hashable`, but `ObjectIdentifier` is
- Based on object identity, not value equality
- Safe for tracking view/menu lifecycle
- Avoids memory leaks (uses weak references internally)

### Wrapping Patterns in Observation

#### Recursive Re-subscription

```swift
private func observeStoreChanges() {
    withObservationTracking {
        _ = self.store.menuObservationToken
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            // IMPORTANT: Re-establish tracking
            // This is called each time an observable property changes
            self.observeStoreChanges()
            
            // Now react
            self.invalidateMenus()
        }
    }
}
```

**Pattern**: Each `onChange` block calls itself at the start. This re-establishes the observation tracking after processing the change. Without this, changes after the first one would be missed.

#### Menu Version Tracking

To invalidate menus only when relevant data changes:

```swift
private var menuContentVersion: Int = 0
private var menuVersions: [ObjectIdentifier: Int] = [:]

private func markMenuFresh(_ menu: NSMenu) {
    self.menuVersions[ObjectIdentifier(menu)] = self.menuContentVersion
}

private func menuNeedsRefresh(_ menu: NSMenu) -> Bool {
    let menuVersion = self.menuVersions[ObjectIdentifier(menu)] ?? -1
    return menuVersion != self.menuContentVersion
}

private func invalidateMenus() {
    self.menuContentVersion &+= 1  // Wrapping increment
    self.refreshOpenMenusIfNeeded()
}
```

**Benefit**: Menus know when to rebuild without re-observing every property individually.

### Consecutive Failure Gating

Display errors only after repeated failures (ignore transient network blips):

```swift
/// Tracks consecutive failures so we can ignore a single flake when we previously had fresh data.
struct ConsecutiveFailureGate {
    private(set) var streak: Int = 0

    mutating func recordSuccess() {
        self.streak = 0
    }

    mutating func reset() {
        self.streak = 0
    }

    /// Returns true when the caller should surface the error to the UI.
    mutating func shouldSurfaceError(onFailureWithPriorData hadPriorData: Bool) -> Bool {
        self.streak += 1
        if hadPriorData, self.streak == 1 { return false }  // Ignore first error if we have old data
        return true
    }
}

// Usage in UsageStore
case let .failure(error):
    await MainActor.run {
        let hadPriorData = self.snapshots[provider] != nil
        let shouldSurface = self.failureGates[provider]?
            .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
        if shouldSurface {
            self.errors[provider] = error.localizedDescription
            self.snapshots.removeValue(forKey: provider)
        } else {
            self.errors[provider] = nil  // Suppress first flake
        }
    }
```

**Benefit**: Prevents flaky UI where errors flash briefly on network hiccups.

### Bidirectional Property Wrapping

Settings that trigger side effects when changed:

```swift
var launchAtLogin: Bool {
    didSet {
        self.userDefaults.set(self.launchAtLogin, forKey: "launchAtLogin")
        LaunchAtLoginManager.setEnabled(self.launchAtLogin)  // Side effect
    }
}

var codexCookieSource: ProviderCookieSource {
    get { ProviderCookieSource(rawValue: self.codexCookieSourceRaw ?? "") ?? .auto }
    set {
        self.codexCookieSourceRaw = newValue.rawValue
        self.openAIWebAccessEnabled = newValue.isEnabled  // Side effect
    }
}

var claudeUsageDataSource: ClaudeUsageDataSource {
    get { ClaudeUsageDataSource(rawValue: self.claudeUsageDataSourceRaw ?? "") ?? .auto }
    set {
        self.claudeUsageDataSourceRaw = newValue.rawValue
        if newValue != .cli {
            self.claudeWebExtrasEnabled = false  // Disable incompatible option
        }
    }
}
```

**Pattern**: Computed getters parse raw stored values; setters persist and trigger related updates.

### Async-Lazy Loading in Stores

For expensive data (keychain access, cookies):

```swift
var codexCookieHeader: String {
    get {
        // Load from keychain if not cached
        if !self.codexCookieLoaded {
            self.ensureCodexCookieLoaded()
        }
        return self._codexCookieHeader
    }
    set {
        self._codexCookieHeader = newValue
        self.schedulePersistCodexCookieHeader()
    }
}

private func ensureCodexCookieLoaded() {
    if self.codexCookieLoading || self.codexCookieLoaded { return }
    self.codexCookieLoading = true
    
    Task {
        do {
            let loaded = try await self.codexCookieStore.load()
            await MainActor.run {
                self._codexCookieHeader = loaded
                self.codexCookieLoaded = true
                self.codexCookieLoading = false
            }
        } catch {
            await MainActor.run {
                self.codexCookieLoading = false
            }
        }
    }
}

private func schedulePersistCodexCookieHeader() {
    self.codexCookiePersistTask?.cancel()
    self.codexCookiePersistTask = Task(priority: .utility) {
        try await Task.sleep(for: .milliseconds(100))
        do {
            try await self.codexCookieStore.save(self._codexCookieHeader)
        } catch {
            // Log error
        }
    }
}
```

**Benefits**:

1. **Lazy loading**: Only fetches from keychain when accessed
2. **Debounced saving**: Waits 100ms before persisting (batches rapid changes)
3. **Cancellation**: Previous save tasks are cancelled on new changes
4. **Loading flag**: Prevents duplicate loads

### Provider Spec Factory

Encapsulates provider-specific logic and fetch configuration:

```swift
struct ProviderSpec {
    let style: IconStyle
    let isEnabled: @MainActor () -> Bool
    let fetch: () async -> ProviderFetchOutcome
}

@MainActor
func specs(
    settings: SettingsStore,
    metadata: [UsageProvider: ProviderMetadata],
    codexFetcher: UsageFetcher,
    claudeFetcher: any ClaudeUsageFetching,
    browserDetection: BrowserDetection) -> [UsageProvider: ProviderSpec]
{
    var specs: [UsageProvider: ProviderSpec] = [:]
    specs.reserveCapacity(UsageProvider.allCases.count)

    for provider in UsageProvider.allCases {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let meta = metadata[provider]!
        let spec = ProviderSpec(
            style: descriptor.branding.iconStyle,
            isEnabled: { settings.isProviderEnabled(provider: provider, metadata: meta) },
            fetch: {
                // Capture source mode and all settings for this provider
                let sourceMode: ProviderSourceMode = switch provider {
                case .codex:
                    switch settings.codexUsageDataSource {
                    case .auto: .auto
                    case .oauth: .oauth
                    case .cli: .cli
                    }
                case .claude:
                    switch settings.claudeUsageDataSource {
                    case .auto: .auto
                    case .oauth: .oauth
                    case .web: .web
                    case .cli: .cli
                    }
                default: .auto
                }
                
                // Build provider-specific snapshot of settings
                let snapshot = await MainActor.run {
                    ProviderSettingsSnapshot(
                        debugMenuEnabled: settings.debugMenuEnabled,
                        codex: ProviderSettingsSnapshot.CodexProviderSettings(
                            usageDataSource: settings.codexUsageDataSource,
                            cookieSource: settings.codexCookieSource,
                            manualCookieHeader: settings.codexCookieHeader),
                        claude: ProviderSettingsSnapshot.ClaudeProviderSettings(
                            usageDataSource: settings.claudeUsageDataSource,
                            webExtrasEnabled: settings.claudeWebExtrasEnabled,
                            cookieSource: settings.claudeCookieSource,
                            manualCookieHeader: settings.claudeCookieHeader),
                        // ... other providers
                    )
                }
                
                let context = ProviderFetchContext(
                    runtime: .app,
                    sourceMode: sourceMode,
                    includeCredits: false,
                    webTimeout: 60,
                    webDebugDumpHTML: false,
                    verbose: false,
                    env: ProcessInfo.processInfo.environment,
                    settings: snapshot,
                    fetcher: codexFetcher,
                    claudeFetcher: claudeFetcher,
                    browserDetection: browserDetection)
                
                return await descriptor.fetchOutcome(context: context)
            })
        specs[provider] = spec
    }

    return specs
}
```

**Benefit**: Each spec closes over all necessary context. When `spec.fetch()` is called, it has everything it needs without passing large parameter lists.

---

## Summary: Pattern Benefits for Menu Bar Apps

| Pattern | Problem Solved | When to Use |
| --------- | ------- | ----------- |
| **Enum Registries** | Global state in testable way | Plugin systems, feature flags |
| **AppKit + SwiftUI Hybrid** | Fast animations + modern UI | Menu bar apps, system tools |
| **Protocol DI** | Testability without mocking frameworks | All business logic |
| **@Observable Stores** | Reactive updates without SwiftUI View | NSObject-based controllers |
| **withObservationTracking** | Manual subscription in AppKit | AppKit NSObject lifecycle |
| **ObjectIdentifier** | Hashable keys for non-hashable objects | Menu/view lifetime tracking |
| **Recursive Re-subscription** | Consistent observation across changes | Observation tracking in loops |
| **Consecutive Failure Gates** | Suppress transient errors | Network-dependent data |
| **Lazy Async Loading** | Avoid blocking UI on startup | Keychain, expensive I/O |
| **Closure Capture in Specs** | Context-specific behavior | Provider-specific logic |
