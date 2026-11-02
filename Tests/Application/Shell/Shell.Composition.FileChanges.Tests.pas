unit Shell.Composition.FileChanges.Tests;

// Dateiänderungen: Quelltexte gehen in die Projektprüfung, .inc prüft offene Dateien neu, die globale Datei
// liest neu, Tippen macht der Projektprüfung Platz, nach dem Beenden der Tipp-Pause wirkt der Editor nicht mehr.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Configuration,
  Shell.Composition.FileChanges;

type
  [TestFixture]
  TShellFileChangesTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FConfiguration: TShellConfiguration;
    FChanges: TShellFileChanges;
    FFolder: string;
    FEvents: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Geänderte Unit: nur die Projektprüfung, keine Neuprüfung der offenen Dateien.</summary>
    [Test]
    procedure SourceChangeChecksAffected;
    /// <summary>Geänderte .inc: zusätzlich die offenen Dateien neu prüfen (#860).</summary>
    [Test]
    procedure IncludeChangeRefreshesOpenFiles;
    /// <summary>Projektdatei ohne Ordner und fremde Dateien bewirken nichts.</summary>
    [Test]
    procedure UnknownFilesDoNothing;
    /// <summary>Die globale Datei von außen geändert: Sie wird neu gelesen.</summary>
    [Test]
    procedure GlobalSettingsReload;
    /// <summary>Tippen meldet sich bei der Projektprüfung, Schließen liest die Datei der Platte.</summary>
    [Test]
    procedure EditorEventsReachChecks;
    /// <summary>Nach StopRefresh wirken Editorereignisse nicht mehr.</summary>
    [Test]
    procedure StoppedRefreshIgnoresEditor;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Contract;

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

procedure NoFiles(const AFiles: TArray<string>);
begin
  // Die Tests ändern keine beobachtete Datei auf der Platte.
end;

procedure TShellFileChangesTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
  mConfiguration: TShellConfigurationServices;
  mServices: TShellFileChangesServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguageLevel);
  mConfiguration := Default(TShellConfigurationServices);
  mConfiguration.Logger := TLogger.Create;
  mConfiguration.Workspaces := FRegistry;
  mConfiguration.Settings := FSettings;
  mConfiguration.Documents := TDocumentStore.Create;
  mConfiguration.FilesChanged := NoFiles;
  FConfiguration := TShellConfiguration.Create(mConfiguration);
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasFileChanges' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
  FEvents := '';
  mServices := Default(TShellFileChangesServices);
  mServices.Logger := TLogger.Create;
  mServices.Workspaces := FRegistry;
  mServices.Configuration := FConfiguration;
  mServices.RefreshLater :=
    procedure
    begin
      FEvents := FEvents + 'refresh;';
    end;
  mServices.Typed :=
    procedure
    begin
      FEvents := FEvents + 'typed;';
    end;
  mServices.Affected :=
    procedure(const AFiles: TArray<string>)
    begin
      FEvents := FEvents + 'affected:' + string.Join(',', AFiles) + ';';
    end;
  FChanges := TShellFileChanges.Create(mServices);
end;

procedure TShellFileChangesTests.TearDown;
begin
  FreeAndNil(FChanges);
  FreeAndNil(FConfiguration);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
  FEvents := '';
end;

procedure TShellFileChangesTests.SourceChangeChecksAffected;
begin
  FChanges.Handle(TArray<TFileChange>.Create(TFileChange.Create('A.pas', TFileChangeKind.Changed),
    TFileChange.Create('B.dpr', TFileChangeKind.Created)));
  Assert.AreEqual('affected:A.pas,B.dpr;', FEvents);
end;

procedure TShellFileChangesTests.IncludeChangeRefreshesOpenFiles;
begin
  FChanges.Handle(TArray<TFileChange>.Create(TFileChange.Create('Defines.inc', TFileChangeKind.Changed)));
  Assert.AreEqual('refresh;affected:Defines.inc;', FEvents);
end;

procedure TShellFileChangesTests.UnknownFilesDoNothing;
begin
  FChanges.Handle(TArray<TFileChange>.Create(TFileChange.Create('P.dproj', TFileChangeKind.Changed),
    TFileChange.Create('Liesmich.txt', TFileChangeKind.Changed)));
  Assert.AreEqual('', FEvents);
end;

procedure TShellFileChangesTests.GlobalSettingsReload;
var
  mFile: string;
begin
  mFile := TPath.Combine(FFolder, 'settings.json');
  TFile.WriteAllText(mFile, '{}', TEncoding.UTF8);
  FConfiguration.UseReplaySettings(mFile);
  FConfiguration.Start;
  TFile.WriteAllText(mFile, '{"hover":{"enabled":false}}', TEncoding.UTF8);
  FChanges.Handle(TArray<TFileChange>.Create(TFileChange.Create(mFile, TFileChangeKind.Changed)));
  Assert.AreEqual('{"hover":{"enabled":false}}', Trim(FSettings.GlobalSettings));
  Assert.AreEqual('', FEvents);
end;

procedure TShellFileChangesTests.EditorEventsReachChecks;
begin
  FChanges.DocumentEvent(TDocumentEventKind.Changed, 'A.pas', 'unit A;');
  Assert.AreEqual('typed;', FEvents);
  FChanges.DocumentEvent(TDocumentEventKind.Closed, 'A.pas', '');
  Assert.AreEqual('typed;affected:A.pas;', FEvents);
end;

procedure TShellFileChangesTests.StoppedRefreshIgnoresEditor;
begin
  FChanges.StopRefresh;
  FChanges.DocumentEvent(TDocumentEventKind.Changed, 'A.pas', 'unit A;');
  FChanges.DocumentEvent(TDocumentEventKind.Closed, 'A.pas', '');
  Assert.AreEqual('', FEvents);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellFileChangesTests);

end.
