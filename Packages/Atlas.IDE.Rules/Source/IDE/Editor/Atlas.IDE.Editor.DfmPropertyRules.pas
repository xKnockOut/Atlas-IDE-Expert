unit Atlas.IDE.Editor.DfmPropertyRules;

// „Eigenschaftsregeln anwenden“ (#309) in der Befehlspalette, je für das
// Formular im Editor, das aktive Projekt oder die Projektgruppe: Atlas schickt
// vorher die offenen Puffer und Formulare an den Server, holt dessen
// WorkspaceEdit (atlas.server.applyDfmPropertyRules) mit den Korrekturen der
// Regel dfm-property in den Formulardateien, zeigt die Vorschau wie beim
// Umbenennen und übernimmt erst nach Bestätigung. Offene Formulare ändert
// TAtlasIdeWorkspaceEdit im Designer, nicht geöffnete auf der Platte; die
// Units bleiben unverändert. Die Befehle verschwinden mit der Einstellung
// DfmPropertyRules (dfmRules.apply). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  {$SCOPEDENUMS ON}
  TAtlasDfmRulesScope = (Form, Project, Group);
  {$SCOPEDENUMS OFF}

  TAtlasIdeDfmPropertyRules = class
  public
    /// <summary>ASession: laufende Sitzung oder nil; APolicy: nicht geöffnete Dateien öffnen oder auf die
    /// Platte schreiben; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; AScope: TAtlasDfmRulesScope; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
    /// <summary>Argument "scope" des Serverbefehls.</summary>
    class function ScopeName(AScope: TAtlasDfmRulesScope): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.UI.Rules.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation;

const
  Command = 'atlas.server.applyDfmPropertyRules';
  // Projektgruppe: alle Formulare prüfen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

class function TAtlasIdeDfmPropertyRules.ScopeName(AScope: TAtlasDfmRulesScope): string;
begin
  case AScope of
    TAtlasDfmRulesScope.Project:
      Result := 'project';
    TAtlasDfmRulesScope.Group:
      Result := 'group';
  else
    Result := 'form';
  end;
end;

/// <summary>Datei im Editor; '' ohne.</summary>
function EditorFile: string;
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
begin
  Result := '';
  View := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    View := Editors.TopView;
  end;
  if (View <> nil) and (View.Buffer <> nil) then
  begin
    Result := View.Buffer.FileName;
  end;
end;

/// <summary>Unit mit Formular: .pas mit .dfm/.fmx daneben oder die Formulardatei selbst.</summary>
function HasForm(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.dfm') or (Extension = '.fmx') or ((Extension = '.pas') and
    (FileExists(ChangeFileExt(AFileName, '.dfm')) or FileExists(ChangeFileExt(AFileName, '.fmx'))));
end;

/// <summary>Datei, über die der Server den Bereich wählt; False mit Meldung, wenn es keine gibt.</summary>
function TargetFile(AScope: TAtlasDfmRulesScope; const AMessage: TProc<string>; out AFileName: string): Boolean;
var
  Project: IOTAProject;
begin
  AFileName := EditorFile;
  if AScope = TAtlasDfmRulesScope.Form then
  begin
    Result := HasForm(AFileName);
    if not Result then
    begin
      AMessage(TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesNoForm));
    end;
    Exit;
  end;
  // Projekt: das aktive; der Server wählt den Arbeitsbereich über die Datei.
  Project := GetActiveProject;
  if ((AScope = TAtlasDfmRulesScope.Project) or (AFileName = '')) and (Project <> nil) then
  begin
    AFileName := Project.FileName;
  end;
  Result := AFileName <> '';
  if not Result then
  begin
    AMessage(TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesNoProject));
  end;
end;

/// <summary>Argumente des Serverbefehls: Datei-URI und Bereich.</summary>
function CommandArguments(const AFileName: string; AScope: TAtlasDfmRulesScope): string;
var
  Values: TJSONArray;
begin
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(AFileName));
    Values.Add(TAtlasIdeDfmPropertyRules.ScopeName(AScope));
    Result := Values.ToJSON;
  finally
    Values.Free;
  end;
end;

/// <summary>Korrekturen vom Server holen; False mit Meldung bei Fehler oder ohne Korrektur.</summary>
function FetchEdit(ASession: TLspSession; const AFileName: string; AScope: TAtlasDfmRulesScope;
  const AMessage: TProc<string>; out AEdit: TLspWorkspaceEdit): Boolean;
var
  Response: TJSONValue;
begin
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    Response := ASession.RunCommand(Command, CommandArguments(AFileName, AScope), TimeoutMs);
    try
      AEdit := TLspWorkspaceEdit.FromJson(Response);
    finally
      Response.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.DfmRulesFailed, [E.Message]));
      Exit(False);
    end;
  end;
  Result := not AEdit.IsEmpty;
  if not Result then
  begin
    AMessage(TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesNothing));
  end;
end;

/// <summary>Vorschau wie beim Umbenennen (#400): Bestätigung durch den Benutzer (needsConfirmation).</summary>
function Confirmed(const AEdit: TLspWorkspaceEdit): Boolean;
var
  Preview: TArray<TAtlasResultEntry>;
  Open: TAtlasResultsOpen;
begin
  Preview := TAtlasResults.RenamePreview(AEdit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  Open :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  Result := TAtlasRenamePreview.Execute(TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesPreviewTitle),
    TAtlasRulesStrings.Fmt(TAtlasRulesTextId.DfmRulesPreviewHint, [AEdit.EditCount, Length(AEdit.Files)]),
    TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesPreviewApply), TAtlasResults.Group(Preview), Open);
end;

/// <summary>Korrekturen übernehmen und das Ergebnis melden.</summary>
procedure ApplyEdit(const AEdit: TLspWorkspaceEdit; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Outcome: TAtlasWorkspaceEditResult;
begin
  Outcome := TAtlasIdeWorkspaceEdit.Apply(AEdit, APolicy,
    TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesPreviewTitle));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
  end
  else
  begin
    AMessage(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.DfmRulesDone, [Outcome.Edits, Outcome.Files]));
  end;
  if Outcome.Written > 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
  end;
end;

class procedure TAtlasIdeDfmPropertyRules.Execute(ASession: TLspSession; AScope: TAtlasDfmRulesScope;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  FileName: string;
  Edit: TLspWorkspaceEdit;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
  end
  else if TargetFile(AScope, AMessage, FileName) and FetchEdit(ASession, FileName, AScope, AMessage, Edit) and
    Confirmed(Edit) then
  begin
    ApplyEdit(Edit, APolicy, AMessage);
  end;
end;

end.
