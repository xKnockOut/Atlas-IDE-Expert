unit Atlas.Common.Editing.Providers.Extract.Tests;

// Tests für IEditingExtract (#2054): mit Duplicates samt gleicher Stelle, ohne gleiche Stelle nur die Auswahl mit
// Grund, nicht extrahierbare Zeilen mit Grund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingExtractProviderTests = class
  public
    [Test]
    procedure ExtractsWithEqualPlaces;
    [Test]
    procedure FallsBackToSelectionWithReason;
    [Test]
    procedure RefusesPartialStatementWithReason;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract.Extract,
  Atlas.Common.Editing.Composition;

const
  cSource = 'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TParser = class'#10 +
    '  private'#10 +
    '    FCount: Integer;'#10 +
    '  public'#10 +
    '    procedure A(AValue: Integer);'#10 +
    '    procedure B(AValue: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TParser.A(AValue: Integer);'#10 +
    'begin'#10 +
    '  FCount := FCount + AValue;'#10 +
    '  Writeln(FCount);'#10 +
    'end;'#10 +
    'procedure TParser.B(AValue: Integer);'#10 +
    'begin'#10 +
    '  FCount := FCount + AValue;'#10 +
    '  Writeln(FCount);'#10 +
    'end;'#10 +
    'end.'#10;

function Wish(ADuplicates: Boolean): TEditingExtractWish;
begin
  Result := Default(TEditingExtractWish);
  Result.MethodName := 'Add';
  Result.Duplicates := ADuplicates;
  Result.InlineVar := True;
  Result.Style := TFormatStyle.Default;
end;

{ TEditingExtractProviderTests }

procedure TEditingExtractProviderTests.ExtractsWithEqualPlaces;
var
  mResult: TEditingExtractResult;
begin
  mResult := TEditingComposition.Extract.ExtractMethod(cSource, TTextRange.Create(13, 0, 14, 17), Wish(True));
  Assert.IsTrue(mResult.Extracted, mResult.Reason);
  Assert.AreEqual('', mResult.DuplicatesReason);
  Assert.AreEqual(1, Integer(Length(mResult.Action.Choices)));
  Assert.IsTrue(Length(mResult.Action.Edits) > 0);
end;

procedure TEditingExtractProviderTests.FallsBackToSelectionWithReason;
var
  mSource: string;
  mResult: TEditingExtractResult;
begin
  // B tut etwas anderes: keine gleiche Stelle, die Aktion gilt nur der Auswahl, mit Grund.
  mSource := StringReplace(cSource, '  FCount := FCount + AValue;'#10'  Writeln(FCount);'#10'end;'#10'end.',
    '  FCount := 0;'#10'end;'#10'end.', []);
  mResult := TEditingComposition.Extract.ExtractMethod(mSource, TTextRange.Create(13, 0, 14, 17), Wish(True));
  Assert.IsTrue(mResult.Extracted, mResult.Reason);
  Assert.AreEqual(0, Integer(Length(mResult.Action.Choices)));
  Assert.AreNotEqual('', mResult.DuplicatesReason);
end;

procedure TEditingExtractProviderTests.RefusesPartialStatementWithReason;
var
  mResult: TEditingExtractResult;
begin
  mResult := TEditingComposition.Extract.ExtractMethod(cSource, TTextRange.Create(0, 0, 1, 9), Wish(False));
  Assert.IsFalse(mResult.Extracted);
  Assert.AreNotEqual('', mResult.Reason);
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingExtractProviderTests);

end.
