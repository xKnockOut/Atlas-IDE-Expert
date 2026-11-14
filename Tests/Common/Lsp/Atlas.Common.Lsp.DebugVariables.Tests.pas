unit Atlas.Common.Lsp.DebugVariables.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.DebugVariables;

type
  [TestFixture]
  TLspDebugVariablesTests = class
  private
    FTree: TSyntaxTree;
    FCalls: TArray<TTextPosition>;
    FNoValue: string;
    function NewVariables: TLspDebugVariables;
    function Autos(ALine, APreviousLine: Integer): string;
    function Locals(ALine: Integer): string;
    function PositionOf(ALine: Integer; const AText: string): TTextPosition;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AssignmentWithCallShowsVariablesOnly;
    [Test]
    procedure StepAddsPreviousStatement;
    [Test]
    procedure PreviousStatementOfOtherRoutineIsIgnored;
    [Test]
    procedure ChainsStopBeforeGetter;
    [Test]
    procedure ForHeaderShowsLoopVariableAndBounds;
    [Test]
    procedure IfShowsConditionNotBranch;
    [Test]
    procedure MethodCallKeepsObjectAndArguments;
    [Test]
    procedure InlineVariableAndInitializer;
    [Test]
    procedure NonValuesAreLeftOut;
    [Test]
    procedure LocalsInSourceOrderWithScope;
    [Test]
    procedure OutsideRoutineIsEmpty;
    [Test]
    procedure JsonShape;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.TreeCache;

const
  cSource =
    'unit Kasse;'#10 +                                                // 0
    'interface'#10 +                                                  // 1
    'type'#10 +                                                       // 2
    '  TKasse = class'#10 +                                           // 3
    '    FSumme: Integer;'#10 +                                       // 4
    '    procedure Buche(const S: string; Anzahl: Integer);'#10 +     // 5
    '    function Gesamt: Integer;'#10 +                              // 6
    '  end;'#10 +                                                     // 7
    'implementation'#10 +                                             // 8
    'function LeseBetrag(const S: string): Integer;'#10 +             // 9
    'begin'#10 +                                                      // 10
    '  Result := Length(S);'#10 +                                     // 11
    'end;'#10 +                                                       // 12
    'procedure TKasse.Buche(const S: string; Anzahl: Integer);'#10 +  // 13
    'var'#10 +                                                        // 14
    '  Betrag, I: Integer;'#10 +                                      // 15
    '  Liste: TArray<Integer>;'#10 +                                  // 16
    'begin'#10 +                                                      // 17
    '  Betrag := LeseBetrag(S);'#10 +                                 // 18
    '  FSumme := FSumme + Betrag * Anzahl;'#10 +                      // 19
    '  for I := 0 to High(Liste) do'#10 +                             // 20
    '    Liste[I] := Kunde.Adresse.Ort.Length + Gesamt;'#10 +         // 21
    '  var Rest := Betrag - 1;'#10 +                                  // 22
    '  if (Rest > 0) and Self.Aktiv then'#10 +                        // 23
    '    Inc(FSumme);'#10 +                                           // 24
    '  Kunde.Speichere(Betrag, nil);'#10 +                            // 25
    'end;'#10 +                                                       // 26
    'initialization'#10 +                                             // 27
    '  Start;'#10 +                                                   // 28
    'end.';

{ TLspDebugVariablesTests }

procedure TLspDebugVariablesTests.Setup;
begin
  FTree := TSyntaxTreeCache.Parse(cSource);
  FCalls := nil;
  FNoValue := '';
end;

procedure TLspDebugVariablesTests.TearDown;
begin
  FreeAndNil(FTree);
  FCalls := nil;
  FNoValue := '';
end;

function TLspDebugVariablesTests.NewVariables: TLspDebugVariables;
var
  mLines: TArray<string>;
