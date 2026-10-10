# eocou-next 合并官方 stable

日期：2026-10-11

## 分支来源

- 新分支：`eocou-next`，后续 Flutter 升级时供 eocou 应用接入。
- 本地工作树：`super_editor-eocou-next`；与现有 `super_editor` 共用 Git 仓库。
- fork 起点：`joeley/super_editor` 的 `eocou`，提交 `44d2d6ad9033bf7bf62d1a132f01d0ceee88ccbe`。
- 合并来源：[Flutter-Bounty-Hunters/super_editor 的 stable](https://github.com/Flutter-Bounty-Hunters/super_editor/tree/stable)，提交 `2eab8e7c46d62801784a0ffd24fdd0152451b285`。
- 共同起点：`405591b670780396218db8396a3041e004b2e011`；fork 有 6 个本地提交，官方有 51 个新提交。
- 保留两边历史，以 merge commit 合并。未合入 `codex/flutter-3.47-compat` 的旧兼容补丁；官方 stable 已有新 `TextInputClient.updateStyle` 接口。

## 本地修复

| 修复 | 合并处理 | 回归验证 |
| --- | --- | --- |
| 代码块多换行被拆分 | 保留 parser 的有效块类型继承，不绕过 `blockFormats` 配置 | Quill multiline parsing |
| 混合邮箱文本粘贴崩溃 | 保留保守识别，新增混合文本、纯邮箱测试 | copy and paste |
| Quill 导入后撤销恢复为空文档 | 保留导入完成后重设 reset 基准 | Quill parsing 的编辑/undo 用例 |
| IME 删字后 composing 越界 | 保留删除清理、序列化出口保护、发送标记 finally 复位 | IME serialization、composing、content deletion |
| 横向滚动祖先遮住纵向滚动祖先 | 保留按 `Axis.vertical` 查找 | build context |
| 键盘布局变化后光标被遮挡 | 保留等待下一次布局后重新显示光标 | SuperEditor scrolling、SuperTextField auto scroll |

本次没有完整删除上述任何一个补丁。官方已补充部分删除路径的 composing 清理，但没有覆盖直接 `DeleteContentRequest` 和序列化出口越界。

## 冲突处理

1. `multi_node_editing.dart`：保留官方新增的 selection 更新和可编辑节点处理，再接回本地 composing 清理。官方新增的“所有选中节点删除后插入空段落”路径也清 composing。
2. 官方已拆分、删除 `supereditor_input_ime_test.dart`：只迁移本地新增的两个用例到 `ime_serialization_test.dart`、`ime_composing_region_test.dart`，采用官方新的测试结构。

额外补充 `ime_content_deletion_test.dart`，覆盖直接删除、完整多节点删除、部分段落合并、无实际删除四种情况。

## 验证

使用独立安装的 Flutter **3.47.1 / Dart 3.13.1**，未修改 eocou 应用的 FVM 配置。

SuperEditor 受影响测试：**300 通过，1 个既有跳过**。跳过项为 Quill multiline parsing 的 `parses inline newline characters into multiple document nodes`。

同仓库基础包的受影响测试：`attributed_text/test/attributed_text_test.dart` **36 通过**；`super_text_layout/test/blink_controller_test.dart`、`super_text_layout/test/super_text_test.dart` **29 通过**。

清理官方新提交中三个 Markdown 测试样例空行的尾随空白后，补跑 `super_editor_markdown_test.dart --plain-name caption`，**3 通过**。总计 **368 通过、1 个既有跳过**。

在 `super_editor/` 执行：

```bash
flutter pub get
flutter test --no-pub --timeout 8s --reporter expanded \
  test/infrastructure/serialization/quill \
  test/infrastructure/flutter/build_context_test.dart \
  test/super_editor/text_entry/ime \
  test/super_editor/supereditor_copy_and_paste_test.dart \
  test/super_editor/supereditor_scrolling_test.dart \
  test/super_textfield/super_textfield_auto_scroll_test.dart
```

基础包分别在对应目录执行：

```bash
# attributed_text/
dart pub get --offline
dart test --timeout 8s --reporter expanded test/attributed_text_test.dart

# super_text_layout/
flutter pub get --offline --no-example
flutter test --no-pub --timeout 8s --reporter expanded \
  test/blink_controller_test.dart test/super_text_test.dart
```

基础包在线依赖解析遇到网络失败，改用已有缓存完成验证；`super_text_layout/example` 的旧 lint 依赖未缓存，本次没有构建或验证该示例。

静态分析覆盖 `super_editor/lib` 及上述受影响测试：没有 error；92 个 warning、149 个 info。与相同回归测试下的官方 stable 代码基线对照，诊断项和数量完全一致，没有新增诊断。静态分析仍因既有 warning 返回非零，不能声称仓库全量 analyze 已通过。

本次手工修改的 Dart 文件按仓库既有 120 列格式化，`git diff --check` 通过。

## 后续接入

- eocou 应用目前仍引用 `eocou`，本次不改应用的 SDK、`pubspec.yaml` 或 lock。
- 升级 Flutter 后，`super_editor`、`super_text_layout`、`attributed_text` 三个 Git 引用应同时切到 `eocou-next`，避免同仓库包版本错配。
- 接入时处理应用自定义文档节点的新 `EditableDocumentNode` 接口，并核对对齐 metadata 的格式变化；不能只换分支后直接认定应用已兼容。
- 再验证应用的旧文档读写、代码块、附件/表格、粘贴、撤销、中文 IME 和键盘滚动。
- 尚未验证 Flutter 3.47.7、真实设备输入法、各平台构建和应用联调；发送 IME 异常后的恢复只有源码核对。

本记录属于 fork 合并过程；应用尚未接入，不提前修改 eocou 应用 `.ai/` 的当前依赖规则。
