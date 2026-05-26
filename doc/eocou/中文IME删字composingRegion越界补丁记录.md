# 中文 IME 删字 composingRegion 越界补丁记录

日期：2026-05-26

分支：`eocou`

## 背景

eocou 在 Windows 桌面端使用中文输入法编辑 SuperEditor 正文时，中文上屏后立刻按硬件 Backspace 删字，偶发 Flutter 断言：

```text
Failed assertion:
range.start >= 0 && range.start <= text.length

Range start 21 is out of text of length 20
```

调用栈落在：

```text
TextEditingValue.toJSON
TextInputConnection.setEditingState
DocumentImeInputClient.setEditingState
DocumentImeInputClient._sendDocumentToIme
CommonEditorOperations.deleteUpstream
deleteUpstreamContentWithBackspace
```

这说明 SuperEditor 发给 Flutter 平台输入法的 `TextEditingValue` 内部 range 已经越界。Flutter 只是校验时报错，不是根因。

## 根因

硬件 Backspace 删除普通文本时，会走：

```text
CommonEditorOperations.deleteUpstream
DeleteUpstreamCharacterCommand
DeleteContentCommand
ChangeSelectionCommand
```

删除后正文长度变短，selection 会被更新到合法位置，但 `composer.composingRegion` 可能还保留着中文 IME 上一次提交留下的旧范围。

随后事务结束触发 `_sendDocumentToIme()`，`DocumentImeSerializer` 把旧 composingRegion 映射到新的 IME 文本里。由于文本已经少了一个字符，映射结果可能超过 `imeText.length`，最终构造出非法 `TextEditingValue`。

## 改动点

### 1. 删除内容后清 composingRegion

文件：

```text
super_editor/lib/src/default_editor/multi_node_editing.dart
```

在 `DeleteContentCommand` 完成实际删除后，若当前 `composer.composingRegion` 非空，则执行：

```dart
ChangeComposingRegionCommand(null)
```

目的：

- 内容删除会让原 composing range 失效；
- 删除后主动清掉 composing，避免后续发送给 IME 时引用旧 offset；
- 这和光标移动、段落合并等路径已有的处理方向一致。

### 2. TextEditingValue 出口加兜底合法性保护

文件：

```text
super_editor/lib/src/default_editor/document_ime/document_serialization.dart
```

`DocumentImeSerializer.toTextEditingValue()` 在返回前新增保护：

- selection 映射超出 `imeText.length` 时，夹到合法范围；
- composingRegion 映射失败、指向已删除节点、或超出 `imeText.length` 时，清成 `TextRange.empty`。

目的：

- 主修是删除路径清 composing；
- 出口保护是双保险，防止其他路径以后再把非法 range 发给 Flutter。

### 3. _sendDocumentToIme 使用 try/finally 收尾

文件：

```text
super_editor/lib/src/default_editor/document_ime/document_ime_communication.dart
```

`_sendDocumentToIme()` 原来如果中途异常，`_isSendingToIme` 可能一直卡在 `true`。现在用 `try/finally` 保证收尾。

## 回归测试

文件：

```text
super_editor/test/super_editor/supereditor_input_ime_test.dart
```

新增覆盖：

1. stale composingRegion 映射超出 IME 文本长度时，序列化会清 composing；
2. 段落末尾存在 composingRegion 时，硬件 Backspace 删除一个字符后：
   - 正文正常少一个字符；
   - SuperEditor composer 的 composingRegion 被清空；
   - 发给平台 IME 的 composingBase / composingExtent 是 `-1 / -1`。

## 合并冲突处理建议

合 upstream 时重点看三处：

1. `multi_node_editing.dart` 的 `DeleteContentCommand`
   - 如果 upstream 已经在删除内容后清 composingRegion，保留 upstream 写法即可；
   - 如果没有，继续保留本补丁的 `_clearComposingRegionIfNeeded(...)` 逻辑。

2. `document_serialization.dart` 的 `toTextEditingValue()`
   - 如果 upstream 已经有合法性校验，确认它同时覆盖 selection 和 composing；
   - composing 越界不要夹断成末尾，建议清成 `TextRange.empty`，否则输入法可能继续认为处于组合态。

3. `document_ime_communication.dart` 的 `_sendDocumentToIme()`
   - 如果 upstream 重构了 SuperIme / IME client，保留“发送中标记必须 finally 复位”的语义。

本补丁只处理崩溃级问题：`TextEditingValue` range 越界。中文输入上屏后的 undo 粒度问题没有放进本次提交，后续单独处理。
