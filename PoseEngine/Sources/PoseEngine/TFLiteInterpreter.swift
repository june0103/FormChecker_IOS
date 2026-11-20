import Foundation
import TensorFlowLiteC

/// LiteRT C API 위의 얇은 래퍼.
///
/// ## 왜 `TensorFlowLiteSwift` 포드가 아닌가
/// 공식 Swift 포드는 CocoaPods로만 배포되는데, 이 저장소는 SwiftPM만 쓴다.
/// C 프레임워크(`TensorFlowLiteC.xcframework`)에는 modulemap이 들어 있어 Swift에서 바로
/// import되고, 우리가 쓰는 API는 10개 남짓이라 직접 감싸는 편이 포드 소스를 벤더링하는
/// 것보다 적은 코드다. Core ML / Metal delegate도 같은 C API로 붙일 수 있다.
///
/// 스레드 안전하지 않다. 단일 추론 스레드에서만 호출할 것.
final class TFLiteInterpreter {

    enum Failure: Error, CustomStringConvertible {
        case modelLoadFailed(path: String)
        case interpreterCreateFailed
        case allocateTensorsFailed
        case invokeFailed
        case inputCopyFailed
        case outputCopyFailed(index: Int)
        case missingTensor(index: Int)

        var description: String {
            switch self {
            case .modelLoadFailed(let path): "모델을 읽지 못했습니다: \(path)"
            case .interpreterCreateFailed: "인터프리터를 만들지 못했습니다"
            case .allocateTensorsFailed: "텐서 할당에 실패했습니다"
            case .invokeFailed: "추론 호출에 실패했습니다"
            case .inputCopyFailed: "입력 텐서 복사에 실패했습니다"
            case .outputCopyFailed(let i): "출력 텐서 \(i) 복사에 실패했습니다"
            case .missingTensor(let i): "텐서 \(i)를 찾을 수 없습니다"
            }
        }
    }

    private let model: OpaquePointer
    private let options: OpaquePointer
    private let interpreter: OpaquePointer

    /// 반드시 백그라운드 스레드에서 호출할 것 — 모델 로드가 수백 ms 걸린다.
    init(modelPath: String, threadCount: Int32 = 4) throws {
        guard let model = TfLiteModelCreateFromFile(modelPath) else {
            throw Failure.modelLoadFailed(path: modelPath)
        }
        guard let options = TfLiteInterpreterOptionsCreate() else {
            TfLiteModelDelete(model)
            throw Failure.interpreterCreateFailed
        }
        TfLiteInterpreterOptionsSetNumThreads(options, threadCount)

        guard let interpreter = TfLiteInterpreterCreate(model, options) else {
            TfLiteInterpreterOptionsDelete(options)
            TfLiteModelDelete(model)
            throw Failure.interpreterCreateFailed
        }
        guard TfLiteInterpreterAllocateTensors(interpreter) == kTfLiteOk else {
            TfLiteInterpreterDelete(interpreter)
            TfLiteInterpreterOptionsDelete(options)
            TfLiteModelDelete(model)
            throw Failure.allocateTensorsFailed
        }

        self.model = model
        self.options = options
        self.interpreter = interpreter
    }

    deinit {
        TfLiteInterpreterDelete(interpreter)
        TfLiteInterpreterOptionsDelete(options)
        TfLiteModelDelete(model)
    }

    var outputCount: Int { Int(TfLiteInterpreterGetOutputTensorCount(interpreter)) }

    func inputShape(at index: Int = 0) throws -> [Int] {
        guard let tensor = TfLiteInterpreterGetInputTensor(interpreter, Int32(index)) else {
            throw Failure.missingTensor(index: index)
        }
        return shape(of: tensor)
    }

    func outputShape(at index: Int) throws -> [Int] {
        guard let tensor = TfLiteInterpreterGetOutputTensor(interpreter, Int32(index)) else {
            throw Failure.missingTensor(index: index)
        }
        return shape(of: UnsafePointer(tensor))
    }

    func copyToInput(_ buffer: UnsafeRawPointer, byteCount: Int, at index: Int = 0) throws {
        guard let tensor = TfLiteInterpreterGetInputTensor(interpreter, Int32(index)) else {
            throw Failure.missingTensor(index: index)
        }
        guard TfLiteTensorCopyFromBuffer(tensor, buffer, byteCount) == kTfLiteOk else {
            throw Failure.inputCopyFailed
        }
    }

    func invoke() throws {
        guard TfLiteInterpreterInvoke(interpreter) == kTfLiteOk else { throw Failure.invokeFailed }
    }

    func copyFromOutput(at index: Int, into buffer: UnsafeMutableRawPointer, byteCount: Int) throws {
        guard let tensor = TfLiteInterpreterGetOutputTensor(interpreter, Int32(index)) else {
            throw Failure.missingTensor(index: index)
        }
        guard TfLiteTensorCopyToBuffer(tensor, buffer, byteCount) == kTfLiteOk else {
            throw Failure.outputCopyFailed(index: index)
        }
    }

    private func shape(of tensor: UnsafePointer<TfLiteTensor>) -> [Int] {
        let dims = TfLiteTensorNumDims(tensor)
        return (0..<dims).map { Int(TfLiteTensorDim(tensor, $0)) }
    }
}
