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
    cClientCommand = 'atlas.propertyFromAccessors';
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
  Atlas.UI.Editor.Strings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit,
  Atlas.Text.Json;

const
  cApplyCommand = 'atlas.server.propertyFromAccessors';
  // Aufrufe im Projekt suchen dauert; wie beim Umbenennen.
  cTimeoutMs = 60000;

class procedure TAtlasIdePropertyFromAccessors.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mReply: TAtlasServerEditReply;
  mProperties, mCalls: Integer;
  mHint: string;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Die Argumente der Code-Aktion gehen unverändert an den Server.
  mProperties := 0;
  mCalls := 0;
  if not TAtlasIdeServerEdit.Fetch(ASession,
    TAtlasServerEditCommand.Create(cApplyCommand, AArgumentsJson, cTimeoutMs, TAtlasTextId.PropertyAccessorsFailed),
    procedure(const AReply: TJSONObject)
    begin
      mProperties := TJsonRead.Int(AReply, 'properties');
      mCalls := TJsonRead.Int(AReply, 'calls');
    end, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty then
  begin
    AMessage(TAtlasEditorStrings.Text(TAtlasEditorTextId.PropertyAccessorsNothing));
    Exit;
  end;
  mHint := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.PropertyAccessorsPreviewHint, [mProperties, mCalls,
    mReply.Edit.EditCount,
    Length(mReply.Edit.Files)]) + TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.PropertyAccessorsWarning);
  if TAtlasIdeServerEdit.Confirm(TAtlasEditorStrings.Text(TAtlasEditorTextId.PropertyAccessorsTitle), mHint,
    TAtlasEditorStrings.Text(TAtlasEditorTextId.PropertyAccessorsApply), mReply.Edit) and
    TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasEditorStrings.Text(TAtlasEditorTextId.PropertyAccessorsTitle),
    AMessage, mOutcome) then
  begin
    AMessage(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.PropertyAccessorsDone, [mProperties, mCalls, mOutcome.Edits,
      mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.PropertyAccessorsWarning, AMessage);
  end;
end;

end.
