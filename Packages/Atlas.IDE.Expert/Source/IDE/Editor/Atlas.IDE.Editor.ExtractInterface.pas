unit Atlas.IDE.Editor.ExtractInterface;

// Code-Aktion „Interface aus … herauslösen …“ (#664) auf der Kopfzeile einer
// Klasse: Der Server bietet sie als Client-Befehl atlas.extractInterface
// mit URI und Position an. Atlas schickt die offenen Puffer, holt die Kandidaten
// (atlas.server.extractInterface.prepare), zeigt den Dialog „Mitglieder
// herauslösen“ (Name, Ziel-Unit, Mitglieder), holt das WorkspaceEdit
// (atlas.server.extractInterface), zeigt die Vorschau wie beim Umbenennen mit
// den Hinweisen des Servers, übernimmt erst nach Bestätigung und öffnet danach
// die Unit mit dem Interface. Abbrüche (Name vergeben, Kreisverweis, ungültige
// Auswahl) meldet der Server als Fehler. Abschaltbar über
// refactoring.extractInterface: Dann bietet der Server die Aktion nicht an.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeExtractInterface = class
  public const
    ClientCommand = 'atlas.extractInterface';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position]); ASession: laufende Sitzung oder nil;
    /// AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
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
  PrepareCommand = 'atlas.server.extractInterface.prepare';
  ApplyCommand = 'atlas.server.extractInterface';
  // Typen der Signaturen auflösen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

/// <summary>Antwort des Servers als Objekt; nil bei anderem Wert. Der Aufrufer gibt Answer frei.</summary>
function AsObject(AAnswer: TJSONValue): TJSONObject;
begin
  Result := nil;
  if AAnswer is TJSONObject then
    Result := TJSONObject(AAnswer);
end;

class procedure TAtlasIdeExtractInterface.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Arguments, Answer, Item: TJSONValue;
  Values: TJSONArray;
  Reply: TJSONObject;
  Model: TAtlasClassExtractionModel;
  Name, SourceClass, ApplyArguments, Hint, Warning, TargetFile: string;
  Warnings: TArray<string>;
  Methods: Integer;
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
        AMessage(TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfFailed, [E.Message]));
        Exit;
      end;
    end;
    if not TAtlasExtractMembersDialog.Execute(Model,
      TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfTitle, [Model.SourceClass])) then
      Exit;
    Name := Trim(Model.Name);
    SourceClass := Model.SourceClass;
    // Argumente der Aktion um Name, Ziel und Auswahl ergänzen.
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
  Methods := 0;
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
        if Reply.GetValue('methods') is TJSONNumber then
          Methods := TJSONNumber(Reply.GetValue('methods')).AsInt;
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
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty or (Methods = 0) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.ExtractIntfNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400); Hinweise (Basisklasse, Zugriffsmethoden, Sichtbarkeit) im Hinweis.
  Hint := TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfPreviewHint, [Name, Edit.EditCount, Length(Edit.Files)]);
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
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfTitle, [SourceClass]), Hint,
    TAtlasStrings.Text(TAtlasTextId.ExtractIntfApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.ExtractIntfApply));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfDone, [Name, Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
  if TargetFile <> '' then
    TAtlasIdeNavigation.GoToLocation(TargetFile, 0, 0);
end;

end.
