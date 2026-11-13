unit Shell.Composition.LeakSetup.Tests;

// Befehl atlas.server.leakSetup der Komposition (#1880): Ausgabeordner der
// Konfiguration Debug, Ordner aus PATH, ohne geladenes Projekt ein Grund.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.LeakSetup;

type
  [TestFixture]
  TShellLeakSetupTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FServices: TShellLeakSetupServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Relativ zur .dproj, absolut unverändert, leer bzw. „.“ = Projektordner.</summary>
    [Test]
    procedure OutputFolderRelativeToProject;
    /// <summary>PATH ohne leere Einträge und Leerzeichen.</summary>
    [Test]
    procedure PathFoldersSkipEmpty;
    /// <summary>Ohne Arbeitsbereich: kein Projekt, Grund mit dem Dateinamen.</summary>
    [Test]
    procedure NoProjectGivesReason;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Leaks.Setup,
  Atlas.Common.Logging.Providers.Logger;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

/// <summary>Pfad mit dem Trenner der Plattform.</summary>
function N(const APath: string): string;
begin
  Result := StringReplace(APath, '\', PathDelim, [rfReplaceAll]);
end;

procedure TShellLeakSetupTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FServices := Default(TShellLeakSetupServices);
  FServices.Logger := mRegistry.Logger;
  FServices.Workspaces := FRegistry;
  FServices.ReadText := NoText;
end;

procedure TShellLeakSetupTests.TearDown;
begin
  FServices := Default(TShellLeakSetupServices);
  FreeAndNil(FRegistry);
end;

procedure TShellLeakSetupTests.OutputFolderRelativeToProject;
var
  mProject, mRoot: string;
begin
  mRoot := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(N('P\App.dproj'))));
  mProject := mRoot + PathDelim + 'App.dproj';
  Assert.AreEqual(mRoot + N('\Win32\Debug'), TShellLeakSetup.OutputFolderOf(mProject, '.\Win32\Debug'));
  Assert.AreEqual(mRoot + N('\Bin'), TShellLeakSetup.OutputFolderOf(mProject, 'Bin\'));
  Assert.AreEqual(mRoot, TShellLeakSetup.OutputFolderOf(mProject, ''));
  Assert.AreEqual(mRoot, TShellLeakSetup.OutputFolderOf(mProject, '.'));
  Assert.AreEqual(N('\Ausgabe'), TShellLeakSetup.OutputFolderOf(mProject, N('\Ausgabe')));
end;

procedure TShellLeakSetupTests.PathFoldersSkipEmpty;
var
  mFolders: TArray<string>;
begin
  mFolders := TShellLeakSetup.PathFolders('A' + PathSep + PathSep + ' B ' + PathSep);
  Assert.AreEqual(2, Integer(Length(mFolders)));
  Assert.AreEqual('A', mFolders[0]);
  Assert.AreEqual('B', mFolders[1]);
end;

procedure TShellLeakSetupTests.NoProjectGivesReason;
var
  mInput: TLeakSetupInput;
  mReason: string;
begin
  Assert.IsFalse(TShellLeakSetup.InputFor(FServices, TDocumentUris.FromPath(N('C:\P\App.dproj')), mInput, mReason));
  Assert.IsTrue(Pos('App.dproj', mReason) > 0, mReason);
  Assert.AreEqual('', mInput.MainSource);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellLeakSetupTests);

end.
