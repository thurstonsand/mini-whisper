import Foundation
import llama
import ModelLibrary
import OSLog

private let localCleanupLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "local-cleanup",
)

// MARK: - S1MiniStyling

/// The model card's styling axis. Dictation into arbitrary fields wants the middle of it.
public enum S1MiniStyling: String, Sendable {
  case casual
  case semiFormal = "semi-formal"
  case formal
}

// MARK: - LocalCleanupError

public enum LocalCleanupError: Error, Equatable, LocalizedError, Sendable {
  case modelUnloadable
  case contextUnavailable
  case promptTooLong
  case decodeFailed(Int32)
  case unfinished

  // MARK: Public

  public var errorDescription: String? {
    switch self {
    case .modelUnloadable:
      "S1-mini could not be loaded"
    case .contextUnavailable:
      "S1-mini could not start a context"
    case .promptTooLong:
      "The transcript is too long for S1-mini"
    case let .decodeFailed(status):
      "S1-mini failed to decode (\(status))"
    case .unfinished:
      "S1-mini ran out of room before it finished"
    }
  }
}

// MARK: - S1Mini

/// "S1-mini" by "Superwhisper", in process through llama.cpp. It takes no instructions: the input
/// is the card's verbatim system prompt, a control line, and the transcript, and anything else
/// degrades it. Decoding is greedy, so the same transcript always cleans the same way.
public actor S1Mini {
  // MARK: Lifecycle

  public init(library: ModelLibrary) {
    modelURL = library.directory(.s1Mini).appending(path: "s1-mini-q4_k_m.gguf")
  }

  isolated deinit {
    unload()
  }

  // MARK: Public

  public nonisolated static let identity = "\(PinnedRepository.s1Mini.repository)@\(PinnedRepository.s1Mini.revision)"

  /// Required verbatim per the model card; any rewording degrades output.
  public nonisolated static let systemPrompt =
    "You are a text normalizer for speech-to-text transcripts. The input begins "
      + "with a control line specifying the styling, structure, and context settings; "
      + "clean the transcript to match those settings and output only the cleaned text."

  /// Loads the model and prewarms it, so the first dictation does not pay for either.
  public func prepare() throws {
    try loadIfNeeded()
  }

  public func unload() {
    if let context {
      llama_free(context)
    }
    if let model {
      llama_model_free(model)
    }
    context = nil
    model = nil
  }

  /// What the model wrote, whole. Text cut off by the output budget is not a cleaning, so it is
  /// an error rather than something to deliver.
  public func clean(_ transcript: String, styling: S1MiniStyling = .semiFormal) throws -> String {
    try loadIfNeeded()
    guard let model, let context else {
      throw LocalCleanupError.modelUnloadable
    }
    let vocab = llama_model_get_vocab(model)
    llama_memory_clear(llama_get_memory(context), true)

    var tokens = tokenize(Self.prompt(transcript, styling: styling), vocab: vocab)
    let budget = Int(llama_n_ctx(context))
    guard tokens.count < budget / 2 else {
      throw LocalCleanupError.promptTooLong
    }
    let maximumOutput = min(budget - tokens.count, tokens.count * 2 + 64)

    let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
    defer { llama_sampler_free(sampler) }
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

    var output = Data()
    var status = tokens.withUnsafeMutableBufferPointer {
      llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count)))
    }
    for _ in 0 ..< maximumOutput {
      try Task.checkCancellation()
      guard status == 0 else {
        throw LocalCleanupError.decodeFailed(status)
      }
      var next = llama_sampler_sample(sampler, context, -1)
      if llama_vocab_is_eog(vocab, next) {
        return String(decoding: output, as: UTF8.self)
      }
      output.append(piece(next, vocab: vocab))
      status = llama_decode(context, llama_batch_get_one(&next, 1))
    }
    throw LocalCleanupError.unfinished
  }

  // MARK: Internal

  /// Qwen3's chat template with thinking disabled, rendered by hand: the template's
  /// `enable_thinking` switch is a Jinja keyword argument llama.cpp's C API has no way to pass,
  /// and what it renders is exactly an empty think block ahead of the answer.
  static func prompt(_ transcript: String, styling: S1MiniStyling) -> String {
    let control = "[Styling: \(styling.rawValue)] [Structure: prose] [Context: general]"
    return """
    <|im_start|>system
    \(systemPrompt)<|im_end|>
    <|im_start|>user
    \(control)
    \(transcript)<|im_end|>
    <|im_start|>assistant
    <think>

    </think>


    """
  }

  // MARK: Private

  private static let backend: Void = {
    llama_log_set({ level, text, _ in
      guard level == GGML_LOG_LEVEL_ERROR, let text else {
        return
      }
      localCleanupLogger.error("\(String(cString: text), privacy: .public)")
    }, nil)
    llama_backend_init()
  }()

  private let modelURL: URL
  private var model: OpaquePointer?
  private var context: OpaquePointer?

  private func loadIfNeeded() throws {
    guard context == nil else {
      return
    }
    Self.backend
    var modelParameters = llama_model_default_params()
    modelParameters.n_gpu_layers = -1
    guard let model = llama_model_load_from_file(modelURL.path, modelParameters) else {
      throw LocalCleanupError.modelUnloadable
    }
    var contextParameters = llama_context_default_params()
    contextParameters.n_ctx = 4096
    contextParameters.n_batch = 4096
    contextParameters.no_perf = true
    guard let context = llama_init_from_model(model, contextParameters) else {
      llama_model_free(model)
      throw LocalCleanupError.contextUnavailable
    }
    self.model = model
    self.context = context
    let file = modelURL.lastPathComponent
    localCleanupLogger.notice("S1-mini loaded from \(file, privacy: .public)")
  }

  private func tokenize(_ text: String, vocab: OpaquePointer?) -> [llama_token] {
    let utf8 = Array(text.utf8CString)
    let capacity = utf8.count + 16
    var tokens = [llama_token](repeating: 0, count: capacity)
    let count = llama_tokenize(
      vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(capacity), false, true,
    )
    precondition(count >= 0, "The token buffer is sized past any tokenization of the prompt")
    return Array(tokens.prefix(Int(count)))
  }

  private func piece(_ token: llama_token, vocab: OpaquePointer?) -> Data {
    var buffer = [CChar](repeating: 0, count: 64)
    var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
    if length < 0 {
      buffer = [CChar](repeating: 0, count: Int(-length))
      length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
    }
    precondition(length >= 0, "The piece buffer was resized to what llama.cpp asked for")
    return buffer.prefix(Int(length)).withUnsafeBufferPointer { Data(buffer: $0) }
  }
}
