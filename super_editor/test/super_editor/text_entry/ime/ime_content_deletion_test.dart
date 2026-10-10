import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  group('IME input > content deletion >', () {
    late MutableDocument document;
    late MutableDocumentComposer composer;
    late Editor editor;

    const composingRegion = DocumentRange(
      start: DocumentPosition(nodeId: '2', nodePosition: TextNodePosition(offset: 5)),
      end: DocumentPosition(nodeId: '2', nodePosition: TextNodePosition(offset: 5)),
    );

    setUp(() {
      document = MutableDocument(nodes: [
        ParagraphNode(id: '1', text: AttributedText('hello')),
        ParagraphNode(id: '2', text: AttributedText('world')),
      ]);
      composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 3)),
        ),
      );
      editor = createDefaultDocumentEditor(document: document, composer: composer);
      composer.setComposingRegion(composingRegion);
    });

    tearDown(() {
      editor.dispose();
      composer.dispose();
      document.dispose();
    });

    test('clears composing region after direct content deletion', () {
      editor.execute([
        DeleteContentRequest(
          documentRange: const DocumentRange(
            start: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 3)),
            end: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
          ),
        ),
      ]);

      expect((document.first as ParagraphNode).text.toPlainText(), 'helo');
      expect(composer.composingRegion.value, isNull);
    });

    test('clears composing region when deleting all selected nodes', () {
      editor.execute([
        DeleteContentRequest(
          documentRange: const DocumentRange(
            start: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
            end: DocumentPosition(nodeId: '2', nodePosition: TextNodePosition(offset: 5)),
          ),
        ),
      ]);

      expect(document.nodeCount, 1);
      expect((document.first as ParagraphNode).text.toPlainText(), isEmpty);
      expect(composer.composingRegion.value, isNull);
    });

    test('clears composing region when merging partially deleted paragraphs', () {
      editor.execute([
        DeleteContentRequest(
          documentRange: const DocumentRange(
            start: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 2)),
            end: DocumentPosition(nodeId: '2', nodePosition: TextNodePosition(offset: 3)),
          ),
        ),
      ]);

      expect(document.nodeCount, 1);
      expect((document.first as ParagraphNode).text.toPlainText(), 'held');
      expect(composer.composingRegion.value, isNull);
    });

    test('preserves composing region when a collapsed range deletes nothing', () {
      editor.execute([
        DeleteContentRequest(
          documentRange: const DocumentRange(
            start: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 3)),
            end: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 3)),
          ),
        ),
      ]);

      expect(document.nodeCount, 2);
      expect((document.first as ParagraphNode).text.toPlainText(), 'hello');
      expect(composer.composingRegion.value, composingRegion);
    });
  });
}
