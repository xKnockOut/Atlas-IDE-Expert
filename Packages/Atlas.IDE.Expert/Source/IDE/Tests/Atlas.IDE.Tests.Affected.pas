unit Atlas.IDE.Tests.Affected;

// Befehl „Betroffene Tests ausführen“ (#1353, Atlas.RunAffectedTests):
// Der Server (atlas/affectedTests) vergleicht den Arbeitsbereich des aktiven
// Projekts mit der Basis (Git: Merge-Base mit main, SVN: BASE; nicht
// eingecheckte Änderungen zählen mit), bestimmt die geänderten Routinen und
// nennt die DUnitX-Tests, die sie erreichen. Die Meldungsansicht zeigt sie mit
// Grund; dann laufen genau diese über den Testläufer (#69). Sind alle Tests
// nötig (Projektdatei geändert, Analyse unvollständig), laufen alle.
// Die Anfrage geht in einen eigenen Thread; nur die jüngste kommt an.
// tests.affectedBeforeCommit: Atlas legt für das Repository des Testprojekts
// den Git-Hook pre-commit an (Atlas.Core.Tests.AffectedHook) bzw. entfernt ihn,
// wenn die Einstellung aus ist. git läuft dabei im Arbeiter-Thread.
// Haken statt Imports (A-09): Testläufer und Serverpfad kommen über Install.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Tests.Run;

type
  /// <summary>Testlauf: Datei aus dem Testprojekt und Namen für --run.</summary>
  TAtlasAffectedTestRun = reference to procedure(const AFileName: string; const ATests: TArray<string>);
  /// <summary>Ziel des Testprojekts (für den Hook).</summary>
  TAtlasAffectedTargetProc = reference to procedure(const ATarget: TAtlasTestTarget);
  /// <summary>Löst das Testprojekt auf und ruft AThen im Hauptthread; ohne Testprojekt nie.</summary>
  TAtlasAffectedResolveTarget = reference to procedure(const AThen: TAtlasAffectedTargetProc);

  /// <summary>Haken der Composition.</summary>
  TAtlasAffectedTestsHooks = record
    RunTests: TAtlasAffectedTestRun;
    RunAll: TProc;
    ResolveTarget: TAtlasAffectedResolveTarget;
    ServerPath: TFunc<string>;
  end;

  TAtlasIdeAffectedTests = class
  private class var
    FWorkers: TArray<TThread>;
    FRequest: Integer;
    FHooks: TAtlasAffectedTestsHooks;
    /// <summary>Hook-Ordner, für die Atlas schon gemeldet hat (einmal je Sitzung).</summary>
    FReported: TArray<string>;
  private
    class procedure Spawn(const AWork: TProc); static;
    class procedure Reap(AWait: Boolean); static;
    class procedure Show(ARequest: Integer; const AFound: TAtlasAffectedTests; const AError: string); static;
    class procedure InstallHook(const ATarget: TAtlasTestTarget); static;
    class procedure RemoveHook(const AFolder: string); static;
    class procedure ReportOnce(const AHooksDir, AText: string); static;
    class function ActiveProject: string; static;
  public
    class procedure Install(const AHooks: TAtlasAffectedTestsHooks); static;
    /// <summary>Beim Entladen: wartet auf laufende Arbeiter und löst die Haken.</summary>
    class procedure Uninstall; static;
    /// <summary>Befehl sichtbar: tests.affected und tests.run.</summary>
    class function Enabled: Boolean; static;
    /// <summary>Betroffene Tests ermitteln und ausführen.</summary>
    class procedure Run; static;
    /// <summary>Nach dem Speichern der Optionen: Hook anlegen bzw. entfernen (tests.affectedBeforeCommit).
    /// </summary>
    class procedure ApplySettings; static;
    /// <summary>Zeilen für die Meldungsansicht (Zusammenfassung, je Test Name und Gründe).</summary>
    class function Lines(const AFound: TAtlasAffectedTests): TArray<string>; static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Tests.AffectedHook,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Vcs.Service;

{ TAtlasIdeAffectedTests }

class procedure TAtlasIdeAffectedTests.Install(const AHooks: TAtlasAffectedTestsHooks);
begin
  FHooks := AHooks;
