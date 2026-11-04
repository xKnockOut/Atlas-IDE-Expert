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
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Completion.ServerPlaceholders,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit;

const
  ApplyCommand = 'atlas.server.createOverload';
  TimeoutMs = 15000;

/// <summary>Startet den Platzhalter-Modus, wenn AEdit nur die Datei von AView geändert hat.</summary>
procedure StartPlaceholders(const AView: IOTAEditView; const ABefore: string; const AEdit: TLspWorkspaceEdit;
  APlaceholders: TJSONValue; const AProc: TAtlasOverloadPlaceholdersProc);
var
  mExpansion: TAtlasSnippetExpansion;
begin
  // Platzhalter nur in der Ansicht der geänderten Datei.
  if (AView = nil) or (AView.Buffer = nil) or (Length(AEdit.Files) <> 1) or
    not SameText(AEdit.Files[0].FileName, AView.Buffer.FileName) then
  begin
    Exit;
  end;
  mExpansion := TAtlasServerPlaceholders.Expansion(APlaceholders, TAtlasEditorBuffer.Text(AView.Buffer));
  if mExpansion.HasPlaceholders and Assigned(AProc) then
  begin
    AProc(AView, ABefore, 0, mExpansion);
  end;
end;

class procedure TAtlasIdeOverloads.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>; const APlaceholders: TAtlasOverloadPlaceholdersProc);
var
  mView: IOTAEditView;
  mBefore, mWarning: string;
  mPlaceholders: TJSONValue;
  mReply: TAtlasServerEditReply;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  mBefore := '';
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    mBefore := TAtlasEditorBuffer.Text(mView.Buffer);
  end;
  mPlaceholders := nil;
  try
    if not TAtlasIdeServerEdit.Fetch(ASession, TAtlasServerEditCommand.Create(ApplyCommand, AArgumentsJson,
      TimeoutMs, TAtlasTextId.OverloadFailed),
      procedure(const AReply: TJSONObject)
      begin
        if AReply.GetValue('placeholders') is TJSONArray then
        begin
          mPlaceholders := AReply.GetValue('placeholders').Clone as TJSONValue;
        end;
      end, AMessage, mReply) then
    begin
      Exit;
    end;
    if mReply.Edit.IsEmpty then
    begin
      AMessage(TAtlasStrings.Text(TAtlasTextId.OverloadNothing));
      Exit;
    end;
    if not TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.OverloadTitle), AMessage,
      mOutcome) then
    begin
      Exit;
    end;
    AMessage(TAtlasStrings.Text(TAtlasTextId.OverloadDone));
    for mWarning in mReply.Warnings do
    begin
      AMessage(TAtlasStrings.Fmt(TAtlasTextId.OverloadNote, [mWarning]));
    end;
    StartPlaceholders(mView, mBefore, mReply.Edit, mPlaceholders, APlaceholders);
  finally
    mPlaceholders.Free;
  end;
end;

end.
