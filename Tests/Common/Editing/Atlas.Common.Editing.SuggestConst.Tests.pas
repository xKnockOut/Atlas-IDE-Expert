unit Atlas.Common.Editing.SuggestConst.Tests;

// Glühbirne „Als Konstante deklarieren“ (#712): Inline-Variable mit Startwert,
// Variable aus dem var-Abschnitt mit einer Zuweisung im Rumpf, und wann es
// keinen Vorschlag gibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSuggestConstTests = class
  public
    [Test]
    procedure InlineVariableBecomesConst;
    [Test]
    procedure TypedInlineVariableKeepsType;
    [Test]
    procedure SectionVariableMovesToAssignment;
    [Test]
    procedure SectionVariableKeepsOtherNames;
    [Test]
    procedure NoSuggestionForChangedOrUnclearNames;
    [Test]
    procedure NoSuggestionInsideBranchOrWithEarlyRead;
    [Test]
    procedure NoSuggestionWhenNestedRoutineUsesIt;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.SuggestConst;

const
  cLF = #10;

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;' + cLF + 'interface' + cLF + 'implementation' + cLF + ABody + cLF + 'end.';
end;

/// <summary>Wendet die Edits (nicht überlappend, Zeilen mit #10) von hinten nach vorn an.</summary>
function Apply(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mLines: TArray<string>;
  mOffsets, mOrder: TArray<Integer>;
  mIndex, mInner, mSwap, mStart, mStop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  begin
    Result := mOffsets[APos.Line] + APos.Character;
  end;

begin
  mLines := AText.Split([cLF]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  SetLength(mOrder, Length(AEdits));
  for mIndex := 0 to High(mOrder) do
  begin
    mOrder[mIndex] := mIndex;
  end;
  for mIndex := 0 to High(mOrder) do
  begin
    for mInner := mIndex + 1 to High(mOrder) do
    begin
      if OffsetOf(AEdits[mOrder[mIndex]].Range.StartPos) < OffsetOf(AEdits[mOrder[mInner]].Range.StartPos) then
      begin
        mSwap := mOrder[mIndex];
        mOrder[mIndex] := mOrder[mInner];
        mOrder[mInner] := mSwap;
      end;
    end;
  end;
  Result := AText;
  for mIndex in mOrder do
  begin
    mStart := OffsetOf(AEdits[mIndex].Range.StartPos);
    mStop := OffsetOf(AEdits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStart) + AEdits[mIndex].NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

/// <summary>Text nach der Aktion am Namen in Zeile ALine, Zeichen ACharacter; '' ohne Vorschlag.</summary>
function Suggest(const AText: string; ALine, ACharacter: Integer; out ATitle: string): string;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := '';
  ATitle := '';
  mTree := TPascalParser.Parse(AText);
  try
    if TSuggestConst.Action(AText, mTree, TTextPosition.Create(ALine, ACharacter), nil, mAction) then
    begin
      ATitle := mAction.Title;
      Result := Apply(AText, mAction.Edits);
    end;
  finally
    mTree.Free;
  end;
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

procedure TSuggestConstTests.InlineVariableBecomesConst;
var
  mTitle, mChanged: string;
begin
  mChanged := Suggest(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  var Count := Liste.Count + 1;' + cLF +
    '  Writeln(Count);' + cLF +
    'end;'), 6, 11, mTitle);
  Assert.AreEqual('Als Konstante deklarieren (const Count)', mTitle);
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  const Count = Liste.Count + 1;' + cLF +
    '  Writeln(Count);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TSuggestConstTests.TypedInlineVariableKeepsType;
var
  mTitle: string;
begin
  // Auch an einer Verwendung.
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  const Rate: Double = 1;' + cLF +
    '  Writeln(Rate);' + cLF +
    'end;'), Suggest(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  var Rate: Double := 1;' + cLF +
    '  Writeln(Rate);' + cLF +
    'end;'), 6, 11, mTitle));
end;

