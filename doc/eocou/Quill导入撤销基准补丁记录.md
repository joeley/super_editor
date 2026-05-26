# eocou fork：Quill 导入文档撤销基准补丁记录（super_editor）

更新时间：2026-05-26  
分支：eocou

## 1. 为什么要改

eocou 中已保存的笔记/任务从 `contentJson` 重新打开后，只要发生一次可撤销编辑，再按撤销，就可能崩溃。

已确认的触发方式：
- 已保存笔记中输入普通文字后撤销。
- 已保存笔记中插入 eocou 自定义表格节点后撤销。

内存中新建、还没有保存再打开过的笔记不触发。

问题不在表格节点，也不在 IME。根因是 Quill Delta 导入流程会先创建一个空 `MutableDocument`，再通过 editor 命令逐条 apply Delta。`MutableDocument` 的 `reset()` 会恢复到构造时保存的初始快照，因此导入后的文档在 undo 时会错误恢复成“导入过程中的空文档”，而不是“导入完成后的真实内容”。

## 2. 崩溃表现

典型现象：

```text
Exception: No such position in document:
node "...", position: TextPosition(offset: ...)

BaseInsertNewlineAtCaretCommand.execute
Editor.undo
```

随后可能出现连锁异常：

```text
DocumentImeSerializer._serialize
InspectDocumentSelection.selectUpstreamPosition
Null check operator used on a null value
```

后者是文档被错误 reset 后，selection 仍指向已经不存在的节点导致的二次错误。

## 3. 本次改动

### 3.1 修改文件

- `super_editor/lib/src/core/editor.dart`
- `super_editor/lib/src/infrastructure/serialization/quill/parsing/parser.dart`

### 3.2 `MutableDocument` 改动点

位置：`super_editor/lib/src/core/editor.dart`

新增方法：

```dart
void setCurrentStateAsInitialState()
```

用途：
- 将当前 `_nodes` 记录为后续 `reset()` 恢复的初始状态。
- 用于“非用户编辑”的构建流程，例如反序列化外部内容。
- 不通知监听器，因为它不改变当前文档内容，只改变 reset/undo 的基准。

实现保持和构造函数一致，都是浅拷贝节点列表：

```dart
_latestNodesSnapshot = List.from(_nodes);
```

同时把 `_latestNodesSnapshot` 从 `late final` 改为 `late`，允许导入完成后重设基准。

### 3.3 Quill parser 改动点

位置：`super_editor/lib/src/infrastructure/serialization/quill/parsing/parser.dart`

在 `parseQuillDeltaOps(...)` 完成所有 Delta operation apply 后，返回 document 前调用：

```dart
document.setCurrentStateAsInitialState();
```

这样 `parseQuillDeltaOps(...)` 返回的 `MutableDocument`，其 reset/undo 基准就是“解析完成后的内容”，不是导入前的一空段。

## 4. 为什么不在 eocou app 层长期兜底

eocou app 层可以在 decode 后重新构造一次 `MutableDocument(nodes: parsed.toList(...))`，临时规避问题。

但这个问题属于 `super_editor` Quill 导入器和 `MutableDocument.reset()` 语义之间的缺口。放在 fork 里修更合理：
- 所有使用 `parseQuillDeltaOps(...)` 的调用方都能受益。
- app 层不需要理解 super_editor 内部 undo/reset 基准。
- 后续自定义导入器也可以复用 `setCurrentStateAsInitialState()`。

## 5. 升级上游时的冲突处理

升级 `super_editor` 时优先关注：
- `super_editor/lib/src/core/editor.dart`
- `super_editor/lib/src/infrastructure/serialization/quill/parsing/parser.dart`

处理建议：
1. 先看上游是否已经提供类似 `checkpoint`、`resetBaseline`、`setCurrentStateAsInitialState` 的 API。
2. 再看上游 `parseQuillDeltaOps(...)` 是否在导入完成后把当前文档设为 reset/undo 基准。
3. 如果上游已有等价实现，本补丁可以删除。
4. 如果上游仍然是 `MutableDocument.empty()` 后逐条 apply Delta，且没有重设 reset 基准，本补丁需要保留。

## 6. 验收建议

本补丁没有在 fork 内新增单测。eocou 侧建议用真实应用流程验证：

1. 打开一个已经保存过的笔记/任务。
2. 输入普通文字，按撤销，确认不报错且内容恢复。
3. 插入 eocou 自定义表格节点，按撤销，确认不报错且表格被撤销。
4. 重复验证未保存的新笔记，确认原有内存编辑行为不变。

如果后续要补测试，建议覆盖 `parseQuillDeltaOps(...)` 返回文档后：
- `document.reset()` 保留解析内容。
- 创建开启 history 的 editor 后，编辑并 undo 能恢复到解析内容。

