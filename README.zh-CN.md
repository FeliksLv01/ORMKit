# ORMKit

Swift 6 SQLite ORM，仅通过 SwiftPM 分发。模型、类型安全查询、字段补丁与显式迁移的示例见 [英文文档](README.md)。支持 iOS 15、macOS 12、tvOS 15、watchOS 9 及以上。

应用只添加 `ORMKit` product，普通模型与 CRUD 代码只需 `import ORMKit`。宏由 SwiftPM 从源码编译；GRDB 7.11.1 使用本仓库 Release 中 SHA256 锁定的 XCFramework，无需编译 GRDB 源码。新版本移除 CocoaPods 和预编译宏分发，历史版本不改动。

## 测试与发布

采用标准 SwiftPM 包结构：`Package.swift`、`Sources/`、`Tests/`。仅支持 SwiftPM，宏从源码编译，历史版本保持不变。

自动化脚本使用 Python 3.11+ 标准库、Xcode 和 xcbeautify，无需安装 Ruby 或 Python 第三方包。

```sh
python3 Scripts/test.py macros
python3 Scripts/test.py ios
```

GitHub Actions 在 PR、main 更新和版本 tag 时执行宿主宏测试及 iOS 包测试。运行时测试覆盖真实宏展开和自动注册/数据库断言。xcodebuild 使用 pipefail 和 xcbeautify；失败时也上传日志与 xcresults。数字版本 tag 的全部 CI 任务通过后才创建 GitHub Release。移除本地发布编排、CocoaPods 和预编译宏分发。

## GRDB 产物

`python3 Scripts/build_grdb.py` 构建固定上游版本的 XCFramework。手动触发 **Build GRDB artifact** workflow 后先在 macOS 和 iOS 验证，再按 publish 选项发布不可变产物；下载并提交生成的 `GRDBArtifact.lock.json`。日常 CI 和 ORMKit 新版本复用校验和锁定的附件。公开接口使用 ORMKit 自己的 `SQLConnection`、`SQLValue`、`SQLRow` 和 `SQLValueConvertible`，应用不依赖 GRDB 类型。

## 从 0.0.3 迁移

只导入和链接 ORMKit。模型不再继承 GRDB 协议；自定义字段值改为遵循 `SQLValueConvertible`，原始值枚举可使用默认转换实现。迁移和原生 SQL 闭包接收 `SQLConnection`，通过 `createTable(Model.self)` 或参数绑定的 `execute(sql:arguments:)` 操作。原生 `Row` 替换成 `SQLRow`。当前构建工具链不再接受 watchOS 8 framework，因此最低 watchOS 版本提升到 9。