end;

class procedure TAtlasIdeAffectedTests.Uninstall;
begin
  // Spätere Antworten verwerfen; beim Entladen bricht TAtlasShutdown die Anfragen ab, dann auf alle warten.
  Inc(FRequest);
  Reap(TAtlasShutdown.Signalled);
  FHooks := Default(TAtlasAffectedTestsHooks);
  FReported := nil;
end;

class function TAtlasIdeAffectedTests.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestsAffected and TAtlasIdeSettings.Current.TestRun;
end;

class function TAtlasIdeAffectedTests.ActiveProject: string;
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
    Exit;
  mProject := mServices.GetActiveProject;
  if mProject <> nil then
    Result := mProject.FileName;
end;

class procedure TAtlasIdeAffectedTests.Reap(AWait: Boolean);
var
  mIndex: Integer;
  mRemaining: TArray<TThread>;
begin
  mRemaining := nil;
  for mIndex := 0 to High(FWorkers) do
    if AWait or FWorkers[mIndex].Finished then
    begin
      FWorkers[mIndex].WaitFor;
      FWorkers[mIndex].Free;
    end
    else
      mRemaining := mRemaining + [FWorkers[mIndex]];
  FWorkers := mRemaining;
end;

class procedure TAtlasIdeAffectedTests.Spawn(const AWork: TProc);
var
  mWorker: TThread;
begin
  Reap(False);
  mWorker := TThread.CreateAnonymousThread(AWork);
  mWorker.FreeOnTerminate := False;
  FWorkers := FWorkers + [mWorker];
  mWorker.Start;
end;

class procedure TAtlasIdeAffectedTests.Run;
var
  mSession: TLspSession;
  mRequest: Integer;
  mFileName: string;
begin
  if not Enabled then
  begin
    TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.TestsAffectedOff));
    Exit;
  end;
  mSession := TAtlasIdeResults.Session;
  if mSession = nil then
  begin
    TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mFileName := ActiveProject;
  if mFileName = '' then
  begin
    TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.TestsAffectedNoProject));
    Exit;
  end;
  // git bzw. svn vergleichen die gespeicherten Dateien; der Server liest sie für die Zuordnung ebenfalls von der
  // Platte. Ungespeicherte Änderungen zählen erst nach dem Speichern.
  Inc(FRequest);
  mRequest := FRequest;
  TAtlasIdeResults.Say(TAtlasStrings.Text(TAtlasTextId.TestsAffectedRunning));
  Spawn(
    procedure
    var
      mFound: TAtlasAffectedTests;
      mError: string;
    begin
      mFound := Default(TAtlasAffectedTests);
      mError := '';
      try
        mFound := mSession.AffectedTests(mFileName, '');
      except
        on E: Exception do
          mError := E.Message;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Build,
        procedure
        begin
          Show(mRequest, mFound, mError);
        end);
    end);
  ApplySettings;
end;

class function TAtlasIdeAffectedTests.Lines(const AFound: TAtlasAffectedTests): TArray<string>;
var
  mTest: TAtlasAffectedTest;
begin
  if AFound.All then
    Exit(TArray<string>.Create(TAtlasStrings.Fmt(TAtlasTextId.TestsAffectedAll, [AFound.AllReason])));
  if Length(AFound.Tests) = 0 then
    Exit(TArray<string>.Create(TAtlasStrings.Fmt(TAtlasTextId.TestsAffectedNone, [AFound.Base])));
  Result := TArray<string>.Create(TAtlasStrings.Fmt(TAtlasTextId.TestsAffectedFound,
    [AFound.Base, AFound.Depth, Length(AFound.Tests)]));
  for mTest in AFound.Tests do
    if Length(mTest.Reasons) > 0 then
      Result := Result + ['  ' + mTest.Name + ' – ' + String.Join('; ', mTest.Reasons)]
    else
      Result := Result + ['  ' + mTest.Name];
end;

class procedure TAtlasIdeAffectedTests.Show(ARequest: Integer; const AFound: TAtlasAffectedTests;
  const AError: string);
var
  mLine: string;
