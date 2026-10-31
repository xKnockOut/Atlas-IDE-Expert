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
  BasisDpk =
    'package Basis;'#10 +
    'requires rtl;'#10 +
    'contains'#10 +
    '  uBasis in ''uBasis.pas'','#10 +
    '  uHilfe;'#10 +
    'end.';

function Files(const AFiles: TArray<TPair<string, TBytes>>; const AReads: TList<string>): TPackageReadFile;
var
  Map: TArray<TPair<string, TBytes>>;
begin
  Map := AFiles;
  Result :=
    function(const AFileName: string; out AData: TBytes): Boolean
    var
      Item: TPair<string, TBytes>;
    begin
      if AReads <> nil then
        AReads.Add(AFileName);
      for Item in Map do
        if SameText(Item.Key, AFileName) then
        begin
          AData := Item.Value;
          Exit(True);
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
  Name: string;
begin
  // Wie im .dcp: Namen als ShortString mit Längenbyte zwischen Binärdaten.
  Result := 'PKX0'#0#1;
  for Name in ANames do
    Result := Result + Chr(Length(Name)) + Name + #0#2;
end;

{ TPackageLocatorTests }

procedure TPackageLocatorTests.SourceAnswersFromContains;
var
  Locator: TPackageLocator;
  Contains: Boolean;
  FileName: string;
  Source: TPackageSource;
begin
  Locator := TPackageLocator.Create(['A', 'B'], Files([Entry(TPath.Combine('B', 'Basis.dpk'), BasisDpk)], nil));
  try
    Assert.IsTrue(Locator.Provides('Basis', 'UBASIS', Contains));
    Assert.IsTrue(Contains);
    Assert.IsTrue(Locator.Provides('basis', 'uHilfe', Contains));
    Assert.IsTrue(Contains);
    Assert.IsTrue(Locator.Provides('Basis', 'uFremd', Contains));
    Assert.IsFalse(Contains);
    Assert.IsTrue(Locator.FindSource('Basis', FileName, Source));
    Assert.AreEqual(TPath.Combine('B', 'Basis.dpk'), FileName);
    Assert.AreEqual(2, Integer(Length(Source.Contains)));
  finally
    Locator.Free;
  end;
end;

procedure TPackageLocatorTests.CompiledPackageIsScanned;
var
  Locator: TPackageLocator;
  Contains: Boolean;
  FileName: string;
  Source: TPackageSource;
begin
  Locator := TPackageLocator.Create(['Lib'],
    Files([Entry(TPath.Combine('Lib', 'rtl.dcp'), Dcp(['System.Classes', 'System.SysUtils']))], nil));
  try
    Assert.IsTrue(Locator.Provides('rtl', 'system.classes', Contains));
    Assert.IsTrue(Contains);
    Assert.IsTrue(Locator.Provides('rtl', 'Vcl.Forms', Contains));
    Assert.IsFalse(Contains);
    // Nur übersetzt: keine Quelle.
    Assert.IsFalse(Locator.FindSource('rtl', FileName, Source));
  finally
    Locator.Free;
  end;
end;

procedure TPackageLocatorTests.SourceWinsOverCompiled;
var
  Locator: TPackageLocator;
  Contains: Boolean;
begin
  Locator := TPackageLocator.Create(['A', 'B'], Files([Entry(TPath.Combine('A', 'Basis.dcp'), Dcp(['uAlt'])),
    Entry(TPath.Combine('B', 'Basis.dpk'), BasisDpk)], nil));
  try
    Assert.IsTrue(Locator.Provides('Basis', 'uAlt', Contains));
    Assert.IsFalse(Contains);
  finally
    Locator.Free;
  end;
end;

procedure TPackageLocatorTests.UnknownPackage;
var
  Locator: TPackageLocator;
  Contains: Boolean;
begin
  Locator := TPackageLocator.Create(['A'], Files([Entry(TPath.Combine('A', 'Kaputt.dpk'), 'unit Kaputt;')], nil));
  try
    Assert.IsFalse(Locator.Provides('Fehlt', 'uBasis', Contains));
    Assert.IsFalse(Contains);
    // Eine .dpk, die kein Package ist, zählt nicht.
    Assert.IsFalse(Locator.Provides('Kaputt', 'Kaputt', Contains));
  finally
    Locator.Free;
  end;
end;

procedure TPackageLocatorTests.CompiledNamesAreWholeWords;
var
  Data: TBytes;
begin
  Data := TEncoding.ASCII.GetBytes(Dcp(['System.Classes', 'uBasisX']));
  Assert.IsTrue(TPackageLocator.CompiledContains(Data, 'System.Classes'));
  Assert.IsFalse(TPackageLocator.CompiledContains(Data, 'Classes'));
  Assert.IsFalse(TPackageLocator.CompiledContains(Data, 'uBasis'));
  Assert.IsTrue(TPackageLocator.CompiledContains(Data, 'UBASISX'));
  Assert.IsFalse(TPackageLocator.CompiledContains(Data, ''));
end;

procedure TPackageLocatorTests.ResultsAreCached;
var
  Locator: TPackageLocator;
  Reads: TList<string>;
  Contains: Boolean;
  Count: Integer;
