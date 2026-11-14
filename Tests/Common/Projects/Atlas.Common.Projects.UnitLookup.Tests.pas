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
      begin
        if SameText(TProjectPaths.DirectoryOf(FileName), AFolder) then
        begin
          Result := Result + [FileName];
        end;
      end;
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
        begin
          Folder := TProjectPaths.DirectoryOf(Folder);
        end;
        if SameText(TProjectPaths.DirectoryOf(Folder), AFolder) and (IndexText(Folder, Result) < 0) then
        begin
          Result := Result + [Folder];
        end;
      end;
    end;
  Result.FileExists :=
    function(AFileName: string): Boolean
    begin
      Result := IndexText(AFileName, AFiles) >= 0;
    end;
end;

const
  cLibraryNames: array[0..3] of string = ('C:\BDS\lib\System.dcu', 'C:\BDS\lib\SysInit.dcu',
    'C:\BDS\lib\System.SysUtils.dcu', 'C:\BDS\lib\Vcl.Forms.dcu');

function LibraryFiles: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in cLibraryNames do
  begin
    Result := Result + [mName];
  end;
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
  mLate: TArray<TUnitLookupGroupOutput>;
  mLookup: IRuleUnitLookup;
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
  // Über GroupOutputsOf: Die IDE meldet die übrigen Projekte erst nach diesem an; die Suche fragt bei Bedarf.
  mLate := nil;
  mSetup.GroupOutputs := nil;
  mSetup.GroupOutputsOf :=
    function: TArray<TUnitLookupGroupOutput>
    begin
      Result := mLate;
    end;
  mLookup := TUnitLookup.Create(mSetup);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(mLookup, 'Common.Vergleich')), 'Gruppe noch leer');
  mOutput.DcuFolder := 'C:\Out\Win32\Debug\Dcu\Common';
  mOutput.Units := ['Common.Vergleich'];
  mLate := [mOutput];
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'Common.Vergleich')), 'später angemeldet');
  mLookup := nil;
  mSetup.GroupOutputsOf := nil;
end;

procedure TUnitLookupTests.FindsSourceAndCompiledUnitsWithNamespaces;var
  mLookup: IRuleUnitLookup;
begin
  mLookup := TUnitLookup.Create(Setup(LibraryFiles + ['C:\P\Src\Rechnung.Druck.pas']));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'System.SysUtils')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'SysUtils')), 'Namespace System');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'forms')), 'Namespace Vcl, .dcu');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'Rechnung.Druck')), 'Suchpfad, .pas');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(mLookup, 'Rechnungs.Druck')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(mLookup, 'Winapi.Windows')));
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
  mData: TUnitLookupSetup;
  mEntry: TProjectUnit;
  mLookup: IRuleUnitLookup;
  mPass: Integer;
begin
  // Projekt-Units stehen in einer Namensliste, die Antwort der Projektordner je Unit wird gemerkt (#1342):
  // Groß-/Kleinschreibung, Namespaces und fehlende Units wie bei der Suche über alle Einträge.
  mData := Setup(LibraryFiles + ['C:\P\Src\Rechnung.Druck.pas']);
  mEntry.Name := 'Vcl.Kunden';
  mEntry.FileName := 'C:\Q\Vcl.Kunden.pas';
  mData.Project.Units := [mEntry];
  mLookup := TUnitLookup.Create(mData);
  for mPass := 1 to 2 do
  begin
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'KUNDEN')), 'Projekt-Unit mit Namespace Vcl');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'vcl.kunden')), 'Projekt-Unit');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'SysUtils')), 'Bibliothek mit Namespace');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'rechnung.druck')), 'Suchpfad');
    Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(mLookup, 'Fehlt')));
  end;
end;

procedure TUnitLookupTests.ProjectUnitsAndFolderOfFile;
var
  mData: TUnitLookupSetup;
  mEntry: TProjectUnit;
  mLookup: IRuleUnitLookup;
begin
  mData := Setup(LibraryFiles + ['C:\Woanders\Neben.pas']);
  mEntry.Name := 'Kunden.Daten';
  mEntry.FileName := 'C:\Q\Kunden.Daten.pas';
  mData.Project.Units := [mEntry];
  mLookup := TUnitLookup.Create(mData);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'Kunden.Daten')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.Find('Neben', '', 'C:\Woanders\Haupt.pas',
    [TRuleUnitSource.Project])), 'Ordner der verwendenden Datei');
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(mLookup, 'Neben')));
end;

