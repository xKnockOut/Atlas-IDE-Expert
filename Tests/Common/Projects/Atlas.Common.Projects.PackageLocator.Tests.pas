unit Atlas.Common.Projects.PackageLocator.Tests;

// Tests der Package-Suche (#46): .dpk vor .dcp, Reihenfolge der Ordner,
// Unit-Namen im .dcp nur als ganzer Name, unbekannte Packages, Zwischenspeicher.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPackageLocatorTests = class
  public
    /// <summary>Datei- und Zeitfunktionen legen beim ersten Aufruf Objekte an, die bis Prozessende leben (z. B.
    /// die Zeitzone); der Leckmonitor zählte sie sonst im ersten Test mit .dcp auf der Platte.</summary>
    [SetupFixture]
    procedure WarmUpFileTimes;
    [Test]
    procedure SourceAnswersFromContains;
    [Test]
    procedure CompiledPackageIsScanned;
    [Test]
    procedure SourceWinsOverCompiled;
    [Test]
    procedure UnknownPackage;
    [Test]
    procedure CompiledNamesAreWholeWords;
    [Test]
    procedure ResultsAreCached;
    /// <summary>Die Projektprüfung fragt je Unit dieselben Namen: ein .dcp nur beim ersten Mal durchsuchen.</summary>
    [Test]
    procedure CompiledAnswersAreCached;
    [Test]
    procedure ContainedFilesAreAbsolute;
    [Test]
    procedure RequiredFilesFollowRequires;
    [Test]
    procedure RequiresComeFromSource;
    /// <summary>Speicher (Rückmeldung 01.11.2026): Jeder Arbeitsbereich und jeder Indexstart hat einen eigenen
    /// Locator; dieselbe .dcp liegt trotzdem nur einmal im Speicher.</summary>
    [Test]
    procedure CompiledFilesAreShared;
    /// <summary>Eine neu übersetzte .dcp (anderer Zeitstempel oder Größe) wird neu gelesen.</summary>
    [Test]
    procedure ChangedCompiledFileIsReread;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Projects.PackageLocator;

const
  cBasisDpk =
    'package Basis;'#10 +
    'requires rtl;'#10 +
    'contains'#10 +
    '  uBasis in ''uBasis.pas'','#10 +
    '  uHilfe;'#10 +
    'end.';

function Files(const AFiles: TArray<TPair<string, TBytes>>; const AReads: TList<string>): TPackageReadFile;
var
  mMap: TArray<TPair<string, TBytes>>;
begin
  mMap := AFiles;
  Result :=
    function(const AFileName: string; out AData: TBytes): Boolean
    var
      Item: TPair<string, TBytes>;
    begin
      if AReads <> nil then
      begin
        AReads.Add(AFileName);
      end;
      for Item in mMap do
      begin
        if SameText(Item.Key, AFileName) then
        begin
          AData := Item.Value;
          Exit(True);
        end;
      end;
      AData := nil;
      Result := False;
    end;
end;

function Entry(const AFileName, AText: string): TPair<string, TBytes>;
begin
  Result := TPair<string, TBytes>.Create(AFileName, TEncoding.UTF8.GetBytes(AText));
end;

function Dcp(const ANames: array of string): string;
var
  mName: string;
begin
  // Wie im .dcp: Namen als ShortString mit Längenbyte zwischen Binärdaten.
  Result := 'PKX0'#0#1;
  for mName in ANames do
  begin
    Result := Result + Chr(Length(mName)) + mName + #0#2;
  end;
end;

{ TPackageLocatorTests }

procedure TPackageLocatorTests.SourceAnswersFromContains;
var
  mLocator: TPackageLocator;
  mContains: Boolean;
  mFileName: string;
  mSource: TPackageSource;
