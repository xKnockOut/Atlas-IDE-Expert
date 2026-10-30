unit Atlas.Common.Projects.UnitLookup.Tests;

// Tests für die Unit-Suche wie beim Compiler (#1016): .pas und .dcu, Unit-
// Namespaces, Units des Projekts, "in 'Pfad'", requires-Packages, unsichere
// Pfade, Quelle Atlas, Ordner außerhalb der Suchpfade und Vorschlagsliste;
// Dateien aus {$I} und {$R} (#1379).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitLookupTests = class
  public
    [Test]
    procedure FindsSourceAndCompiledUnitsWithNamespaces;
    [Test]
    procedure ProjectUnitsAndFolderOfFile;
    [Test]
    procedure InPathChecksOnlyThatFile;
    [Test]
    procedure UnknownWithoutInstallationOrWithMacro;
    [Test]
    procedure RequiredPackagesProvideUnits;
    [Test]
    procedure UnitsOfIndirectlyRequiredPackages;
    [Test]
    procedure AtlasSourceUsesIndexAndBrowsingPaths;
    [Test]
    procedure FolderOutsideSearchPaths;
    [Test]
    procedure KnownUnitsAndPackages;
    [Test]
    procedure RepeatedQuestionsGiveSameAnswers;
    [Test]
    procedure FindFileLikeCompiler;
    /// <summary>3a: Units, die ein Projekt der Gruppe in einen Suchpfad übersetzt, auch ohne .dcu für diese
    /// Plattform (AtlasServer mit Atlas.Common im DCU-Suchpfad).</summary>
    [Test]
    procedure UnitsBuiltByGroupProjects;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Projects.UnitLookup;

/// <summary>Einrichtung mit den Dateien AFiles (vollständige Pfade) als Dateisystem.</summary>
function Setup(const AFiles: TArray<string>): TUnitLookupSetup;
begin
  Result := Default(TUnitLookupSetup);
  Result.Project.FileName := 'C:\P\App.dproj';
  Result.Project.SearchPaths := ['C:\P\Src'];
  Result.Project.Namespaces := ['System', 'Vcl'];
  Result.LibraryPaths := ['C:\BDS\lib'];
  Result.LibraryKnown := True;
  Result.ListFiles :=
    function(AFolder: string): TArray<string>
    var
      FileName: string;
    begin
      Result := nil;
      for FileName in AFiles do
        if SameText(TProjectPaths.DirectoryOf(FileName), AFolder) then
          Result := Result + [FileName];
    end;
  Result.ListFolders :=
    function(AFolder: string): TArray<string>
    var
      FileName, Folder: string;
    begin
      Result := nil;
      for FileName in AFiles do
      begin
        Folder := TProjectPaths.DirectoryOf(FileName);
        while (Folder <> '') and not SameText(TProjectPaths.DirectoryOf(Folder), AFolder) and
          (Length(Folder) > Length(AFolder)) do
          Folder := TProjectPaths.DirectoryOf(Folder);
        if SameText(TProjectPaths.DirectoryOf(Folder), AFolder) and (IndexText(Folder, Result) < 0) then
          Result := Result + [Folder];
      end;
    end;
  Result.FileExists :=
    function(AFileName: string): Boolean
    begin
      Result := IndexText(AFileName, AFiles) >= 0;
    end;
end;

const
  LibraryNames: array[0..3] of string = ('C:\BDS\lib\System.dcu', 'C:\BDS\lib\SysInit.dcu',
    'C:\BDS\lib\System.SysUtils.dcu', 'C:\BDS\lib\Vcl.Forms.dcu');

function LibraryFiles: TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in LibraryNames do
    Result := Result + [Name];
end;

// Ohne const: Aufrufer übergeben TUnitLookup.Create(...) direkt; nur so zählt Delphi die Referenz und gibt das
// Objekt wieder frei.
function Answer(ALookup: IRuleUnitLookup; const AName: string): TRuleUnitAnswer;
begin
  Result := ALookup.Find(AName, '', 'C:\P\Main.pas', [TRuleUnitSource.Project]);
end;

procedure TUnitLookupTests.UnitsBuiltByGroupProjects;
var
  mSetup: TUnitLookupSetup;
  mOutput: TUnitLookupGroupOutput;