procedure TUnitLookupTests.InPathChecksOnlyThatFile;
var
  mLookup: IRuleUnitLookup;
begin
  mLookup := TUnitLookup.Create(Setup(LibraryFiles + ['C:\P\Src\Haupt.Form.pas']));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.Find('Haupt.Form', 'Src\Haupt.Form.pas', 'C:\P\App.dpr',
    [TRuleUnitSource.Project])));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(mLookup.Find('Haupt.Form', 'Haupt.Form.pas', 'C:\P\App.dpr',
    [TRuleUnitSource.Project])), 'Datei fehlt, auch wenn die Unit im Suchpfad liegt');
end;

procedure TUnitLookupTests.UnknownWithoutInstallationOrWithMacro;
var
  mData: TUnitLookupSetup;
begin
  mData := Setup(LibraryFiles);
  mData.LibraryKnown := False;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(mData), 'Fehlt')));
  mData := Setup(LibraryFiles);
  mData.Project.SearchPaths := ['$(MEINE_LIB)\Source'];
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(mData), 'Fehlt')));
  mData := Setup(LibraryFiles);
  mData.ListFiles := nil;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(mData), 'Fehlt')));
  // Gefundenes bleibt gefunden.
  mData := Setup(LibraryFiles);
  mData.LibraryKnown := False;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(TUnitLookup.Create(mData), 'SysUtils')));
end;

procedure TUnitLookupTests.RequiredPackagesProvideUnits;
var
  mData: TUnitLookupSetup;
  mLookup: IRuleUnitLookup;
begin
  mData := Setup(LibraryFiles);
  mData.RequiredPackages := ['Komponenten', 'Fremd'];
  mData.PackageProvides :=
    function(const APackage, AUnitName: string): TRulePackageAnswer
    begin
      if SameText(APackage, 'Fremd') then
      begin
        Exit(TRulePackageAnswer.Unknown);
      end;
      if SameText(AUnitName, 'Komp.Knopf') then
      begin
        Exit(TRulePackageAnswer.Yes);
      end;
      Result := TRulePackageAnswer.No;
    end;
  mLookup := TUnitLookup.Create(mData);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(mLookup, 'Komp.Knopf')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(mLookup, 'Komp.Fehlt')), 'Fremd ist unbekannt');
  mData.RequiredPackages := ['Komponenten'];
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(mData), 'Komp.Fehlt')));
end;

procedure TUnitLookupTests.UnitsOfIndirectlyRequiredPackages;
var
  mData: TUnitLookupSetup;
begin
  // Wie Atlas.Windows: requires rtl, Atlas.Common; Atlas.Common verlangt Atlas.Text, dessen Units dcc mitsieht.
  mData := Setup(LibraryFiles);
  mData.RequiredPackages := ['rtl', 'Atlas.Common'];
  mData.PackageProvides :=
    function(const APackage, AUnitName: string): TRulePackageAnswer
    begin
      if SameText(APackage, 'Atlas.Text') and SameText(AUnitName, 'Atlas.Text.MapFile') then
      begin
        Exit(TRulePackageAnswer.Yes);
      end;
      if SameText(APackage, 'Fremd') then
      begin
        Exit(TRulePackageAnswer.Unknown);
      end;
      Result := TRulePackageAnswer.No;
    end;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(mData), 'Atlas.Text.MapFile')),
    'ohne requires der Packages nur die direkten');
  mData.PackageRequires :=
    function(APackage: string): TArray<string>
    begin
      Result := nil;
      if SameText(APackage, 'Atlas.Common') then
      begin
        Result := TArray<string>.Create('rtl', 'Atlas.Text');
      end;
      if SameText(APackage, 'Atlas.Text') then
      begin
        Result := TArray<string>.Create('rtl', 'Atlas.Common');
      end;
    end;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(Answer(TUnitLookup.Create(mData), 'Atlas.Text.MapFile')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(TUnitLookup.Create(mData), 'Atlas.Text.Fehlt')),
    'Ringe im requires enden');
  // Ein unbekanntes Package weiter hinten macht die Antwort unsicher.
  mData.PackageRequires :=
    function(APackage: string): TArray<string>
    begin
      Result := nil;
      if SameText(APackage, 'Atlas.Common') then
      begin
        Result := TArray<string>.Create('Fremd');
      end;
    end;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord(Answer(TUnitLookup.Create(mData), 'Atlas.Text.Fehlt')));
