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
    View := Editors.TopView;
  if (View <> nil) and (View.Buffer <> nil) then
    Result := View.Buffer.FileName;
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

class procedure TAtlasIdeDfmPropertyRules.Execute(ASession: TLspSession; AScope: TAtlasDfmRulesScope;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  FileName, Arguments: string;
  Project: IOTAProject;
  Values: TJSONArray;
  Response: TJSONValue;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Preview: TArray<TAtlasResultEntry>;
  Open: TAtlasResultsOpen;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  FileName := EditorFile;
  if AScope = TAtlasDfmRulesScope.Form then
  begin
    if not HasForm(FileName) then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.DfmRulesNoForm));
      Exit;
    end;
  end
  else
  begin
    // Projekt: das aktive; der Server wählt den Arbeitsbereich über die Datei.
    Project := GetActiveProject;
    if (AScope = TAtlasDfmRulesScope.Project) or (FileName = '') then
      if Project <> nil then
        FileName := Project.FileName;
    if FileName = '' then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.DfmRulesNoProject));
      Exit;
    end;
  end;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(FileName));
    Values.Add(ScopeName(AScope));
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  try
    Response := ASession.RunCommand(Command, Arguments, TimeoutMs);
    try
      Edit := TLspWorkspaceEdit.FromJson(Response);
    finally
      Response.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.DfmRulesFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.DfmRulesNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400): Bestätigung durch den Benutzer (needsConfirmation).
  Preview := TAtlasResults.RenamePreview(Edit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  Open :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.DfmRulesPreviewTitle),
    TAtlasStrings.Fmt(TAtlasTextId.DfmRulesPreviewHint, [Edit.EditCount, Length(Edit.Files)]),
    TAtlasStrings.Text(TAtlasTextId.DfmRulesPreviewApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.DfmRulesPreviewTitle));
  if Outcome.Error <> '' then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]))
  else
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.DfmRulesDone, [Outcome.Edits, Outcome.Files]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
