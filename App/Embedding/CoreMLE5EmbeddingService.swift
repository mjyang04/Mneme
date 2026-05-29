@preconcurrency import CoreML
import Foundation
import MnemeCore
import Tokenizers

struct CoreMLE5EmbeddingService: EmbeddingService, @unchecked Sendable {
    let id = "coreml-e5-small-v1"
    let dimension = 384

    private let model: MLModel
    private let tokenizer: any Tokenizer

    static func make(resources: CoreMLE5Resources) async throws -> CoreMLE5EmbeddingService {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let compiledURL = try await MLModel.compileModel(at: resources.modelURL)
        let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        let tokenizer = try await AutoTokenizer.from(modelFolder: resources.tokenizerDirectoryURL)
        return CoreMLE5EmbeddingService(model: model, tokenizer: tokenizer)
    }

    func embed(_ texts: [String], kind: EmbedKind) async throws -> [[Float]] {
        try texts.map { text in
            let prepared = E5Input.preprocessedText(text, kind: kind)
            let input = E5Input(tokenIds: tokenizer.encode(text: prepared))
            return try embed(input)
        }
    }

    private func embed(_ input: E5Input) throws -> [Float] {
        let tokenCount = max(input.tokenIds.count, 1)
        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: tokenCount)], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: tokenCount)], dataType: .int32)
        let tokenTypeIDs = try MLMultiArray(shape: [1, NSNumber(value: tokenCount)], dataType: .int32)
        let positionIDs = try MLMultiArray(shape: [1, NSNumber(value: tokenCount)], dataType: .int32)

        if input.tokenIds.isEmpty {
            inputIDs[0] = 0
            attentionMask[0] = 0
            tokenTypeIDs[0] = 0
            positionIDs[0] = 0
        } else {
            for index in 0..<input.tokenIds.count {
                inputIDs[index] = NSNumber(value: input.tokenIds[index])
                attentionMask[index] = NSNumber(value: input.attentionMask[index])
                tokenTypeIDs[index] = NSNumber(value: input.tokenTypeIds[index])
                positionIDs[index] = NSNumber(value: input.positionIds[index])
            }
        }

        let expectedInputs = Set(model.modelDescription.inputDescriptionsByName.keys)
        var dictionary: [String: Any] = ["input_ids": inputIDs]
        if expectedInputs.contains("attention_mask") {
            dictionary["attention_mask"] = attentionMask
        }
        if expectedInputs.contains("token_type_ids") {
            dictionary["token_type_ids"] = tokenTypeIDs
        }
        if expectedInputs.contains("position_ids") {
            dictionary["position_ids"] = positionIDs
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: dictionary)
        let output = try model.prediction(from: provider)
        guard let vector = output.featureNames.compactMap({ output.featureValue(for: $0)?.multiArrayValue }).first else {
            throw EmbeddingError.modelUnavailable
        }
        guard vector.count == dimension else {
            throw EmbeddingError.dimensionMismatch
        }

        var result = [Float](repeating: 0, count: dimension)
        for index in 0..<dimension {
            result[index] = vector[index].floatValue
        }
        return Vector.normalize(result)
    }
}

enum CoreMLE5Loader {
    static func loadEmbedder(appSupportDirectory: URL) -> (embedder: (any EmbeddingService)?, resourcesURL: URL?) {
        let candidateRoots = [
            appSupportDirectory.appendingPathComponent("Models/e5", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("Models/e5", isDirectory: true)
        ].compactMap { $0 }

        for root in candidateRoots {
            let resources: CoreMLE5Resources
            do {
                resources = try CoreMLE5ResourceLocator(root: root).locate()
            } catch {
                log("e5.loader.locate.failed root=\(root.path) error=\(error)")
                continue
            }
            switch BlockingAsync.run({ try await CoreMLE5EmbeddingService.make(resources: resources) }) {
            case let .success(embedder):
                log("e5.loader.loaded root=\(root.path)")
                return (embedder, root)
            case let .failure(error):
                log("e5.loader.make.failed root=\(root.path) error=\(error)")
                continue
            }
        }
        return (nil, nil)
    }

    private static func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["MNEME_E5_VERBOSE"] == "1" else {
            return
        }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

private enum BlockingAsync {
    static func run<T>(_ operation: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<T, Error>?

        Task.detached {
            let value: Result<T, Error>
            do {
                value = .success(try await operation())
            } catch {
                value = .failure(error)
            }
            lock.withLock {
                result = value
            }
            semaphore.signal()
        }

        semaphore.wait()
        return lock.withLock {
            result ?? .failure(EmbeddingError.modelUnavailable)
        }
    }
}
