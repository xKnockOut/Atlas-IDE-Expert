unit Atlas.Core.Editor.NewLine.Tests;

// Neue Zeile ober- oder unterhalb (#700): Einzug nach und vor allen
// Schlüsselwörtern, Klassenabschnitte, mehrzeilige Anweisungen mit und ohne
// StatementAware, Kommentare fortsetzen; die Cursorzeile bleibt gleich.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.NewLine;

type
  [TestFixture]
  TAtlasNewLineTests = class
  private
    FOptions: TAtlasNewLineOptions;
    function Below(const ALines: TArray<string>; ALine: Integer): TAtlasNewLineResult;
    function Above(const ALines: TArray<string>; ALine: Integer): TAtlasNewLineResult;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BelowPlainStatementKeepsIndent;
    [Test]
    procedure BelowIndentsAfterKeyword;
    [Test]
    procedure BelowKeepsIndent;
    [Test]
    procedure AboveIndentsBeforeCloser;
    [Test]
    procedure AbovePlainStatementKeepsIndent;
    [Test]
    procedure ClassSection;
    [Test]
    procedure MultiLineStatementAware;
    [Test]
    procedure MultiLineWithoutStatementAware;
    [Test]
    procedure MultiLineCondition;
    [Test]
    procedure ContinuesLineComments;
    [Test]
    procedure CommentsOffOrInBlock;
    [Test]
    procedure CursorLineStaysAndEdges;
    [Test]
    procedure StatementLinesOfCall;
  end;

implementation

uses
  System.SysUtils;

procedure TAtlasNewLineTests.Setup;
begin
  FOptions := TAtlasNewLineOptions.Defaults;
end;

procedure TAtlasNewLineTests.TearDown;
begin
  FOptions := Default(TAtlasNewLineOptions);
end;

function TAtlasNewLineTests.Below(const ALines: TArray<string>; ALine: Integer): TAtlasNewLineResult;
begin
  Result := TAtlasNewLine.Insert(ALines, ALine, TAtlasNewLineDirection.Below, FOptions);
end;

function TAtlasNewLineTests.Above(const ALines: TArray<string>; ALine: Integer): TAtlasNewLineResult;
begin
  Result := TAtlasNewLine.Insert(ALines, ALine, TAtlasNewLineDirection.Above, FOptions);
end;

procedure TAtlasNewLineTests.BelowPlainStatementKeepsIndent;
var
  Done: TAtlasNewLineResult;
begin
  Done := Below(['begin', '    Foo(1);', 'end;'], 1);
  Assert.AreEqual(2, Done.Line);
  Assert.AreEqual('    ', Done.Text);
  Assert.AreEqual(2, Done.Cursor.Line);
  Assert.AreEqual(4, Done.Cursor.Character);
  Assert.AreEqual(4, Integer(Length(Done.Lines)));
  Assert.AreEqual('end;', Done.Lines[3]);
end;

procedure TAtlasNewLineTests.BelowIndentsAfterKeyword;
var
  Text, Line: string;
begin
  for Text in TArray<string>.Create(
      'if A then',
      'while A do',
      'begin',
      'try',
      'end else',
      'repeat',
      'except',
      'finally',
      'asm',
      'case A of',
      'TRec = packed record',
      'var',
      'const',
      'type',
      'uses',
      'on E: Exception do',
      'if A then // Kommentar') do
  begin
    Line := '  ' + Text;
    FOptions.IndentWidth := 2;
    Assert.AreEqual('    ', Below([Line, '  Foo;'], 0).Text, Line);
    FOptions.IndentWidth := 4;
    Assert.AreEqual('      ', Below([Line, '  Foo;'], 0).Text, Line + ' (Einzug 4)');
  end;
end;

procedure TAtlasNewLineTests.BelowKeepsIndent;
var
  Text, Line: string;
begin
  for Text in TArray<string>.Create(
      'Werte: array of',
      'if A then Foo;',
      'end;',
      'S := ''then''') do
  begin
    Line := '  ' + Text;
    Assert.AreEqual('  ', Below([Line], 0).Text, Line);
  end;
end;

procedure TAtlasNewLineTests.AboveIndentsBeforeCloser;
var
  Text, Line: string;
  Done: TAtlasNewLineResult;
