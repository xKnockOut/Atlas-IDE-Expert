unit Atlas.IDE.Editor.ExtractSuperclass;

// Code-Aktion „Basisklasse aus … herauslösen …“ (#713) auf der Kopfzeile einer
// Klasse: Der Server bietet sie als Client-Befehl atlas.extractSuperclass
// mit URI und Position an. Atlas schickt die offenen Puffer, holt die Kandidaten
// (atlas.server.extractSuperclass.prepare), zeigt den Dialog „Mitglieder
// herauslösen“ (Name, Ziel-Unit, Felder, Methoden und Properties, Methoden
// wahlweise nur abstrakt, Abhängigkeiten mitnehmen), holt das WorkspaceEdit
// (atlas.server.extractSuperclass), zeigt die Vorschau wie beim Umbenennen mit
// den Hinweisen des Servers, übernimmt erst nach Bestätigung und öffnet danach
// die Basisklasse. Abbrüche (Name vergeben, fehlende
// Abhängigkeit, Kreisverweis) meldet der Server als Fehler. Abschaltbar über
// refactoring.extractSuperclass: Dann bietet der Server die Aktion nicht an.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeExtractSuperclass = class
  public const
    ClientCommand = 'atlas.extractSuperclass';
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
  cPrepareCommand = 'atlas.server.extractSuperclass.prepare';
  cApplyCommand = 'atlas.server.extractSuperclass';
  // Namen für die neue Unit auflösen dauert; wie beim Umbenennen.
  cTimeoutMs = 60000;

class procedure TAtlasIdeExtractSuperclass.Execute(ASession: TLspSession; const AArgumentsJson: string;
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
    cTimeoutMs, TAtlasTextId.ExtractSuperFailed),
    function(AModel: TAtlasClassExtractionModel): string
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractSuperTitle, [AModel.Source.SourceClass]);
    end, AMessage, mChoice) then
  begin
    Exit;
  end;
  mTargetFile := '';
  mMoved := 0;
  mTargetLine := 0;
  if not TAtlasIdeServerEdit.Fetch(ASession, TAtlasServerEditCommand.Create(cApplyCommand, mChoice.ApplyArguments,
    cTimeoutMs, TAtlasTextId.ExtractSuperFailed),
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
    AMessage(TAtlasStrings.Text(TAtlasTextId.ExtractSuperNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400); Hinweise (gehobene Sichtbarkeit, aufgeteilte Konstruktoren) im Hinweis.
  mHint := TAtlasStrings.Fmt(TAtlasTextId.ExtractSuperPreviewHint, [mChoice.Name, mReply.Edit.EditCount,
    Length(mReply.Edit.Files)]) + TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.ExtractIntfWarning);
  if TAtlasIdeServerEdit.Confirm(mChoice.Title, mHint, TAtlasStrings.Text(TAtlasTextId.ExtractIntfApply), mReply.Edit) and
    TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.ExtractIntfApply), AMessage, mOutcome) then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.ExtractSuperDone, [mChoice.Name, mOutcome.Edits, mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.ExtractIntfWarning, AMessage);
    if mTargetFile <> '' then
    begin
      TAtlasIdeNavigation.GoToLocation(mTargetFile, mTargetLine, 0);
    end;
  end;
end;

end.
