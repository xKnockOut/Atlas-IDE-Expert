unit Atlas.Core.Debug.ReturnValues.Tests;

// Tests für die Rückgabewerte (#844): end-Zeile und Art der Routine um eine Zeile, die beobachteten Funktionen der
// Aufrufe einer Zeile, Anzeige am Zeilenende und Verlauf.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.StepInto,
  Atlas.Core.Debug.ReturnValues;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasReturnValuesTests = class
  private
    FValues: TAtlasReturnValues;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FunctionAtFindsEndLine;
    [Test]
    procedure ProcedureIsNoFunction;
    [Test]
    procedure NestedFunctionIsInnermost;
    [Test]
    procedure ClassFunctionAndOperatorAreFunctions;
    [Test]
    procedure LocalRoutinesInsideLocalFunction;
    [Test]
    procedure WatchesOwnFunctionsInCallOrder;
    [Test]
    procedure LineTextShowsAllInReturnOrder;
    [Test]
    procedure BeginStepHidesButKeepsHistory;
    [Test]
    procedure ShowWithoutResultsShowsNothing;
    [Test]
    procedure HistoryKeepsLatestTwenty;
    [Test]
    procedure HistoryLineNamesPlaceAndTime;
  end;

implementation

uses
  System.SysUtils;

const
  cPreise =
    'unit Preise;' + #10 +                                     // 0
    'interface' + #10 +                                        // 1
    'type' + #10 +                                             // 2
    '  TRechner = class' + #10 +                               // 3
    '    function Netto(A: Double): Double;' + #10 +           // 4
    '  end;' + #10 +                                           // 5
    'implementation' + #10 +                                   // 6
    'function BerechneNetto(A: Double): Double;' + #10 +       // 7
    'begin' + #10 +                                            // 8
    '  if A < 0 then' + #10 +                                  // 9
    '    Exit(0);' + #10 +                                     // 10
    '  Result := A / 1.19;' + #10 +                            // 11
    'end;' + #10 +                                             // 12
    '' + #10 +                                                 // 13
    'procedure Melden;' + #10 +                                // 14
    'begin' + #10 +                                            // 15
    'end;' + #10 +                                             // 16
    '' + #10 +                                                 // 17
    'function TRechner.Netto(A: Double): Double;' + #10 +      // 18
    '' + #10 +                                                 // 19
    '  function Runden(B: Double): Double;' + #10 +            // 20
    '  begin' + #10 +                                          // 21
    '    Result := B;' + #10 +                                 // 22
    '  end;' + #10 +                                           // 23
    '' + #10 +                                                 // 24
    'begin' + #10 +                                            // 25
    '  Result := Runden(A);' + #10 +                           // 26
    'end;' + #10 +                                             // 27
    '' + #10 +                                                 // 28
    'end.';                                                    // 29

  cBetrag =
    'unit Betrag;' + #10 +                                     // 0
    'interface' + #10 +                                        // 1
    'type' + #10 +                                             // 2
    '  TBetrag = record' + #10 +                               // 3
    '    Wert: Integer;' + #10 +                               // 4
    '    class operator Add(A, B: TBetrag): TBetrag;' + #10 +  // 5
    '    class function Null: TBetrag; static;' + #10 +        // 6
    '  end;' + #10 +                                           // 7
    'implementation' + #10 +                                   // 8
    'class operator TBetrag.Add(A, B: TBetrag): TBetrag;' + #10 + // 9
    'begin' + #10 +                                            // 10
    '  Result.Wert := A.Wert + B.Wert;' + #10 +                // 11
    'end;' + #10 +                                             // 12
    '' + #10 +                                                 // 13
    'class function TBetrag.Null: TBetrag;' + #10 +            // 14
    'begin' + #10 +                                            // 15
    '  Result.Wert := 0;' + #10 +                              // 16
    'end;' + #10 +                                             // 17
    '' + #10 +                                                 // 18
    'end.';                                                    // 19

  cAussen =
    'unit Aussen;' + #10 +                                     // 0
    'implementation' + #10 +                                   // 1
    'function Aussen(A: Integer): Integer;' + #10 +            // 2
    'type' + #10 +                                             // 3
    '  TF = function(X: Integer): Integer;' + #10 +            // 4
    'var' + #10 +                                              // 5
    '  F: TF;' + #10 +                                         // 6
    '  function Mitte(B: Integer): Integer;' + #10 +           // 7
    '    procedure Innen;' + #10 +                             // 8
    '    begin' + #10 +                                        // 9
    '    end;' + #10 +                                         // 10
    '  begin' + #10 +                                          // 11
    '    Innen;' + #10 +                                       // 12
    '    Result := B;' + #10 +                                 // 13
    '  end;' + #10 +                                           // 14
    'begin' + #10 +                                            // 15
    '  case A of' + #10 +                                      // 16
    '    0: Result := Mitte(A);' + #10 +                       // 17
    '  else' + #10 +                                           // 18
    '    Result := 1;' + #10 +                                 // 19
    '  end;' + #10 +                                           // 20
    'end;' + #10 +                                             // 21
    '' + #10 +                                                 // 22
    'end.';                                                    // 23

