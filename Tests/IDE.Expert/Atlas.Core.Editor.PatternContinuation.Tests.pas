unit Atlas.Core.Editor.PatternContinuation.Tests;

// Tests für Muster fortsetzen (#671): Zahlenfolgen (auch negativ und
// hexadezimal), Zeichen, nummerierte Bezeichner, Aufzählungswerte, freie
// Strings, Mindestzeilen, abweichende Form, ungleiche Schritte, Ende des
// Aufzählungstyps und Laufzeit bei großen Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPatternContinuationTests = class
  public
    [Test]
    procedure ContinuesNumbers;
    [Test]
    procedure ContinuesNegativeNumbers;
    [Test]
    procedure KeepsHexWidthAndCase;
    [Test]
    procedure ContinuesChars;
    [Test]
    procedure ContinuesCaseBranches;
    [Test]
    procedure ContinuesArrayConstants;
    [Test]
    procedure NumberedIdentifierNeedsExistingName;
    [Test]
    procedure NumberedDeclarationMayBeNew;
    [Test]
    procedure RegisterClassWithExistingName;
    [Test]
    procedure ContinuesLocalEnum;
    [Test]
    procedure NoSuggestionAtEndOfEnum;
    [Test]
    procedure FreeStringsBecomeFields;
    [Test]
    procedure OnlyFreeStringsIsNoPattern;
    [Test]
    procedure NeedsMinLines;
    [Test]
    procedure DifferentShapeIsNoPattern;
    [Test]
    procedure UnevenStepIsNoPattern;
    [Test]
    procedure UnrelatedIdentifiersAreNoPattern;
    [Test]
    procedure OnlyOnEmptyLine;
    [Test]
    procedure UsesSameIndentOnly;
    [Test]
    procedure KeepsSpacingAndComments;
    [Test]
    procedure LocalEnumValuesSkipsParentheses;
    [Test]
    procedure ContainsWordMatchesWholeWords;
    [Test]
    [Category('Benchmark')]
    procedure LargeUnitIsFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Editor.PatternContinuation;

/// <summary>Vorschlag für die letzte (leere) Zeile von AText; '-' ohne Vorschlag.</summary>
function Suggested(const AText: string; AMinLines: Integer; const AEnums: TAtlasEnumLookup;
  const AExists: TAtlasNameExists; out ASuggestion: TAtlasPatternSuggestion): string; overload;
var
  Lines: TArray<string>;
