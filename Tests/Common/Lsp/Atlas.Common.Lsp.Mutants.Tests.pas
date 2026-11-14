unit Atlas.Common.Lsp.Mutants.Tests;

// Befehl atlas.server.mutants (#1460): Mutanten als JSON mit uri, Auswahl nach Routine, Operatoren und Zeilen,
// unbekannter Operator und fehlende URI als Fehler, Zeilen der Routinen für die Prüfsumme.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspMutantsTests = class
  public
    [Test]
    procedure AllMutantsAsJson;
    [Test]
    procedure FiltersByRoutineAndOperator;
    [Test]
    procedure FiltersByLines;
    [Test]
    procedure UnknownOperatorIsError;
    [Test]
    procedure MissingUriIsError;
    [Test]
    procedure RoutineLines;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Mutants;

const
  cUri = 'file:///C:/P/Preise.pas';
  cBreak = #13#10;
  cText = 'unit Preise;' + cBreak + 'interface' + cBreak + 'implementation' + cBreak +
    'function Satz(AMenge: Integer): Integer;' + cBreak + 'begin' + cBreak +
    '  if AMenge >= 100 then' + cBreak + '    Result := 10' + cBreak + '  else' + cBreak + '    Result := 0;' +
    cBreak + 'end;' + cBreak +
    'function Doppelt(A: Integer): Integer;' + cBreak + 'begin' + cBreak + '  Result := A + A;' + cBreak + 'end;' +
    cBreak + 'end.';

function Run(const AArguments: string): TJSONObject;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    Result := TLspMutants.Execute(mArguments,
      function(const AUri: string; out AText: string): Boolean
      begin
        AText := cText;
        Result := AUri = cUri;
      end) as TJSONObject;
  finally
    mArguments.Free;
  end;
end;

function Mutants(AObject: TJSONObject): TJSONArray;
begin
  Result := AObject.GetValue('mutants') as TJSONArray;
end;

function Routines(AObject: TJSONObject): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to Mutants(AObject).Count - 1 do
  begin
    Result := Result + (Mutants(AObject).Items[mIndex] as TJSONObject).GetValue('routine').Value + ';';
  end;
end;

{ TLspMutantsTests }

procedure TLspMutantsTests.AllMutantsAsJson;
var
  mResult: TJSONObject;
  mFirst: TJSONObject;
begin
  mResult := Run('["' + cUri + '"]');
  try
    Assert.AreEqual(cUri, mResult.GetValue('uri').Value);
    Assert.AreEqual(1, (mResult.GetValue('format') as TJSONNumber).AsInt);
    Assert.IsTrue(Mutants(mResult).Count >= 3, 'Satz und Doppelt');
    Assert.AreEqual(Mutants(mResult).Count, (mResult.GetValue('count') as TJSONNumber).AsInt);
    mFirst := Mutants(mResult).Items[0] as TJSONObject;
    Assert.AreEqual('Satz', mFirst.GetValue('routine').Value);
    Assert.AreEqual('>=', mFirst.GetValue('original').Value);
    // Bereich ab 1, Ende hinter dem letzten Zeichen: so wendet das Plugin ihn auf Zeilen an.
    Assert.AreEqual(6, (mFirst.GetValue('line') as TJSONNumber).AsInt);
    Assert.AreEqual(13, (mFirst.GetValue('character') as TJSONNumber).AsInt);
    Assert.AreEqual(15, (mFirst.GetValue('endCharacter') as TJSONNumber).AsInt);
    Assert.IsTrue(Routines(mResult).Contains('Doppelt;'));
  finally
    mResult.Free;
  end;
end;

procedure TLspMutantsTests.FiltersByRoutineAndOperator;
var
  mResult: TJSONObject;
  mMutant: TJSONObject;
begin
  mResult := Run('["' + cUri + '", {"routine": "satz", "operators": ["boundary"]}]');
  try
    Assert.AreEqual(1, Integer(Mutants(mResult).Count));
    mMutant := Mutants(mResult).Items[0] as TJSONObject;
    Assert.AreEqual('boundary', mMutant.GetValue('operator').Value);
    Assert.AreEqual('>', mMutant.GetValue('replacement').Value);
  finally
    mResult.Free;
  end;
end;

procedure TLspMutantsTests.FiltersByLines;
var
  mResult: TJSONObject;
begin
  // Zeile 12 (0-basiert) ist "Result := A + A;" in Doppelt.
  mResult := Run('["' + cUri + '", {"firstLine": 12, "lastLine": 12}]');
  try
    Assert.IsTrue(Mutants(mResult).Count > 0);
    Assert.IsFalse(Routines(mResult).Contains('Satz;'));
  finally
    mResult.Free;
  end;
end;

procedure TLspMutantsTests.UnknownOperatorIsError;
begin
  Assert.WillRaise(
    procedure
    begin
      Run('["' + cUri + '", {"operators": ["gibtsnicht"]}]').Free;
    end, EJsonRpcError);
end;

procedure TLspMutantsTests.MissingUriIsError;
begin
  Assert.WillRaise(
    procedure
    begin
      Run('[]').Free;
    end, EJsonRpcError);
end;

procedure TLspMutantsTests.RoutineLines;
var
  mResult: TJSONObject;
  mRoutines: TJSONArray;
  mRoutine: TJSONObject;
begin
  mResult := Run('["' + cUri + '"]');
  try
    mRoutines := mResult.GetValue('routines') as TJSONArray;
    Assert.AreEqual(2, Integer(mRoutines.Count));
    mRoutine := mRoutines.Items[0] as TJSONObject;
    Assert.AreEqual('Satz', mRoutine.GetValue('name').Value);
    Assert.AreEqual(3, (mRoutine.GetValue('line') as TJSONNumber).AsInt);
    Assert.AreEqual(9, (mRoutine.GetValue('endLine') as TJSONNumber).AsInt);
    mRoutine := mRoutines.Items[1] as TJSONObject;
    Assert.AreEqual('Doppelt', mRoutine.GetValue('name').Value);
    Assert.AreEqual(10, (mRoutine.GetValue('line') as TJSONNumber).AsInt);
  finally
    mResult.Free;
  end;
  // Nur Doppelt gewählt: nur seine Zeilen.
  mResult := Run('["' + cUri + '", {"routine": "Doppelt"}]');
  try
    Assert.AreEqual(1, Integer((mResult.GetValue('routines') as TJSONArray).Count));
  finally
    mResult.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMutantsTests);

end.