function Watch(const AName, AFileName: string; AEndLine: Integer): TAtlasReturnWatch;
begin
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.EndLine := AEndLine;
end;

function Call(const AName, AFileName: string; ALine: Integer): TAtlasStepCall;
var
  mTarget: TAtlasStepTarget;
begin
  Result := Default(TAtlasStepCall);
  Result.Name := AName;
  mTarget := Default(TAtlasStepTarget);
  mTarget.Name := AName;
  mTarget.FileName := AFileName;
  mTarget.Line := ALine;
  SetLength(Result.Targets, 1);
  Result.Targets[0] := mTarget;
end;

{ TAtlasReturnValuesTests }

procedure TAtlasReturnValuesTests.Setup;
begin
  FValues := TAtlasReturnValues.Create;
end;

procedure TAtlasReturnValuesTests.TearDown;
begin
  FreeAndNil(FValues);
end;

procedure TAtlasReturnValuesTests.FunctionAtFindsEndLine;
var
  mWatch: TAtlasReturnWatch;
begin
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cPreise, 'Preise.pas', 8, mWatch));
  Assert.AreEqual('BerechneNetto', mWatch.Name);
  Assert.AreEqual('Preise.pas', mWatch.FileName);
  Assert.AreEqual(12, mWatch.EndLine);
  // Auch aus der Mitte des Rumpfs.
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cPreise, 'Preise.pas', 10, mWatch));
  Assert.AreEqual(12, mWatch.EndLine);
  // Außerhalb jeder Routine.
  Assert.IsFalse(TAtlasReturnValues.FunctionAt(cPreise, 'Preise.pas', 13, mWatch));
  Assert.AreEqual(-1, mWatch.EndLine);
end;

procedure TAtlasReturnValuesTests.ProcedureIsNoFunction;
var
  mWatch: TAtlasReturnWatch;
begin
  Assert.IsFalse(TAtlasReturnValues.FunctionAt(cPreise, 'Preise.pas', 15, mWatch));
end;

procedure TAtlasReturnValuesTests.NestedFunctionIsInnermost;
var
  mWatch: TAtlasReturnWatch;
begin
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cPreise, 'Preise.pas', 21, mWatch));
  Assert.AreEqual('Runden', mWatch.Name);
  Assert.AreEqual(23, mWatch.EndLine);
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cPreise, 'Preise.pas', 25, mWatch));
  Assert.AreEqual('Netto', mWatch.Name);
  Assert.AreEqual(27, mWatch.EndLine);
end;

procedure TAtlasReturnValuesTests.ClassFunctionAndOperatorAreFunctions;
var
  mWatch: TAtlasReturnWatch;
begin
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cBetrag, 'Betrag.pas', 10, mWatch));
  Assert.AreEqual('Add', mWatch.Name);
  Assert.AreEqual(12, mWatch.EndLine);
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cBetrag, 'Betrag.pas', 15, mWatch));
  Assert.AreEqual('Null', mWatch.Name);
  Assert.AreEqual(17, mWatch.EndLine);
end;

procedure TAtlasReturnValuesTests.LocalRoutinesInsideLocalFunction;
var
  mWatch: TAtlasReturnWatch;
begin
  // Lokale Prozedur in einer lokalen Funktion: keine Funktion.
  Assert.IsFalse(TAtlasReturnValues.FunctionAt(cAussen, 'Aussen.pas', 9, mWatch));
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cAussen, 'Aussen.pas', 11, mWatch));
  Assert.AreEqual('Mitte', mWatch.Name);
  Assert.AreEqual(14, mWatch.EndLine);
  // Der Anweisungsteil der umgebenden Funktion endet nach dem case.
  Assert.IsTrue(TAtlasReturnValues.FunctionAt(cAussen, 'Aussen.pas', 17, mWatch));
  Assert.AreEqual('Aussen', mWatch.Name);
  Assert.AreEqual(21, mWatch.EndLine);
  // Typ- und Variablenteil gehören zu keinem Anweisungsteil.
  Assert.IsFalse(TAtlasReturnValues.FunctionAt(cAussen, 'Aussen.pas', 4, mWatch));
end;

