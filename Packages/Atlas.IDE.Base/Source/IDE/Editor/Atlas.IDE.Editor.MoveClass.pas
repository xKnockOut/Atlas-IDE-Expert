unit Atlas.IDE.Editor.MoveClass;

// Code-Aktion „Klasse in eigene Unit verschieben …“ (#103 Teil B): Der Server
// bietet sie als Client-Befehl atlas.moveClass mit URI, Position und dem
// vorgeschlagenen Unit-Namen an. Atlas schickt die offenen Puffer, fragt den
// Namen ab (Vorschlag: Klassenname ohne T), holt das WorkspaceEdit
// (atlas.server.moveClass), zeigt die Vorschau wie beim Umbenennen mit den
// Hinweisen des Servers, übernimmt erst nach Bestätigung und öffnet danach
// die neue Unit. Abbrüche (Datei vorhanden, Zugriff auf implementation-lokale
// Namen) meldet der Server als Fehler. Abschaltbar über refactoring.moveClass:
// Dann bietet der Server die Aktion nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeMoveClass = class
  public const
    ClientCommand = 'atlas.moveClass';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Vcl.Dialogs,
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
  ApplyCommand = 'atlas.server.moveClass';
  // Alle verwendenden Units suchen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

class procedure TAtlasIdeMoveClass.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Arguments, Answer, Item: TJSONValue;
  Values, List: TJSONArray;
  Reply: TJSONObject;
  Name, ApplyArguments, Hint, Warning, NewFile: string;
  Warnings: TArray<string>;
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
  // Name abfragen und das dritte Argument ersetzen.
  Arguments := TJSONObject.ParseJSONValue(AArgumentsJson);
  try
    if not (Arguments is TJSONArray) or (TJSONArray(Arguments).Count < 3) then
      Exit;
    Values := TJSONArray(Arguments);
    Name := Values.Items[2].Value;
    if not InputQuery(TAtlasStrings.Text(TAtlasTextId.MoveClassTitle),
      TAtlasStrings.Text(TAtlasTextId.MoveClassPrompt), Name) then
      Exit;
    Name := Trim(Name);
    if Name = '' then
      Exit;
    List := TJSONArray.Create;
    try
      List.AddElement(Values.Items[0].Clone as TJSONValue);
      List.AddElement(Values.Items[1].Clone as TJSONValue);
      List.Add(Name);
      ApplyArguments := List.ToJSON;
    finally
      List.Free;
    end;
  finally
    Arguments.Free;
  end;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  Warnings := nil;
  NewFile := '';
  try
    Answer := ASession.RunCommand(ApplyCommand, ApplyArguments, TimeoutMs);
    try
      Reply := nil;
      if Answer is TJSONObject then
        Reply := TJSONObject(Answer);
      Edit := TLspWorkspaceEdit.FromJson(nil);
      if Reply <> nil then
      begin
        Edit := TLspWorkspaceEdit.FromJson(Reply.GetValue('edit'));
        if Reply.GetValue('file') is TJSONString then
          NewFile := TLspSession.UriToPath(Reply.GetValue('file').Value);
        if Reply.GetValue('warnings') is TJSONArray then
          for Item in TJSONArray(Reply.GetValue('warnings')) do
            Warnings := Warnings + [Item.Value];
      end;
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveClassFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MoveClassNothing));
    Exit;
  end;
  Hint := TAtlasStrings.Fmt(TAtlasTextId.MoveClassPreviewHint, [Name, Edit.EditCount, Length(Edit.Files)]);
  for Warning in Warnings do
    Hint := Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.MoveClassWarning, [Warning]);
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
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.MoveClassTitle), Hint,
    TAtlasStrings.Text(TAtlasTextId.MoveClassApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.MoveClassTitle));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveClassDone, [Name, Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveClassWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
  if NewFile <> '' then
    TAtlasIdeNavigation.GoToLocation(NewFile, 0, 0);
end;

end.
