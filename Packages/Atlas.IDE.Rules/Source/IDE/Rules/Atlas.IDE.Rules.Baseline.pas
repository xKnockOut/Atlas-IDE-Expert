unit Atlas.IDE.Rules.Baseline;

// Baseline des Projekts im Modul Prüfregeln (#97, #1455):
// - „Baseline des Projekts aktualisieren“ (Atlas.UpdateBaseline): nennt vorher
//   die Einträge ohne Datei und fragt nach, dann lässt der Server
//   (atlas.updateBaseline) alle Dateien des aktiven Projekts prüfen und die
//   Baseline schreiben. Die Zähler stehen danach in der Meldungsansicht, den
//   neuen Stand schreibt das Modul in die Projekt-Zusammenfassung von Base
//   (TAtlasIdeProjectSummaries, Projektverlauf #758).
//   StartUpdate ist zugleich IAtlasBaselineSource für die Einrichtung (#759).
// - „Aktuelle Compilermeldungen in die Basislinie“ (#530): Warnungen und
//   Hinweise des letzten Builds des aktiven Projekts
//   (TAtlasIdeLastBuildMessages.Current) über atlas.baselineCompilerMessages.
// Beide sind mit BaselineUpdate (baseline.update) abschaltbar. Befehle an den
// Server gehen über TAtlasIdeHost: Antworten kommen im Hauptthread und nur,
// solange das Modul angemeldet ist (Regel 3). Den Stand der Datei danach liest
// das Modul deshalb im Hauptthread; das geschieht einmal je Aktualisieren,
// das der Benutzer anstößt (vorher liest es ihn für die Rückfrage ebenso).
// Install setzt den Scope des Moduls, Uninstall nimmt ihn zurück.

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Contracts.Rules;

type
  TAtlasIdeRulesBaseline = class
  private class var
    FScope: IAtlasModuleScope;
  public
    class procedure Install(const AScope: IAtlasModuleScope); static;
    class procedure Uninstall; static;
    /// <summary>baseline.update an.</summary>
    class function Enabled: Boolean; static;
    /// <summary>Baseline von AProject über den Server aktualisieren; ADone darf nil sein. '' = gestartet, sonst
    /// der Grund.</summary>
    class function StartUpdate(const AProject: string; const ADone: TAtlasBaselineUpdateDone): string; static;
    /// <summary>Befehl „Baseline des Projekts aktualisieren“ für das aktive Projekt.</summary>
    class procedure UpdateActiveProject; static;
    /// <summary>Befehl „Aktuelle Compilermeldungen in die Basislinie“ für das aktive Projekt.</summary>
    class procedure AddCompilerMessages; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Projects.Baseline,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Build.LastMessages,
  Atlas.UI.Rules.Strings;

const
  /// <summary>Höchstens so viele Pfade in Rückfrage und Meldung; der Rest als „… und n weitere“.</summary>
  OrphanLines = 15;

function ActiveProjectFile: string;
var
  mProject: IOTAProject;
begin
  Result := '';
  mProject := GetActiveProject;
  if mProject <> nil then
    Result := mProject.FileName;
end;

/// <summary>Einträge ohne Datei als Zeilen „Pfad (n Treffer)“, höchstens OrphanLines.</summary>
function OrphanText(const AOrphans: TArray<TAtlasBaselineOrphan>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AOrphans) do
  begin
    if mIndex = OrphanLines then
    begin
      Result := Result + [TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateOrphansMore,
        [Length(AOrphans) - mIndex])];
      Break;
    end;
    Result := Result + [TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateOrphanLine, [AOrphans[mIndex].Path,
      AOrphans[mIndex].Count])];
  end;
end;

/// <summary>Ergebnis von atlas.updateBaseline in der Meldungsansicht: zuerst die entfernten Einträge ohne Datei mit
/// Pfaden, dann die Zähler. Nur dort, nicht im Plugin-Protokoll: Es enthält Pfade.</summary>
procedure ReportUpdate(const AUpdate: TAtlasBaselineUpdate);
var
  mLine: string;
begin
  if AUpdate.OrphanCount > 0 then
  begin
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateOrphans, [AUpdate.OrphanCount]));
    for mLine in OrphanText(AUpdate.Orphans) do
      TAtlasIdeHost.Message(mLine);
  end;
  TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateDone, [AUpdate.FileName, AUpdate.Total,
    AUpdate.Files, AUpdate.Added, AUpdate.Removed, AUpdate.Unchanged]));
  if AUpdate.Completed > 0 then
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateCompleted, [AUpdate.Completed]));
  // Bericht N3: Die unbrauchbare bisherige Datei wurde nicht still ersetzt.
  if AUpdate.SetAside <> '' then
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateSetAside, [AUpdate.SetAside]));
end;

