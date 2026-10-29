unit Atlas.IDE.Editor.ChangeSignature;

// Code-Aktion „Signatur ändern …“ (#100): Der Server bietet sie als
// Client-Befehl atlas.changeSignature mit URI und Position an. Atlas schickt
// die offenen Puffer, holt die heutige Signatur
// (atlas.server.changeSignature.prepare), zeigt den Dialog als Eingabemaske,
// holt mit der neuen Liste das WorkspaceEdit (atlas.server.changeSignature),
// zeigt die Vorschau wie beim Umbenennen mit den Warnungen des Servers und
// übernimmt erst nach Bestätigung. Abbrüche (gebundener Bibliothekshandler,
// im Rumpf benutzter Parameter, Kollision) meldet der Server als Fehler.
// Abschaltbar über refactoring.changeSignature: Dann bietet der Server die
// Aktion nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeChangeSignature = class
  public const
    ClientCommand = 'atlas.changeSignature';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position]); ASession: laufende Sitzung oder nil;
    /// AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model,
  Atlas.Core.Editor.ChangeSignature,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.UI.Editor.ChangeSignature,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation;

const
  PrepareCommand = 'atlas.server.changeSignature.prepare';
  ApplyCommand = 'atlas.server.changeSignature';
  // Alle Aufrufer im Projekt suchen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

/// <summary>Antwort des Servers als Objekt; nil bei anderem Wert. Der Aufrufer gibt Answer frei.</summary>
function AsObject(AAnswer: TJSONValue): TJSONObject;
begin
  Result := nil;
  if AAnswer is TJSONObject then
    Result := TJSONObject(AAnswer);
end;

class procedure TAtlasIdeChangeSignature.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Arguments, Answer: TJSONValue;
  Reply: TJSONObject;
  Values, List: TJSONArray;
  Found: TJSONValue;
  Model: TAtlasSignatureModel;
  ApplyArguments, Hint, Warning: string;
  Warnings: TArray<string>;
  Item: TJSONValue;
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
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  Model := nil;
  try
    try
      Answer := ASession.RunCommand(PrepareCommand, AArgumentsJson, TimeoutMs);
      try
        Model := TAtlasSignatureModel.Create(AsObject(Answer));
      finally
        Answer.Free;
      end;
    except
      on E: ELspClientError do
      begin
        AMessage(TAtlasStrings.Fmt(TAtlasTextId.SigFailed, [E.Message]));
        Exit;
      end;
    end;
    if not TAtlasChangeSignatureDialog.Execute(Model) then
      Exit;
    if not Model.Changed then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.SigNothing));
      Exit;
    end;
    // Argumente der Aktion um die neue Liste ergänzen.
    Arguments := TJSONObject.ParseJSONValue(AArgumentsJson);
    try
      if not (Arguments is TJSONArray) then
        Exit;
      Values := TJSONArray(Arguments);
      Values.AddElement(Model.RequestJson);
      ApplyArguments := Values.ToJSON;
    finally
      Arguments.Free;
    end;
  finally
    Model.Free;
  end;
  Warnings := nil;
  try
    Answer := ASession.RunCommand(ApplyCommand, ApplyArguments, TimeoutMs);
    try
      Reply := AsObject(Answer);
      Found := nil;
      List := nil;
      if Reply <> nil then
      begin
        Found := Reply.GetValue('edit');
        if Reply.GetValue('warnings') is TJSONArray then
          List := TJSONArray(Reply.GetValue('warnings'));
      end;
      Edit := TLspWorkspaceEdit.FromJson(Found);
      if List <> nil then
        for Item in List do
          Warnings := Warnings + [Item.Value];
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.SigFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.SigNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400); Warnungen (Methodenzeiger, schreibgeschützte Aufrufer) im Hinweis.
  Hint := TAtlasStrings.Fmt(TAtlasTextId.SigPreviewHint, [Edit.EditCount, Length(Edit.Files)]);
  for Warning in Warnings do
    Hint := Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SigWarning, [Warning]);
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
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.SigPreviewTitle), Hint,
    TAtlasStrings.Text(TAtlasTextId.SigPreviewApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.SigPreviewTitle));
  if Outcome.Error <> '' then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]))
  else
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.SigDone, [Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.SigWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
