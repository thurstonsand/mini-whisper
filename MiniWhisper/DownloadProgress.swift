enum DownloadProgress {
  static func percentage(_ fraction: Double) -> String {
    "\(Int(fraction * 100))%"
  }
}
