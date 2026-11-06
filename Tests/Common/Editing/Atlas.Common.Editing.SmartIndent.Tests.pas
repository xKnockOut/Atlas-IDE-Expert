unit Atlas.Common.Editing.SmartIndent.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Editing.SmartIndent;

type
  /// <summary>Einrückung beim Tippen (#1827): neue Zeile (#1828), Schlusswort (#1829), String teilen (#1831),
  /// Spalte fürs Einfügen (#1832).</summary>
  [TestFixture]
  TSmartIndentTests = class
  private
    /// <summary>ALines nach Enter (ALine ist die neue Zeile) mit den Änderungen; Zeilen mit "/" verbunden, die
    /// Schreibmarke als "|"; '-' ohne Antwort.</summary>
    function Entered(const ALines: TArray<string>; ALine: Integer; const AOptions: TSmartIndentOptions): string;
      overload;
    function Entered(const ALines: TArray<string>; ALine: Integer): string; overload;
  public
    [Test]
    procedure IndentsAfterBlockOpeners;
    [Test]
    procedure ReturnsAfterSingleStatement;
    [Test]
    procedure FollowsExistingIndentation;
    [Test]
    procedure AlignsInOpenBracket;
    [Test]
    procedure IndentsContinuation;
    [Test]
    procedure OutdentsClosers;
    [Test]
    procedure SplitsStringIndented;
    [Test]
    procedure SplitsStringAligned;
    [Test]
    procedure KeepsCommentsAndStringsEnds;
    [Test]
    procedure HonoursSwitches;
    [Test]
    procedure UsesTabsAndIndentSize;
    [Test]
    procedure GivesColumnForPaste;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

const
  LF = #10;

/// <summary>Zeichenindex von APosition in ALines (Zeilen mit LF verbunden).</summary>
function OffsetOf(const ALines: TArray<string>; const APosition: TTextPosition): Integer;
var
  mLine: Integer;
begin
  Result := 0;
  for mLine := 0 to APosition.Line - 1 do
  begin
    Inc(Result, Length(ALines[mLine]) + 1);
  end;
  Inc(Result, APosition.Character);
end;

{ TSmartIndentTests }

function TSmartIndentTests.Entered(const ALines: TArray<string>; ALine: Integer;
  const AOptions: TSmartIndentOptions): string;
var
  mResult: TSmartIndentResult;
  mText: string;
  mIndex, mCursor, mStart, mEnd: Integer;
begin
  if not TSmartIndent.AfterEnter(string.Join(LF, ALines), ALine, AOptions, mResult) then
  begin
    Exit('-');
  end;
  mText := string.Join(LF, ALines);
  mCursor := OffsetOf(ALines, mResult.Cursor);
  // Rückwärts anwenden, damit die vorderen Positionen gelten; die Schreibmarke zählt nach den Änderungen.
  for mIndex := High(mResult.Edits) downto 0 do
  begin
    mStart := OffsetOf(ALines, mResult.Edits[mIndex].Range.StartPos);
    mEnd := OffsetOf(ALines, mResult.Edits[mIndex].Range.EndPos);
    mText := Copy(mText, 1, mStart) + mResult.Edits[mIndex].NewText + Copy(mText, mEnd + 1, MaxInt);
    if mResult.Edits[mIndex].Range.StartPos.Line < mResult.Cursor.Line then
    begin
      Inc(mCursor, Length(mResult.Edits[mIndex].NewText) - (mEnd - mStart));
    end;
  end;
  Insert('|', mText, mCursor + 1);
  Result := mText.Replace(LF, '/');
end;

