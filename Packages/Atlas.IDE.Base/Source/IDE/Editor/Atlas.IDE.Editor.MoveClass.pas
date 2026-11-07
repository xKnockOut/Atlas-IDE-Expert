unit Atlas.IDE.Editor.MoveClass;

// Code-Aktion „Klasse in eigene Unit verschieben …“ (#103 Teil B): Der Server
// bietet sie als Client-Befehl atlas.moveClass mit URI, Position und dem
// vorgeschlagenen Unit-Namen an. Atlas schickt die offenen Puffer, fragt den
// Namen ab (Vorschlag: Klassenname ohne T), holt das WorkspaceEdit
// (atlas.server.moveClass), zeigt die Vorschau wie beim Umbenennen mit den
// Hinweisen des Servers, übernimmt erst nach Bestätigung und öffnet danach
// die neue Unit. Abbrüche (Datei vorhanden, Zugriff auf implementation-lokale
// Namen) meldet der Server als Fehler. Abschaltbar über refactoring.moveClass:
// Dann bietet der Server die Aktion nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeMoveClass = class
  public const
    ClientCommand = 'atlas.moveClass';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.JSON,
  Atlas.UI.Strings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit,
  Atlas.IDE.Foundation.Navigation;

const
  cApplyCommand = 'atlas.server.moveClass';
  // Alle verwendenden Units suchen dauert; wie beim Umbenennen.
  cTimeoutMs = 60000;

class procedure TAtlasIdeMoveClass.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mName, mApplyArguments, mHint, mNewFile: string;
  mReply: TAtlasServerEditReply;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Name abfragen und das dritte Argument ersetzen.
  if not TAtlasIdeServerEdit.AskName(AArgumentsJson, TAtlasTextId.MoveClassTitle, TAtlasTextId.MoveClassPrompt, mName,
    mApplyArguments) then
  begin
    Exit;
  end;
  mNewFile := '';
  if not TAtlasIdeServerEdit.Fetch(ASession, TAtlasServerEditCommand.Create(cApplyCommand, mApplyArguments, cTimeoutMs,
    TAtlasTextId.MoveClassFailed),
    procedure(const AReply: TJSONObject)
    begin
      mNewFile := TAtlasIdeServerEdit.TextOf(AReply, 'file');
    end, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MoveClassNothing));
    Exit;
  end;
  mHint := TAtlasStrings.Fmt(TAtlasTextId.MoveClassPreviewHint, [mName, mReply.Edit.EditCount,
    Length(mReply.Edit.Files)]) + TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.MoveClassWarning);
  if TAtlasIdeServerEdit.Confirm(TAtlasStrings.Text(TAtlasTextId.MoveClassTitle), mHint,
    TAtlasStrings.Text(TAtlasTextId.MoveClassApply), mReply.Edit) and
    TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.MoveClassTitle), AMessage,
    mOutcome) then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveClassDone, [mName, mOutcome.Edits, mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.MoveClassWarning, AMessage);
    if mNewFile <> '' then
    begin
      TAtlasIdeNavigation.GoToLocation(TLspSession.UriToPath(mNewFile), 0, 0);
    end;
  end;
end;

end.
