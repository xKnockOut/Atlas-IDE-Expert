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
  Atlas.UI.Results.View,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation;

const
  cCommand = 'atlas.server.applyDfmPropertyRules';
  // Projektgruppe: alle Formulare prüfen dauert; wie beim Umbenennen.
  cTimeoutMs = 60000;

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
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  Result := '';
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    Result := mView.Buffer.FileName;
  end;
end;

/// <summary>Unit mit Formular: .pas mit .dfm/.fmx daneben oder die Formulardatei selbst.</summary>
function HasForm(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.dfm') or (mExtension = '.fmx') or ((mExtension = '.pas') and
    (FileExists(ChangeFileExt(AFileName, '.dfm')) or FileExists(ChangeFileExt(AFileName, '.fmx'))));
end;

/// <summary>Datei, über die der Server den Bereich wählt; False mit Meldung, wenn es keine gibt.</summary>
function TargetFile(AScope: TAtlasDfmRulesScope; const AMessage: TProc<string>; out AFileName: string): Boolean;
var
  mProject: IOTAProject;
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
  mProject := GetActiveProject;
  if ((AScope = TAtlasDfmRulesScope.Project) or (AFileName = '')) and (mProject <> nil) then
  begin
    AFileName := mProject.FileName;
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
  mValues: TJSONArray;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(AFileName));
    mValues.Add(TAtlasIdeDfmPropertyRules.ScopeName(AScope));
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

/// <summary>Korrekturen vom Server holen; False mit Meldung bei Fehler oder ohne Korrektur.</summary>
function FetchEdit(ASession: TLspSession; const AFileName: string; AScope: TAtlasDfmRulesScope;
  const AMessage: TProc<string>; out AEdit: TLspWorkspaceEdit): Boolean;
var
  mResponse: TJSONValue;
begin
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    mResponse := ASession.RunCommand(cCommand, CommandArguments(AFileName, AScope), cTimeoutMs);
    try
      AEdit := TLspWorkspaceEdit.FromJson(mResponse);
    finally
      mResponse.Free;
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
  mPreview: TArray<TAtlasResultEntry>;
  mOpen: TAtlasResultsOpen;
begin
  mPreview := TAtlasResults.RenamePreview(AEdit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  mOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  Result := TAtlasRenamePreview.Execute(TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesPreviewTitle),
    TAtlasRulesStrings.Fmt(TAtlasRulesTextId.DfmRulesPreviewHint, [AEdit.EditCount, Length(AEdit.Files)]),
    TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesPreviewApply), TAtlasResults.Group(mPreview), mOpen);
end;

/// <summary>Korrekturen übernehmen und das Ergebnis melden.</summary>
procedure ApplyEdit(const AEdit: TLspWorkspaceEdit; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(AEdit, APolicy,
    TAtlasRulesStrings.Text(TAtlasRulesTextId.DfmRulesPreviewTitle));
  if mOutcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
  end
  else
  begin
    AMessage(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.DfmRulesDone, [mOutcome.Edits, mOutcome.Files]));
  end;
  if mOutcome.Written > 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [mOutcome.Written]));
  end;
end;

class procedure TAtlasIdeDfmPropertyRules.Execute(ASession: TLspSession; AScope: TAtlasDfmRulesScope;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mFileName: string;
  mEdit: TLspWorkspaceEdit;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
  end
  else if TargetFile(AScope, AMessage, mFileName) and FetchEdit(ASession, mFileName, AScope, AMessage, mEdit) and
    Confirmed(mEdit) then
  begin
    ApplyEdit(mEdit, APolicy, AMessage);
  end;
end;

end.
