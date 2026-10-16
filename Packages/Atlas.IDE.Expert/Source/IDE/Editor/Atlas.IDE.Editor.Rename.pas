unit Atlas.IDE.Editor.Rename;

// „Symbol umbenennen…“ (#397, erster Nutzer der WorkspaceEdits) im Menü
// Atlas und in der Befehlspalette: Symbol am Cursor über prepareRename
// prüfen, neuen Namen erfragen, textDocument/rename beim Server und die
// Änderungen projektweit in die Puffer der IDE übernehmen
// (TAtlasIdeWorkspaceEdit), je Datei ein Rückgängig-Schritt.
// Vorher bekommt der Server den aktuellen Text aller offenen, schon
// abgeglichenen Dateien, damit seine Positionen zu den Puffern passen.
// Vor dem Übernehmen zeigt eine Vorschau alle betroffenen Zeilen vorher und
// nachher (#400); erst „Umbenennen“ ändert etwas.
// Ergebnis und Fehler als Zeile in der Meldungsansicht, nie als Dialog.
// Über mehrere Dateien landet das Umbenennen als ein Satz im
// Änderungsprotokoll (#721) und lässt sich mit Strg+Alt+Z ganz zurücknehmen.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeRename = class
  public
    /// <summary>Schickt dem Server den aktuellen Text aller offenen, schon abgeglichenen Dateien und
    /// der im Designer offenen Formulare (#402).</summary>
    class procedure SyncOpenBuffers(ASession: TLspSession); static;
    /// <summary>ASession: laufende Sitzung oder nil; APolicy: nicht geöffnete Dateien öffnen
    /// oder auf die Platte schreiben; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.JSON,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Forms.Designer,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Foundation.Files;

const
  // Projektweit über viele Units; deutlich länger als eine Hover-Anfrage.
  RenameTimeoutMs = 60000;

class procedure TAtlasIdeRename.SyncOpenBuffers(ASession: TLspSession);
var
  FileName: string;
  Buffer: IOTAEditBuffer;
begin
  for FileName in ASession.SyncedFiles do
  begin
    Buffer := TAtlasIdeFiles.BufferOf(FileName);
    if Buffer <> nil then
      ASession.Sync(FileName, TAtlasEditorBuffer.Text(Buffer));
  end;
  TAtlasIdeForms.SyncNow(ASession);
end;

class procedure TAtlasIdeRename.Execute(ASession: TLspSession; APolicy: TAtlasUnopenedPolicy;
  const AMessage: TProc<string>);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  FileName, Text, OldName, NewName: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  Line, Character: Integer;
  Response: TJSONValue;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Preview: TArray<TAtlasResultEntry>;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  View := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
    Exit;
  end;
  FileName := View.Buffer.FileName;
  SyncOpenBuffers(ASession);
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := Text.Split([#13#10, #10]);
  Cursor := View.CursorPos;
  if (Cursor.Line < 1) or (Cursor.Line > Length(Lines)) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
    Exit;
  end;
  Line := Cursor.Line - 1;
  Character := TLspSession.ColumnToIndex(Lines[Line], Cursor.Col, TAtlasEditorBuffer.TabWidth(View.Buffer));
  try
    if not ASession.PrepareRename(FileName, Text, Line, Character, OldName) then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
      Exit;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.RenameFailed, [E.Message]));
      Exit;
    end;
  end;
  NewName := OldName;
  if not InputQuery(TAtlasStrings.Text(TAtlasTextId.RenameTitle), TAtlasStrings.Fmt(TAtlasTextId.RenamePrompt,
    [OldName]), NewName) then
    Exit;
  NewName := Trim(NewName);
  if (NewName = '') or (NewName = OldName) then
    Exit;
  try
    Response := ASession.Rename(FileName, Line, Character, NewName, RenameTimeoutMs);
    try
      Edit := TLspWorkspaceEdit.FromJson(Response);
    finally
      Response.Free;
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.RenameFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
    Exit;
  end;
  // Vorschau (#400): alle betroffenen Zeilen vorher und nachher.
  Preview := TAtlasResults.RenamePreview(Edit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Fmt(TAtlasTextId.RenamePreviewTitle, [OldName, NewName]),
    TAtlasStrings.Fmt(TAtlasTextId.RenamePreviewHint, [Edit.EditCount, Length(Edit.Files)]),
    TAtlasResults.Group(Preview),
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasEditorHover.GoToLocation(AFileName, ALine, ACharacter);
    end) then
    Exit;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, APolicy,
    TAtlasStrings.Fmt(TAtlasTextId.UndoActionRename, [OldName, NewName]));
  if Outcome.Error <> '' then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]))
  else
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.RenameDone, [OldName, NewName, Outcome.Edits, Outcome.Files]));
  if Outcome.Written > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [Outcome.Written]));
  if Edit.Unsupported > 0 then
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditUnsupported, [Edit.Unsupported]));
end;

end.
