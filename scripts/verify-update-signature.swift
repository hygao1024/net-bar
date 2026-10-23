import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4, let keyData = Data(base64Encoded: args[1]),
      let signature = Data(base64Encoded: args[3]) else {
    fatalError("用法：verify-update-signature <公钥> <文件> <签名>")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
let data = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
guard key.isValidSignature(signature, for: data) else {
    FileHandle.standardError.write(Data("更新包签名与应用公钥不匹配，拒绝发布。\n".utf8))
    exit(1)
}
