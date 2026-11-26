unit Editing.Providers.BoundaryCases.Tests;

// Tests für TEditingBoundaryCasesProvider: Anfrage geht an den Bericht, ohne Routine False.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingBoundaryCasesProviderTests = class
  public
    [Test]
    procedure ReportsRoutineByName;
    [Test]
    procedure FalseWithoutRoutine;
  end;

implementation

uses
  Editing.Contract.BoundaryCases,
  Editing.Providers.BoundaryCases;

const
  cText = 'unit Rabatt;'#13#10'interface'#13#10'implementation'#13#10 +
    'function Rabatt(ABetrag: Integer): Integer;'#13#10'begin'#13#10'  Result := 0;'#13#10 +
    '  if ABetrag >= 100 then'#13#10'    Result := 5;'#13#10'end;'#13#10'end.';

function Request(const ARoutine: string; ALine: Integer): TEditingBoundaryRequest;
begin
  Result := Default(TEditingBoundaryRequest);
  Result.Text := cText;
  Result.FileName := 'Rabatt.pas';
  Result.Line := ALine;
  Result.Routine := ARoutine;
end;

{ TEditingBoundaryCasesProviderTests }

procedure TEditingBoundaryCasesProviderTests.ReportsRoutineByName;
var
  mBoundaryCases: IEditingBoundaryCases;
  mReport: string;
begin
  mBoundaryCases := TEditingBoundaryCasesProvider.Create;
  Assert.IsTrue(mBoundaryCases.Report(Request('Rabatt', -1), mReport));
  Assert.Contains(mReport, 'Rabatt.pas');
  Assert.Contains(mReport, '| ABetrag | `100` |');
end;

procedure TEditingBoundaryCasesProviderTests.FalseWithoutRoutine;
var
  mBoundaryCases: IEditingBoundaryCases;
  mReport: string;
begin
  mBoundaryCases := TEditingBoundaryCasesProvider.Create;
  Assert.IsFalse(mBoundaryCases.Report(Request('Fehlt', -1), mReport));
  Assert.IsFalse(mBoundaryCases.Report(Request('', 0), mReport));
end;

end.