begin
  mSetup := Setup(LibraryFiles);
  mSetup.Project.SearchPaths := ['C:\P\Src', 'C:\Out\Win32\Debug\Dcu\Common'];
  mOutput := Default(TUnitLookupGroupOutput);
  mOutput.DcuFolder := 'C:\Out\Win32\Debug\Dcu\Common\';
  mOutput.Units := ['Common.Vergleich', 'Common.Text'];
  mSetup.GroupOutputs := [mOutput];
  // Ein zweites Projekt übersetzt in einen Ordner außerhalb der Suchpfade: zählt nicht.
  mOutput.DcuFolder := 'C:\Out\Win32\Debug\Dcu\Fremd';
  mOutput.Units := ['Fremd.Unit'];
  mSetup.GroupOutputs := mSetup.GroupOutputs + [mOutput];
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(TUnitLookup.Create(mSetup), 'Common.Vergleich')),
    'ohne .dcu, aber von der Gruppe gebaut');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(TUnitLookup.Create(mSetup), 'common.text')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(mSetup), 'Fremd.Unit')),
    'Ausgabe nicht im Suchpfad');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(mSetup), 'Common.Fehlt')));
end;

procedure TUnitLookupTests.FindsSourceAndCompiledUnitsWithNamespaces;var
  Lookup: IRuleUnitLookup;
begin
  Lookup := TUnitLookup.Create(Setup(LibraryFiles + ['C:\P\Src\Rechnung.Druck.pas']));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'System.SysUtils')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'SysUtils')), 'Namespace System');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'forms')), 'Namespace Vcl, .dcu');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'Rechnung.Druck')), 'Suchpfad, .pas');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(Lookup, 'Rechnungs.Druck')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(Lookup, 'Winapi.Windows')));
end;

procedure TUnitLookupTests.FindFileLikeCompiler;
var
  mData: TUnitLookupSetup;
  mLookup: IRuleUnitLookup;
begin
  mData := Setup(LibraryFiles + ['C:\P\Main.inc', 'C:\P\Src\Gemeinsam.inc', 'C:\P\Inc\Version.inc',
    'C:\P\Res\Bilder.res', 'C:\BDS\lib\Bibliothek.inc', 'C:\Abs\Absolut.inc']);
  mData.Project.Properties := [TPair<string, string>.Create('DCC_IncludePath', 'Inc'),
    TPair<string, string>.Create('DCC_ResourcePath', 'C:\P\Res')];
  mLookup := TUnitLookup.Create(mData);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindFile('Main.inc', 'C:\P\Main.pas')), 'neben der Datei');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindFile('Gemeinsam.inc', 'C:\P\Main.pas')), 'Suchpfad');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindFile('Version.inc', 'C:\P\Main.pas')),
    'DCC_IncludePath relativ zur .dproj');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindFile('Bilder.res', 'C:\P\Main.pas')),
    'DCC_ResourcePath');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindFile('Bibliothek.inc', 'C:\P\Main.pas')),
    'Bibliothekspfad');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindFile('C:\Abs\Absolut.inc', 'C:\P\Main.pas')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(mLookup.FindFile('Fehlt.inc', 'C:\P\Main.pas')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(mLookup.FindFile('C:\Abs\Fehlt.inc', 'C:\P\Main.pas')));
  // Ohne Installation, mit offenem Makro oder ohne Dateizugriff keine sichere Aussage.
  mData.LibraryKnown := False;
  mLookup := TUnitLookup.Create(mData);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(mLookup.FindFile('Fehlt.inc', 'C:\P\Main.pas')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindFile('Main.inc', 'C:\P\Main.pas')));
  mData.LibraryKnown := True;
  mData.Project.Properties := [TPair<string, string>.Create('DCC_IncludePath', '$(MEINE_INC)')];
  mLookup := TUnitLookup.Create(mData);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(mLookup.FindFile('Fehlt.inc', 'C:\P\Main.pas')));
  mData.FileExists := nil;
  mLookup := TUnitLookup.Create(mData);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(mLookup.FindFile('Main.inc', 'C:\P\Main.pas')));
end;

procedure TUnitLookupTests.RepeatedQuestionsGiveSameAnswers;
var
  Data: TUnitLookupSetup;
  Entry: TProjectUnit;
  Lookup: IRuleUnitLookup;
  mPass: Integer;