procedure TAtlasReturnValuesTests.WatchesOwnFunctionsInCallOrder;
var
  mAnswer: TAtlasStepAnswer;
  mWatches: TArray<TAtlasReturnWatch>;
begin
  mAnswer := Default(TAtlasStepAnswer);
  // Zeile „Summe := Rechner.Netto(BerechneNetto(X)); Melden; Format(...); BerechneNetto(Y)“.
  mAnswer.Calls := TArray<TAtlasStepCall>.Create(Call('Netto', 'C:\P\Preise.pas', 25),
    Call('BerechneNetto', 'C:\P\Preise.pas', 8), Call('Melden', 'C:\P\Preise.pas', 15),
    Call('Format', 'C:\Bds\System.SysUtils.pas', 100), Call('BerechneNetto', 'C:\P\Preise.pas', 8));
  mWatches := TAtlasReturnValues.Watches(mAnswer,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cPreise;
      Result := SameText(AFileName, 'C:\P\Preise.pas');
    end,
    function(const AFileName: string): Boolean
    begin
      Result := not AFileName.StartsWith('C:\Bds\');
    end);
  Assert.AreEqual(2, Integer(Length(mWatches)));
  Assert.AreEqual('Netto', mWatches[0].Name);
  Assert.AreEqual(27, mWatches[0].EndLine);
  Assert.AreEqual('BerechneNetto', mWatches[1].Name);
  Assert.AreEqual(12, mWatches[1].EndLine);
  Assert.AreEqual('C:\P\Preise.pas', mWatches[1].FileName);
end;

procedure TAtlasReturnValuesTests.LineTextShowsAllInReturnOrder;
begin
  FValues.BeginStep;
  FValues.Add(Watch('IstRabattfaehig', 'Preise.pas', 30), 'False', Now);
  FValues.Add(Watch('BerechneNetto', 'Preise.pas', 12), '109,16', Now);
  Assert.IsTrue(FValues.Show('Kasse.pas', 40));
  Assert.AreEqual('→ IstRabattfaehig = False   → BerechneNetto = 109,16', FValues.LineText('kasse.pas', 40));
  Assert.AreEqual('', FValues.LineText('Kasse.pas', 41));
  Assert.AreEqual('', FValues.LineText('Preise.pas', 40));
  FValues.Hide;
  Assert.AreEqual('', FValues.LineText('Kasse.pas', 40));
end;

procedure TAtlasReturnValuesTests.BeginStepHidesButKeepsHistory;
var
  mFileName: string;
  mLine: Integer;
begin
  FValues.Add(Watch('BerechneNetto', 'Preise.pas', 12), '109,16', Now);
  FValues.Show('Kasse.pas', 40);
  Assert.IsTrue(FValues.Shown(mFileName, mLine));
  Assert.AreEqual(40, mLine);
  FValues.BeginStep;
  Assert.IsFalse(FValues.Shown(mFileName, mLine));
  Assert.AreEqual('', FValues.LineText('Kasse.pas', 40));
  Assert.AreEqual(1, FValues.Count);
  FValues.Clear;
  Assert.AreEqual(0, FValues.Count);
end;

procedure TAtlasReturnValuesTests.ShowWithoutResultsShowsNothing;
begin
  FValues.BeginStep;
  Assert.IsFalse(FValues.Show('Kasse.pas', 40));
  Assert.AreEqual('', FValues.LineText('Kasse.pas', 40));
end;

procedure TAtlasReturnValuesTests.HistoryKeepsLatestTwenty;
var
  mIndex: Integer;
begin
  for mIndex := 0 to 24 do
  begin
    FValues.Add(Watch('F' + IntToStr(mIndex), 'Preise.pas', mIndex), IntToStr(mIndex), Now);
  end;
  Assert.AreEqual(TAtlasReturnValues.cMaxEntries, FValues.Count);
  Assert.AreEqual('F24', FValues.Entries[0].Name);
  Assert.AreEqual('F5', FValues.Entries[TAtlasReturnValues.cMaxEntries - 1].Name);
end;

procedure TAtlasReturnValuesTests.HistoryLineNamesPlaceAndTime;
var
  mEntry: TAtlasReturnEntry;
begin
  mEntry := Default(TAtlasReturnEntry);
  mEntry.Name := 'BerechneNetto';
  mEntry.Value := '109,16';
  mEntry.FileName := 'C:\P\Preise.pas';
  mEntry.EndLine := 12;
  mEntry.Time := EncodeTime(14, 3, 12, 0);
  Assert.AreEqual('BerechneNetto = 109,16   Preise.pas 13   14:03:12', TAtlasReturnValues.HistoryLine(mEntry));
  Assert.AreEqual('→ BerechneNetto = 109,16', TAtlasReturnValues.Note(mEntry));
end;

end.
