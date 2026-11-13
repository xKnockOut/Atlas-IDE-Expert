unit Atlas.Common.Index.UsageCounts.Tests;

// Tests für die Zählung der Namen in den Projekt-Units (#2109): Summe über Units, Fortschreibung bei neuer Fassung
// und beim Entfernen, Bibliotheken, ausgelagerte Verwendungen und Speicherbedarf.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TIndexUsageCountsTests = class
  private
    FIndex: ISymbolIndex;
    /// <summary>Legt Datei AFileName mit ABody im Rumpf einer Routine an (Verwendungen erfasst).</summary>
    procedure AddUnit(const AFileName, ABody: string; ALibrary: Boolean = False);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CountsAcrossUnits;
    [Test]
    procedure IgnoresCase;
    [Test]
    procedure NewVersionReplacesCount;
    [Test]
    procedure RemovedFileDropsCount;
    [Test]
    procedure LibraryDoesNotCount;
    [Test]
    procedure WithoutUsagesDoesNotCount;
    [Test]
    procedure OffloadedUsagesKeepCount;
    [Test]
    procedure IdeIndexAsksInner;
    [Test]
    [Category('Benchmark')]
    procedure ManyUnitsStaySmallAndFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.UsageCounts,
  Atlas.Common.Lsp.IdeIndex;

function UnitText(const AName, ABody: string): string;
begin
  Result := 'unit ' + AName + ';'#13#10'interface'#13#10'implementation'#13#10 +
    'procedure Lauf(AListe: TStringList);'#13#10'begin'#13#10 + ABody + #13#10'end;'#13#10'end.';
end;

{ TIndexUsageCountsTests }

procedure TIndexUsageCountsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TIndexUsageCountsTests.TearDown;
begin
  FIndex := nil;
end;

procedure TIndexUsageCountsTests.AddUnit(const AFileName, ABody: string; ALibrary: Boolean);
var
  mUnit: TUnitIndex;
begin
  mUnit := TIndexExtractor.ExtractText(UnitText(ChangeFileExt(ExtractFileName(AFileName), ''), ABody), AFileName,
    nil, nil, True);
  mUnit.Library_ := ALibrary;
  FIndex.AddUnit(mUnit);
end;

procedure TIndexUsageCountsTests.CountsAcrossUnits;
begin
  AddUnit('C:\P\Eins.pas', '  AListe.Add(''a''); AListe.Add(''b''); AListe.Clear;');
  AddUnit('C:\P\Zwei.pas', '  AListe.Add(''c'');');
  Assert.AreEqual(3, FIndex.UsageCount('Add'));
  Assert.AreEqual(1, FIndex.UsageCount('Clear'));
  Assert.AreEqual(0, FIndex.UsageCount('Delete'));
end;

procedure TIndexUsageCountsTests.IgnoresCase;
begin
  AddUnit('C:\P\Eins.pas', '  AListe.add(''a''); AListe.ADD(''b'');');
  Assert.AreEqual(2, FIndex.UsageCount('Add'));
end;

procedure TIndexUsageCountsTests.NewVersionReplacesCount;
begin
  AddUnit('C:\P\Eins.pas', '  AListe.Add(''a''); AListe.Add(''b'');');
  AddUnit('C:\P\Zwei.pas', '  AListe.Add(''c'');');
  AddUnit('C:\P\Eins.pas', '  AListe.Clear;');
  Assert.AreEqual(1, FIndex.UsageCount('Add'));
  Assert.AreEqual(1, FIndex.UsageCount('Clear'));
end;

procedure TIndexUsageCountsTests.RemovedFileDropsCount;
begin
  AddUnit('C:\P\Eins.pas', '  AListe.Add(''a'');');
  AddUnit('C:\P\Zwei.pas', '  AListe.Add(''c'');');
  FIndex.RemoveFile('c:\p\eins.pas');
  Assert.AreEqual(1, FIndex.UsageCount('Add'));
  FIndex.RemoveFile('C:\P\Zwei.pas');
  Assert.AreEqual(0, FIndex.UsageCount('Add'));
