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
    cClientCommand = 'atlas.disableWarning';
    cProjectCommand = 'atlas.disableWarningProject';
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
  Atlas.UI.Editor.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.DisableWarning,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Files;

const
  cApplyCommand = 'atlas.server.disableWarning';
  cTimeoutMs = 10000;

/// <summary>Fragt nach dem Grund, wenn ARequest es verlangt; False bei Abbruch.</summary>
function AskReason(const ARequest: TAtlasDisableWarningRequest; out AReason: string): Boolean;
begin
  AReason := '';
  Result := not ARequest.AskReason or InputQuery(TAtlasEditorStrings.Text(TAtlasEditorTextId.DisableWarningTitle),
    TAtlasEditorStrings.Text(TAtlasEditorTextId.DisableWarningReasonPrompt), AReason);
end;

/// <summary>Lässt den Server die Änderung berechnen; False, wenn er scheitert (Meldung über AMessage) oder
/// nichts zu ändern ist.</summary>
function FetchEdit(ASession: TLspSession; const ARequest: TAtlasDisableWarningRequest; const AReason: string;
  const AMessage: TProc<string>; out AEdit: TLspWorkspaceEdit; out AAllWarnings: Boolean): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  AEdit := TLspWorkspaceEdit.FromJson(nil);
  AAllWarnings := False;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    mAnswer := ASession.RunCommand(cApplyCommand, ARequest.ApplyArguments(AReason), cTimeoutMs);
    try
      if mAnswer is TJSONObject then
      begin
        AEdit := TLspWorkspaceEdit.FromJson(TJSONObject(mAnswer).GetValue('edit'));
        AAllWarnings := TJSONObject(mAnswer).GetValue<Boolean>('allWarnings', False);
      end;
    finally
      mAnswer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningFailed, [E.Message]));
      Exit;
    end;
  end;
  Result := not AEdit.IsEmpty;
end;

/// <summary>Meldet das Ergebnis der angewendeten Änderung.</summary>
procedure ReportOutcome(const ARequest: TAtlasDisableWarningRequest; const AOutcome: TAtlasWorkspaceEditResult;
  AAllWarnings: Boolean; const AMessage: TProc<string>);
begin
  if AOutcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [AOutcome.Error]));
    Exit;
  end;
  AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningDone, [ARequest.Code,
    ExtractFileName(TLspSession.UriToPath(ARequest.Uri))]));
  if AAllWarnings then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningAllWarnings, [ARequest.Code]));
  end;
  if AOutcome.Written > 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [AOutcome.Written]));
  end;
end;

/// <summary>Fragt, ob die Warnung im ganzen Projekt AProject aus sein soll.</summary>
function ConfirmProject(const ARequest: TAtlasDisableWarningProject; const AProject: IOTAProject): Boolean;
begin
  Result := MessageDlg(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningProjectConfirm, [ARequest.Code,
    ARequest.Identifier, ExtractFileName(AProject.FileName), ARequest.OptionName]), mtConfirmation, [mbYes, mbNo],
    0) = mrYes;
end;

/// <summary>Basiskonfiguration von AProject oder nil.</summary>
function BaseConfiguration(const AProject: IOTAProject): IOTABuildConfiguration;
var
  mConfigurations: IOTAProjectOptionsConfigurations;
begin
  Result := nil;
  if Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, mConfigurations) then
  begin
    Result := mConfigurations.BaseConfiguration;
  end;
end;

/// <summary>Schaltet die Warnung in ABase ab; False mit Meldung, wenn die IDE das ablehnt.</summary>
function SwitchOff(const ABase: IOTABuildConfiguration; const AProject: IOTAProject;
  const ARequest: TAtlasDisableWarningProject; const AMessage: TProc<string>): Boolean;
begin
  Result := False;
  try
    ABase.SetValue(ARequest.OptionName, cAtlasWarningOptionOff);
    AProject.MarkModified;
    Result := True;
  except
    on E: Exception do
    begin
      AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningProjectFailed, [ARequest.Code, E.Message]));
    end;
  end;
end;

class procedure TAtlasIdeDisableWarning.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mRequest: TAtlasDisableWarningRequest;
  mReason: string;
  mEdit: TLspWorkspaceEdit;
  mAllWarnings: Boolean;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  if not TAtlasDisableWarningRequest.TryParse(AArgumentsJson, mRequest) then
  begin
    Exit;
  end;
  if not AskReason(mRequest, mReason) then
  begin
    Exit;
  end;
  if FetchEdit(ASession, mRequest, mReason, AMessage, mEdit, mAllWarnings) then
  begin
    // Ein Rückgängig-Schritt: beide Schalter in einer Änderung der Datei.
    ReportOutcome(mRequest, TAtlasIdeWorkspaceEdit.Apply(mEdit, APolicy,
      TAtlasEditorStrings.Text(TAtlasEditorTextId.DisableWarningTitle)), mAllWarnings, AMessage);
  end;
end;

class procedure TAtlasIdeDisableWarning.ExecuteProject(const AArgumentsJson: string; const AMessage: TProc<string>);
var
  mRequest: TAtlasDisableWarningProject;
  mFileName: string;
  mProject: IOTAProject;
  mBase: IOTABuildConfiguration;
begin
  if not TAtlasDisableWarningProject.TryParse(AArgumentsJson, mRequest) then
  begin
    Exit;
  end;
  mFileName := TLspSession.UriToPath(mRequest.Uri);
  mProject := TAtlasIdeFiles.GroupProject(TAtlasIdeFiles.ProjectOfFile(mFileName));
  if mProject = nil then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningNoProject, [ExtractFileName(mFileName)]));
    Exit;
  end;
  if not ConfirmProject(mRequest, mProject) then
  begin
    Exit;
  end;
  mBase := BaseConfiguration(mProject);
  if mBase = nil then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningProjectFailed, [mRequest.Code,
      ExtractFileName(mProject.FileName)]));
    Exit;
  end;
  if SwitchOff(mBase, mProject, mRequest, AMessage) then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.DisableWarningProjectDone, [mRequest.Code,
      ExtractFileName(mProject.FileName), mRequest.OptionName]));
  end;
end;

end.