begin
  mLocator := TPackageLocator.Create(['A', 'B'], Files([Entry(TPath.Combine('B', 'Basis.dpk'), cBasisDpk)], nil));
  try
    Assert.IsTrue(mLocator.Provides('Basis', 'UBASIS', mContains));
    Assert.IsTrue(mContains);
    Assert.IsTrue(mLocator.Provides('basis', 'uHilfe', mContains));
    Assert.IsTrue(mContains);
    Assert.IsTrue(mLocator.Provides('Basis', 'uFremd', mContains));
    Assert.IsFalse(mContains);
    Assert.IsTrue(mLocator.FindSource('Basis', mFileName, mSource));
    Assert.AreEqual(TPath.Combine('B', 'Basis.dpk'), mFileName);
    Assert.AreEqual(2, Integer(Length(mSource.Contains)));
  finally
    mLocator.Free;
  end;
end;

procedure TPackageLocatorTests.CompiledPackageIsScanned;
var
  mLocator: TPackageLocator;
  mContains: Boolean;
  mFileName: string;
  mSource: TPackageSource;
begin
  mLocator := TPackageLocator.Create(['Lib'],
    Files([Entry(TPath.Combine('Lib', 'rtl.dcp'), Dcp(['System.Classes', 'System.SysUtils']))], nil));
  try
    Assert.IsTrue(mLocator.Provides('rtl', 'system.classes', mContains));
    Assert.IsTrue(mContains);
    Assert.IsTrue(mLocator.Provides('rtl', 'Vcl.Forms', mContains));
    Assert.IsFalse(mContains);
    // Nur übersetzt: keine Quelle.
    Assert.IsFalse(mLocator.FindSource('rtl', mFileName, mSource));
  finally
    mLocator.Free;
  end;
end;

procedure TPackageLocatorTests.SourceWinsOverCompiled;
var
  mLocator: TPackageLocator;
  mContains: Boolean;
begin
  mLocator := TPackageLocator.Create(['A', 'B'], Files([Entry(TPath.Combine('A', 'Basis.dcp'), Dcp(['uAlt'])),
    Entry(TPath.Combine('B', 'Basis.dpk'), cBasisDpk)], nil));
  try
    Assert.IsTrue(mLocator.Provides('Basis', 'uAlt', mContains));
    Assert.IsFalse(mContains);
  finally
    mLocator.Free;
  end;
end;

procedure TPackageLocatorTests.UnknownPackage;
var
  mLocator: TPackageLocator;
  mContains: Boolean;
begin
  mLocator := TPackageLocator.Create(['A'], Files([Entry(TPath.Combine('A', 'Kaputt.dpk'), 'unit Kaputt;')], nil));
  try
    Assert.IsFalse(mLocator.Provides('Fehlt', 'uBasis', mContains));
    Assert.IsFalse(mContains);
    // Eine .dpk, die kein Package ist, zählt nicht.
    Assert.IsFalse(mLocator.Provides('Kaputt', 'Kaputt', mContains));
  finally
    mLocator.Free;
  end;
end;

procedure TPackageLocatorTests.CompiledNamesAreWholeWords;
var
  mData: TBytes;
begin
  mData := TEncoding.ASCII.GetBytes(Dcp(['System.Classes', 'uBasisX']));
  Assert.IsTrue(TPackageLocator.CompiledContains(mData, 'System.Classes'));
  Assert.IsFalse(TPackageLocator.CompiledContains(mData, 'Classes'));
  Assert.IsFalse(TPackageLocator.CompiledContains(mData, 'uBasis'));
  Assert.IsTrue(TPackageLocator.CompiledContains(mData, 'UBASISX'));
  Assert.IsFalse(TPackageLocator.CompiledContains(mData, ''));
end;

procedure TPackageLocatorTests.ResultsAreCached;
var
  mLocator: TPackageLocator;
  mReads: TList<string>;
  mContains: Boolean;
  mCount: Integer;
begin
  mReads := TList<string>.Create;
  mLocator := TPackageLocator.Create(['A'], Files([Entry(TPath.Combine('A', 'Basis.dpk'), cBasisDpk)], mReads));
  try
    mLocator.Provides('Basis', 'uBasis', mContains);
    mCount := mReads.Count;
    mLocator.Provides('BASIS', 'uHilfe', mContains);
    mLocator.Provides('Fehlt', 'uHilfe', mContains);
    Assert.AreEqual(mCount + 2, Integer(mReads.Count));
    mLocator.Provides('Fehlt', 'uBasis', mContains);
    Assert.AreEqual(mCount + 2, Integer(mReads.Count));
  finally
    mLocator.Free;
    mReads.Free;
  end;
