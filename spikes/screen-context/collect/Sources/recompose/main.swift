// recompose CAPTURE_DIR...
//
// Rewrites each capture's ax.txt and ocr.txt from the ax-lines.json and ocr-lines.json beside
// it, through the current VisibleText.compose, so a change to composition needs no recapture.

import CoreGraphics
import FieldContext
import Foundation

// MARK: - Line

struct Line: Decodable {
  let text: String
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

// MARK: - Meta

struct Meta: Decodable {
  let bundleID: String?
  let windowFrame: [Double]
  let focusedFrame: [Double]?
}

func rect(_ values: [Double]) -> CGRect {
  CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}

for path in CommandLine.arguments.dropFirst() {
  let directory = URL(fileURLWithPath: path)
  func read<T: Decodable>(_ name: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
  }
  let meta: Meta = try read("meta.json")
  let bounds = rect(meta.windowFrame)
  let focus = TerminalBundleIDs.contains(meta.bundleID) ? nil : meta.focusedFrame.map(rect)
  for source in ["ax", "ocr"] {
    let lines: [Line] = try read("\(source)-lines.json")
    let visible = lines.map { VisibleLine(
      text: $0.text,
      frame: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height),
    ) }
    let text = VisibleText.compose(
      source == "ax" ? VisibleText.joiningRuns(visible) : visible, within: bounds, excluding: focus,
    )
    try text.write(
      to: directory.appendingPathComponent("\(source).txt"),
      atomically: true,
      encoding: .utf8,
    )
  }
  print(path)
}