begin
  Reads := TList<string>.Create;
  Locator := TPackageLocator.Create(['A'], Files([Entry(TPath.Combine('A', 'Basis.dpk'), BasisDpk)], Reads));
  try
    Locator.Provides('Basis', 'uBasis', Contains);
    Count := Reads.Count;
    Locator.Provides('BASIS', 'uHilfe', Contains);
    Locator.Provides('Fehlt', 'uHilfe', Contains);
    Assert.AreEqual(Count + 2, Integer(Reads.Count));
    Locator.Provides('Fehlt', 'uBasis', Contains);
    Assert.AreEqual(Count + 2, Integer(Reads.Count));
  finally
    Locator.Free;
    Reads.Free;
  end;
end;

procedure TPackageLocatorTests.CompiledAnswersAreCached;
const
  // Wie rtl.dcp: mehrere MB, die gesuchten Namen am Ende.
  Size = 4 * 1024 * 1024;
  Calls = 500;
var
  Locator: TPackageLocator;
  Data: TBytes;
  Tail: TBytes;
  Contains: Boolean;
  Index: Integer;
  Watch: TStopwatch;
begin
  Tail := TEncoding.ASCII.GetBytes(Dcp(['System.Classes']));
  SetLength(Data, Size);
  FillChar(Data[0], Size, 1);
  Move(Tail[0], Data[Size - Length(Tail)], Length(Tail));
  Locator := TPackageLocator.Create(['Lib'], Files([TPair<string, TBytes>.Create(TPath.Combine('Lib', 'rtl.dcp'),
    Data)], nil));
  try
    Watch := TStopwatch.StartNew;
    for Index := 1 to Calls do
    begin
      Assert.IsTrue(Locator.Provides('rtl', 'System.Classes', Contains));
      Assert.IsTrue(Contains);
      Assert.IsTrue(Locator.Provides('RTL', 'vcl.forms', Contains));
      Assert.IsFalse(Contains);
    end;
    // Ohne Cache 2 × 500 Läufe über 4 MB (4 GB), mehrere Sekunden; mit Cache zwei Läufe.
    Assert.IsTrue(Watch.ElapsedMilliseconds < 1000, Format('%d ms', [Watch.ElapsedMilliseconds]));
  finally
    Locator.Free;
  end;
end;

procedure TPackageLocatorTests.ContainedFilesAreAbsolute;
var
  Found: TArray<string>;
  Folder: string;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'Basis');
  Found := TPackageLocator.ContainedFiles(TPath.Combine(Folder, 'Basis.dpk'), TPackageReader.Read(BasisDpk));
  // uHilfe ohne in '…' findet der Compiler über die Suchpfade.
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(ExpandFileName(TPath.Combine(Folder, 'uBasis.pas')), Found[0]);
end;

procedure TPackageLocatorTests.RequiredFilesFollowRequires;
const
  KernDpk = 'package Kern;'#10'contains'#10'  uKern in ''uKern.pas'';'#10'end.';
  AppDpk = 'package App;'#10'requires Basis, rtl;'#10'contains'#10'  uApp in ''uApp.pas'';'#10'end.';
  BasisMitKern = 'package Basis;'#10'requires Kern, App;'#10'contains'#10'  uBasis in ''uBasis.pas'';'#10'end.';
var
  Locator: TPackageLocator;
  Found: TArray<string>;
  Folder: string;
begin
  Folder := TPath.GetTempPath;
  Locator := TPackageLocator.Create([Folder], Files([Entry(TPath.Combine(Folder, 'Basis.dpk'), BasisMitKern),
    Entry(TPath.Combine(Folder, 'Kern.dpk'), KernDpk)], nil));
  try
    // App selbst zählt nicht mit, auch wenn Basis es wieder verlangt; rtl hat keine Quelle.
    Found := Locator.RequiredFiles(TPackageReader.Read(AppDpk));
    Assert.AreEqual(2, Integer(Length(Found)), String.Join(';', Found));
    Assert.AreEqual(ExpandFileName(TPath.Combine(Folder, 'uBasis.pas')), Found[0]);
    Assert.AreEqual(ExpandFileName(TPath.Combine(Folder, 'uKern.pas')), Found[1]);
  finally
    Locator.Free;
  end;
end;

procedure TPackageLocatorTests.RequiresComeFromSource;
const
  MitRequires = 'package Basis;'#10'requires rtl, Kern;'#10'contains'#10'  uBasis in ''uBasis.pas'';'#10'end.';
var
  Locator: TPackageLocator;
  Found: TArray<string>;
begin
  Locator := TPackageLocator.Create(['A'], Files([Entry(TPath.Combine('A', 'Basis.dpk'), MitRequires),
    Entry(TPath.Combine('A', 'Kern.dcp'), Dcp(['uKern']))], nil));
  try
    Found := Locator.Requires('basis');
    Assert.AreEqual('rtl;Kern', String.Join(';', Found));
    // Ein .dcp nennt seine requires nicht, ein unbekanntes Package hat keine.
    Assert.AreEqual(0, Integer(Length(Locator.Requires('Kern'))));
    Assert.AreEqual(0, Integer(Length(Locator.Requires('Fehlt'))));
  finally
    Locator.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPackageLocatorTests);

end.
