/// What a role and subrole say about a focused element, independent of how they were read.
public enum FieldTargetPolicy {
  /// Containers own a document, not a field. Chromium hands one out as the focused element and
  /// answers character counts for it — zero — so its empty answer proves nothing.
  public static let containerRoles: Set<String> = [
    "AXWebArea", "AXGroup", "AXScrollArea", "AXSplitGroup", "AXWindow", "AXApplication",
  ]

  public static let secureTextFieldRole = "AXSecureTextField"
  public static let textFieldRole = "AXTextField"

  public static func isContainer(role: String) -> Bool {
    containerRoles.contains(role)
  }

  /// Password fields are the one place subrole is worth a read: AppKit reports them as a plain
  /// `AXTextField` with a secure subrole, while some targets put it in the role itself.
  public static func needsSubroleCheck(role: String) -> Bool {
    role == textFieldRole
  }

  public static func isSecure(role: String, subrole: String?) -> Bool {
    role == secureTextFieldRole || subrole == secureTextFieldRole
  }
}
