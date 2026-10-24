unit Atlas.IDE.Editor.NamedRefactoring;

// Ablauf für Code-Aktionen, die einen Namen brauchen und projektweit ändern
// (Boolean umkehren #715, Variable und Feld umwandeln #668, anonyme Methode
// umwandeln #680, Typ-Alias einführen #681): Der Server bietet sie als
// Client-Befehl mit [uri, position, vorgeschlagener Name, weitere …] an;
// weitere Argumente (die Reichweite bei #681) gehen unverändert mit. Atlas
// fragt den Namen ab, schickt die offenen Puffer, holt die Antwort des
// Server-Befehls ({"edit", "warnings", "places", "files", optional
// "preview"}), zeigt die Vorschau wie beim
// Umbenennen mit dem Vorschautext und den Warnungen und übernimmt erst nach
// Bestätigung, je Datei ein Rückgängig-Schritt. Die Texte kommen je Aktion
// aus TAtlasNamedRefactoringTexts. Aktionen ohne Namen (Methode ohne Self
// #686) reichen ihre Argumente unverändert über ExecuteWithoutName weiter.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  /// <summary>Texte einer Aktion: Titel, Frage nach dem Namen, Fehler (%s), nichts zu tun, Hinweis der Vorschau
  /// (%d Stellen, %d Dateien), Knopf, Ergebnis (%d Änderungen, %d Dateien), Warnung (%s).</summary>
  TAtlasNamedRefactoringTexts = record
    Title: TAtlasTextId;
    Prompt: TAtlasTextId;
    Failed: TAtlasTextId;
    Nothing: TAtlasTextId;
    PreviewHint: TAtlasTextId;
    Apply: TAtlasTextId;
    Done: TAtlasTextId;
    Warning: TAtlasTextId;
  end;

  TAtlasIdeNamedRefactoring = class
  private
    /// <summary>Server-Befehl mit AApplyArguments ausführen, Vorschau zeigen und nach Bestätigung übernehmen.
    /// </summary>
    class procedure Run(ASession: TLspSession; const AApplyArguments, AApplyCommand: string;
      const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
      static;
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name, weitere …]); AApplyCommand:
    /// Befehl des Servers; ASession: laufende Sitzung oder nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson, AApplyCommand: string;
      const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
      static;
    /// <summary>Wie Execute, aber ohne Namensabfrage: AArgumentsJson geht unverändert an AApplyCommand;
    /// ATexts.Prompt bleibt ungenutzt.</summary>
    class procedure ExecuteWithoutName(ASession: TLspSession; const AArgumentsJson, AApplyCommand: string;
      const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
      static;
  end;

implementation

uses
  System.JSON,
  Vcl.Dialogs,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation;

const
  // Verweise, Überschreibungen und Formulare im Projekt suchen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

function NumberOf(AReply: TJSONObject; const AName: string): Integer;
begin
  Result := 0;
  if (AReply <> nil) and (AReply.GetValue(AName) is TJSONNumber) then
    Result := TJSONNumber(AReply.GetValue(AName)).AsInt;
end;

class procedure TAtlasIdeNamedRefactoring.Execute(ASession: TLspSession; const AArgumentsJson, AApplyCommand: string;
  const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Arguments: TJSONValue;
  Values, List: TJSONArray;
  Name, ApplyArguments: string;
  Index: Integer;
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
    if not InputQuery(TAtlasStrings.Text(ATexts.Title), TAtlasStrings.Text(ATexts.Prompt), Name) then
      Exit;
    Name := Trim(Name);
    if Name = '' then
      Exit;
    List := TJSONArray.Create;
    try
      List.AddElement(Values.Items[0].Clone as TJSONValue);
      List.AddElement(Values.Items[1].Clone as TJSONValue);
      List.Add(Name);
      for Index := 3 to Values.Count - 1 do
        List.AddElement(Values.Items[Index].Clone as TJSONValue);
      ApplyArguments := List.ToJSON;
    finally
      List.Free;
    end;
  finally
    Arguments.Free;
  end;
  Run(ASession, ApplyArguments, AApplyCommand, ATexts, APolicy, AMessage);
end;

class procedure TAtlasIdeNamedRefactoring.ExecuteWithoutName(ASession: TLspSession; const AArgumentsJson,
  AApplyCommand: string; const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy;
  const AMessage: TProc<string>);
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Run(ASession, AArgumentsJson, AApplyCommand, ATexts, APolicy, AMessage);
end;

class procedure TAtlasIdeNamedRefactoring.Run(ASession: TLspSession; const AApplyArguments, AApplyCommand: string;
  const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Answer, Item: TJSONValue;
  Reply: TJSONObject;
  Hint, Warning, Explanation: string;
  Warnings: TArray<string>;
  Places, Files: Integer;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Preview: TArray<TAtlasResultEntry>;
  Open: TAtlasResultsOpen;
begin
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  Warnings := nil;
  Places := 0;
  Files := 0;
  Explanation := '';
  try
    Answer := ASession.RunCommand(AApplyCommand, AApplyArguments, TimeoutMs);
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
        // Erklärung des Servers, z. B. die Form der Umwandlung (#680).
        if Reply.GetValue('preview') is TJSONString then
          Explanation := Reply.GetValue('preview').Value;
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
      AMessage(TAtlasStrings.Fmt(ATexts.Failed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(ATexts.Nothing));
    Exit;
  end;
  Hint := TAtlasStrings.Fmt(ATexts.PreviewHint, [Places, Files]);
  if Explanation <> '' then
    Hint := Hint + sLineBreak + Explanation;
  for Warning in Warnings do
    Hint := Hint + sLineBreak + TAtlasStrings.Fmt(ATexts.Warning, [Warning]);
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
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(ATexts.Title), Hint, TAtlasStrings.Text(ATexts.Apply),
    TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(ATexts.Title));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(ATexts.Done, [Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(ATexts.Warning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
