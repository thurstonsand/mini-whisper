import CoreGraphics
import Foundation

public enum ModifierKey: String, CaseIterable, Codable, Hashable, Sendable {
  case leftCommand
  case rightCommand
  case leftShift
  case rightShift
  case leftOption
  case rightOption
  case leftControl
  case rightControl
  case function

  var keyCode: UInt16 {
    switch self {
    case .leftCommand: 55
    case .rightCommand: 54
    case .leftShift: 56
    case .rightShift: 60
    case .leftOption: 58
    case .rightOption: 61
    case .leftControl: 59
    case .rightControl: 62
    case .function: 63
    }
  }

  var deviceFlagMask: CGEventFlags {
    switch self {
    case .leftCommand: CGEventFlags(rawValue: 0x0000_0008)
    case .rightCommand: CGEventFlags(rawValue: 0x0000_0010)
    case .leftShift: CGEventFlags(rawValue: 0x0000_0002)
    case .rightShift: CGEventFlags(rawValue: 0x0000_0004)
    case .leftOption: CGEventFlags(rawValue: 0x0000_0020)
    case .rightOption: CGEventFlags(rawValue: 0x0000_0040)
    case .leftControl: CGEventFlags(rawValue: 0x0000_0001)
    case .rightControl: CGEventFlags(rawValue: 0x0000_2000)
    case .function: .maskSecondaryFn
    }
  }

  func isDown(in flags: CGEventFlags) -> Bool { flags.contains(deviceFlagMask) }
}

public enum HotkeyValidationError: Error, Equatable, Sendable {
  case empty
  case reservedKeyCode(UInt16)
  case modifierKeyCode(UInt16)
  case unsupportedKeyCode(UInt16)
}

public struct Hotkey: Equatable, Codable, Sendable {
  public let keyCode: UInt16?
  public let modifiers: Set<ModifierKey>

  public init(keyCode: UInt16? = nil, modifiers: Set<ModifierKey>) throws {
    try Self.validate(keyCode: keyCode, modifiers: modifiers)
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public static let rightOption = Hotkey(validatedKeyCode: nil, modifiers: [.rightOption])

  private enum CodingKeys: String, CodingKey {
    case keyCode
    case modifiers
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(keyCode, forKey: .keyCode)
    try container.encode(modifiers.sorted { $0.rawValue < $1.rawValue }, forKey: .modifiers)
  }

  func validate() throws { try Self.validate(keyCode: keyCode, modifiers: modifiers) }

  private init(validatedKeyCode keyCode: UInt16?, modifiers: Set<ModifierKey>) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  private static func validate(keyCode: UInt16?, modifiers: Set<ModifierKey>) throws {
    guard keyCode != nil || !modifiers.isEmpty else { throw HotkeyValidationError.empty }
    guard let keyCode else { return }
    guard keyCode <= 127 else { throw HotkeyValidationError.unsupportedKeyCode(keyCode) }
    guard keyCode != PhysicalKey.escapeKeyCode else {
      throw HotkeyValidationError.reservedKeyCode(keyCode)
    }
    guard !ModifierKey.allCases.contains(where: { $0.keyCode == keyCode }) else {
      throw HotkeyValidationError.modifierKeyCode(keyCode)
    }
  }
}