begin
  // Projekt-Units stehen in einer Namensliste, die Antwort der Projektordner je Unit wird gemerkt (#1342):
  // Groß-/Kleinschreibung, Namespaces und fehlende Units wie bei der Suche über alle Einträge.
  Data := Setup(LibraryFiles + ['C:\P\Src\Rechnung.Druck.pas']);
  Entry.Name := 'Vcl.Kunden';
  Entry.FileName := 'C:\Q\Vcl.Kunden.pas';
  Data.Project.Units := [Entry];
  Lookup := TUnitLookup.Create(Data);
  for mPass := 1 to 2 do
  begin
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'KUNDEN')), 'Projekt-Unit mit Namespace Vcl');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'vcl.kunden')), 'Projekt-Unit');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'SysUtils')), 'Bibliothek mit Namespace');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'rechnung.druck')), 'Suchpfad');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(Lookup, 'Fehlt')));
  end;
end;

procedure TUnitLookupTests.ProjectUnitsAndFolderOfFile;
var
  Data: TUnitLookupSetup;
  Entry: TProjectUnit;
  Lookup: IRuleUnitLookup;
begin
  Data := Setup(LibraryFiles + ['C:\Woanders\Neben.pas']);
  Entry.Name := 'Kunden.Daten';
  Entry.FileName := 'C:\Q\Kunden.Daten.pas';
  Data.Project.Units := [Entry];
  Lookup := TUnitLookup.Create(Data);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'Kunden.Daten')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Lookup.Find('Neben', '', 'C:\Woanders\Haupt.pas',
    [TRuleUnitSource.Project])), 'Ordner der verwendenden Datei');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(Lookup, 'Neben')));
end;

procedure TUnitLookupTests.InPathChecksOnlyThatFile;
var
  Lookup: IRuleUnitLookup;
begin
  Lookup := TUnitLookup.Create(Setup(LibraryFiles + ['C:\P\Src\Haupt.Form.pas']));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Lookup.Find('Haupt.Form', 'Src\Haupt.Form.pas', 'C:\P\App.dpr',
    [TRuleUnitSource.Project])));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Lookup.Find('Haupt.Form', 'Haupt.Form.pas', 'C:\P\App.dpr',
    [TRuleUnitSource.Project])), 'Datei fehlt, auch wenn die Unit im Suchpfad liegt');
end;

procedure TUnitLookupTests.UnknownWithoutInstallationOrWithMacro;
var
  Data: TUnitLookupSetup;
begin
  Data := Setup(LibraryFiles);
  Data.LibraryKnown := False;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(Data), 'Fehlt')));
  Data := Setup(LibraryFiles);
  Data.Project.SearchPaths := ['$(MEINE_LIB)\Source'];
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(Data), 'Fehlt')));
  Data := Setup(LibraryFiles);
  Data.ListFiles := nil;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(Data), 'Fehlt')));
  // Gefundenes bleibt gefunden.
  Data := Setup(LibraryFiles);
  Data.LibraryKnown := False;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(TUnitLookup.Create(Data), 'SysUtils')));
end;

procedure TUnitLookupTests.RequiredPackagesProvideUnits;
var
  Data: TUnitLookupSetup;
  Lookup: IRuleUnitLookup;
begin
  Data := Setup(LibraryFiles);
  Data.RequiredPackages := ['Komponenten', 'Fremd'];
  Data.PackageProvides :=
    function(const APackage, AUnitName: string): TRulePackageAnswer
    begin
      if SameText(APackage, 'Fremd') then
        Exit(TRulePackageAnswer.Unknown);
      if SameText(AUnitName, 'Komp.Knopf') then
        Exit(TRulePackageAnswer.Yes);
      Result := TRulePackageAnswer.No;
    end;
  Lookup := TUnitLookup.Create(Data);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(Lookup, 'Komp.Knopf')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(Lookup, 'Komp.Fehlt')), 'Fremd ist unbekannt');
  Data.RequiredPackages := ['Komponenten'];
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(Data), 'Komp.Fehlt')));
end;

procedure TUnitLookupTests.UnitsOfIndirectlyRequiredPackages;
var
  Data: TUnitLookupSetup;
