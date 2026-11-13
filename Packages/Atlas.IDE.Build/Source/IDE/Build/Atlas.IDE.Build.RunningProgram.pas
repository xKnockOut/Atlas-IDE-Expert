unit Atlas.IDE.Build.RunningProgram;

// Laufendes Programm vor dem Build beenden (#551), Teilnehmer an den Compile-Ereignissen
// (#527): Vor jedem Compile entscheidet TAtlasRunningProgram (Core) nach
// build.stopRunningProgram, den laufenden Prozessen und den Prozessen im Debugger der IDE.
// - Rückfrage (ask): Ja beendet und baut, Nein baut wie bisher (scheitert dann mit F2039),
//   Immer beendet und stellt die Einstellung auf always.
// - Beenden: WM_CLOSE, nach 2 s TerminateProcess. Gelingt es nicht, bricht der Compile mit
//   Grund ab, statt erst am Ende zu scheitern.
// - Package: Hinweis in der Gruppe Atlas des Meldungsfensters mit den Prozessen.
// Nur im Hauptthread (BeforeCompile der IDE).

interface

uses
  Atlas.Core.Build.Events;

type
  TAtlasIdeRunningProgram = class
  public
    /// <summary>Neuer Teilnehmer; die Compile-Ereignisse übernehmen ihn.</summary>
    class function CreateParticipant: TAtlasCompileParticipant; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Build.RunningProgram,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Build.RunningProcesses,
  Atlas.UI.Build.RunningPrompt,
  Atlas.UI.Build.Strings;

type
  TParticipant = class(TAtlasCompileParticipant)
  private
    function Stop(const APlan: TAtlasRunningProgramPlan; out AReason: string): Boolean;
    function Ask(const APlan: TAtlasRunningProgramPlan; out AReason: string): Boolean;
  public
    function CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean; override;
  end;

/// <summary>Prozesse im Debugger der IDE; die bleiben unberührt.</summary>
function DebuggedPids: TArray<Cardinal>;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ProcessCount - 1 do
  begin
    Result := Result + [Cardinal(mServices.Processes[mIndex].ProcessId)];
  end;
end;

/// <summary>build.stopRunningProgram auf always stellen (Antwort „Immer“).</summary>
procedure RememberAlways;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Stored;
  mSettings.BuildStopRunningProgram := TAtlasRunningProgram.cModeNames[TAtlasStopRunningMode.Always];
  TAtlasIdeSettings.Update(mSettings);
end;

{ TParticipant }

function TParticipant.Stop(const APlan: TAtlasRunningProgramPlan; out AReason: string): Boolean;
var
  mProcess: TAtlasRunningProcess;
begin
  AReason := '';
  for mProcess in APlan.Processes do
  begin
    if not TAtlasIdeRunningProcesses.Stop(mProcess.Pid, TAtlasRunningProgram.cGraceMs) then
    begin
      AReason := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.RunningProgramNotStopped, [mProcess.Name, mProcess.Pid]);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TParticipant.Ask(const APlan: TAtlasRunningProgramPlan; out AReason: string): Boolean;
begin
  AReason := '';
  case TAtlasRunningPrompt.Ask(APlan.ProgramName, APlan.ProcessNames) of
    TAtlasRunningPromptChoice.Stop:
      Result := Stop(APlan, AReason);
    TAtlasRunningPromptChoice.Always:
      begin
        RememberAlways;
        Result := Stop(APlan, AReason);
      end;
  else
    // Nein: der Build läuft wie bisher.
    Result := False;
  end;
end;

function TParticipant.CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
var
  mMode: TAtlasStopRunningMode;
  mPlan: TAtlasRunningProgramPlan;
  mRunning: TArray<TAtlasRunningProcess>;
begin
  AReason := '';
  Result := False;
  mMode := TAtlasRunningProgram.ModeOf(TAtlasIdeSettings.Current.BuildStopRunningProgram);
  if (mMode = TAtlasStopRunningMode.Never) or (Trim(AProject.OutputFile) = '') then
  begin
    Exit;
  end;
  if TAtlasRunningProgram.IsPackage(AProject.OutputFile) then
  begin
    mRunning := TAtlasIdeRunningProcesses.LoadingModule(AProject.OutputFile);
  end
  else
  begin
    mRunning := TAtlasIdeRunningProcesses.Programs;
  end;
  mPlan := TAtlasRunningProgram.Plan(AProject, mMode, mRunning, DebuggedPids, TAtlasIdeRunningProcesses.OwnPid);
  case mPlan.Action of
    TAtlasRunningProgramAction.None:
      Exit;
    TAtlasRunningProgramAction.Ask:
      Result := Ask(mPlan, AReason);
    TAtlasRunningProgramAction.Stop:
      Result := Stop(mPlan, AReason);
    TAtlasRunningProgramAction.Notice:
      TAtlasIdeHost.Message(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.RunningProgramPackageLoaded,
        [mPlan.ProgramName, mPlan.ProcessNames]));
  end;
end;

{ TAtlasIdeRunningProgram }

class function TAtlasIdeRunningProgram.CreateParticipant: TAtlasCompileParticipant;
begin
  Result := TParticipant.Create;
end;

end.