begin
  mLines := cSource.Split([#10]);
  Result := TLspDebugVariables.Create(FTree, cSource,
    function(ALine: Integer): TArray<TTextPosition>
    begin
      Result := FCalls;
    end,
    function(const APosition: TTextPosition): Boolean
    var
      mRest: string;
    begin
      // Wert, außer der Name an der Stelle steht in FNoValue.
      mRest := Copy(mLines[APosition.Line], APosition.Character + 1, MaxInt);
      Result := (FNoValue = '') or not mRest.StartsWith(FNoValue);
    end);
end;

function TLspDebugVariablesTests.Autos(ALine, APreviousLine: Integer): string;
var
  mVariables: TLspDebugVariables;
begin
  mVariables := NewVariables;
  try
    Result := string.Join(' | ', mVariables.Autos(ALine, APreviousLine));
  finally
    mVariables.Free;
  end;
end;

function TLspDebugVariablesTests.Locals(ALine: Integer): string;
var
  mVariables: TLspDebugVariables;
begin
  mVariables := NewVariables;
  try
    Result := string.Join(' | ', mVariables.Locals(ALine));
  finally
    mVariables.Free;
  end;
end;

function TLspDebugVariablesTests.PositionOf(ALine: Integer; const AText: string): TTextPosition;
begin
  Result.Line := ALine;
  Result.Character := Pos(AText, cSource.Split([#10])[ALine]) - 1;
end;

procedure TLspDebugVariablesTests.AssignmentWithCallShowsVariablesOnly;
begin
  // Abnahme: Bei „Betrag := LeseBetrag(S);“ zeigt Autos Betrag und S, nicht den Aufruf.
  Assert.AreEqual('Betrag | S', Autos(18, -1));
end;

procedure TLspDebugVariablesTests.StepAddsPreviousStatement;
begin
  // Nach F8: die neue Anweisung zuerst, dann die vorige; jeder Ausdruck einmal.
  Assert.AreEqual('FSumme | Betrag | Anzahl | S', Autos(19, 18));
end;

procedure TLspDebugVariablesTests.PreviousStatementOfOtherRoutineIsIgnored;
begin
  Assert.AreEqual('Betrag | S', Autos(18, 11), 'Rücksprung aus LeseBetrag');
end;

procedure TLspDebugVariablesTests.ChainsStopBeforeGetter;
begin
  // Length (Helfer ohne Klammern) und Gesamt (Funktion ohne Klammern) sind Aufrufe.
  FCalls := [PositionOf(21, 'Length'), PositionOf(21, 'Gesamt')];
  Assert.AreEqual('Liste[I] | I | Kunde.Adresse.Ort', Autos(21, -1));
end;

procedure TLspDebugVariablesTests.ForHeaderShowsLoopVariableAndBounds;
begin
  Assert.AreEqual('I | Liste', Autos(20, -1), 'High(Liste) ist ein Aufruf, Liste nicht');
end;

procedure TLspDebugVariablesTests.IfShowsConditionNotBranch;
begin
  Assert.AreEqual('Rest | Self.Aktiv', Autos(23, -1));
end;

procedure TLspDebugVariablesTests.MethodCallKeepsObjectAndArguments;
begin
  Assert.AreEqual('Kunde | Betrag', Autos(25, -1), 'nil ist kein Wert');
end;

procedure TLspDebugVariablesTests.InlineVariableAndInitializer;
begin
  Assert.AreEqual('Rest | Betrag', Autos(22, -1));
end;

procedure TLspDebugVariablesTests.NonValuesAreLeftOut;
begin
  FCalls := [PositionOf(21, 'Gesamt')];
  FNoValue := 'Kunde';
  Assert.AreEqual('Liste[I] | I', Autos(21, -1), 'Kunde ist hier kein Wert (Typ, Konstante, Unit)');
end;

procedure TLspDebugVariablesTests.LocalsInSourceOrderWithScope;
begin
  Assert.AreEqual('Self | S | Anzahl | Betrag | I | Liste', Locals(18), 'Rest erst ab seiner Zeile');
  Assert.AreEqual('Self | S | Anzahl | Betrag | I | Liste | Rest', Locals(23));
  Assert.AreEqual('S | Result', Locals(11), 'Funktion ohne Self');
end;

procedure TLspDebugVariablesTests.OutsideRoutineIsEmpty;
begin
  Assert.AreEqual('', Autos(28, -1));
  Assert.AreEqual('', Locals(28));
end;

procedure TLspDebugVariablesTests.JsonShape;
var
  mVariables: TLspDebugVariables;
  mJson: TJSONObject;
begin
  mVariables := NewVariables;
  try
    mJson := mVariables.Execute(18, -1);
    try
      Assert.AreEqual('{"format":1,"autos":["Betrag","S"],"locals":["Self","S","Anzahl","Betrag","I","Liste"]}',
        mJson.ToJSON);
    finally
      mJson.Free;
    end;
  finally
    mVariables.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDebugVariablesTests);

end.