begin
  // Wie Atlas.Windows: requires rtl, Atlas.Common; Atlas.Common verlangt Atlas.Text, dessen Units dcc mitsieht.
  Data := Setup(LibraryFiles);
  Data.RequiredPackages := ['rtl', 'Atlas.Common'];
  Data.PackageProvides :=
    function(const APackage, AUnitName: string): TRulePackageAnswer
    begin
      if SameText(APackage, 'Atlas.Text') and SameText(AUnitName, 'Atlas.Text.MapFile') then
        Exit(TRulePackageAnswer.Yes);
      if SameText(APackage, 'Fremd') then
        Exit(TRulePackageAnswer.Unknown);
      Result := TRulePackageAnswer.No;
    end;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(Data), 'Atlas.Text.MapFile')),
    'ohne requires der Packages nur die direkten');
  Data.PackageRequires :=
    function(APackage: string): TArray<string>
    begin
      Result := nil;
      if SameText(APackage, 'Atlas.Common') then
        Result := TArray<string>.Create('rtl', 'Atlas.Text');
      if SameText(APackage, 'Atlas.Text') then
        Result := TArray<string>.Create('rtl', 'Atlas.Common');
    end;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(TUnitLookup.Create(Data), 'Atlas.Text.MapFile')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(Data), 'Atlas.Text.Fehlt')),
    'Ringe im requires enden');
  // Ein unbekanntes Package weiter hinten macht die Antwort unsicher.
  Data.PackageRequires :=
    function(APackage: string): TArray<string>
    begin
      Result := nil;
      if SameText(APackage, 'Atlas.Common') then
        Result := TArray<string>.Create('Fremd');
    end;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(Data), 'Atlas.Text.Fehlt')));
end;

procedure TUnitLookupTests.AtlasSourceUsesIndexAndBrowsingPaths;
var
  Data: TUnitLookupSetup;
  Lookup: IRuleUnitLookup;
begin
  Data := Setup(LibraryFiles + ['C:\BDS\source\Quelle.Nur.pas']);
  Data.BrowsingPaths := ['C:\BDS\source'];
  Data.IndexKnows :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'Im.Index');
    end;
  Lookup := TUnitLookup.Create(Data);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(Lookup, 'Im.Index')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Lookup.Find('Im.Index', '', 'C:\P\Main.pas',
    [TRuleUnitSource.Atlas])));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Lookup.Find('Quelle.Nur', '', 'C:\P\Main.pas',
    [TRuleUnitSource.Project, TRuleUnitSource.Atlas])));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Lookup.Find('Gibt.Es.Nicht', '', 'C:\P\Main.pas',
    [TRuleUnitSource.Project, TRuleUnitSource.Atlas])));
  // Nur Atlas ohne Index: keine Aussage.
  Data.IndexKnows := nil;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord((TUnitLookup.Create(Data) as IRuleUnitLookup).Find('Gibt.Es.Nicht', '',
    'C:\P\Main.pas', [TRuleUnitSource.Atlas])));
end;

procedure TUnitLookupTests.FolderOutsideSearchPaths;
var
  Lookup: IRuleUnitLookup;
begin
  Lookup := TUnitLookup.Create(Setup(LibraryFiles + ['C:\P\Src\Im.Pfad.pas', 'C:\P\Extra\Druck\Rechnung.pas',
    'C:\P\Haupt.pas']));
  Assert.AreEqual('Extra\Druck', Lookup.FolderOutsidePaths('Rechnung'));
  Assert.AreEqual('', Lookup.FolderOutsidePaths('Im.Pfad'), 'steht im Suchpfad');
  Assert.AreEqual('', Lookup.FolderOutsidePaths('Haupt'), 'Projektordner wird ohnehin durchsucht');
  Assert.AreEqual('', Lookup.FolderOutsidePaths('Fehlt'));
end;

procedure TUnitLookupTests.KnownUnitsAndPackages;
var
  Data: TUnitLookupSetup;
  Lookup: IRuleUnitLookup;
  Known: TArray<string>;
  FileName, Text: string;
begin
  Data := Setup(LibraryFiles + ['C:\P\Src\Rechnung.Druck.pas']);
  Data.PackageExists :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'rtl');
    end;
  Data.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '<Project/>';
      Result := SameText(AFileName, 'C:\P\App.dproj');
    end;
  Lookup := TUnitLookup.Create(Data);
  Known := Lookup.KnownUnits([TRuleUnitSource.Project]);
  Assert.IsTrue(IndexText('Rechnung.Druck', Known) >= 0);
  Assert.IsTrue(IndexText('Vcl.Forms', Known) >= 0);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Lookup.FindPackage('rtl')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Lookup.FindPackage('Fehlend')));
  Assert.IsTrue(Lookup.ReadProject(FileName, Text));
  Assert.AreEqual('C:\P\App.dproj', FileName);
  Assert.AreEqual('<Project/>', Text);
  Data.PackageExists := nil;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord((TUnitLookup.Create(Data) as IRuleUnitLookup).FindPackage('Fehlend')));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitLookupTests);

end.
