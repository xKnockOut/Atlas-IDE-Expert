unit Atlas.Common.Projects.MissingUnit.Tests;

// Tests für die Suche nach einer Unit, die der Compiler nicht fand (#550),
// mit unechter Platte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMissingUnitTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UnitFromMessages;
    /// <summary>Abnahme: Unit in einem Unterordner außerhalb des Suchpfads.</summary>
    [Test]
    procedure FindsSubfolderOfProject;
    [Test]
    procedure SkipsFoldersTheCompilerSearched;
    /// <summary>Abnahme: Ein Suchpfad, der nur in Debug steht, wird für Release gefunden.</summary>
    [Test]
    procedure FindsSearchPathOfOtherConfiguration;
    [Test]
    procedure FindsGroupProjectAndIndex;
    [Test]
    procedure OtherPlatformLibraryOnly;
    [Test]
    procedure NothingFoundListsPlaces;
    [Test]
    procedure NamespacePrefixCounts;
    /// <summary>Abnahme: Der eingetragene Pfad ist relativ.</summary>
    [Test]
    procedure RelativePaths;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.MissingUnit;

var
  /// <summary>Unechte Platte: Ordner (klein) → Dateien und Unterordner.</summary>
  Files: TDictionary<string, TArray<string>>;
  Folders: TDictionary<string, TArray<string>>;

procedure AddFile(const AFileName: string);
var
  Folder: string;
  Items: TArray<string>;