function TSmartIndentTests.Entered(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := Entered(ALines, ALine, TSmartIndentOptions.Default);
end;

procedure TSmartIndentTests.IndentsAfterBlockOpeners;
begin
  Assert.AreEqual('procedure P;/begin/  |/end;', Entered(['procedure P;', 'begin', '', 'end;'], 2));
  Assert.AreEqual('begin/  if A then/    |', Entered(['begin', '  if A then', ''], 2));
  Assert.AreEqual('begin/  try/    |', Entered(['begin', '  try', ''], 2));
  Assert.AreEqual('begin/  for I := 0 to 9 do/    |', Entered(['begin', '  for I := 0 to 9 do', ''], 2));
  Assert.AreEqual('begin/  case A of/    1:/      |', Entered(['begin', '  case A of', '    1:', ''], 3));
  Assert.AreEqual('type/  TA = class/  private/    |', Entered(['type', '  TA = class', '  private', ''], 3));
  Assert.AreEqual('begin/  if A then/    B/  else/    |', Entered(['begin', '  if A then', '    B', '    else', ''], 4));
  // Virtuelle Schreibmarke der IDE: die Zeile ist leer, Atlas setzt den Leerraum.
  Assert.AreEqual('begin/  if A then/    |', Entered(['begin', '  if A then', '        '], 2));
end;

procedure TSmartIndentTests.ReturnsAfterSingleStatement;
begin
  Assert.AreEqual('begin/  if A then/    B;/  |', Entered(['begin', '  if A then', '    B;', ''], 3));
  Assert.AreEqual('begin/  X := 1;/  |', Entered(['begin', '  X := 1;', '    '], 2));
end;

procedure TSmartIndentTests.FollowsExistingIndentation;
begin
  // Die Datei rückt mit 4 ein, der Stil sagt 2: Die Zeile darüber gibt den Abstand vor.
  Assert.AreEqual('begin/    if A then/      |', Entered(['begin', '    if A then', ''], 2));
end;

procedure TSmartIndentTests.AlignsInOpenBracket;
begin
  Assert.AreEqual('begin/  Foo(A,/      |', Entered(['begin', '  Foo(A,', ''], 2));
  // Klammer ohne erstes Argument in derselben Zeile: eine Ebene tiefer als ihre Zeile.
  Assert.AreEqual('begin/  Foo(/    |', Entered(['begin', '  Foo(', ''], 2));
end;

procedure TSmartIndentTests.IndentsContinuation;
begin
  Assert.AreEqual('begin/  X := A +/    |', Entered(['begin', '  X := A +', ''], 2));
end;

procedure TSmartIndentTests.OutdentsClosers;
begin
  Assert.AreEqual('begin/  if A then/  begin/    B;/  end/  |',
    Entered(['begin', '  if A then', '  begin', '    B;', '    end', ''], 5));
  Assert.AreEqual('begin/  try/    B;/  finally/    |', Entered(['begin', '  try', '    B;', '    finally', ''], 4));
  // Steht das Schlusswort schon richtig, ändert sich nur die neue Zeile.
  Assert.AreEqual('begin/  repeat/    B;/  until A;/  |',
    Entered(['begin', '  repeat', '    B;', '  until A;', ''], 4));
end;

procedure TSmartIndentTests.SplitsStringIndented;
begin
  Assert.AreEqual('begin/  S := ''abc'' +/    ''|def'';', Entered(['begin', '  S := ''abc', 'def'';'], 2));
end;

procedure TSmartIndentTests.SplitsStringAligned;
var
  mOptions: TSmartIndentOptions;
begin
  mOptions := TSmartIndentOptions.Default;
  mOptions.StringContinuation := TStringContinuation.Align;
  // Unter dem ersten Wert hinter :=.
  Assert.AreEqual('begin/  S := ''abc'' +/       ''|def'';', Entered(['begin', '  S := ''abc', 'def'';'], 2, mOptions));
  // In offener Klammer unter dem ersten Argument.
  Assert.AreEqual('begin/  Foo(''abc'' +/      ''|def'');', Entered(['begin', '  Foo(''abc', 'def'');'], 2, mOptions));
end;

procedure TSmartIndentTests.KeepsCommentsAndStringsEnds;
begin
  Assert.AreEqual('-', Entered(['begin', '  { Kommentar', '', '  }'], 2));
  Assert.AreEqual('-', Entered(['begin', '  (* Kommentar', ''], 2));
  // Erste Zeile: keine Zeile darüber.
  Assert.AreEqual('-', Entered([''], 0));
end;

procedure TSmartIndentTests.HonoursSwitches;
var
  mOptions: TSmartIndentOptions;
begin
  mOptions := TSmartIndentOptions.Default;
  mOptions.AfterEnter := False;
  // Nur das Schlusswort: die neue Zeile behält ihren Abstand zu ihm.
  Assert.AreEqual('begin/  try/    B;/  finally/  |', Entered(['begin', '  try', '    B;', '    finally', '    '], 4,
    mOptions));
  Assert.AreEqual('-', Entered(['begin', '  if A then', ''], 2, mOptions));
  mOptions := TSmartIndentOptions.Default;
  mOptions.OutdentClosers := False;
  Assert.AreEqual('begin/  try/    B;/    finally/      |', Entered(['begin', '  try', '    B;', '    finally', ''], 4,
    mOptions));
  mOptions := TSmartIndentOptions.Default;
  mOptions.SplitStrings := False;
  Assert.AreNotEqual('begin/  S := ''abc'' +/    ''|def'';', Entered(['begin', '  S := ''abc', 'def'';'], 2, mOptions));
end;

procedure TSmartIndentTests.UsesTabsAndIndentSize;
var
  mOptions: TSmartIndentOptions;
begin
  mOptions := TSmartIndentOptions.Default;
  mOptions.IndentSize := 4;
  Assert.AreEqual('begin/    if A then/        |', Entered(['begin', '    if A then', ''], 2, mOptions));
  mOptions.UseTabs := True;
  Assert.AreEqual('begin/'#9'if A then/'#9#9'|', Entered(['begin', #9'if A then', ''], 2, mOptions));
end;

procedure TSmartIndentTests.GivesColumnForPaste;
var
  mColumn: Integer;
begin
  Assert.IsTrue(TSmartIndent.ColumnAt(string.Join(LF, ['begin', '  if A then B;', 'X := 1;']), 2, 2, mColumn));
  Assert.AreEqual(2, mColumn);
  Assert.IsTrue(TSmartIndent.ColumnAt(string.Join(LF, ['begin', '  case A of', '    1:', 'X := 1;']), 3, 2, mColumn));
  Assert.AreEqual(6, mColumn);
  Assert.IsFalse(TSmartIndent.ColumnAt(string.Join(LF, ['{', 'X := 1;', '}']), 1, 2, mColumn));
end;

initialization
  TDUnitX.RegisterTestFixture(TSmartIndentTests);

end.
