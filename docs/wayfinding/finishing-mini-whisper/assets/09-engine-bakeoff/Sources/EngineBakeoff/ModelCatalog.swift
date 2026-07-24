import Foundation

struct ModelConfiguration: Codable {
    let id: String
    let repository: String
    let revision: String
    let filename: String
    let bytes: Int
    let sha256: String
    let mode: String

    var fileURL: URL {
        prototypeRoot.appending(path: "models").appending(path: filename)
    }
}

let modelCatalog = [
    ModelConfiguration(
        id: "parakeet-v2",
        repository: "handy-computer/parakeet-tdt-0.6b-v2-GGUF",
        revision: "07cee0616125a08ef619729bb47f40ef747e4bc4",
        filename: "parakeet-tdt-0.6b-v2-Q5_K_M.gguf",
        bytes: 539_012_608,
        sha256: "dfa904520b95451599683613fea47766c378c5fdf5d8cddf48151226b6eaec85",
        mode: "batch"
    ),
    ModelConfiguration(
        id: "parakeet-v3",
        repository: "handy-computer/parakeet-tdt-0.6b-v3-GGUF",
        revision: "85ac09ea12fc4b1112fa76810059364bc6adc9de",
        filename: "parakeet-tdt-0.6b-v3-Q5_K_M.gguf",
        bytes: 548_946_272,
        sha256: "cc722e76adc1a629fc0b2535de879d99b8160d07ad4c0215e2ca7d7ea0ae4b8f",
        mode: "batch"
    ),
    ModelConfiguration(
        id: "whisper-turbo",
        repository: "handy-computer/whisper-large-v3-turbo-GGUF",
        revision: "d222c9f621c1128299248f2ded4d8a1820519780",
        filename: "whisper-large-v3-turbo-Q5_K_M.gguf",
        bytes: 619_628_192,
        sha256: "065dce9c5c13c6b5f5b92b926a519ad3b4416ecbbe701a247835bda529d4b2a9",
        mode: "batch"
    ),
    ModelConfiguration(
        id: "whisper-base-en",
        repository: "handy-computer/whisper-base.en-GGUF",
        revision: "cf0804db15fb341d00c9274b90da9cbb4fe2e5c6",
        filename: "whisper-base.en-Q5_K_M.gguf",
        bytes: 63_709_472,
        sha256: "549e6e991588cd748dc6bf53b8fe47629dc08ed9038b8955270ee98fbc5e4c54",
        mode: "batch"
    ),
    ModelConfiguration(
        id: "whisper-small-en",
        repository: "handy-computer/whisper-small.en-gguf",
        revision: "41b0f75fd44415ba127a5356c5ba9ed450c1debd",
        filename: "whisper-small.en-Q5_K_M.gguf",
        bytes: 193_672_256,
        sha256: "e96a679e57d36f80bb26512f3893185d219ddd8880cdac4c433e5af13a001b47",
        mode: "batch"
    ),
    ModelConfiguration(
        id: "whisper-medium-en",
        repository: "handy-computer/whisper-medium.en-gguf",
        revision: "f25c70d9095dcfdad187ebb3b113d157b414aee8",
        filename: "whisper-medium.en-Q5_K_M.gguf",
        bytes: 582_669_056,
        sha256: "8c90b55725036f1362fc5a583432a4e63370304dbf0f96b6245685f8a588174f",
        mode: "batch"
    ),
    ModelConfiguration(
        id: "whisper-large-v3",
        repository: "handy-computer/whisper-large-v3-gguf",
        revision: "e3e29bee6389c7da4a141406f07bb80ddac5337c",
        filename: "whisper-large-v3-Q5_K_M.gguf",
        bytes: 1_161_143_008,
        sha256: "6053d0fd69a0fd48b8fea5ea7a52b9e0cde389343566fa30e453a1b2b258dc38",
        mode: "batch"
    ),
    ModelConfiguration(
        id: "moonshine-streaming-tiny",
        repository: "handy-computer/moonshine-streaming-tiny-gguf",
        revision: "85ddff612fa3a2cf40b2f745abcfa90ef82f293b",
        filename: "moonshine-streaming-tiny-Q8_0.gguf",
        bytes: 50_462_816,
        sha256: "930e4622ad3a24158b91406c30c977fa6a26b34cb32d6ac3e57cfb23383a869e",
        mode: "streaming"
    ),
]

func modelConfiguration(id: String) throws -> ModelConfiguration {
    guard let model = modelCatalog.first(where: { $0.id == id }) else {
        throw BakeoffError("unknown model \(id)")
    }
    return model
}