begin
  Folder := Copy(AFileName, 1, LastDelimiter('\', AFileName) - 1);
  if not Files.TryGetValue(LowerCase(Folder), Items) then
    Items := nil;
  Files.AddOrSetValue(LowerCase(Folder), Items + [AFileName]);
end;

procedure AddFolder(const AParent, AChild: string);
var
  Items: TArray<string>;
begin
  if not Folders.TryGetValue(LowerCase(AParent), Items) then
    Items := nil;
  Folders.AddOrSetValue(LowerCase(AParent), Items + [AParent + '\' + AChild]);
end;

function BaseSetup(const AUnit: string): TMissingUnitSetup;
begin
  Result := Default(TMissingUnitSetup);
  Result.UnitName := AUnit;
  Result.Project.FileName := 'C:\Projekt\Kasse.dproj';
  Result.Project.Config := 'Release';
  Result.Project.Platform := 'Win32';
  Result.ListFiles :=
    function(AFolder: string): TArray<string>
    begin
      if not Files.TryGetValue(LowerCase(AFolder), Result) then
        Result := nil;
    end;
  Result.ListFolders :=
    function(AFolder: string): TArray<string>
    begin
      if not Folders.TryGetValue(LowerCase(AFolder), Result) then
        Result := nil;
    end;
end;

function Places(const AHits: TArray<TMissingUnitHit>): string;
var
  Hit: TMissingUnitHit;
begin
  Result := '';
  for Hit in AHits do
    Result := Result + Format('%d %s (%s)|', [Ord(Hit.Place), Hit.FileName, Hit.Detail]);
end;

procedure TMissingUnitTests.Setup;
begin
  Files.Clear;
  Folders.Clear;
  AddFolder('C:\Projekt', 'Source');
  AddFolder('C:\Projekt\Source', 'Common');
  AddFolder('C:\Projekt', 'Lib');
  AddFile('C:\Projekt\Kasse.dpr');
  AddFile('C:\Projekt\Source\Main.pas');
  AddFile('C:\Projekt\Source\Common\Werkzeug.pas');
  AddFile('C:\Projekt\Lib\Alt.dcu');
end;

procedure TMissingUnitTests.TearDown;
begin
  Files.Clear;
  Folders.Clear;
end;

procedure TMissingUnitTests.UnitFromMessages;
begin
  Assert.AreEqual('Werkzeug', TMissingUnitSearch.UnitOfMessage('F2613', 'Unit ''Werkzeug'' not found.'));
  Assert.AreEqual('Werkzeug', TMissingUnitSearch.UnitOfMessage('F2613', 'Unit ''Werkzeug'' nicht gefunden.'));
  Assert.AreEqual('Werkzeug', TMissingUnitSearch.UnitOfMessage('F1026', 'File not found: ''Werkzeug.dcu'''));
  Assert.AreEqual('Werkzeug', TMissingUnitSearch.UnitOfMessage('F1026',
    'Datei nicht gefunden: ''Source\Werkzeug.pas'''));
  Assert.AreEqual('', TMissingUnitSearch.UnitOfMessage('F2613', 'ohne Namen'));
end;

procedure TMissingUnitTests.FindsSubfolderOfProject;
var
  Searched: TArray<string>;
begin
  Assert.AreEqual('0 C:\Projekt\Source\Common\Werkzeug.pas (Kasse.dproj)|',
    Places(TMissingUnitSearch.Search(BaseSetup('werkzeug'), Searched)));
  Assert.AreEqual('0 C:\Projekt\Lib\Alt.dcu (Kasse.dproj)|', Places(TMissingUnitSearch.Search(BaseSetup('Alt'),
    Searched)), 'auch eine .dcu');
end;

procedure TMissingUnitTests.SkipsFoldersTheCompilerSearched;
var
  Setup: TMissingUnitSetup;
  Searched: TArray<string>;
begin
  Setup := BaseSetup('Werkzeug');
  Setup.Project.SearchPaths := ['C:\Projekt\Source\Common\'];
  Assert.AreEqual('', Places(TMissingUnitSearch.Search(Setup, Searched)));
  // Der Projektordner selbst zählt nie: Dort sucht der Compiler immer.
  AddFile('C:\Projekt\Wurzel.pas');
  Assert.AreEqual('', Places(TMissingUnitSearch.Search(BaseSetup('Wurzel'), Searched)));
end;

procedure TMissingUnitTests.FindsSearchPathOfOtherConfiguration;
var
  Setup: TMissingUnitSetup;
  Target: TMissingUnitTarget;
  Searched: TArray<string>;
begin
  AddFile('D:\Fremd\Helfer.pas');
  Setup := BaseSetup('Helfer');
  Target.Config := 'Debug';
  Target.Platform := 'Win32';
  Target.SearchPaths := ['D:\Fremd'];
  Setup.Targets := [Target];
  Target.Config := 'Release';
  Target.SearchPaths := ['D:\Nicht'];
  Setup.Targets := Setup.Targets + [Target];
  Assert.AreEqual('2 D:\Fremd\Helfer.pas (Debug, Win32)|', Places(TMissingUnitSearch.Search(Setup, Searched)));
  Assert.AreEqual('Projektordner C:\Projekt und Unterordner|Suchpfade von Debug, Win32', string.Join('|', Searched),
    'die aktive Konfiguration zählt nicht');
end;

procedure TMissingUnitTests.FindsGroupProjectAndIndex;
var
  Setup: TMissingUnitSetup;
  Project: TMissingUnitProject;
  Searched: TArray<string>;
begin
  AddFile('C:\Server\Protokoll.pas');
  AddFile('C:\Index\Protokoll.pas');
  Setup := BaseSetup('Protokoll');
  Project.FileName := 'C:\Server\Server.dproj';
  Project.SearchPaths := nil;
  Setup.GroupProjects := [Project];
  Setup.IndexFile :=
    function(AName: string): string
    begin
      Result := 'C:\Index\Protokoll.pas';
    end;
  Assert.AreEqual('1 C:\Server\Protokoll.pas (Server.dproj)|4 C:\Index\Protokoll.pas (Index)|',
    Places(TMissingUnitSearch.Search(Setup, Searched)));
end;

procedure TMissingUnitTests.OtherPlatformLibraryOnly;
var
  Setup: TMissingUnitSetup;
  Searched: TArray<string>;
begin
  AddFile('C:\BDS\lib\win32\release\Winapi.Windows.dcu');
  Setup := BaseSetup('Winapi.Windows');
  Setup.Project.Platform := 'Linux64';
  Setup.Platforms := ['Linux64', 'Win32'];
  Setup.LibraryPaths :=
    function(APlatform: string): TArray<string>
    begin
      Result := nil;
      if APlatform = 'Win32' then
        Result := ['C:\BDS\lib\win32\release'];
    end;
  Assert.AreEqual('3 C:\BDS\lib\win32\release\Winapi.Windows.dcu (Win32)|',
    Places(TMissingUnitSearch.Search(Setup, Searched)));
end;

procedure TMissingUnitTests.NothingFoundListsPlaces;
var
  Setup: TMissingUnitSetup;
  Searched: TArray<string>;
begin
  Setup := BaseSetup('Gibts');
  Setup.Platforms := ['Win64'];
  Setup.LibraryPaths :=
    function(APlatform: string): TArray<string>
    begin
      Result := nil;
    end;
  Setup.IndexFile :=
    function(AName: string): string
    begin
      Result := '';
    end;
  Assert.AreEqual('', Places(TMissingUnitSearch.Search(Setup, Searched)));
  Assert.AreEqual('Projektordner C:\Projekt und Unterordner|Bibliothek Win64|Index', string.Join('|', Searched));
end;

procedure TMissingUnitTests.NamespacePrefixCounts;
var
  Setup: TMissingUnitSetup;
  Searched: TArray<string>;
begin
  AddFile('C:\Projekt\Lib\Firma.Werkzeuge.pas');
  Setup := BaseSetup('Werkzeuge');
  Setup.Namespaces := ['Firma'];
  Assert.AreEqual('0 C:\Projekt\Lib\Firma.Werkzeuge.pas (Kasse.dproj)|', Places(TMissingUnitSearch.Search(Setup,
    Searched)));
end;

procedure TMissingUnitTests.RelativePaths;
begin
  Assert.AreEqual('Source\Common', TMissingUnitSearch.RelativePath('C:\Projekt\Kasse.dproj',
    'C:\Projekt\Source\Common\'));
  Assert.AreEqual('..\Gemeinsam\Lib', TMissingUnitSearch.RelativePath('C:\Projekt\Kasse.dproj',
    'C:\Gemeinsam\Lib'));
  Assert.AreEqual('.', TMissingUnitSearch.RelativePath('C:\Projekt\Kasse.dproj', 'C:\Projekt'));
  Assert.AreEqual('D:\Fremd', TMissingUnitSearch.RelativePath('C:\Projekt\Kasse.dproj', 'D:\Fremd'),
    'anderes Laufwerk bleibt absolut');
end;

initialization
  Files := TDictionary<string, TArray<string>>.Create(64);
  Folders := TDictionary<string, TArray<string>>.Create(64);
  TDUnitX.RegisterTestFixture(TMissingUnitTests);

finalization
  Files.Free;
  Folders.Free;

end.
