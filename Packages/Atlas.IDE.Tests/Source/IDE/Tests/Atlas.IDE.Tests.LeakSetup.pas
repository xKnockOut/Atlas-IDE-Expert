unit Atlas.IDE.Tests.LeakSetup;

// Befehl „Leckprüfung einrichten …“ (#1880) des Moduls Tests: Projekt aus der
// Auswahl der Projektverwaltung, sonst das aktive. Ablauf:
//   1. atlas.server.leakSetup [uri] → Stand, Dialog (Atlas.UI.Tests.LeakSetup)
//   2. mit der gewählten Variante noch einmal → Plan
//   3. Einfügungen in den Hauptquelltext mit Vorschau wie beim Umbenennen
//      (rückgängig im Editor), Symbole über die Projektoptionen der IDE in die
//      Konfiguration Debug (nie in Release), DLL nur nach Rückfrage kopieren.
// Nur im Hauptthread; die Antworten des Servers kommen über TAtlasIdeHost.

interface

uses
  Atlas.Core.Modules.Contract;

type
  TAtlasIdeLeakSetup = class
  public const
    cTimeoutMs = 15000;
  public
    /// <summary>Befehl ausführen; AScope hält die Antworten des Servers (nach dem Abmelden kommen keine).</summary>
    class procedure Run(const AScope: IAtlasModuleScope); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.UITypes,
  System.JSON,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.ProjectSelection,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Tests.LeakSetup,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit,
  Atlas.UI.Tests.LeakSetup,
  Atlas.UI.Tests.Strings;

/// <summary>Projekt der Auswahl in der Projektverwaltung, sonst das aktive; '' ohne.</summary>
function TargetProject: string;
begin
  Result := '';
  if TAtlasProjectContext.Active then
  begin
    Result := TAtlasProjectContext.Current.ProjectFile;
  end;
  if Result = '' then
  begin
    Result := TAtlasIdeFiles.ActiveProjectFile;
  end;
end;

procedure Report(AId: TAtlasTestsTextId; const AArgs: array of const);
begin
  TAtlasIdeHost.Message(TAtlasTestsStrings.Fmt(AId, AArgs));
end;

{ Symbole }

/// <summary>Konfiguration Debug des Projekts; nil ohne.</summary>
function DebugConfiguration(const AProject: IOTAProject): IOTABuildConfiguration;
var
  mConfigurations: IOTAProjectOptionsConfigurations;
  mIndex: Integer;
begin
  Result := nil;
  if (AProject = nil) or not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations,
    mConfigurations) then
  begin
    Exit;
  end;
  for mIndex := 0 to mConfigurations.ConfigurationCount - 1 do
  begin
    if SameText(mConfigurations.Configurations[mIndex].Name, TAtlasLeakSetup.cDebugConfiguration) then
    begin
      Exit(mConfigurations.Configurations[mIndex]);
    end;
  end;
end;

procedure WriteDefines(const AProjectFile: string; const ADefines: TArray<string>);
var
  mProject: IOTAProject;
  mConfiguration: IOTABuildConfiguration;
  mNames: string;
begin
  if Length(ADefines) = 0 then
  begin
    Exit;
  end;
  mNames := string.Join(', ', ADefines);
  mProject := TAtlasIdeFiles.GroupProject(AProjectFile);
  mConfiguration := DebugConfiguration(mProject);
  if mConfiguration = nil then
  begin
    Report(TAtlasTestsTextId.LeakNoDebugConfig, [ExtractFileName(AProjectFile), mNames]);
    Exit;
  end;
  try
    mConfiguration.SetValue(TAtlasLeakSetup.cDefineOption,
      TAtlasLeakSetup.WithDefines(mConfiguration.GetValue(TAtlasLeakSetup.cDefineOption, False), ADefines));
    mProject.MarkModified;
    Report(TAtlasTestsTextId.LeakDefinesDone, [mNames, ExtractFileName(AProjectFile)]);
  except
    on E: Exception do
    begin
      Report(TAtlasTestsTextId.LeakDefinesFailed, [E.Message]);
    end;
  end;
end;

{ DLL }

procedure CopyDll(const AInfo: TAtlasLeakSetupInfo);
var
  mTarget: string;