begin
  Result := '-';
  Lines := AText.Split([#10]);
  if TAtlasPatternContinuation.Suggest(Lines, High(Lines), AMinLines, AEnums, AExists, ASuggestion) then
    Result := ASuggestion.Indent + ASuggestion.Text;
end;

function Suggested(const AText: string): string; overload;
var
  Suggestion: TAtlasPatternSuggestion;
begin
  Result := Suggested(AText, TAtlasPatternContinuation.MinLines, nil, nil, Suggestion);
end;

function Suggested(const AText: string; AMinLines: Integer): string; overload;
var
  Suggestion: TAtlasPatternSuggestion;
begin
  Result := Suggested(AText, AMinLines, nil, nil, Suggestion);
end;

function SuggestedWithText(const AText: string): string;
var
  Suggestion: TAtlasPatternSuggestion;
begin
  Result := Suggested(AText, TAtlasPatternContinuation.MinLines,
    function(const AMember: string; ALine, ACharacter: Integer): TArray<string>
    begin
      Result := TAtlasPatternContinuation.LocalEnumValues(AText, AMember);
    end,
    function(const AName: string): Boolean
    begin
      Result := TAtlasPatternContinuation.ContainsWord(AText, AName);
    end, Suggestion);
end;

{ TAtlasPatternContinuationTests }

procedure TAtlasPatternContinuationTests.ContinuesNumbers;
begin
  Assert.AreEqual('  Grid.Cells[0, 3] := ''x'';',
    Suggested('  Grid.Cells[0, 1] := ''x'';'#10'  Grid.Cells[0, 2] := ''x'';'#10));
  Assert.AreEqual('  A[30] := 6;', Suggested('  A[10] := 2;'#10'  A[20] := 4;'#10));
end;

procedure TAtlasPatternContinuationTests.ContinuesNegativeNumbers;
begin
  Assert.AreEqual('  Add(-1);', Suggested('  Add(-3);'#10'  Add(-2);'#10));
  Assert.AreEqual('  Add(-6);', Suggested('  Add(-2);'#10'  Add(-4);'#10));
end;

procedure TAtlasPatternContinuationTests.KeepsHexWidthAndCase;
begin
  Assert.AreEqual('  Mask($0C);', Suggested('  Mask($08);'#10'  Mask($0A);'#10));
  Assert.AreEqual('  Mask($0c);', Suggested('  Mask($08);'#10'  Mask($0a);'#10));
end;

procedure TAtlasPatternContinuationTests.ContinuesChars;
begin
  Assert.AreEqual('  Keys.Add(''C'');', Suggested('  Keys.Add(''A'');'#10'  Keys.Add(''B'');'#10));
end;

procedure TAtlasPatternContinuationTests.ContinuesCaseBranches;
var
  Suggestion: TAtlasPatternSuggestion;
begin
  Assert.AreEqual('    2: Result := '''';', Suggested('    0: Result := ''Null'';'#10 +
    '    1: Result := ''Eins'';'#10, TAtlasPatternContinuation.MinLines, nil, nil, Suggestion));
  Assert.AreEqual(1, Integer(Length(Suggestion.Fields)));
  // Zwischen den Hochkommas: "2: Result := '|';"
  Assert.AreEqual(14, Suggestion.Fields[0]);
  Assert.AreEqual('''', Copy(Suggestion.Text, Suggestion.Fields[0], 1));
end;

procedure TAtlasPatternContinuationTests.ContinuesArrayConstants;
begin
  Assert.AreEqual('    (Id: 3; Name: ''''),', Suggested('    (Id: 1; Name: ''Eins''),'#10 +
    '    (Id: 2; Name: ''Zwei''),'#10));
end;

procedure TAtlasPatternContinuationTests.NumberedIdentifierNeedsExistingName;
const
  Form = 'var Edit1, Edit2, Edit3: TEdit;'#10 +
    '  Edit1.Text := '''';'#10 +
    '  Edit2.Text := '''';'#10;
begin
  Assert.AreEqual('  Edit3.Text := '''';', SuggestedWithText(Form));
  Assert.AreEqual('-', SuggestedWithText('  Edit1.Text := '''';'#10'  Edit2.Text := '''';'#10));
  Assert.AreEqual('-', Suggested(Form));
end;

procedure TAtlasPatternContinuationTests.NumberedDeclarationMayBeNew;
begin
  Assert.AreEqual('    Spalte03: Integer;', Suggested('    Spalte01: Integer;'#10'    Spalte02: Integer;'#10));
  Assert.AreEqual('    Edit3: TEdit;', Suggested('    Edit1: TEdit;'#10'    Edit2: TEdit;'#10));
end;

procedure TAtlasPatternContinuationTests.RegisterClassWithExistingName;
const
  Text = 'type TFoo1 = class end; TFoo2 = class end; TFoo3 = class end;'#10 +
    '  RegisterClass(TFoo1);'#10'  RegisterClass(TFoo2);'#10;
begin
  Assert.AreEqual('  RegisterClass(TFoo3);', SuggestedWithText(Text));
end;

procedure TAtlasPatternContinuationTests.ContinuesLocalEnum;
const
  Text = 'type TAmpel = (Rot, Gelb, Gruen, Aus);'#10 +
    '  Show(Rot);'#10'  Show(Gelb);'#10;
var
  Lookups: Integer;
  Suggestion: TAtlasPatternSuggestion;
begin
  Assert.AreEqual('  Show(Gruen);', SuggestedWithText(Text));
  // Die Stelle des letzten Werts geht an den Nachschlag.
  Lookups := 0;
  Suggested(Text, TAtlasPatternContinuation.MinLines,
    function(const AMember: string; ALine, ACharacter: Integer): TArray<string>
    begin
      Inc(Lookups);
      Assert.AreEqual('Gelb', AMember);
      Assert.AreEqual(2, ALine);
      Assert.AreEqual(7, ACharacter);
      Result := ['Rot', 'Gelb', 'Gruen'];
    end, nil, Suggestion);
  Assert.AreEqual(1, Lookups);
  Assert.AreEqual('Show(Gruen);', Suggestion.Text);
end;

procedure TAtlasPatternContinuationTests.NoSuggestionAtEndOfEnum;
begin
  Assert.AreEqual('-', SuggestedWithText('type TAmpel = (Rot, Gelb, Gruen);'#10 +
    '  Show(Gelb);'#10'  Show(Gruen);'#10));
end;

procedure TAtlasPatternContinuationTests.FreeStringsBecomeFields;
var
  Suggestion: TAtlasPatternSuggestion;
begin
  Assert.AreEqual('  Add(3, '''', '''');', Suggested('  Add(1, ''ab'', ''x'');'#10'  Add(2, ''cd'', ''xy'');'#10,
    TAtlasPatternContinuation.MinLines, nil, nil, Suggestion));
  Assert.AreEqual(2, Integer(Length(Suggestion.Fields)));
  Assert.AreEqual(8, Suggestion.Fields[0]);
  Assert.AreEqual(12, Suggestion.Fields[1]);
end;

procedure TAtlasPatternContinuationTests.OnlyFreeStringsIsNoPattern;
begin
  Assert.AreEqual('-', Suggested('  Log(''Start'');'#10'  Log(''Ende'');'#10));
  Assert.AreEqual('-', Suggested('  Log(1);'#10'  Log(1);'#10));
end;

procedure TAtlasPatternContinuationTests.NeedsMinLines;
const
  Text = '  A[1] := 1;'#10'  A[2] := 2;'#10;
begin
  Assert.AreEqual('  A[3] := 3;', Suggested(Text));
  Assert.AreEqual('-', Suggested(Text, 3));
  Assert.AreEqual('  A[4] := 4;', Suggested('  A[1] := 1;'#10'  A[2] := 2;'#10'  A[3] := 3;'#10, 3));
end;

procedure TAtlasPatternContinuationTests.DifferentShapeIsNoPattern;
begin
  Assert.AreEqual('-', Suggested('  A[1] := 1;'#10'  B := 2;'#10));
  Assert.AreEqual('-', Suggested('  A[1] := 1;'#10'  A[2] := 2 + 1;'#10));
end;

procedure TAtlasPatternContinuationTests.UnevenStepIsNoPattern;
begin
  Assert.AreEqual('-', Suggested('  A[1] := 0;'#10'  A[2] := 0;'#10'  A[4] := 0;'#10));
end;

procedure TAtlasPatternContinuationTests.UnrelatedIdentifiersAreNoPattern;
begin
  Assert.AreEqual('-', Suggested('  Show(Alpha);'#10'  Show(Beta);'#10));
end;

procedure TAtlasPatternContinuationTests.OnlyOnEmptyLine;
begin
  Assert.AreEqual('-', Suggested('  A[1] := 1;'#10'  A[2] := 2;'#10'  x'));
end;

procedure TAtlasPatternContinuationTests.UsesSameIndentOnly;
begin
  // Die Zeile mit anderem Einzug beendet den Lauf, zwei Zeilen genügen trotzdem.
  Assert.AreEqual('  A[3] := 3;', Suggested('    A[0] := 0;'#10'  A[1] := 1;'#10'  A[2] := 2;'#10));
  Assert.AreEqual('-', Suggested('    A[1] := 1;'#10'  A[2] := 2;'#10));
end;

procedure TAtlasPatternContinuationTests.KeepsSpacingAndComments;
begin
  Assert.AreEqual('  A[3]:=3; // gleich', Suggested('  A[1]:=1; // gleich'#10'  A[2]:=2; // gleich'#10));
end;

procedure TAtlasPatternContinuationTests.LocalEnumValuesSkipsParentheses;
var
  Values: TArray<string>;
begin
  Values := TAtlasPatternContinuation.LocalEnumValues('X := (A + B); type TS = (sA = 1, sB, sC);', 'sb');
  Assert.AreEqual(3, Integer(Length(Values)));
  Assert.AreEqual('sC', Values[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasPatternContinuation.LocalEnumValues('F := (A, B);', 'C'))));
end;

procedure TAtlasPatternContinuationTests.ContainsWordMatchesWholeWords;
begin
  Assert.IsTrue(TAtlasPatternContinuation.ContainsWord('var Edit3: TEdit;', 'edit3'));
  Assert.IsFalse(TAtlasPatternContinuation.ContainsWord('var Edit30: TEdit;', 'Edit3'));
  Assert.IsFalse(TAtlasPatternContinuation.ContainsWord('var MyEdit3: TEdit;', 'Edit3'));
end;

procedure TAtlasPatternContinuationTests.LargeUnitIsFast;
var
  Lines: TArray<string>;
  Index: Integer;
  Watch: TStopwatch;
  Suggestion: TAtlasPatternSuggestion;
  Found: Boolean;
begin
  SetLength(Lines, 5001);
  for Index := 0 to 4999 do
    Lines[Index] := Format('  Grid.Cells[%d, %d] := Werte[%d]; // Zeile', [Index mod 1000, Index, Index]);
  Lines[5000] := '';
  Watch := TStopwatch.StartNew;
  Found := TAtlasPatternContinuation.Suggest(Lines, 5000, TAtlasPatternContinuation.MinLines, nil, nil,
    Suggestion);
  Watch.Stop;
  Assert.IsTrue(Found);
  Assert.AreEqual('Grid.Cells[1000, 5000] := Werte[5000]; // Zeile', Suggestion.Text);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 20, Format('%d ms', [Watch.ElapsedMilliseconds]));
  Lines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPatternContinuationTests);

end.
