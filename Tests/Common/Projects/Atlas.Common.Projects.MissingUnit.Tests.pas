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
  Atlas.Common.Projects.MissingUnit;

var
  /// <summary>Unechte Platte: Ordner (klein) → Dateien und Unterordner.</summary>
  Files: TDictionary<string, TArray<string>>;
  Folders: TDictionary<string, TArray<string>>;

procedure AddFile(const AFileName: string);
var
  mFolder: string;
  mItems: TArray<string>;
begin
  mFolder := Copy(AFileName, 1, LastDelimiter('\', AFileName) - 1);
  if not Files.TryGetValue(LowerCase(mFolder), mItems) then
  begin
    mItems := nil;
  end;
  Files.AddOrSetValue(LowerCase(mFolder), mItems + [AFileName]);
end;

procedure AddFolder(const AParent, AChild: string);
var
  mItems: TArray<string>;
begin
  if not Folders.TryGetValue(LowerCase(AParent), mItems) then
  begin
    mItems := nil;
  end;
  Folders.AddOrSetValue(LowerCase(AParent), mItems + [AParent + '\' + AChild]);
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
      begin
        Result := nil;
      end;
    end;
  Result.ListFolders :=
    function(AFolder: string): TArray<string>
    begin
      if not Folders.TryGetValue(LowerCase(AFolder), Result) then
      begin
        Result := nil;
      end;
    end;
end;

function Places(const AHits: TArray<TMissingUnitHit>): string;
var
  mHit: TMissingUnitHit;
begin
  Result := '';
  for mHit in AHits do
  begin
    Result := Result + Format('%d %s (%s)|', [Ord(mHit.Place), mHit.FileName, mHit.Detail]);
  end;
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
  mSearched: TArray<string>;
begin
  Assert.AreEqual('0 C:\Projekt\Source\Common\Werkzeug.pas (Kasse.dproj)|',
    Places(TMissingUnitSearch.Search(BaseSetup('werkzeug'), mSearched)));
  Assert.AreEqual('0 C:\Projekt\Lib\Alt.dcu (Kasse.dproj)|', Places(TMissingUnitSearch.Search(BaseSetup('Alt'),
    mSearched)), 'auch eine .dcu');
end;

procedure TMissingUnitTests.SkipsFoldersTheCompilerSearched;
var
  mSetup: TMissingUnitSetup;
  mSearched: TArray<string>;
begin
  mSetup := BaseSetup('Werkzeug');
  mSetup.Project.SearchPaths := ['C:\Projekt\Source\Common\'];
  Assert.AreEqual('', Places(TMissingUnitSearch.Search(mSetup, mSearched)));
  // Der Projektordner selbst zählt nie: Dort sucht der Compiler immer.
  AddFile('C:\Projekt\Wurzel.pas');
  Assert.AreEqual('', Places(TMissingUnitSearch.Search(BaseSetup('Wurzel'), mSearched)));
end;

procedure TMissingUnitTests.FindsSearchPathOfOtherConfiguration;
var
  mSetup: TMissingUnitSetup;
  mTarget: TMissingUnitTarget;
  mSearched: TArray<string>;
begin
  AddFile('D:\Fremd\Helfer.pas');
  mSetup := BaseSetup('Helfer');
  mTarget.Config := 'Debug';
  mTarget.Platform := 'Win32';
  mTarget.SearchPaths := ['D:\Fremd'];
  mSetup.Targets := [mTarget];
  mTarget.Config := 'Release';
  mTarget.SearchPaths := ['D:\Nicht'];
  mSetup.Targets := mSetup.Targets + [mTarget];
  Assert.AreEqual('2 D:\Fremd\Helfer.pas (Debug, Win32)|', Places(TMissingUnitSearch.Search(mSetup, mSearched)));
  Assert.AreEqual('Projektordner C:\Projekt und Unterordner|Suchpfade von Debug, Win32', string.Join('|', mSearched),
    'die aktive Konfiguration zählt nicht');
end;

procedure TMissingUnitTests.FindsGroupProjectAndIndex;
var
  mSetup: TMissingUnitSetup;
  mProject: TMissingUnitProject;
  mSearched: TArray<string>;
begin
  AddFile('C:\Server\Protokoll.pas');
  AddFile('C:\Index\Protokoll.pas');
  mSetup := BaseSetup('Protokoll');
  mProject.FileName := 'C:\Server\Server.dproj';
  mProject.SearchPaths := nil;
  mSetup.GroupProjects := [mProject];
  mSetup.IndexFile :=
    function(AName: string): string
    begin
      Result := 'C:\Index\Protokoll.pas';
    end;
  Assert.AreEqual('1 C:\Server\Protokoll.pas (Server.dproj)|4 C:\Index\Protokoll.pas (Index)|',
    Places(TMissingUnitSearch.Search(mSetup, mSearched)));
end;

procedure TMissingUnitTests.OtherPlatformLibraryOnly;
var
  mSetup: TMissingUnitSetup;
  mSearched: TArray<string>;
begin
  AddFile('C:\BDS\lib\win32\release\Winapi.Windows.dcu');
  mSetup := BaseSetup('Winapi.Windows');
  mSetup.Project.Platform := 'Linux64';
  mSetup.Platforms := ['Linux64', 'Win32'];
  mSetup.LibraryPaths :=
    function(APlatform: string): TArray<string>
    begin
      Result := nil;
      if APlatform = 'Win32' then
      begin
        Result := ['C:\BDS\lib\win32\release'];
      end;
    end;
  Assert.AreEqual('3 C:\BDS\lib\win32\release\Winapi.Windows.dcu (Win32)|',
    Places(TMissingUnitSearch.Search(mSetup, mSearched)));
end;

procedure TMissingUnitTests.NothingFoundListsPlaces;
var
  mSetup: TMissingUnitSetup;
  mSearched: TArray<string>;
begin
  mSetup := BaseSetup('Gibts');
  mSetup.Platforms := ['Win64'];
  mSetup.LibraryPaths :=
    function(APlatform: string): TArray<string>
    begin
      Result := nil;
    end;
  mSetup.IndexFile :=
    function(AName: string): string
    begin
      Result := '';
    end;
  Assert.AreEqual('', Places(TMissingUnitSearch.Search(mSetup, mSearched)));
  Assert.AreEqual('Projektordner C:\Projekt und Unterordner|Bibliothek Win64|Index', string.Join('|', mSearched));
end;

procedure TMissingUnitTests.NamespacePrefixCounts;
var
  mSetup: TMissingUnitSetup;
  mSearched: TArray<string>;
begin
  AddFile('C:\Projekt\Lib\Firma.Werkzeuge.pas');
  mSetup := BaseSetup('Werkzeuge');
  mSetup.Namespaces := ['Firma'];
  Assert.AreEqual('0 C:\Projekt\Lib\Firma.Werkzeuge.pas (Kasse.dproj)|', Places(TMissingUnitSearch.Search(mSetup,
    mSearched)));
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
