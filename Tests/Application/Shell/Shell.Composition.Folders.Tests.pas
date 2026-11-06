unit Shell.Composition.Folders.Tests;

// Arbeitsbereiche anlegen und entfernen ohne Ordner: keine Unit ladbar, unbekannter Eintrag ändert nichts,
// Datei ohne Projekt darüber legt keinen Arbeitsbereich an.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Folders;

type
  [TestFixture]
  TShellFoldersTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FFolders: TShellFolders;
    FLoaded: Integer;
    FTempDir: string;
    procedure ProjectLoaded;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich lässt sich keine Unit laden, auch nicht über die Methodenreferenz.</summary>
    [Test]
    procedure EnsureUnitWithoutWorkspaces;
    /// <summary>Ein Eintrag, der keinen Arbeitsbereich erzeugt hat, meldet kein Projekt als geladen.</summary>
    [Test]
    procedure RemoveUnknownFolder;
    /// <summary>Datei ohne Projektdatei darüber: kein Arbeitsbereich (#175).</summary>
    [Test]
    procedure DeriveWithoutProject;
    /// <summary>Die Reihenfolge der Indexaufbauten besteht ab dem Anlegen (#648).</summary>
    [Test]
    procedure SchedulerExists;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Lsp.WorkspaceFolders,
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

function NoLanguageLevel(const AUri: string): string;
begin
  Result := '';
end;

procedure TShellFoldersTests.ProjectLoaded;
begin
  Inc(FLoaded);
end;

procedure TShellFoldersTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
  mServices: TShellFoldersServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguageLevel);
  mServices := Default(TShellFoldersServices);
  mServices.Logger := mRegistry.Logger;
  mServices.Workspaces := FRegistry;
  mServices.Settings := FSettings;
  mServices.ProjectLoaded := ProjectLoaded;
  FFolders := TShellFolders.Create(mServices);
  FLoaded := 0;
  FTempDir := TPath.Combine(TPath.GetTempPath, 'AtlasFolders' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TShellFoldersTests.TearDown;
begin
  FreeAndNil(FFolders);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
  if TDirectory.Exists(FTempDir) then
  begin
    TDirectory.Delete(FTempDir, True);
  end;
  FTempDir := '';
end;

procedure TShellFoldersTests.EnsureUnitWithoutWorkspaces;
begin
  Assert.IsFalse(FFolders.EnsureUnit('System.SysUtils'));
  Assert.IsFalse(FFolders.EnsureUnitFunc()('System.SysUtils'));
end;

procedure TShellFoldersTests.RemoveUnknownFolder;
begin
  FFolders.Remove(TWorkspaceFolder.Create(FTempDir, 'Unbekannt'));
  Assert.AreEqual(0, FLoaded);
  Assert.AreEqual(0, Integer(FRegistry.Items.Count));
end;

procedure TShellFoldersTests.DeriveWithoutProject;
var
  mFile: string;
begin
  mFile := TPath.Combine(FTempDir, 'Einzeln.pas');
  TFile.WriteAllText(mFile, 'unit Einzeln; interface implementation end.');
  FFolders.Derive(mFile);
  Assert.AreEqual(0, Integer(FRegistry.Items.Count));
  Assert.AreEqual(0, FLoaded);
end;

procedure TShellFoldersTests.SchedulerExists;
begin
  Assert.IsNotNull(FFolders.Scheduler);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellFoldersTests);

end.
