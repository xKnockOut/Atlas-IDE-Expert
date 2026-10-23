unit Atlas.IDE.Editor.DisableWarning;

// Compilerwarnung gezielt abschalten (#531). Der Server bietet die Code-
// Aktionen auf Warnungen und Hinweisen des letzten Compilerlaufs an
// (refactoring.disableWarning):
//   - atlas.disableWarning: Begründung abfragen (refactoring.disableWarning-
//     Reason, leer erlaubt, Abbrechen bricht ab), die offenen Puffer schicken,
//     das WorkspaceEdit holen (atlas.server.disableWarning) und als ein
//     Rückgängig-Schritt einfügen.
//   - atlas.disableWarningProject: nach Rückfrage DCC_<Bezeichner> = false in
//     die Basiskonfiguration des Projekts der Datei; das Projekt gilt danach
//     als geändert.
// Argumente in Atlas.Core.Editor.DisableWarning. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeDisableWarning = class
  public const
    ClientCommand = 'atlas.disableWarning';
    ProjectCommand = 'atlas.disableWarningProject';
  public
    /// <summary>atlas.disableWarning; ASession: laufende Sitzung oder nil; AMessage: Zeile für die
    /// Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
    /// <summary>atlas.disableWarningProject.</summary>
    class procedure ExecuteProject(const AArgumentsJson: string; const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.UITypes,
  System.JSON,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.DisableWarning,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Files;

const
  ApplyCommand = 'atlas.server.disableWarning';
  TimeoutMs = 10000;

class procedure TAtlasIdeDisableWarning.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Request: TAtlasDisableWarningRequest;
  Reason: string;
  Answer: TJSONValue;
  Edit: TLspWorkspaceEdit;
  AllWarnings: Boolean;
  Outcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  if not TAtlasDisableWarningRequest.TryParse(AArgumentsJson, Request) then
    Exit;
  Reason := '';
  if Request.AskReason and not InputQuery(TAtlasStrings.Text(TAtlasTextId.DisableWarningTitle),
    TAtlasStrings.Text(TAtlasTextId.DisableWarningReasonPrompt), Reason) then
    Exit;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  AllWarnings := False;
  try
    Answer := ASession.RunCommand(ApplyCommand, Request.ApplyArguments(Reason), TimeoutMs);
    try
      Edit := TLspWorkspaceEdit.FromJson(nil);
      if Answer is TJSONObject then
      begin
        Edit := TLspWorkspaceEdit.FromJson(TJSONObject(Answer).GetValue('edit'));
        AllWarnings := TJSONObject(Answer).GetValue<Boolean>('allWarnings', False);
      end;
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
    Exit;
  // Ein Rückgängig-Schritt: beide Schalter in einer Änderung der Datei.
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.DisableWarningTitle));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningDone, [Request.Code,
    ExtractFileName(TLspSession.UriToPath(Request.Uri))]));
  if AllWarnings then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningAllWarnings, [Request.Code]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

function ProjectByFileName(const AFileName: string): IOTAProject;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  Result := nil;
  if (AFileName = '') or not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Group := Services.MainProjectGroup;
  if Group = nil then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    if SameFileName(Group.Projects[Index].FileName, AFileName) then
      Exit(Group.Projects[Index]);
end;

class procedure TAtlasIdeDisableWarning.ExecuteProject(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  Request: TAtlasDisableWarningProject;
  FileName: string;
  Project: IOTAProject;
  Configurations: IOTAProjectOptionsConfigurations;
  Base: IOTABuildConfiguration;
begin
  if not TAtlasDisableWarningProject.TryParse(AArgumentsJson, Request) then
    Exit;
  FileName := TLspSession.UriToPath(Request.Uri);
  Project := ProjectByFileName(TAtlasIdeFiles.ProjectOfFile(FileName));
  if Project = nil then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningNoProject, [ExtractFileName(FileName)]));
    Exit;
  end;
  if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningProjectConfirm, [Request.Code, Request.Identifier,
    ExtractFileName(Project.FileName), Request.OptionName]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  Base := nil;
  if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configurations) then
    Base := Configurations.BaseConfiguration;
  if Base = nil then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningProjectFailed, [Request.Code,
      ExtractFileName(Project.FileName)]));
    Exit;
  end;
  try
    Base.SetValue(Request.OptionName, AtlasWarningOptionOff);
    Project.MarkModified;
  except
    on E: Exception do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningProjectFailed, [Request.Code, E.Message]));
      Exit;
    end;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.DisableWarningProjectDone, [Request.Code,
    ExtractFileName(Project.FileName), Request.OptionName]));
end;

end.