end;

procedure TIndexUsageCountsTests.LibraryDoesNotCount;
begin
  AddUnit('C:\Lib\Classes.pas', '  AListe.Add(''a'');', True);
  AddUnit('C:\P\Eins.pas', '  AListe.Add(''c'');');
  Assert.AreEqual(1, FIndex.UsageCount('Add'));
end;

procedure TIndexUsageCountsTests.WithoutUsagesDoesNotCount;
begin
  // index.usages aus: Der Index kennt nur Deklarationen.
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitText('Eins', '  AListe.Add(''a'');'), 'C:\P\Eins.pas', nil));
  Assert.AreEqual(0, FIndex.UsageCount('Add'));
end;

procedure TIndexUsageCountsTests.OffloadedUsagesKeepCount;
begin
  AddUnit('C:\P\Eins.pas', '  AListe.Add(''a''); AListe.Add(''b'');');
  // Kleinstes Budget: Der Index lagert die Verwendungen aus, die Zählung bleibt.
  FIndex.SetBudget(1);
  AddUnit('C:\P\Zwei.pas', '  AListe.Add(''c'');');
  Assert.IsTrue(FIndex.OffloadedCount > 0, 'Verwendungen nicht ausgelagert');
  Assert.AreEqual(3, FIndex.UsageCount('Add'));
end;

procedure TIndexUsageCountsTests.IdeIndexAsksInner;
var
  mIdeUnits, mIde: ISymbolIndex;
begin
  AddUnit('C:\P\Eins.pas', '  AListe.Add(''a'');');
  // Erst in eine Interface-Variable: direkt an den const-Parameter übergeben würde nie freigegeben.
  mIdeUnits := TSymbolIndex.Create;
  mIde := TIdeIndex.Create(FIndex, mIdeUnits);
  Assert.AreEqual(1, mIde.UsageCount('Add'));
end;

procedure TIndexUsageCountsTests.ManyUnitsStaySmallAndFast;
const
  cUnits = 300;
  cNames = 200;
  cLookups = 100000;
var
  mCounts: TIndexUsageCounts;
  mUnit: TUnitIndex;
  mUnitIndex, mName: Integer;
  mWatch: TStopwatch;
  mBytes: Int64;
begin
  // 300 Units mit je 200 verschiedenen Namen, davon 100 in allen Units gleich.
  mCounts := TIndexUsageCounts.Create;
  try
    for mUnitIndex := 1 to cUnits do
    begin
      mUnit := Default(TUnitIndex);
      mUnit.UsagesIndexed := True;
      SetLength(mUnit.Usages, cNames);
      for mName := 0 to cNames - 1 do
      begin
        if mName < cNames div 2 then
        begin
          mUnit.Usages[mName].Name := 'Gemein' + IntToStr(mName);
        end
        else
        begin
          mUnit.Usages[mName].Name := 'Eigen' + IntToStr(mUnitIndex) + '_' + IntToStr(mName);
        end;
        SetLength(mUnit.Usages[mName].Positions, 2);
      end;
      mCounts.Replace('U' + IntToStr(mUnitIndex), mUnit);
    end;
    Assert.AreEqual(2 * cUnits, mCounts.Count('gemein7'));
    Assert.AreEqual(cNames div 2 + cUnits * (cNames div 2), mCounts.NameCount);
    mBytes := mCounts.Bytes;
    // Je verschiedenem Namen ein String samt Eintrag, je Unit und Name acht Byte.
    Assert.IsTrue(mBytes < 4 * 1024 * 1024, Format('%d Byte', [mBytes]));
    mWatch := TStopwatch.StartNew;
    for mName := 1 to cLookups do
    begin
      mCounts.Count('Gemein' + IntToStr(mName mod (cNames div 2)));
    end;
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 1000, Format('%d ms für %d Abfragen',
      [mWatch.ElapsedMilliseconds, cLookups]));
  finally
    mCounts.Free;
  end;
end;

end.
