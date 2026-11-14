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
  mDone: TAtlasNewLineResult;
begin
  mDone := Below(['begin', '    Foo(1);', 'end;'], 1);
  Assert.AreEqual(2, mDone.Line);
  Assert.AreEqual('    ', mDone.Text);
  Assert.AreEqual(2, mDone.Cursor.Line);
  Assert.AreEqual(4, mDone.Cursor.Character);
  Assert.AreEqual(4, Integer(Length(mDone.Lines)));
  Assert.AreEqual('end;', mDone.Lines[3]);
end;

procedure TAtlasNewLineTests.BelowIndentsAfterKeyword;
var
  mText, mLine: string;
begin
  for mText in TArray<string>.Create(
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
    mLine := '  ' + mText;
    FOptions.IndentWidth := 2;
    Assert.AreEqual('    ', Below([mLine, '  Foo;'], 0).Text, mLine);
    FOptions.IndentWidth := 4;
    Assert.AreEqual('      ', Below([mLine, '  Foo;'], 0).Text, mLine + ' (Einzug 4)');
  end;
end;

procedure TAtlasNewLineTests.BelowKeepsIndent;
var
  mText, mLine: string;
begin
  for mText in TArray<string>.Create(
      'Werte: array of',
      'if A then Foo;',
      'end;',
      'S := ''then''') do
  begin
    mLine := '  ' + mText;
    Assert.AreEqual('  ', Below([mLine], 0).Text, mLine);
  end;
end;

procedure TAtlasNewLineTests.AboveIndentsBeforeCloser;
var
  mText, mLine: string;
  mDone: TAtlasNewLineResult;
begin
  for mText in TArray<string>.Create(
      'end;',
      'until A;',
      'except',
      'finally',
      'else',
      'private',
      'strict private') do
  begin
    mLine := '  ' + mText;
    mDone := Above(['  begin', '    Foo;', mLine], 2);
    Assert.AreEqual(2, mDone.Line, mLine);
    Assert.AreEqual('    ', mDone.Text, mLine);
    Assert.AreEqual(mLine, mDone.Lines[3]);
  end;
end;

procedure TAtlasNewLineTests.AbovePlainStatementKeepsIndent;
var
  mDone: TAtlasNewLineResult;
begin
  mDone := Above(['begin', '    Foo(1);', 'end;'], 1);
  Assert.AreEqual(1, mDone.Line);
  Assert.AreEqual('    ', mDone.Text);
  Assert.AreEqual('    Foo(1);', mDone.Lines[2]);
  // Erste Zeile: oben eingefügt.
  mDone := Above(['if A then', '  Foo;'], 0);
  Assert.AreEqual(0, mDone.Line);
  Assert.AreEqual('', mDone.Text);
end;

procedure TAtlasNewLineTests.ClassSection;
var
  mLines: TArray<string>;
begin
  mLines := [
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
  Assert.AreEqual('    ', Below(mLines, 1).Text, 'Klassenkopf');
  Assert.AreEqual('    ', Below(mLines, 2).Text, 'private');
  Assert.AreEqual('    ', Below(mLines, 3).Text, 'Feld');
  Assert.AreEqual('    ', Above(mLines, 4).Text, 'vor public');
  Assert.AreEqual('    ', Below(mLines, 5).Text, 'Methode');
  Assert.AreEqual('    ', Above(mLines, 6).Text, 'vor end');
  Assert.AreEqual('  ', Below(mLines, 7).Text, 'kurze Klasse');
  Assert.AreEqual('  ', Below(mLines, 8).Text, 'Vorwärtsdeklaration');
  Assert.AreEqual('  ', Below(mLines, 9).Text, 'class of');
  Assert.AreEqual('    ', Below(mLines, 10).Text, 'interface');
  Assert.AreEqual('    ', Below(mLines, 11).Text, 'record');
  Assert.AreEqual('', Below(['interface'], 0).Text);
end;

procedure TAtlasNewLineTests.MultiLineStatementAware;
var
  mLines: TArray<string>;
  mDone: TAtlasNewLineResult;
begin
  mLines := [
    'begin',                 // 0
    '  Kunde := Laden(1,',   // 1
    '      ''Name'',',       // 2
    '      True);',          // 3
    'end;'];                 // 4
  // Unterhalb: hinter dem Ende der Anweisung, Einzug ihrer ersten Zeile.
  mDone := Below(mLines, 1);
  Assert.AreEqual(4, mDone.Line);
  Assert.AreEqual('  ', mDone.Text);
  mDone := Below(mLines, 2);
  Assert.AreEqual(4, mDone.Line);
  Assert.AreEqual('  ', mDone.Text);
  // Oberhalb: vor ihrem Anfang.
  mDone := Above(mLines, 3);
  Assert.AreEqual(1, mDone.Line);
  Assert.AreEqual('  ', mDone.Text);
  Assert.AreEqual('  Kunde := Laden(1,', mDone.Lines[2]);
end;

procedure TAtlasNewLineTests.MultiLineWithoutStatementAware;
var
  mLines: TArray<string>;
  mDone: TAtlasNewLineResult;
begin
  FOptions.StatementAware := False;
  mLines := [
    'begin',
    '  Kunde := Laden(1,',
    '      ''Name'',',
    '      True);',
    'end;'];
  mDone := Below(mLines, 1);
  Assert.AreEqual(2, mDone.Line);
  Assert.AreEqual('  ', mDone.Text);
  mDone := Below(mLines, 2);
  Assert.AreEqual(3, mDone.Line);
  Assert.AreEqual('      ', mDone.Text);
  mDone := Above(mLines, 3);
  Assert.AreEqual(3, mDone.Line);
  Assert.AreEqual('      ', mDone.Text);
end;

procedure TAtlasNewLineTests.MultiLineCondition;
var
  mLines: TArray<string>;
  mDone: TAtlasNewLineResult;
begin
  mLines := [
    '  if A and',     // 0
    '    B then',     // 1
    '    Foo;'];      // 2
  mDone := Below(mLines, 0);
  Assert.AreEqual(2, mDone.Line, 'hinter then');
  Assert.AreEqual('    ', mDone.Text, 'Einzug von if plus eine Ebene');
  mDone := Above(mLines, 1);
  Assert.AreEqual(0, mDone.Line);
  Assert.AreEqual('  ', mDone.Text);
  // Anweisung im Zweig endet vor else.
  mDone := Below(['  if A then', '    Foo(1,', '      2)', '  else', '    Bar;'], 1);
  Assert.AreEqual(3, mDone.Line);
  Assert.AreEqual('    ', mDone.Text);
end;

procedure TAtlasNewLineTests.ContinuesLineComments;
var
  mDone: TAtlasNewLineResult;
begin
  mDone := Below(['  // Kunde laden', '  Laden;'], 0);
  Assert.AreEqual('  // ', mDone.Text);
  Assert.AreEqual(5, mDone.Cursor.Character);
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
  mLines: TArray<string>;
  mDone: TAtlasNewLineResult;
begin
  mLines := ['unit A;', '  if A then', '    Foo;'];
  mDone := Below(mLines, 2);
  Assert.AreEqual(3, mDone.Line, 'letzte Zeile');
  Assert.AreEqual(4, Integer(Length(mDone.Lines)));
  Assert.AreEqual('    Foo;', mDone.Lines[2]);
  mDone := Above(mLines, 1);
  Assert.AreEqual('  if A then', mDone.Lines[2]);
  mDone := Below(nil, 0);
  Assert.AreEqual(2, Integer(Length(mDone.Lines)), 'leerer Text');
  mDone := Below(['', ''], 9);
  Assert.AreEqual(2, mDone.Line, 'Zeile außerhalb');
end;

procedure TAtlasNewLineTests.StatementLinesOfCall;
var
  mFirst, mLast: Integer;
begin
  Assert.IsTrue(TAtlasNewLine.StatementLines(['begin', '  Laden(1,', '    2);', 'end;'], 2,
    TAtlasNewLineDirection.Above, mFirst, mLast));
  Assert.AreEqual(1, mFirst);
  Assert.AreEqual(2, mLast);
  Assert.IsFalse(TAtlasNewLine.StatementLines(['begin', '', 'end;'], 1, TAtlasNewLineDirection.Below, mFirst, mLast));
  Assert.AreEqual(1, mFirst);
  Assert.AreEqual(1, mLast);
end;

end.
