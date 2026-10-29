unit Atlas.IDE.Editor.MoveMember;

// Code-Aktionen „„Run“ in Vorfahr verschieben …“ und „„Run“ in Nachfahren
// verschieben …“ (#675) auf einem Mitglied der Klassendeklaration: Der Server
// bietet sie als Client-Befehl atlas.moveMember mit URI, Position und
// Richtung an. Atlas schickt die offenen Puffer, holt Kandidaten und Ziele
// (atlas.server.moveMember.prepare), zeigt den Dialog „Mitglieder
// herauslösen“ im Verschiebe-Modus (Ziel bzw. Nachfahren, Mitglieder,
// Methoden nach oben wahlweise abstrakt, „andere Nachfahren überschreiben“
// bzw. „abstrakt im Vorfahren lassen“), holt das WorkspaceEdit
// (atlas.server.moveMember), zeigt die Vorschau wie beim Umbenennen mit den
// Hinweisen des Servers, übernimmt erst nach Bestätigung und springt danach
// zur Zielklasse. Abbrüche (Name im Ziel vergeben, Nutzung über den
// Vorfahr-Typ, Kreisverweis) meldet der Server als Fehler. Abschaltbar über
// refactoring.moveMember: Dann bietet der Server die Aktionen nicht an.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeMoveMember = class
  public const
    ClientCommand = 'atlas.moveMember';
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
  Atlas.Core.Editor.ClassExtraction,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.UI.Editor.ExtractMembers,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation;

const
  PrepareCommand = 'atlas.server.moveMember.prepare';
  ApplyCommand = 'atlas.server.moveMember';
  // Verweise suchen und Namen auflösen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

/// <summary>Antwort des Servers als Objekt; nil bei anderem Wert. Der Aufrufer gibt Answer frei.</summary>
function AsObject(AAnswer: TJSONValue): TJSONObject;
begin
  Result := nil;
  if AAnswer is TJSONObject then
    Result := TJSONObject(AAnswer);
end;

class procedure TAtlasIdeMoveMember.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Arguments, Answer, Item: TJSONValue;
  Values: TJSONArray;
  Reply: TJSONObject;
  Model: TAtlasClassExtractionModel;
  Title, ApplyArguments, Hint, Warning, TargetFile: string;
  Warnings: TArray<string>;
  Moved, TargetLine: Integer;
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
        Model := TAtlasClassExtractionModel.Create(AsObject(Answer));
      finally
        Answer.Free;
      end;
    except
      on E: ELspClientError do
      begin
        AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveMemberFailed, [E.Message]));
        Exit;
      end;
    end;
    if Model.Direction = 'down' then
      Title := TAtlasStrings.Fmt(TAtlasTextId.MoveDownTitle, [Model.MemberName])
    else
      Title := TAtlasStrings.Fmt(TAtlasTextId.MoveUpTitle, [Model.MemberName]);
    if not TAtlasExtractMembersDialog.Execute(Model, Title) then
      Exit;
    // Argumente der Aktion (URI, Position, Richtung) um Auswahl, Ziele und Wahl ergänzen.
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
  TargetFile := '';
  Moved := 0;
  TargetLine := 0;
  try
    Answer := ASession.RunCommand(ApplyCommand, ApplyArguments, TimeoutMs);
    try
      Reply := AsObject(Answer);
      Edit := TLspWorkspaceEdit.FromJson(nil);
      if Reply <> nil then
      begin
        Edit := TLspWorkspaceEdit.FromJson(Reply.GetValue('edit'));
        if Reply.GetValue('file') is TJSONString then
          TargetFile := TLspSession.UriToPath(Reply.GetValue('file').Value);
        if Reply.GetValue('moved') is TJSONNumber then
          Moved := TJSONNumber(Reply.GetValue('moved')).AsInt;
        if Reply.GetValue('line') is TJSONNumber then
          TargetLine := TJSONNumber(Reply.GetValue('line')).AsInt;
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
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveMemberFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty or (Moved = 0) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MoveMemberNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400); Hinweise (gehobene Sichtbarkeit, override, uses) im Hinweis.
  Hint := TAtlasStrings.Fmt(TAtlasTextId.MoveMemberPreviewHint, [Moved, Edit.EditCount, Length(Edit.Files)]);
  for Warning in Warnings do
    Hint := Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfWarning, [Warning]);
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
  if not TAtlasRenamePreview.Execute(Title, Hint,
    TAtlasStrings.Text(TAtlasTextId.MoveMemberApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.MoveMemberApply));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveMemberDone, [Moved, Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
  if TargetFile <> '' then
    TAtlasIdeNavigation.GoToLocation(TargetFile, TargetLine, 0);
end;

end.
