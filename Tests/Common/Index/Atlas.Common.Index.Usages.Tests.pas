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
  cFileName = 'C:\P\Kunden.pas';
  cText =
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
  Result := TIndexExtractor.ExtractText(cText, cFileName, nil, nil, True);
end;

{ TIndexUsagesTests }

procedure TIndexUsagesTests.HasFindsNamesIgnoringCase;
var
  mUsages: TArray<TIndexUsage>;
begin
  mUsages := Extracted.Usages;
  Assert.IsTrue(TIndexUsages.Has(mUsages, 'Rechne'));
  Assert.IsTrue(TIndexUsages.Has(mUsages, 'WERT'));
  Assert.IsTrue(TIndexUsages.Has(mUsages, 'werkzeug'));
  // Deklarationen zählen nicht als Verwendung.
  Assert.IsFalse(TIndexUsages.Has(mUsages, 'Speichern'));
  Assert.IsFalse(TIndexUsages.Has(mUsages, 'Fehlt'));
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
  mIndexed: TUnitIndex;
begin
  mIndexed := Extracted;
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Present, TIndexUsages.Lookup(mIndexed, 'Rechne'));
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Absent, TIndexUsages.Lookup(mIndexed, 'Fehlt'));
  // Ein Wort, das der Index nicht zählt, kann er nicht beantworten.
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Unknown, TIndexUsages.Lookup(mIndexed, 'Self'));
end;

procedure TIndexUsagesTests.LookupUnknownWithoutUsages;
var
  mIndexed: TUnitIndex;
begin
  mIndexed := TIndexExtractor.ExtractText(cText, cFileName, nil);
  Assert.IsFalse(mIndexed.UsagesIndexed);
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Unknown, TIndexUsages.Lookup(mIndexed, 'Fehlt'));
  mIndexed := Extracted;
  mIndexed.UsagesOffloaded := True;
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Unknown, TIndexUsages.Lookup(mIndexed, 'Fehlt'));
end;

procedure TIndexUsagesTests.LookupUnknownWithIncludes;
var
  mIndexed: TUnitIndex;
begin
  // Bezeichner aus Include-Dateien stehen nicht in den Verwendungen der Unit.
  mIndexed := Extracted;
  mIndexed.Includes := TArray<string>.Create('C:\P\Teil.inc');
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Unknown, TIndexUsages.Lookup(mIndexed, 'Fehlt'));
end;

procedure TIndexUsagesTests.LookupUnknownOutsideIndex;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(Extracted);
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Absent, TIndexUsages.Lookup(mIndex, cFileName, 'Fehlt'));
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Unknown, TIndexUsages.Lookup(mIndex, 'C:\P\Andere.pas', 'Fehlt'));
  Assert.AreEqual<TIndexUsageAnswer>(TIndexUsageAnswer.Unknown, TIndexUsages.Lookup(nil, cFileName, 'Fehlt'));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexUsagesTests);

end.