/// <summary>Neuer Stand der Baseline in die Projekt-Zusammenfassung (Projektverlauf #758).</summary>
procedure NotifyUpdated(const AProject: string; const AUpdate: TAtlasBaselineUpdate;
  const AState: TAtlasBaselineState);
begin
  if TAtlasIdeProjectSummaries.Current <> nil then
    TAtlasGuard.Run(TAtlasFeature.Palette,
      procedure
      begin
        TAtlasIdeProjectSummaries.Current.RecordBaseline(AProject, AState, AUpdate,
          TAtlasIdeProjectSummaries.StampUtc);
      end);
end;

/// <summary>Der Server schrieb außerhalb des Projektordners: nur der Stand im Projektordner.</summary>
procedure NotifyMeasured(const AProject: string; const AState: TAtlasBaselineState);
begin
  if TAtlasIdeProjectSummaries.Current <> nil then
    TAtlasGuard.Run(TAtlasFeature.Palette,
      procedure
      begin
        TAtlasIdeProjectSummaries.Current.RecordBaseline(AProject, AState, TAtlasIdeProjectSummaries.StampUtc);
      end);
end;

/// <summary>Antwort von atlas.updateBaseline auswerten (Hauptthread).</summary>
procedure UpdateAnswered(const AProject, AAnswer: string; const ADone: TAtlasBaselineUpdateDone);
var
  mUpdate: TAtlasBaselineUpdate;
  mState: TAtlasBaselineState;
begin
  if not TAtlasProjectBaselines.FromServer(AAnswer, mUpdate) then
  begin
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Text(TAtlasRulesTextId.BaselineUpdateFailed));
    if Assigned(ADone) then
      ADone(False, 0, 0, TAtlasRulesStrings.Text(TAtlasRulesTextId.BaselineUpdateFailed));
    Exit;
  end;
  ReportUpdate(mUpdate);
  // Nicht im Projektordner geschrieben (#758): Verlauf und Einrichtung lesen weiter dort.
  if TAtlasProjectBaselines.WrittenElsewhere(AProject, mUpdate.FileName) then
  begin
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateElsewhere,
      [ExtractFileDir(mUpdate.FileName),
      ExtractFileDir(AProject)]));
    // Zähler des Servers gehören zur anderen Datei: nur den Stand im Projektordner melden.
    mState := TAtlasProjectBaselines.StateOnDisk(ExtractFileDir(AProject));
    NotifyMeasured(AProject, mState);
    if Assigned(ADone) then
      ADone(False, 0, 0, TAtlasRulesStrings.Text(TAtlasRulesTextId.WelcomeSetupBaselineElsewhere));
    Exit;
  end;
  mState := TAtlasProjectBaselines.StateOnDisk(ExtractFileDir(mUpdate.FileName));
  NotifyUpdated(AProject, mUpdate, mState);
  if Assigned(ADone) then
    ADone(True, mUpdate.Total, mUpdate.Files, '');
end;

/// <summary>Rückruf für die Antwort; eigene Routine, damit der Rahmen nur Projekt und ADone hält.</summary>
function UpdateAnswer(const AProject: string; const ADone: TAtlasBaselineUpdateDone): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mAnswer: string;
    begin
      mAnswer := AAnswer;
      TAtlasGuard.Run(TAtlasFeature.Palette,
        procedure
        begin
          UpdateAnswered(AProject, mAnswer, ADone);
        end);
    end;
end;

{ TAtlasIdeRulesBaseline }

class procedure TAtlasIdeRulesBaseline.Install(const AScope: IAtlasModuleScope);
begin
  FScope := AScope;
end;

class procedure TAtlasIdeRulesBaseline.Uninstall;
begin
  FScope := nil;
end;

class function TAtlasIdeRulesBaseline.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BaselineUpdate;
end;

class function TAtlasIdeRulesBaseline.StartUpdate(const AProject: string;
  const ADone: TAtlasBaselineUpdateDone): string;
