unit Atlas.IDE.Editor.InvertBoolean;

// Code-Aktion „Bedeutung umkehren (X → Y)“ (#715): Der Server bietet sie als
// Client-Befehl atlas.invertBoolean mit URI, Position und dem vorgeschlagenen
// Namen an. Atlas fragt den Namen ab, schickt die offenen Puffer, holt das
// WorkspaceEdit (atlas.server.invertBoolean), zeigt die Vorschau wie beim
// Umbenennen mit den Warnungen des Servers (var/out-Übergaben, @X,
// Zeichenketten für RTTI, published Properties) und übernimmt erst nach
// Bestätigung, je Datei ein Rückgängig-Schritt. Abschaltbar über
// refactoring.invertBoolean: Dann bietet der Server die Aktion nicht an. Nur
// im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeInvertBoolean = class
  public const
    ClientCommand = 'atlas.invertBoolean';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
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
  ApplyCommand = 'atlas.server.invertBoolean';
  // Verweise, Überschreibungen und Formulare im Projekt suchen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

function NumberOf(AReply: TJSONObject; const AName: string): Integer;
begin
  Result := 0;
  if (AReply <> nil) and (AReply.GetValue(AName) is TJSONNumber) then
    Result := TJSONNumber(AReply.GetValue(AName)).AsInt;
end;

class procedure TAtlasIdeInvertBoolean.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Arguments, Answer, Item: TJSONValue;
  Values, List: TJSONArray;
  Reply: TJSONObject;
  Name, ApplyArguments, Hint, Warning: string;
  Warnings: TArray<string>;
  Places, Files: Integer;
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
  // Namen abfragen (Vorschlag des Servers) und das dritte Argument ersetzen.
  Arguments := TJSONObject.ParseJSONValue(AArgumentsJson);
  try
    if not (Arguments is TJSONArray) or (TJSONArray(Arguments).Count < 3) then
      Exit;
    Values := TJSONArray(Arguments);
    Name := Values.Items[2].Value;
    if not InputQuery(TAtlasStrings.Text(TAtlasTextId.InvertBooleanTitle),
      TAtlasStrings.Text(TAtlasTextId.InvertBooleanPrompt), Name) then
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
  Places := 0;
  Files := 0;
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
        Places := NumberOf(Reply, 'places');
        Files := NumberOf(Reply, 'files');
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
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.InvertBooleanFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.InvertBooleanNothing));
    Exit;
  end;
  Hint := TAtlasStrings.Fmt(TAtlasTextId.InvertBooleanPreviewHint, [Places, Files]);
  for Warning in Warnings do
    Hint := Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.InvertBooleanWarning, [Warning]);
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
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.InvertBooleanTitle), Hint,
    TAtlasStrings.Text(TAtlasTextId.InvertBooleanApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.InvertBooleanTitle));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.InvertBooleanDone, [Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.InvertBooleanWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
