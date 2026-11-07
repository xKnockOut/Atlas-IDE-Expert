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
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Editor.ClassExtraction,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit,
  Atlas.IDE.Editor.ClassExtraction,
  Atlas.IDE.Foundation.Navigation;

const
  cPrepareCommand = 'atlas.server.moveMember.prepare';
  cApplyCommand = 'atlas.server.moveMember';
  // Verweise suchen und Namen auflösen dauert; wie beim Umbenennen.
  cTimeoutMs = 60000;

/// <summary>„… in Vorfahr verschieben“ bzw. „… in Nachfahren verschieben“ je nach Richtung von AModel.</summary>
function TitleOf(AModel: TAtlasClassExtractionModel): string;
begin
  if AModel.Source.Direction = 'down' then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.MoveDownTitle, [AModel.Source.MemberName]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.MoveUpTitle, [AModel.Source.MemberName]);
  end;
end;

class procedure TAtlasIdeMoveMember.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mChoice: TAtlasClassExtractionChoice;
  mReply: TAtlasServerEditReply;
  mTargetFile, mHint: string;
  mMoved, mTargetLine: Integer;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  if not TAtlasIdeClassExtraction.Choose(ASession, TAtlasServerEditCommand.Create(cPrepareCommand, AArgumentsJson,
    cTimeoutMs, TAtlasTextId.MoveMemberFailed),
    function(AModel: TAtlasClassExtractionModel): string
    begin
      Result := TitleOf(AModel);
    end, AMessage, mChoice) then
  begin
    Exit;
  end;
  mTargetFile := '';
  mMoved := 0;
  mTargetLine := 0;
  if not TAtlasIdeServerEdit.Fetch(ASession, TAtlasServerEditCommand.Create(cApplyCommand, mChoice.ApplyArguments,
    cTimeoutMs, TAtlasTextId.MoveMemberFailed),
    procedure(const AReply: TJSONObject)
    begin
      mTargetFile := TAtlasIdeServerEdit.TextOf(AReply, 'file');
      if mTargetFile <> '' then
      begin
        mTargetFile := TLspSession.UriToPath(mTargetFile);
      end;
      mMoved := TAtlasIdeServerEdit.NumberOf(AReply, 'moved');
      mTargetLine := TAtlasIdeServerEdit.NumberOf(AReply, 'line');
    end, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty or (mMoved = 0) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MoveMemberNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400); Hinweise (gehobene Sichtbarkeit, override, uses) im Hinweis.
  mHint := TAtlasStrings.Fmt(TAtlasTextId.MoveMemberPreviewHint, [mMoved, mReply.Edit.EditCount,
    Length(mReply.Edit.Files)]) + TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.ExtractIntfWarning);
  if TAtlasIdeServerEdit.Confirm(mChoice.Title, mHint, TAtlasStrings.Text(TAtlasTextId.MoveMemberApply),
    mReply.Edit) and
    TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.MoveMemberApply), AMessage,
      mOutcome) then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.MoveMemberDone, [mMoved, mOutcome.Edits, mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.ExtractIntfWarning, AMessage);
    if mTargetFile <> '' then
    begin
      TAtlasIdeNavigation.GoToLocation(mTargetFile, mTargetLine, 0);
    end;
  end;
end;

end.