begin
  if MessageDlg(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.LeakCopyDllAsk, [AInfo.DllName, AInfo.DllTarget,
    ExtractFileDir(AInfo.DllSource)]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  mTarget := IncludeTrailingPathDelimiter(AInfo.DllTarget) + AInfo.DllName;
  try
    ForceDirectories(AInfo.DllTarget);
    TFile.Copy(AInfo.DllSource, mTarget, False);
    Report(TAtlasTestsTextId.LeakCopyDllDone, [AInfo.DllName, AInfo.DllTarget]);
  except
    on E: Exception do
    begin
      Report(TAtlasTestsTextId.LeakCopyDllFailed, [AInfo.DllName, E.Message]);
    end;
  end;
end;

{ Plan }

/// <summary>Einfügungen mit Vorschau übernehmen; False, wenn der Benutzer abbricht oder es scheitert.</summary>
function ApplyEdit(const AEditJson: string): Boolean;
var
  mValue: TJSONValue;
  mEdit: TLspWorkspaceEdit;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mValue := TJSONObject.ParseJSONValue(AEditJson);
  try
    mEdit := TLspWorkspaceEdit.FromJson(mValue);
  finally
    mValue.Free;
  end;
  if mEdit.IsEmpty then
  begin
    Exit(True);
  end;
  Result := TAtlasIdeServerEdit.Confirm(TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakPreviewTitle),
    TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakPreviewHint),
    TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakPreviewApply), mEdit) and
    TAtlasIdeServerEdit.Apply(mEdit, TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    TAtlasTestsStrings.Text(TAtlasTestsTextId.LeakEditAction),
    procedure(AText: string)
    begin
      TAtlasIdeHost.Message(AText);
    end, mOutcome);
end;

procedure ApplyPlan(const AInfo: TAtlasLeakSetupInfo; const APlan: TAtlasLeakSetupPlan);
begin
  if APlan.Empty then
  begin
    Report(TAtlasTestsTextId.LeakNothingToDo, [ExtractFileName(AInfo.Project)]);
    Exit;
  end;
  if not ApplyEdit(APlan.EditJson) then
  begin
    Exit;
  end;
  WriteDefines(AInfo.Project, APlan.Defines);
  if APlan.CopyDll then
  begin
    CopyDll(AInfo);
  end;
  Report(TAtlasTestsTextId.LeakDone, [ExtractFileName(AInfo.Project)]);
end;

/// <summary>Antwort mit Plan (Hauptthread); eigene Routine, damit der Rahmen nur den Stand hält.</summary>
function PlanAnswer(const AInfo: TAtlasLeakSetupInfo): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mPlan: TAtlasLeakSetupPlan;
    begin
      if not TAtlasLeakSetupPlan.FromJson(AAnswer, mPlan) then
      begin
        Report(TAtlasTestsTextId.LeakSetupNoServer, []);
        Exit;
      end;
      ApplyPlan(AInfo, mPlan);
    end;
end;

{ Stand }

procedure RequestPlan(const AScope: IAtlasModuleScope; const AInfo: TAtlasLeakSetupInfo;
  AChoice: TAtlasLeakChoice; AFileReport: Boolean);
begin
  if not TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Build, TAtlasLeakSetup.cCommand,
    TAtlasLeakSetup.ArgumentsJson(AInfo.Project, True, AChoice, AFileReport), TAtlasIdeLeakSetup.cTimeoutMs,
    PlanAnswer(AInfo)) then
  begin
    Report(TAtlasTestsTextId.LeakSetupNoServer, []);
  end;
end;

/// <summary>Antwort mit dem Stand (Hauptthread): Dialog, dann der Plan.</summary>
function StateAnswer(const AScope: IAtlasModuleScope): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mInfo: TAtlasLeakSetupInfo;
      mChoice: TAtlasLeakChoice;
      mFileReport: Boolean;
    begin
      if not TAtlasLeakSetupInfo.FromJson(AAnswer, mInfo) then
      begin
        Report(TAtlasTestsTextId.LeakSetupNoServer, []);
        Exit;
      end;
      if TAtlasLeakSetupDialog.Execute(mInfo, mChoice, mFileReport) then
      begin
        RequestPlan(AScope, mInfo, mChoice, mFileReport);
      end;
    end;
end;

class procedure TAtlasIdeLeakSetup.Run(const AScope: IAtlasModuleScope);
var
  mProject: string;
begin
  mProject := TargetProject;
  if mProject = '' then
  begin
    Report(TAtlasTestsTextId.LeakSetupNoProject, []);
    Exit;
  end;
  if (TAtlasIdeHost.ActiveSession = nil) or not TAtlasIdeHost.RunServerCommandAsync(AScope, TAtlasFeature.Build,
    TAtlasLeakSetup.cCommand, TAtlasLeakSetup.ArgumentsJson(mProject, False, TAtlasLeakChoice.Simple, False),
    cTimeoutMs, StateAnswer(AScope)) then
  begin
    Report(TAtlasTestsTextId.LeakSetupNoServer, []);
  end;
end;

end.