end;

procedure TPackageLocatorTests.CompiledAnswersAreCached;
const
  // Wie rtl.dcp: mehrere MB, die gesuchten Namen am Ende.
  cSize = 4 * 1024 * 1024;
  cCalls = 500;
var
  mLocator: TPackageLocator;
  mData: TBytes;
  mTail: TBytes;
  mContains: Boolean;
  mIndex: Integer;
  mWatch: TStopwatch;
begin
  mTail := TEncoding.ASCII.GetBytes(Dcp(['System.Classes']));
  SetLength(mData, cSize);
  FillChar(mData[0], cSize, 1);
  Move(mTail[0], mData[cSize - Length(mTail)], Length(mTail));
  mLocator := TPackageLocator.Create(['Lib'], Files([TPair<string, TBytes>.Create(TPath.Combine('Lib', 'rtl.dcp'),
    mData)], nil));
  try
    mWatch := TStopwatch.StartNew;
    for mIndex := 1 to cCalls do
    begin
      Assert.IsTrue(mLocator.Provides('rtl', 'System.Classes', mContains));
      Assert.IsTrue(mContains);
      Assert.IsTrue(mLocator.Provides('RTL', 'vcl.forms', mContains));
      Assert.IsFalse(mContains);
    end;
    // Ohne Cache 2 × 500 Läufe über 4 MB (4 GB), mehrere Sekunden; mit Cache zwei Läufe.
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 1000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  finally
    mLocator.Free;
  end;
end;

procedure TPackageLocatorTests.ContainedFilesAreAbsolute;
var
  mFound: TArray<string>;
  mFolder: string;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'Basis');
  mFound := TPackageLocator.ContainedFiles(TPath.Combine(mFolder, 'Basis.dpk'), TPackageReader.Read(cBasisDpk));
  // uHilfe ohne in '…' findet der Compiler über die Suchpfade.
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(ExpandFileName(TPath.Combine(mFolder, 'uBasis.pas')), mFound[0]);
end;

procedure TPackageLocatorTests.RequiredFilesFollowRequires;
const
  cKernDpk = 'package Kern;'#10'contains'#10'  uKern in ''uKern.pas'';'#10'end.';
  cAppDpk = 'package App;'#10'requires Basis, rtl;'#10'contains'#10'  uApp in ''uApp.pas'';'#10'end.';
  cBasisMitKern = 'package Basis;'#10'requires Kern, App;'#10'contains'#10'  uBasis in ''uBasis.pas'';'#10'end.';
var
  mLocator: TPackageLocator;
  mFound: TArray<string>;
  mFolder: string;
begin
  mFolder := TPath.GetTempPath;
  mLocator := TPackageLocator.Create([mFolder], Files([Entry(TPath.Combine(mFolder, 'Basis.dpk'), cBasisMitKern),
    Entry(TPath.Combine(mFolder, 'Kern.dpk'), cKernDpk)], nil));
  try
    // App selbst zählt nicht mit, auch wenn Basis es wieder verlangt; rtl hat keine Quelle.
    mFound := mLocator.RequiredFiles(TPackageReader.Read(cAppDpk));
    Assert.AreEqual(2, Integer(Length(mFound)), String.Join(';', mFound));
    Assert.AreEqual(ExpandFileName(TPath.Combine(mFolder, 'uBasis.pas')), mFound[0]);
    Assert.AreEqual(ExpandFileName(TPath.Combine(mFolder, 'uKern.pas')), mFound[1]);
  finally
    mLocator.Free;
  end;
end;

procedure TPackageLocatorTests.RequiresComeFromSource;
const
  cMitRequires = 'package Basis;'#10'requires rtl, Kern;'#10'contains'#10'  uBasis in ''uBasis.pas'';'#10'end.';