end;

procedure TUnitLookupTests.AtlasSourceUsesIndexAndBrowsingPaths;
var
  mData: TUnitLookupSetup;
  mLookup: IRuleUnitLookup;
begin
  mData := Setup(LibraryFiles + ['C:\BDS\source\Quelle.Nur.pas']);
  mData.BrowsingPaths := ['C:\BDS\source'];
  mData.IndexKnows :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'Im.Index');
    end;
  mLookup := TUnitLookup.Create(mData);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(Answer(mLookup, 'Im.Index')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.Find('Im.Index', '', 'C:\P\Main.pas',
    [TRuleUnitSource.Atlas])));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.Find('Quelle.Nur', '', 'C:\P\Main.pas',
    [TRuleUnitSource.Project, TRuleUnitSource.Atlas])));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(mLookup.Find('Gibt.Es.Nicht', '', 'C:\P\Main.pas',
    [TRuleUnitSource.Project, TRuleUnitSource.Atlas])));
  // Nur Atlas ohne Index: keine Aussage.
  mData.IndexKnows := nil;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord((TUnitLookup.Create(mData) as IRuleUnitLookup).Find('Gibt.Es.Nicht', '',
    'C:\P\Main.pas', [TRuleUnitSource.Atlas])));
end;

procedure TUnitLookupTests.FolderOutsideSearchPaths;
var
  mLookup: IRuleUnitLookup;
begin
  mLookup := TUnitLookup.Create(Setup(LibraryFiles + ['C:\P\Src\Im.Pfad.pas', 'C:\P\Extra\Druck\Rechnung.pas',
    'C:\P\Haupt.pas']));
  Assert.AreEqual('Extra\Druck', mLookup.FolderOutsidePaths('Rechnung'));
  Assert.AreEqual('', mLookup.FolderOutsidePaths('Im.Pfad'), 'steht im Suchpfad');
  Assert.AreEqual('', mLookup.FolderOutsidePaths('Haupt'), 'Projektordner wird ohnehin durchsucht');
  Assert.AreEqual('', mLookup.FolderOutsidePaths('Fehlt'));
end;

procedure TUnitLookupTests.KnownUnitsAndPackages;
var
  mData: TUnitLookupSetup;
  mLookup: IRuleUnitLookup;
  mKnown: TArray<string>;
  mFileName, mText: string;
  mGroup: TUnitLookupGroupOutput;
begin
  mData := Setup(LibraryFiles + ['C:\P\Src\Rechnung.Druck.pas']);
  mData.PackageExists :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'rtl');
    end;
  mData.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '<Project/>';
      Result := SameText(AFileName, 'C:\P\App.dproj');
    end;
  mLookup := TUnitLookup.Create(mData);
  mKnown := mLookup.KnownUnits([TRuleUnitSource.Project]);
  Assert.IsTrue(IndexText('Rechnung.Druck', mKnown) >= 0);
  Assert.IsTrue(IndexText('Vcl.Forms', mKnown) >= 0);
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord(mLookup.FindPackage('rtl')));
  Assert.AreEqual(Ord(TRuleUnitAnswer.Missing), Ord(mLookup.FindPackage('Fehlend')));
  // Package derselben Projektgruppe: gilt als vorhanden, auch ohne .dcp und ohne Ausgabeordner.
  mGroup := Default(TUnitLookupGroupOutput);
  mGroup.ProjectName := 'Atlas.Text';
  mData.GroupOutputs := [mGroup];
  Assert.AreEqual(Ord(TRuleUnitAnswer.Found), Ord((TUnitLookup.Create(mData) as IRuleUnitLookup).FindPackage(
    'atlas.text')));
  mData.GroupOutputs := nil;
  Assert.IsTrue(mLookup.ReadProject(mFileName, mText));
  Assert.AreEqual('C:\P\App.dproj', mFileName);
  Assert.AreEqual('<Project/>', mText);
  mData.PackageExists := nil;
  Assert.AreEqual(Ord(TRuleUnitAnswer.Unknown), Ord((TUnitLookup.Create(mData) as IRuleUnitLookup).FindPackage('Fehlend')));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitLookupTests);

end.