begin
  for Text in TArray<string>.Create(
      'end;',
      'until A;',
      'except',
      'finally',
      'else',
      'private',
      'strict private') do
  begin
    Line := '  ' + Text;
    Done := Above(['  begin', '    Foo;', Line], 2);
    Assert.AreEqual(2, Done.Line, Line);
    Assert.AreEqual('    ', Done.Text, Line);
    Assert.AreEqual(Line, Done.Lines[3]);
  end;
end;

procedure TAtlasNewLineTests.AbovePlainStatementKeepsIndent;
var
  Done: TAtlasNewLineResult;
begin
  Done := Above(['begin', '    Foo(1);', 'end;'], 1);
  Assert.AreEqual(1, Done.Line);
  Assert.AreEqual('    ', Done.Text);
  Assert.AreEqual('    Foo(1);', Done.Lines[2]);
  // Erste Zeile: oben eingefügt.
  Done := Above(['if A then', '  Foo;'], 0);
  Assert.AreEqual(0, Done.Line);
  Assert.AreEqual('', Done.Text);
end;

procedure TAtlasNewLineTests.ClassSection;
var
  Lines: TArray<string>;
begin
  Lines := [
    'type',                            // 0
    '  TKunde = class(TBasis)',        // 1
    '  private',                       // 2
    '    FName: string;',              // 3
    '  public',                        // 4
    '    procedure Speichern;',        // 5
    '  end;',                          // 6
    '  EFehler = class(Exception);',   // 7
    '  TListe = class;',               // 8
    '  TKlasse = class of TKunde;',    // 9
    '  IKunde = interface',            // 10
    '  TRec = record'];                // 11
  Assert.AreEqual('    ', Below(Lines, 1).Text, 'Klassenkopf');
  Assert.AreEqual('    ', Below(Lines, 2).Text, 'private');
  Assert.AreEqual('    ', Below(Lines, 3).Text, 'Feld');
  Assert.AreEqual('    ', Above(Lines, 4).Text, 'vor public');
  Assert.AreEqual('    ', Below(Lines, 5).Text, 'Methode');
  Assert.AreEqual('    ', Above(Lines, 6).Text, 'vor end');
  Assert.AreEqual('  ', Below(Lines, 7).Text, 'kurze Klasse');
  Assert.AreEqual('  ', Below(Lines, 8).Text, 'Vorwärtsdeklaration');
  Assert.AreEqual('  ', Below(Lines, 9).Text, 'class of');
  Assert.AreEqual('    ', Below(Lines, 10).Text, 'interface');
  Assert.AreEqual('    ', Below(Lines, 11).Text, 'record');
  Assert.AreEqual('', Below(['interface'], 0).Text);
end;

procedure TAtlasNewLineTests.MultiLineStatementAware;
var
  Lines: TArray<string>;
  Done: TAtlasNewLineResult;
begin
  Lines := [
    'begin',                 // 0
    '  Kunde := Laden(1,',   // 1
    '      ''Name'',',       // 2
    '      True);',          // 3
    'end;'];                 // 4
  // Unterhalb: hinter dem Ende der Anweisung, Einzug ihrer ersten Zeile.
  Done := Below(Lines, 1);
  Assert.AreEqual(4, Done.Line);
  Assert.AreEqual('  ', Done.Text);
  Done := Below(Lines, 2);
  Assert.AreEqual(4, Done.Line);
  Assert.AreEqual('  ', Done.Text);
  // Oberhalb: vor ihrem Anfang.
  Done := Above(Lines, 3);
  Assert.AreEqual(1, Done.Line);
  Assert.AreEqual('  ', Done.Text);
  Assert.AreEqual('  Kunde := Laden(1,', Done.Lines[2]);
end;

procedure TAtlasNewLineTests.MultiLineWithoutStatementAware;
var
  Lines: TArray<string>;
  Done: TAtlasNewLineResult;
begin
  FOptions.StatementAware := False;
  Lines := [
    'begin',
    '  Kunde := Laden(1,',
    '      ''Name'',',
    '      True);',
    'end;'];
  Done := Below(Lines, 1);
  Assert.AreEqual(2, Done.Line);
  Assert.AreEqual('  ', Done.Text);
  Done := Below(Lines, 2);
  Assert.AreEqual(3, Done.Line);
  Assert.AreEqual('      ', Done.Text);
  Done := Above(Lines, 3);
  Assert.AreEqual(3, Done.Line);
  Assert.AreEqual('      ', Done.Text);