var
  mLocator: TPackageLocator;
  mFound: TArray<string>;
begin
  mLocator := TPackageLocator.Create(['A'], Files([Entry(TPath.Combine('A', 'Basis.dpk'), cMitRequires),
    Entry(TPath.Combine('A', 'Kern.dcp'), Dcp(['uKern']))], nil));
  try
    mFound := mLocator.Requires('basis');
    Assert.AreEqual('rtl;Kern', String.Join(';', mFound));
    // Ein .dcp nennt seine requires nicht, ein unbekanntes Package hat keine.
    Assert.AreEqual(0, Integer(Length(mLocator.Requires('Kern'))));
    Assert.AreEqual(0, Integer(Length(mLocator.Requires('Fehlt'))));
  finally
    mLocator.Free;
  end;
end;

procedure TPackageLocatorTests.WarmUpFileTimes;
var
  mFolder: string;
  mLocator: TPackageLocator;
  mContains: Boolean;
begin
  // Einmal der ganze Weg der Tests mit .dcp auf der Platte (Ordner, Zeitstempel, geteiltes Lesen).
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDcpWarmUp' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mFolder);
  TFile.WriteAllBytes(TPath.Combine(mFolder, 'Warm.dcp'), TEncoding.ASCII.GetBytes('WARM'));
  mLocator := TPackageLocator.Create([mFolder]);
  try
    mLocator.Provides('Warm', 'Warm', mContains);
  finally
    mLocator.Free;
    TPackageCompiledFiles.Clear;
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TPackageLocatorTests.CompiledFilesAreShared;
var
  mFolder: string;
  mFirst, mSecond: TPackageLocator;
  mContains: Boolean;
  mBefore: Int64;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDcpShared' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mFolder);
  TFile.WriteAllBytes(TPath.Combine(mFolder, 'Geteilt.dcp'), TEncoding.ASCII.GetBytes('xx GETEILT.EINS yy'));
  mBefore := TPackageCompiledFiles.Bytes;
  mFirst := TPackageLocator.Create([mFolder]);
  mSecond := TPackageLocator.Create([mFolder]);
  try
    Assert.IsTrue(mFirst.Provides('Geteilt', 'Geteilt.Eins', mContains));
    Assert.IsTrue(mContains);
    Assert.IsTrue(mSecond.Provides('Geteilt', 'Geteilt.Eins', mContains));
    Assert.IsTrue(mContains);
    // Zwei Locatoren, eine Kopie: die Bytes der Datei zählen einmal.
    Assert.AreEqual(Int64(18), TPackageCompiledFiles.Bytes - mBefore);
  finally
    mSecond.Free;
    mFirst.Free;
    TPackageCompiledFiles.Clear;
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TPackageLocatorTests.ChangedCompiledFileIsReread;
var
  mFolder, mFile: string;
  mData: TBytes;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDcpChanged' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mFolder);
  mFile := TPath.Combine(mFolder, 'Neu.dcp');
  try
    TFile.WriteAllBytes(mFile, TEncoding.ASCII.GetBytes('ALT'));
    TFile.SetLastWriteTime(mFile, EncodeDate(2026, 1, 1));
    Assert.IsTrue(TPackageCompiledFiles.Read(mFile, mData));
    Assert.AreEqual('ALT', TEncoding.ASCII.GetString(mData));
    TFile.WriteAllBytes(mFile, TEncoding.ASCII.GetBytes('NEUER'));
    TFile.SetLastWriteTime(mFile, EncodeDate(2026, 2, 1));
    Assert.IsTrue(TPackageCompiledFiles.Read(mFile, mData));
    Assert.AreEqual('NEUER', TEncoding.ASCII.GetString(mData));
    Assert.IsFalse(TPackageCompiledFiles.Read(TPath.Combine(mFolder, 'Fehlt.dcp'), mData));
  finally
    mData := nil;
    TPackageCompiledFiles.Clear;
    TDirectory.Delete(mFolder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPackageLocatorTests);

end.
