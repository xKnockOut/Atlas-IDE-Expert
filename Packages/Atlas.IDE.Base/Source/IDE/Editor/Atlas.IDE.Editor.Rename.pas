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
  Atlas.UI.Results.View,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Forms.Designer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Navigation;

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
    begin
      ASession.Sync(FileName, TAtlasEditorBuffer.Text(Buffer));
    end;
  end;
  TAtlasIdeForms.SyncNow(ASession);
end;

type
  // Stelle des Namens unter dem Cursor und sein bisheriger Name.
  TRenameTarget = record
    FileName: string;
    Line: Integer;
    Character: Integer;
    OldName: string;
  end;

/// <summary>Oberer Editor, sonst nil.</summary>
function TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

/// <summary>Name unter dem Cursor von AView, den der Server umbenennen kann. False mit Meldung, wenn es keinen gibt
/// oder der Server scheitert.</summary>
function PrepareTarget(ASession: TLspSession; const AView: IOTAEditView; const AMessage: TProc<string>;
  out ATarget: TRenameTarget): Boolean;
var
  mText: string;
  mLines: TArray<string>;
  mCursor: TOTAEditPos;
begin
  Result := False;
  ATarget := Default(TRenameTarget);
  ATarget.FileName := AView.Buffer.FileName;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mLines := mText.Split([#13#10, #10]);
  mCursor := AView.CursorPos;
  if (mCursor.Line < 1) or (mCursor.Line > Length(mLines)) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
    Exit;
  end;
  ATarget.Line := mCursor.Line - 1;
  ATarget.Character := TLspSession.ColumnToIndex(mLines[ATarget.Line], mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  try
    Result := ASession.PrepareRename(ATarget.FileName, mText, ATarget.Line, ATarget.Character, ATarget.OldName);
    if not Result then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
    end;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.RenameFailed, [E.Message]));
    end;
  end;
end;

/// <summary>Fragt nach dem neuen Namen; False bei Abbruch, leerem oder unverändertem Namen.</summary>
function AskNewName(const AOldName: string; out ANewName: string): Boolean;
begin
  ANewName := AOldName;
  Result := InputQuery(TAtlasStrings.Text(TAtlasTextId.RenameTitle), TAtlasStrings.Fmt(TAtlasTextId.RenamePrompt,
    [AOldName]), ANewName);
  ANewName := Trim(ANewName);
  Result := Result and (ANewName <> '') and (ANewName <> AOldName);
end;

/// <summary>Änderung des Servers für ATarget mit ANewName; False mit Meldung, wenn er scheitert.</summary>
function FetchEdit(ASession: TLspSession; const ATarget: TRenameTarget; const ANewName: string;
  const AMessage: TProc<string>; out AEdit: TLspWorkspaceEdit): Boolean;
var
  mResponse: TJSONValue;
begin
  Result := False;
  AEdit := TLspWorkspaceEdit.FromJson(nil);
  try
    mResponse := ASession.Rename(ATarget.FileName, ATarget.Line, ATarget.Character, ANewName, RenameTimeoutMs);
    try
      AEdit := TLspWorkspaceEdit.FromJson(mResponse);
    finally
      mResponse.Free;
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.RenameFailed, [E.Message]));
    end;
  end;
end;

/// <summary>Vorschau (#400): alle betroffenen Zeilen vorher und nachher; True, wenn der Benutzer umbenennt.</summary>
function ConfirmRename(const AOldName, ANewName: string; const AEdit: TLspWorkspaceEdit): Boolean;
var
  mPreview: TArray<TAtlasResultEntry>;
  mOpen: TAtlasResultsOpen;
begin
  mPreview := TAtlasResults.RenamePreview(AEdit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  // Typisierte Variable: Execute ist überladen (Delphi und anonyme Methoden).
  mOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  Result := TAtlasRenamePreview.Execute(TAtlasStrings.Fmt(TAtlasTextId.RenamePreviewTitle, [AOldName, ANewName]),
    TAtlasStrings.Fmt(TAtlasTextId.RenamePreviewHint, [AEdit.EditCount, Length(AEdit.Files)]),
    TAtlasResults.Group(mPreview), mOpen);
end;

/// <summary>Übernimmt AEdit und meldet das Ergebnis.</summary>
procedure ApplyRename(const AOldName, ANewName: string; const AEdit: TLspWorkspaceEdit;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(AEdit, APolicy,
    TAtlasStrings.Fmt(TAtlasTextId.UndoActionRename, [AOldName, ANewName]));
  if mOutcome.Error <> '' then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
  end
  else
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.RenameDone, [AOldName, ANewName, mOutcome.Edits, mOutcome.Files]));
  end;
  if mOutcome.Written > 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [mOutcome.Written]));
  end;
  if AEdit.Unsupported > 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditUnsupported, [AEdit.Unsupported]));
  end;
end;

class procedure TAtlasIdeRename.Execute(ASession: TLspSession; APolicy: TAtlasUnopenedPolicy;
  const AMessage: TProc<string>);
var
  mView: IOTAEditView;
  mTarget: TRenameTarget;
  mNewName: string;
  mEdit: TLspWorkspaceEdit;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mView := TopView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
    Exit;
  end;
  if not PrepareTarget(ASession, mView, AMessage, mTarget) or not AskNewName(mTarget.OldName, mNewName) or
    not FetchEdit(ASession, mTarget, mNewName, AMessage, mEdit) then
  begin
    Exit;
  end;
  if mEdit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.RenameNothing));
  end
  else if ConfirmRename(mTarget.OldName, mNewName, mEdit) then
  begin
    ApplyRename(mTarget.OldName, mNewName, mEdit, APolicy, AMessage);
  end;
end;

end.
