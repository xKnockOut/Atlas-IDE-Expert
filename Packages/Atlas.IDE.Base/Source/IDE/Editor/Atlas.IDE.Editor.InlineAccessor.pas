unit Atlas.IDE.Editor.InlineAccessor;

// Code-Aktionen „Zugriffsmethode durch Feld ersetzen“ und die Sammelaktionen
// für Unit und Projekt (#717): Der Server bietet sie als Client-Befehl
// atlas.inlineAccessor mit URI, Position und Bereich. Atlas schickt die
// offenen Puffer, holt das WorkspaceEdit (atlas.server.inlineAccessor), zeigt
// die Vorschau wie beim Umbenennen mit den Hinweisen des Servers (Methoden,
// die wegen Aufrufen bleiben) und übernimmt erst nach Bestätigung, je Datei
// ein Rückgängig-Schritt. Abschaltbar über refactoring.inlineAccessor (und
// refactoring.inlineAccessorBulk für die Sammelaktionen): Dann bietet der
// Server die Aktionen nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeInlineAccessor = class
  public const
    ClientCommand = 'atlas.inlineAccessor';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, scope]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
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
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation;

const
  ApplyCommand = 'atlas.server.inlineAccessor';
  // Aufrufe im Projekt suchen dauert, die Sammelaktion über das Projekt erst recht.
  TimeoutMs = 120000;

function NumberOf(AReply: TJSONObject; const AName: string): Integer;
begin
  Result := 0;
  if (AReply <> nil) and (AReply.GetValue(AName) is TJSONNumber) then
    Result := TJSONNumber(AReply.GetValue(AName)).AsInt;
end;

class procedure TAtlasIdeInlineAccessor.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Answer, Item: TJSONValue;
  Reply: TJSONObject;
  Hint, Warning: string;
  Warnings: TArray<string>;
  Accessors: Integer;
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
  Warnings := nil;
  Accessors := 0;
  try
    // Die Argumente der Code-Aktion gehen unverändert an den Server.
    Answer := ASession.RunCommand(ApplyCommand, AArgumentsJson, TimeoutMs);
    try
      Reply := nil;
      if Answer is TJSONObject then
        Reply := TJSONObject(Answer);
      Edit := TLspWorkspaceEdit.FromJson(nil);
      if Reply <> nil then
      begin
        Edit := TLspWorkspaceEdit.FromJson(Reply.GetValue('edit'));
        Accessors := NumberOf(Reply, 'accessors');
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
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.InlineAccessorFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.InlineAccessorNothing));
    Exit;
  end;
  Hint := TAtlasStrings.Fmt(TAtlasTextId.InlineAccessorPreviewHint, [Accessors, Edit.EditCount, Length(Edit.Files)]);
  for Warning in Warnings do
    Hint := Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.InlineAccessorWarning, [Warning]);
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
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.InlineAccessorTitle), Hint,
    TAtlasStrings.Text(TAtlasTextId.InlineAccessorApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.InlineAccessorTitle));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.InlineAccessorDone, [Accessors, Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.InlineAccessorWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
