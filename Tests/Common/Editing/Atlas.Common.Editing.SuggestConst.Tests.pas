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
  LF = #10;

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;' + LF + 'interface' + LF + 'implementation' + LF + ABody + LF + 'end.';
end;

/// <summary>Wendet die Edits (nicht überlappend, Zeilen mit #10) von hinten nach vorn an.</summary>
function Apply(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  Lines: TArray<string>;
  Offsets, Order: TArray<Integer>;
  Index, Inner, Swap, Start, Stop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  begin
    Result := Offsets[APos.Line] + APos.Character;
  end;

begin
  Lines := AText.Split([LF]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  SetLength(Order, Length(AEdits));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  for Index := 0 to High(Order) do
    for Inner := Index + 1 to High(Order) do
      if OffsetOf(AEdits[Order[Index]].Range.StartPos) < OffsetOf(AEdits[Order[Inner]].Range.StartPos) then
      begin
        Swap := Order[Index];
        Order[Index] := Order[Inner];
        Order[Inner] := Swap;
      end;
  Result := AText;
  for Index in Order do
  begin
    Start := OffsetOf(AEdits[Index].Range.StartPos);
    Stop := OffsetOf(AEdits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start) + AEdits[Index].NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

/// <summary>Text nach der Aktion am Namen in Zeile ALine, Zeichen ACharacter; '' ohne Vorschlag.</summary>
function Suggest(const AText: string; ALine, ACharacter: Integer; out ATitle: string): string;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Result := '';
  ATitle := '';
  Tree := TPascalParser.Parse(AText);
  try
    if TSuggestConst.Action(AText, Tree, TTextPosition.Create(ALine, ACharacter), nil, Action) then
    begin
      ATitle := Action.Title;
      Result := Apply(AText, Action.Edits);
    end;
  finally
    Tree.Free;
  end;
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TSuggestConstTests.InlineVariableBecomesConst;
var
  Title, Changed: string;
begin
  Changed := Suggest(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  var Count := Liste.Count + 1;' + LF +
    '  Writeln(Count);' + LF +
    'end;'), 6, 11, Title);
  Assert.AreEqual('Als Konstante deklarieren (const Count)', Title);
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  const Count = Liste.Count + 1;' + LF +
    '  Writeln(Count);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TSuggestConstTests.TypedInlineVariableKeepsType;
var
  Title: string;
begin
  // Auch an einer Verwendung.
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  const Rate: Double = 1;' + LF +
    '  Writeln(Rate);' + LF +
    'end;'), Suggest(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  var Rate: Double := 1;' + LF +
    '  Writeln(Rate);' + LF +
    'end;'), 6, 11, Title));
end;

procedure TSuggestConstTests.SectionVariableMovesToAssignment;
var
  Title, Changed: string;
begin
  Changed := Suggest(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  Name: string;' + LF +
    'begin' + LF +
    '  Writeln(1);' + LF +
    '  Name := Trim(Eingabe);' + LF +
    '  Writeln(Name);' + LF +
    'end;'), 5, 3, Title);
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'begin' + LF +
    '  Writeln(1);' + LF +
    '  const Name: string = Trim(Eingabe);' + LF +
    '  Writeln(Name);' + LF +
    'end;'), Changed);
  Assert.IsTrue(Parses(Changed));
end;

procedure TSuggestConstTests.SectionVariableKeepsOtherNames;
var
  Title: string;
begin
  Assert.AreEqual(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  A, B: Integer;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  B := 1;' + LF +
    '  B := B + 1;' + LF +
    '  const C: Integer = A + B;' + LF +
    '  Writeln(C);' + LF +
    'end;'), Suggest(Wrap(
    'procedure P;' + LF +
    'var' + LF +
    '  A, B, C: Integer;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  B := 1;' + LF +
    '  B := B + 1;' + LF +
    '  C := A + B;' + LF +
    '  Writeln(C);' + LF +
    'end;'), 10, 3, Title));
end;

procedure TSuggestConstTests.NoSuggestionForChangedOrUnclearNames;
const
  Source =
    'procedure P(A: Integer);' + LF +
    'var' + LF +
    '  B, C, D: Integer;' + LF +
    'begin' + LF +
    '  B := 1;' + LF +
    '  B := 2;' + LF +
    '  C := 1;' + LF +
    '  Unbekannt(C);' + LF +
    '  for D := 1 to 2 do' + LF +
    '    Writeln(A, B, C, D);' + LF +
    'end;';
var
  Title: string;
begin
  // Zweimal geschrieben, womöglich geändert, Schleifenzähler, Parameter.
  Assert.AreEqual('', Suggest(Wrap(Source), 7, 3, Title));
  Assert.AreEqual('', Suggest(Wrap(Source), 9, 3, Title));
  Assert.AreEqual('', Suggest(Wrap(Source), 11, 7, Title));
  Assert.AreEqual('', Suggest(Wrap(Source), 3, 12, Title));
  Assert.AreEqual('', Title);
end;

procedure TSuggestConstTests.NoSuggestionInsideBranchOrWithEarlyRead;
const
  Source =
    'procedure P(F: Boolean);' + LF +
    'var' + LF +
    '  A, B: Integer;' + LF +
    'begin' + LF +
    '  if F then' + LF +
    '    A := 1;' + LF +
    '  Writeln(B);' + LF +
    '  B := 2;' + LF +
    '  Writeln(A, B);' + LF +
    'end;';
var
  Title: string;
begin
  Assert.AreEqual('', Suggest(Wrap(Source), 8, 4, Title), 'Zuweisung in einer Verzweigung');
  Assert.AreEqual('', Suggest(Wrap(Source), 10, 2, Title), 'Lesen vor der Zuweisung');
end;

procedure TSuggestConstTests.NoSuggestionWhenNestedRoutineUsesIt;
const
  Source =
    'procedure P;' + LF +
    'var' + LF +
    '  A: Integer;' + LF +
    '  procedure Show;' + LF +
    '  begin' + LF +
    '    Writeln(A);' + LF +
    '  end;' + LF +
    'begin' + LF +
    '  A := 1;' + LF +
    '  Show;' + LF +
    'end;';
var
  Title: string;
begin
  Assert.AreEqual('', Suggest(Wrap(Source), 11, 2, Title));
end;

initialization
  TDUnitX.RegisterTestFixture(TSuggestConstTests);

end.
