/// A spreadsheet attached to a post or a bounty submission.
///
/// Stored as data rather than only as an uploaded file so the app can render
/// a preview in the feed and regenerate a clean `.xlsx` on demand — a file
/// someone uploaded from Excel may carry charts, macros and formatting we
/// have no business round-tripping.
///
/// Formulas are kept verbatim as strings. The app deliberately does **not**
/// evaluate them: Excel and Google Sheets both recalculate on open, so the
/// "run" step happens in a tool built for it, and shipping a half-correct
/// formula engine would only produce numbers that disagree with the ones the
/// user sees when they open the file.
class SheetDoc {
  const SheetDoc({required this.columns, required this.rows, this.name});

  /// Header labels. Length defines the column count; rows are padded or
  /// trimmed to match so the grid can never render ragged.
  final List<String> columns;
  final List<List<String>> rows;
  final String? name;

  int get columnCount => columns.length;
  int get rowCount => rows.length;
  bool get isEmpty => columns.isEmpty || rows.isEmpty;

  /// A1, B2 … for the header row and the row-number gutter.
  static String columnLabel(int index) {
    var i = index;
    final buffer = StringBuffer();
    do {
      buffer.write(String.fromCharCode(65 + (i % 26)));
      i = i ~/ 26 - 1;
    } while (i >= 0);
    return String.fromCharCodes(buffer.toString().codeUnits.reversed);
  }

  static bool isFormula(String cell) => cell.trimLeft().startsWith('=');

  String cellAt(int row, int column) {
    if (row < 0 || row >= rows.length) return '';
    final line = rows[row];
    return column < line.length ? line[column] : '';
  }

  SheetDoc copyWith({
    List<String>? columns,
    List<List<String>>? rows,
    String? name,
  }) =>
      SheetDoc(
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
        name: name ?? this.name,
      );

  /// A blank sheet for the composer.
  factory SheetDoc.blank({int columns = 4, int rows = 6}) => SheetDoc(
        columns: [for (var i = 0; i < columns; i++) columnLabel(i)],
        rows: [
          for (var r = 0; r < rows; r++) [for (var c = 0; c < columns; c++) ''],
        ],
      );

  factory SheetDoc.fromMap(Map<String, dynamic> map) {
    final columns = (map['columns'] as List?)?.map((c) => '$c').toList() ?? [];
    final rawRows = (map['rows'] as List?) ?? const [];

    // Normalise every row to the header width. A sheet that came back from a
    // third-party editor is routinely ragged, and a ragged grid throws on
    // render rather than looking slightly wrong.
    final rows = <List<String>>[
      for (final row in rawRows)
        [
          for (var c = 0; c < columns.length; c++)
            (row is List && c < row.length) ? '${row[c]}' : '',
        ],
    ];

    return SheetDoc(
      columns: columns,
      rows: rows,
      name: map['name'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'columns': columns,
        'rows': rows,
        if (name != null) 'name': name,
      };

  /// Rough guide for the reader before they commit to opening it elsewhere.
  String get summary {
    final cells = rowCount * columnCount;
    final formulas = rows
        .expand((r) => r)
        .where(isFormula)
        .length;
    final parts = [
      '$rowCount ${rowCount == 1 ? 'row' : 'rows'}',
      '$columnCount ${columnCount == 1 ? 'column' : 'columns'}',
      if (formulas > 0) '$formulas ${formulas == 1 ? 'formula' : 'formulas'}',
    ];
    return cells == 0 ? 'Empty sheet' : parts.join(' · ');
  }
}
