import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sheet.dart';

/// Moves work between RTC Hub and the tools people actually use.
///
/// The app is not trying to be an IDE or a spreadsheet editor, and it should
/// not pretend to be. A Business student's model belongs in Excel, which
/// recalculates it on open — that is what makes "run this spreadsheet" a real
/// thing rather than a feature we would have to reimplement badly. A
/// developer's snippet belongs wherever they already work.
///
/// A note on the difference between the two, because it shapes the UI:
/// opening a spreadsheet in Excel *does* run it, while opening code in an
/// editor does **not** — an editor is not a runtime. That is why code keeps
/// its in-app Run button (see `data/code_runner.dart`) and gains sharing on
/// top, instead of trading one for the other.
class DocumentService {
  const DocumentService();

  /// Extension used when saving a snippet, so the receiving editor picks the
  /// right syntax highlighting instead of treating it as plain text.
  static const _extensions = <String, String>{
    'dart': 'dart',
    'java': 'java',
    'python': 'py',
    'javascript': 'js',
    'typescript': 'ts',
    'sql': 'sql',
    'csharp': 'cs',
    'cpp': 'cpp',
    'php': 'php',
    'html': 'html',
    'css': 'css',
  };

  /// Windows forbids `\ / : * ? " < > |` in names and every platform dislikes
  /// a leading dot, so a post title cannot be used as a filename unedited.
  static String _safeName(String raw, {required String fallback}) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty || cleaned.startsWith('.')) return fallback;
    return cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
  }

  Future<Directory> _scratch() async {
    final dir = await getTemporaryDirectory();
    final out = Directory(p.join(dir.path, 'rtc_hub'));
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  // ─── Code ──────────────────────────────────────────────────

  /// Writes a snippet to a temp file with the right extension.
  Future<File> writeSnippet({
    required String code,
    String? language,
    String title = 'snippet',
  }) async {
    final ext = _extensions[language] ?? 'txt';
    final name = '${_safeName(title, fallback: 'snippet')}.$ext';
    final file = File(p.join((await _scratch()).path, name));
    return file.writeAsString(code);
  }

  // ─── Spreadsheets ──────────────────────────────────────────

  /// Builds a real `.xlsx`, not a CSV rename.
  ///
  /// It matters that formulas survive as formulas: a CSV would flatten
  /// `=SUM(A1:A5)` into text, and the whole point of handing the file to
  /// Excel is that Excel evaluates it.
  Future<File> writeSheet(SheetDoc sheet, {String title = 'sheet'}) async {
    final book = xl.Excel.createExcel();
    final sheetName = sheet.name?.trim().isNotEmpty == true
        ? _safeName(sheet.name!, fallback: 'Sheet1')
        : 'Sheet1';

    // createExcel() seeds a default sheet; rename it rather than adding a
    // second one and leaving an empty tab in the delivered file. The getter
    // is nullable and a bang here would crash the export rather than produce
    // a slightly oddly-named tab, which is the wrong trade.
    final seeded = book.getDefaultSheet();
    if (seeded != null && seeded != sheetName) {
      book.rename(seeded, sheetName);
    }
    // Indexing creates the sheet when the rename did not happen.
    final tab = book[sheetName];

    for (var c = 0; c < sheet.columns.length; c++) {
      tab
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = xl.TextCellValue(sheet.columns[c]);
    }

    for (var r = 0; r < sheet.rows.length; r++) {
      for (var c = 0; c < sheet.columns.length; c++) {
        final raw = sheet.cellAt(r, c);
        if (raw.isEmpty) continue;

        final index =
            xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1);
        tab.cell(index).value = switch (raw) {
          _ when SheetDoc.isFormula(raw) => xl.FormulaCellValue(raw.substring(1)),
          _ when int.tryParse(raw) != null =>
            xl.IntCellValue(int.parse(raw)),
          _ when double.tryParse(raw) != null =>
            xl.DoubleCellValue(double.parse(raw)),
          _ => xl.TextCellValue(raw),
        };
      }
    }

    final bytes = book.encode();
    if (bytes == null) {
      throw const FileSystemException('Could not build the spreadsheet');
    }

    final name = '${_safeName(title, fallback: 'sheet')}.xlsx';
    final file = File(p.join((await _scratch()).path, name));
    return file.writeAsBytes(bytes);
  }

  /// Reads an `.xlsx` or `.csv` back into a [SheetDoc].
  ///
  /// Formulas come back with the leading `=` restored so a round-trip through
  /// Excel and back does not silently turn a model into a page of constants.
  Future<SheetDoc> readSheet(File file) async {
    if (p.extension(file.path).toLowerCase() == '.csv') {
      final lines = const LineSplitter().convert(await file.readAsString());
      if (lines.isEmpty) return SheetDoc.blank();
      final rows = lines.map((l) => l.split(',')).toList();
      return SheetDoc(
        columns: rows.first,
        rows: rows.skip(1).toList(),
        name: p.basenameWithoutExtension(file.path),
      );
    }

    final book = xl.Excel.decodeBytes(await file.readAsBytes());
    final tabName = book.tables.keys.first;
    final tab = book.tables[tabName]!;
    if (tab.rows.isEmpty) return SheetDoc.blank();

    String render(xl.Data? cell) {
      final value = cell?.value;
      return switch (value) {
        null => '',
        xl.FormulaCellValue f => '=${f.formula}',
        xl.TextCellValue t => t.value.toString(),
        xl.IntCellValue i => '${i.value}',
        xl.DoubleCellValue d => '${d.value}',
        xl.BoolCellValue b => '${b.value}',
        _ => '$value',
      };
    }

    final header = tab.rows.first.map(render).toList();
    return SheetDoc(
      columns: header,
      rows: [for (final row in tab.rows.skip(1)) row.map(render).toList()],
      name: tabName,
    );
  }

  // ─── Handing off ───────────────────────────────────────────

  /// Opens the file in whatever app claims the type — Excel or Sheets for a
  /// spreadsheet, an editor for code.
  ///
  /// Returns a message when nothing on the device can open it, which is the
  /// normal case for source files on a stock Android install and the reason
  /// [share] exists as a fallback.
  Future<String?> openExternally(File file) async {
    final result = await OpenFilex.open(file.path);
    return switch (result.type) {
      ResultType.done => null,
      ResultType.noAppToOpen =>
        'No app on this device opens ${p.extension(file.path)} files. '
            'Try Share instead.',
      ResultType.permissionDenied => 'Permission to open the file was denied.',
      ResultType.fileNotFound => 'The file went missing before it could open.',
      _ => 'Could not open the file.',
    };
  }

  /// The share sheet — mail it, drop it in Drive, send it to a laptop.
  /// On a phone with no code editor this is the realistic route for a
  /// snippet, which is why it sits next to Open rather than behind it.
  Future<void> share(File file, {String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }

  /// Picks a file to attach to a submission.
  ///
  /// `pickFile` rather than `pickFiles`: a submission is one artefact, and
  /// the multi-select variant would leave the caller deciding what to do with
  /// the second file.
  Future<PlatformFile?> pickAttachment({List<String>? extensions}) =>
      FilePicker.pickFile(
        dialogTitle: 'Choose a file to submit',
        type: extensions == null ? FileType.any : FileType.custom,
        allowedExtensions: extensions,
      );
}
