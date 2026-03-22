import Foundation
import JavaScriptCore

class JSEngine {
    private let context: JSContext

    init() {
        context = JSContext()
        setupErrorHandler()
    }

    private func setupErrorHandler() {
        context.exceptionHandler = { _, exception in
            if let exception = exception {
                print("JS Error: \(exception.toString())")
            }
        }
    }

    func transform(script: String, input: [String: Any]) -> [String: Any] {
        // 将输入转换为 JSON 字符串
        guard let inputJSON = try? JSONSerialization.data(withJSONObject: input),
              let inputString = String(data: inputJSON, encoding: .utf8) else {
            return ["error": "Invalid input"]
        }

        // 构建完整的脚本
        let fullScript = """
        \(script)

        var input = \(inputString);
        var result = transform(input);
        JSON.stringify(result);
        """

        // 执行脚本
        guard let result = context.evaluateScript(fullScript) else {
            return ["error": "Script execution failed"]
        }

        // 解析结果
        if let resultString = result.toString(),
           let resultData = resultString.data(using: .utf8),
           let resultJSON = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            return resultJSON
        }

        return ["error": "Invalid result"]
    }

    func validate(script: String) -> (isValid: Bool, error: String?) {
        // 尝试执行脚本检查语法
        let testScript = """
        \(script)
        function test() { return transform({}); }
        """

        context.evaluateScript(testScript)

        if let exception = context.exception {
            return (false, exception.toString())
        }

        return (true, nil)
    }
}

// 扩展：简单的 JSON 转换
extension Dictionary where Key == String {
    func toJSONString() -> String {
        if let data = try? JSONSerialization.data(withJSONObject: self),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