procedure TSuggestConstTests.SectionVariableMovesToAssignment;
var
  mTitle, mChanged: string;
begin
  mChanged := Suggest(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  Name: string;' + cLF +
    'begin' + cLF +
    '  Writeln(1);' + cLF +
    '  Name := Trim(Eingabe);' + cLF +
    '  Writeln(Name);' + cLF +
    'end;'), 5, 3, mTitle);
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'begin' + cLF +
    '  Writeln(1);' + cLF +
    '  const Name: string = Trim(Eingabe);' + cLF +
    '  Writeln(Name);' + cLF +
    'end;'), mChanged);
  Assert.IsTrue(Parses(mChanged));
end;

procedure TSuggestConstTests.SectionVariableKeepsOtherNames;
var
  mTitle: string;
begin
  Assert.AreEqual(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  A, B: Integer;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  B := 1;' + cLF +
    '  B := B + 1;' + cLF +
    '  const C: Integer = A + B;' + cLF +
    '  Writeln(C);' + cLF +
    'end;'), Suggest(Wrap(
    'procedure P;' + cLF +
    'var' + cLF +
    '  A, B, C: Integer;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  B := 1;' + cLF +
    '  B := B + 1;' + cLF +
    '  C := A + B;' + cLF +
    '  Writeln(C);' + cLF +
    'end;'), 10, 3, mTitle));
end;

procedure TSuggestConstTests.NoSuggestionForChangedOrUnclearNames;
const
  cSource =
    'procedure P(A: Integer);' + cLF +
    'var' + cLF +
    '  B, C, D: Integer;' + cLF +
    'begin' + cLF +
    '  B := 1;' + cLF +
    '  B := 2;' + cLF +
    '  C := 1;' + cLF +
    '  Unbekannt(C);' + cLF +
    '  for D := 1 to 2 do' + cLF +
    '    Writeln(A, B, C, D);' + cLF +
    'end;';
var
  mTitle: string;
begin
  // Zweimal geschrieben, womöglich geändert, Schleifenzähler, Parameter.
  Assert.AreEqual('', Suggest(Wrap(cSource), 7, 3, mTitle));
  Assert.AreEqual('', Suggest(Wrap(cSource), 9, 3, mTitle));
  Assert.AreEqual('', Suggest(Wrap(cSource), 11, 7, mTitle));
  Assert.AreEqual('', Suggest(Wrap(cSource), 3, 12, mTitle));
  Assert.AreEqual('', mTitle);
end;

procedure TSuggestConstTests.NoSuggestionInsideBranchOrWithEarlyRead;
const
  cSource =
    'procedure P(F: Boolean);' + cLF +
    'var' + cLF +
    '  A, B: Integer;' + cLF +
    'begin' + cLF +
    '  if F then' + cLF +
    '    A := 1;' + cLF +
    '  Writeln(B);' + cLF +
    '  B := 2;' + cLF +
    '  Writeln(A, B);' + cLF +
    'end;';
var
  mTitle: string;
begin
  Assert.AreEqual('', Suggest(Wrap(cSource), 8, 4, mTitle), 'Zuweisung in einer Verzweigung');
  Assert.AreEqual('', Suggest(Wrap(cSource), 10, 2, mTitle), 'Lesen vor der Zuweisung');
end;

procedure TSuggestConstTests.NoSuggestionWhenNestedRoutineUsesIt;
const
  cSource =
    'procedure P;' + cLF +
    'var' + cLF +
    '  A: Integer;' + cLF +
    '  procedure Show;' + cLF +
    '  begin' + cLF +
    '    Writeln(A);' + cLF +
    '  end;' + cLF +
    'begin' + cLF +
    '  A := 1;' + cLF +
    '  Show;' + cLF +
    'end;';
var
  mTitle: string;
begin
  Assert.AreEqual('', Suggest(Wrap(cSource), 11, 2, mTitle));
end;

initialization
  TDUnitX.RegisterTestFixture(TSuggestConstTests);

end.