begin
  // Eine neuere Anfrage läuft schon oder das Package wird entladen.
  if ARequest <> FRequest then
    Exit;
  if AError <> '' then
  begin
    TAtlasIdeResults.Say(TAtlasStrings.Fmt(TAtlasTextId.TestsAffectedFailed, [AError]));
    Exit;
  end;
  for mLine in Lines(AFound) do
    TAtlasIdeResults.Say(mLine);
  if AFound.All then
  begin
    if Assigned(FHooks.RunAll) then
      FHooks.RunAll();
  end
  else if (Length(AFound.Tests) > 0) and Assigned(FHooks.RunTests) then
    // Der Server meldet nur Tests aus Testprogrammen: Eine Datei genügt, um das Testprojekt zu finden.
    FHooks.RunTests(AFound.Tests[0].FileName, AFound.Run);
end;

class procedure TAtlasIdeAffectedTests.ApplySettings;
var
  mProject: string;
begin
  if TAtlasIdeSettings.Current.TestsAffectedBeforeCommit and Enabled then
  begin
    if Assigned(FHooks.ResolveTarget) then
      FHooks.ResolveTarget(
        procedure(const ATarget: TAtlasTestTarget)
        begin
          InstallHook(ATarget);
        end);
    Exit;
  end;
  mProject := ActiveProject;
  if mProject <> '' then
    RemoveHook(ExtractFilePath(mProject));
end;

class procedure TAtlasIdeAffectedTests.InstallHook(const ATarget: TAtlasTestTarget);
var
  mConfig: TAtlasAffectedHookConfig;
  mFolder: string;
begin
  if (ATarget.Project = '') or not Assigned(FHooks.ServerPath) then
    Exit;
  mConfig := Default(TAtlasAffectedHookConfig);
  mConfig.ServerPath := FHooks.ServerPath();
  mConfig.Project := ATarget.Project;
  mConfig.Executable := ATarget.Executable;
  mFolder := ExtractFilePath(ATarget.Project);
  Spawn(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mBranching: IAtlasVcsBranching;
      mHooks, mGitDir, mText: string;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder);
      // SVN hat keine Hooks auf dem Client: Nur Git kennt HookFolders.
      if not Supports(mVcs, IAtlasVcsBranching, mBranching) or
        (mBranching.HookFolders(mHooks, mGitDir) <> TAtlasVcsOutcome.Ok) then
        Exit;
      if TAtlasAffectedHook.State(mHooks) = TAtlasAffectedHookState.Foreign then
        mText := TAtlasStrings.Fmt(TAtlasTextId.TestsAffectedHookForeign, [mHooks])
      else if (TAtlasAffectedHook.State(mHooks) = TAtlasAffectedHookState.Missing) and
        TAtlasAffectedHook.Install(mHooks, mGitDir, mConfig) then
        mText := TAtlasStrings.Fmt(TAtlasTextId.TestsAffectedHookInstalled, [mHooks])
      else
      begin
        // Eigener Hook: Skript und Angaben auf den Stand bringen (Testprojekt, Serverpfad).
        TAtlasAffectedHook.Install(mHooks, mGitDir, mConfig);
        mText := '';
      end;
      if mText <> '' then
        TAtlasMainThread.Queue(TAtlasFeature.Build,
          procedure
          begin
            ReportOnce(mHooks, mText);
          end);
    end);
end;

class procedure TAtlasIdeAffectedTests.RemoveHook(const AFolder: string);
begin
  Spawn(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mBranching: IAtlasVcsBranching;
      mHooks, mGitDir: string;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(AFolder);
      if Supports(mVcs, IAtlasVcsBranching, mBranching) and
        (mBranching.HookFolders(mHooks, mGitDir) = TAtlasVcsOutcome.Ok) and
        (TAtlasAffectedHook.State(mHooks) = TAtlasAffectedHookState.Own) then
        TAtlasAffectedHook.Uninstall(mHooks, mGitDir);
    end);
end;

class procedure TAtlasIdeAffectedTests.ReportOnce(const AHooksDir, AText: string);
var
  mDir: string;
begin
  for mDir in FReported do
    if SameText(mDir, AHooksDir) then
      Exit;
  FReported := FReported + [AHooksDir];
  TAtlasIdeResults.Say(AText);
end;

end.
