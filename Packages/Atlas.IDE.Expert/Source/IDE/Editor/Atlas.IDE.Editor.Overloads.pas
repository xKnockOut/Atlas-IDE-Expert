unit Atlas.IDE.Editor.Overloads;

// Überladung anlegen (#674): Der Server bietet „Überladung anlegen (als
// Weiterleitung)“ und „Überladung anlegen (Kopie)“ als Client-Befehl
// atlas.createOverload mit URI, Position und Art an. Atlas holt das
// WorkspaceEdit samt Platzhaltern (atlas.server.createOverload), wendet es
// als einen Rückgängig-Schritt an und startet in der Ansicht der Datei den
// Platzhalter-Modus (#51): erst die Parameterliste der neuen Überladung (in
// Deklaration und Implementierung verknüpft), dann Rumpf bzw. Standardwert;
// endet der Modus regulär, bleibt es bei einem Rückgängig-Schritt. Ein Grund
// dagegen kommt als Fehler, Hinweise (override) als Zeile in der
// Meldungsansicht. Abschaltbar über refactoring.overloads. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Editor.WorkspacePlan;

type
  /// <summary>Platzhalter-Modus starten: ABefore = Puffertext vor der Änderung, AOffset = 0, Offsets der Vorlage
  /// im ganzen Text.</summary>
  TAtlasOverloadPlaceholdersProc = reference to procedure(const AView: IOTAEditView; const ABefore: string;
    AOffset: Integer; const AExpansion: TAtlasSnippetExpansion);

  TAtlasIdeOverloads = class
  public const
    ClientCommand = 'atlas.createOverload';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, art]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht; APlaceholders: Platzhalter-Modus (nil = nur Cursor).</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>; const APlaceholders: TAtlasOverloadPlaceholdersProc); static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Completion.ServerPlaceholders,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit;

const
  ApplyCommand = 'atlas.server.createOverload';
  TimeoutMs = 15000;

class procedure TAtlasIdeOverloads.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>; const APlaceholders: TAtlasOverloadPlaceholdersProc);
var
  Answer, Item: TJSONValue;
  Reply: TJSONObject;
  Placeholders: TJSONValue;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Warnings: TArray<string>;
  Warning, Before, FileName: string;
  View: IOTAEditView;
  Expansion: TAtlasSnippetExpansion;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  View := TAtlasEditorBuffer.ActiveView;
  Before := '';
  if (View <> nil) and (View.Buffer <> nil) then
    Before := TAtlasEditorBuffer.Text(View.Buffer);
  Warnings := nil;
  Placeholders := nil;
  try
    try
      Answer := ASession.RunCommand(ApplyCommand, AArgumentsJson, TimeoutMs);
      try
        Edit := TLspWorkspaceEdit.FromJson(nil);
        if Answer is TJSONObject then
        begin
          Reply := TJSONObject(Answer);
          Edit := TLspWorkspaceEdit.FromJson(Reply.GetValue('edit'));
          if Reply.GetValue('placeholders') is TJSONArray then
            Placeholders := Reply.GetValue('placeholders').Clone as TJSONValue;
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
        AMessage(TAtlasStrings.Fmt(TAtlasTextId.OverloadFailed, [E.Message]));
        Exit;
      end;
    end;
    if Edit.IsEmpty then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.OverloadNothing));
      Exit;
    end;
    Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.OverloadTitle));
    if Outcome.Error <> '' then
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
      Exit;
    end;
    AMessage(TAtlasStrings.Text(TAtlasTextId.OverloadDone));
    for Warning in Warnings do
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.OverloadNote, [Warning]));
    // Platzhalter nur in der Ansicht der geänderten Datei.
    if (View = nil) or (View.Buffer = nil) or (Length(Edit.Files) <> 1) then
      Exit;
    FileName := Edit.Files[0].FileName;
    if not SameText(FileName, View.Buffer.FileName) then
      Exit;
    Expansion := TAtlasServerPlaceholders.Expansion(Placeholders, TAtlasEditorBuffer.Text(View.Buffer));
    if Expansion.HasPlaceholders and Assigned(APlaceholders) then
      APlaceholders(View, Before, 0, Expansion);
  finally
    Placeholders.Free;
  end;
end;

end.
