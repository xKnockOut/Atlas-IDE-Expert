unit Atlas.IDE.Editor.PropertyFromAccessors;

// Code-Aktionen „Property X anlegen“ und „Fehlende Properties anlegen (n)“
// (#682): Der Server bietet sie als Client-Befehl atlas.propertyFromAccessors
// mit URI, Position und der Angabe, ob Aufrufe umgestellt werden. Atlas
// schickt die offenen Puffer, holt das WorkspaceEdit
// (atlas.server.propertyFromAccessors), zeigt die Vorschau wie beim
// Umbenennen mit den Hinweisen des Servers (Methodenzeiger, sichtbar
// gebliebene Zugriffsmethoden) und übernimmt erst nach Bestätigung, je Datei
// ein Rückgängig-Schritt. Abschaltbar über refactoring.propertyFromAccessors:
// Dann bietet der Server die Aktionen nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdePropertyFromAccessors = class
  public const
    ClientCommand = 'atlas.propertyFromAccessors';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, calls]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
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
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Navigation;

const
  ApplyCommand = 'atlas.server.propertyFromAccessors';
  // Aufrufe im Projekt suchen dauert; wie beim Umbenennen.
  TimeoutMs = 60000;

function NumberOf(AReply: TJSONObject; const AName: string): Integer;
begin
  Result := 0;
  if (AReply <> nil) and (AReply.GetValue(AName) is TJSONNumber) then
    Result := TJSONNumber(AReply.GetValue(AName)).AsInt;
end;

class procedure TAtlasIdePropertyFromAccessors.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Answer, Item: TJSONValue;
  Reply: TJSONObject;
  Hint, Warning: string;
  Warnings: TArray<string>;
  Properties, Calls: Integer;
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
  Properties := 0;
  Calls := 0;
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
        Properties := NumberOf(Reply, 'properties');
        Calls := NumberOf(Reply, 'calls');
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
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.PropertyAccessorsFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.PropertyAccessorsNothing));
    Exit;
  end;
  Hint := TAtlasStrings.Fmt(TAtlasTextId.PropertyAccessorsPreviewHint, [Properties, Calls, Edit.EditCount,
    Length(Edit.Files)]);
  for Warning in Warnings do
    Hint := Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.PropertyAccessorsWarning, [Warning]);
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
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.PropertyAccessorsTitle), Hint,
    TAtlasStrings.Text(TAtlasTextId.PropertyAccessorsApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.PropertyAccessorsTitle));
  if Outcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  AMessage(TAtlasStrings.Fmt(TAtlasTextId.PropertyAccessorsDone, [Properties, Calls, Outcome.Edits, Outcome.Files]));
  for Warning in Warnings do
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.PropertyAccessorsWarning, [Warning]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
end;

end.