begin
  Result := '';
  // Startet den Server bei Bedarf; der Befehl selbst läuft im Hintergrund.
  if (FScope = nil) or (TAtlasIdeHost.ActiveSession = nil) then
    Exit(TAtlasRulesStrings.Text(TAtlasRulesTextId.BaselineUpdateFailed));
  if not TAtlasIdeHost.RunCommandAsync(FScope, TAtlasFeature.Menu, TAtlasProjectBaselines.Command,
    TAtlasProjectBaselines.Arguments(TLspSession.PathToUri(AProject)), TAtlasProjectBaselines.TimeoutMs,
    UpdateAnswer(AProject, ADone)) then
    // Ein Befehl im Hintergrund läuft schon (etwa die Werte nach einem Build): später noch einmal.
    Result := TAtlasRulesStrings.Text(TAtlasRulesTextId.BaselineUpdateBusy);
end;

class procedure TAtlasIdeRulesBaseline.UpdateActiveProject;
var
  mFileName, mReason: string;
  mState: TAtlasBaselineState;
begin
  // Abgeschaltet: auch über Tastenkürzel oder „Ausprobieren“ nichts tun.
  if not Enabled then
    Exit;
  mFileName := ActiveProjectFile;
  if mFileName = '' then
  begin
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Text(TAtlasRulesTextId.BaselineUpdateNoProject));
    Exit;
  end;
  if TAtlasIdeHost.ActiveSession = nil then
  begin
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Text(TAtlasRulesTextId.BaselineUpdateFailed));
    Exit;
  end;
  // Einträge ohne Datei nennen, bevor das Aktualisieren sie entfernt (umbenannte oder verschobene Dateien).
  mState := TAtlasProjectBaselines.StateOnDisk(ExtractFileDir(mFileName));
  if (mState.OrphanCount > 0) and (MessageDlg(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.BaselineUpdateConfirm,
    [mState.OrphanCount, sLineBreak + string.Join(sLineBreak, OrphanText(mState.Orphans)) + sLineBreak +
    sLineBreak]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  mReason := StartUpdate(mFileName, nil);
  if mReason = '' then
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Text(TAtlasRulesTextId.BaselineUpdateRunning))
  else
    TAtlasIdeHost.Warning(mReason);
end;

/// <summary>Antwort von atlas.baselineCompilerMessages (#530) in der Meldungsansicht.</summary>
procedure ReportCompilerBaseline(AAnswer: string);
var
  mValue: TJSONValue;
  mAdded: TAtlasCompilerBaselineAdd;
  mValid: Boolean;
begin
  mValue := nil;
  if AAnswer <> '' then
    mValue := TJSONValue.ParseJSONValue(AAnswer);
  try
    mValid := TAtlasCompilerBaselineAdd.FromServer(mValue, mAdded);
  finally
    mValue.Free;
  end;
  if not mValid then
  begin
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Text(TAtlasRulesTextId.CompilerBaselineFailed));
    Exit;
  end;
  TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.CompilerBaselineDone, [mAdded.FileName, mAdded.Total,
    mAdded.Added, mAdded.Removed, mAdded.Unchanged]));
  if mAdded.Skipped > 0 then
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.CompilerBaselineSkipped, [mAdded.Skipped]));
end;

class procedure TAtlasIdeRulesBaseline.AddCompilerMessages;
var
  mFileName: string;
  mSummary: TAtlasIdeLastBuildMessages;
  mMessages: TArray<TAtlasCompilerMessage>;
begin
  mSummary := TAtlasIdeLastBuildMessages.Current;
  if (FScope = nil) or (mSummary = nil) or not Enabled then
    Exit;
  mFileName := ActiveProjectFile;
  if mFileName = '' then
  begin
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Text(TAtlasRulesTextId.CompilerBaselineNoProject));
    Exit;
  end;
  mMessages := mSummary.Baselinable(mFileName);
  if Length(mMessages) = 0 then
  begin
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.CompilerBaselineNone, [ExtractFileName(mFileName)]));
    Exit;
  end;
  // Startet den Server bei Bedarf; der Befehl selbst läuft nebenläufig im Hintergrund.
  if (TAtlasIdeHost.ActiveSession = nil) or not TAtlasIdeHost.RunServerCommandAsync(FScope, TAtlasFeature.Menu,
    TAtlasBuildVerdicts.AddCommand, TAtlasBuildVerdicts.Arguments(TLspSession.PathToUri(mFileName), mMessages),
    TAtlasBuildVerdicts.AddTimeoutMs, ReportCompilerBaseline) then
    TAtlasIdeHost.Warning(TAtlasRulesStrings.Text(TAtlasRulesTextId.CompilerBaselineFailed));
end;

end.