end;

procedure TAtlasNewLineTests.MultiLineCondition;
var
  Lines: TArray<string>;
  Done: TAtlasNewLineResult;
begin
  Lines := [
    '  if A and',     // 0
    '    B then',     // 1
    '    Foo;'];      // 2
  Done := Below(Lines, 0);
  Assert.AreEqual(2, Done.Line, 'hinter then');
  Assert.AreEqual('    ', Done.Text, 'Einzug von if plus eine Ebene');
  Done := Above(Lines, 1);
  Assert.AreEqual(0, Done.Line);
  Assert.AreEqual('  ', Done.Text);
  // Anweisung im Zweig endet vor else.
  Done := Below(['  if A then', '    Foo(1,', '      2)', '  else', '    Bar;'], 1);
  Assert.AreEqual(3, Done.Line);
  Assert.AreEqual('    ', Done.Text);
end;

procedure TAtlasNewLineTests.ContinuesLineComments;
var
  Done: TAtlasNewLineResult;
begin
  Done := Below(['  // Kunde laden', '  Laden;'], 0);
  Assert.AreEqual('  // ', Done.Text);
  Assert.AreEqual(5, Done.Cursor.Character);
  Assert.AreEqual('  /// ', Below(['  /// <summary>Kunde', '  procedure Laden;'], 0).Text);
  Assert.AreEqual('  //   ', Above(['  //   eingerückt'], 0).Text);
  Assert.AreEqual('  /// ', Above(['  /// Doku'], 0).Text);
  FOptions.Comments.LineComments := False;
  Assert.AreEqual('  ', Below(['  // Kunde laden'], 0).Text, '"//" aus');
  Assert.AreEqual('  ', Above(['  // Kunde laden'], 0).Text, '"//" aus');
  Assert.AreEqual('  /// ', Above(['  /// Doku'], 0).Text, '"///" immer');
  // Kommentar hinter Code setzt nicht fort.
  Assert.AreEqual('  ', Below(['  Foo; // Kommentar'], 0).Text);
end;

procedure TAtlasNewLineTests.CommentsOffOrInBlock;
begin
  Assert.AreEqual('    ', Above(['  {', '    Text', '  }'], 1).Text, 'oberhalb im Blockkommentar');
  Assert.AreEqual('    ', Below(['  {', '    Text', '  }'], 1).Text, 'unterhalb im Blockkommentar');
  FOptions.ContinueComments := False;
  Assert.AreEqual('  ', Below(['  // Kunde laden'], 0).Text);
  Assert.AreEqual('  ', Above(['  /// Doku'], 0).Text);
  // Schlüsselwörter im Kommentar zählen nicht.
  Assert.AreEqual('  ', Below(['  Foo; { begin }'], 0).Text);
end;

procedure TAtlasNewLineTests.CursorLineStaysAndEdges;
var
  Lines: TArray<string>;
  Done: TAtlasNewLineResult;
begin
  Lines := ['unit A;', '  if A then', '    Foo;'];
  Done := Below(Lines, 2);
  Assert.AreEqual(3, Done.Line, 'letzte Zeile');
  Assert.AreEqual(4, Integer(Length(Done.Lines)));
  Assert.AreEqual('    Foo;', Done.Lines[2]);
  Done := Above(Lines, 1);
  Assert.AreEqual('  if A then', Done.Lines[2]);
  Done := Below(nil, 0);
  Assert.AreEqual(2, Integer(Length(Done.Lines)), 'leerer Text');
  Done := Below(['', ''], 9);
  Assert.AreEqual(2, Done.Line, 'Zeile außerhalb');
end;

procedure TAtlasNewLineTests.StatementLinesOfCall;
var
  First, Last: Integer;
begin
  Assert.IsTrue(TAtlasNewLine.StatementLines(['begin', '  Laden(1,', '    2);', 'end;'], 2,
    TAtlasNewLineDirection.Above, First, Last));
  Assert.AreEqual(1, First);
  Assert.AreEqual(2, Last);
  Assert.IsFalse(TAtlasNewLine.StatementLines(['begin', '', 'end;'], 1, TAtlasNewLineDirection.Below, First, Last));
  Assert.AreEqual(1, First);
  Assert.AreEqual(1, Last);
end;

end.
