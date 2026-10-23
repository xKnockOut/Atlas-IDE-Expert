unit Atlas.Common.Index.Usages.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexUsagesTests = class
  public
    [Test]
    procedure HasFindsNamesIgnoringCase;
    [Test]
    procedure DirectivesSelfAndResultUncounted;
    [Test]
    procedure LookupPresentAndAbsent;
    [Test]
    procedure LookupUnknownWithoutUsages;
    [Test]
    procedure LookupUnknownWithIncludes;
    [Test]
    procedure LookupUnknownOutsideIndex;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Usages;

const
  FileName = 'C:\P\Kunden.pas';
  Text =
    'unit Kunden;'#10 +
    'interface'#10 +
    'procedure Speichern;'#10 +
    'implementation'#10 +
    'uses Werkzeug;'#10 +
    'procedure Speichern;'#10 +
    'begin'#10 +
    '  Rechne(Wert);'#10 +
    'end;'#10 +
    'end.';

function Extracted: TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(Text, FileName, nil, nil, True);
end;

{ TIndexUsagesTests }

procedure TIndexUsagesTests.HasFindsNamesIgnoringCase;
var
  Usages: TArray<TIndexUsage>;
begin
  Usages := Extracted.Usages;
  Assert.IsTrue(TIndexUsages.Has(Usages, 'Rechne'));
  Assert.IsTrue(TIndexUsages.Has(Usages, 'WERT'));
  Assert.IsTrue(TIndexUsages.Has(Usages, 'werkzeug'));
  // Deklarationen zählen nicht als Verwendung.
  Assert.IsFalse(TIndexUsages.Has(Usages, 'Speichern'));
  Assert.IsFalse(TIndexUsages.Has(Usages, 'Fehlt'));
  Assert.IsFalse(TIndexUsages.Has(nil, 'Rechne'));
end;

procedure TIndexUsagesTests.DirectivesSelfAndResultUncounted;
begin
  Assert.IsFalse(TIndexUsages.Counted('override'));
  Assert.IsFalse(TIndexUsages.Counted('Self'));
  Assert.IsFalse(TIndexUsages.Counted('RESULT'));
  Assert.IsTrue(TIndexUsages.Counted('Rechne'));
end;

procedure TIndexUsagesTests.LookupPresentAndAbsent;
var
  Indexed: TUnitIndex;
begin
  Indexed := Extracted;
  Assert.IsTrue(TIndexUsages.Lookup(Indexed, 'Rechne') = TIndexUsageAnswer.Present);
  Assert.IsTrue(TIndexUsages.Lookup(Indexed, 'Fehlt') = TIndexUsageAnswer.Absent);
  // Ein Wort, das der Index nicht zählt, kann er nicht beantworten.
  Assert.IsTrue(TIndexUsages.Lookup(Indexed, 'Self') = TIndexUsageAnswer.Unknown);
end;

procedure TIndexUsagesTests.LookupUnknownWithoutUsages;
var
  Indexed: TUnitIndex;
begin
  Indexed := TIndexExtractor.ExtractText(Text, FileName, nil);
  Assert.IsFalse(Indexed.UsagesIndexed);
  Assert.IsTrue(TIndexUsages.Lookup(Indexed, 'Fehlt') = TIndexUsageAnswer.Unknown);
  Indexed := Extracted;
  Indexed.UsagesOffloaded := True;
  Assert.IsTrue(TIndexUsages.Lookup(Indexed, 'Fehlt') = TIndexUsageAnswer.Unknown);
end;

procedure TIndexUsagesTests.LookupUnknownWithIncludes;
var
  Indexed: TUnitIndex;
begin
  // Bezeichner aus Include-Dateien stehen nicht in den Verwendungen der Unit.
  Indexed := Extracted;
  Indexed.Includes := TArray<string>.Create('C:\P\Teil.inc');
  Assert.IsTrue(TIndexUsages.Lookup(Indexed, 'Fehlt') = TIndexUsageAnswer.Unknown);
end;

procedure TIndexUsagesTests.LookupUnknownOutsideIndex;
var
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(Extracted);
  Assert.IsTrue(TIndexUsages.Lookup(Index, FileName, 'Fehlt') = TIndexUsageAnswer.Absent);
  Assert.IsTrue(TIndexUsages.Lookup(Index, 'C:\P\Andere.pas', 'Fehlt') = TIndexUsageAnswer.Unknown);
  Assert.IsTrue(TIndexUsages.Lookup(nil, FileName, 'Fehlt') = TIndexUsageAnswer.Unknown);
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexUsagesTests);

end.
