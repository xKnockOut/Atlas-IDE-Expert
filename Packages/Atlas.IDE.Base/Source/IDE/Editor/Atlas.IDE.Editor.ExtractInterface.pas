unit Atlas.IDE.Editor.ExtractInterface;

// Code-Aktion „Interface aus … herauslösen …“ (#664) auf der Kopfzeile einer
// Klasse: Der Server bietet sie als Client-Befehl atlas.extractInterface
// mit URI und Position an. Atlas schickt die offenen Puffer, holt die Kandidaten
// (atlas.server.extractInterface.prepare), zeigt den Dialog „Mitglieder
// herauslösen“ (Name, Ziel-Unit, Mitglieder), holt das WorkspaceEdit
// (atlas.server.extractInterface), zeigt die Vorschau wie beim Umbenennen mit
// den Hinweisen des Servers, übernimmt erst nach Bestätigung und öffnet danach
// die Unit mit dem Interface. Abbrüche (Name vergeben, Kreisverweis, ungültige
// Auswahl) meldet der Server als Fehler. Abschaltbar über
// refactoring.extractInterface: Dann bietet der Server die Aktion nicht an.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeExtractInterface = class
  public const
    cClientCommand = 'atlas.extractInterface';
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
  cPrepareCommand = 'atlas.server.extractInterface.prepare';
  cApplyCommand = 'atlas.server.extractInterface';
  // Typen der Signaturen auflösen dauert; wie beim Umbenennen.
  cTimeoutMs = 60000;

class procedure TAtlasIdeExtractInterface.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mChoice: TAtlasClassExtractionChoice;
  mReply: TAtlasServerEditReply;
  mTargetFile, mHint: string;
  mMethods: Integer;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  if not TAtlasIdeClassExtraction.Choose(ASession, TAtlasServerEditCommand.Create(cPrepareCommand, AArgumentsJson,
    cTimeoutMs, TAtlasTextId.ExtractIntfFailed),
    function(AModel: TAtlasClassExtractionModel): string
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfTitle, [AModel.Source.SourceClass]);
    end, AMessage, mChoice) then
  begin
    Exit;
  end;
  mTargetFile := '';
  mMethods := 0;
  if not TAtlasIdeServerEdit.Fetch(ASession, TAtlasServerEditCommand.Create(cApplyCommand, mChoice.ApplyArguments,
    cTimeoutMs, TAtlasTextId.ExtractIntfFailed),
    procedure(const AReply: TJSONObject)
    begin
      mTargetFile := TAtlasIdeServerEdit.TextOf(AReply, 'file');
      if mTargetFile <> '' then
      begin
        mTargetFile := TLspSession.UriToPath(mTargetFile);
      end;
      mMethods := TAtlasIdeServerEdit.NumberOf(AReply, 'methods');
    end, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty or (mMethods = 0) then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.ExtractIntfNothing));
    Exit;
  end;
  // Vorschau wie beim Umbenennen (#400); Hinweise (Basisklasse, Zugriffsmethoden, Sichtbarkeit) im Hinweis.
  mHint := TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfPreviewHint, [mChoice.Name, mReply.Edit.EditCount,
    Length(mReply.Edit.Files)]) + TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.ExtractIntfWarning);
  if TAtlasIdeServerEdit.Confirm(mChoice.Title, mHint, TAtlasStrings.Text(TAtlasTextId.ExtractIntfApply),
    mReply.Edit) and
    TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.ExtractIntfApply), AMessage,
      mOutcome) then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.ExtractIntfDone, [mChoice.Name, mOutcome.Edits, mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.ExtractIntfWarning, AMessage);
    if mTargetFile <> '' then
    begin
      TAtlasIdeNavigation.GoToLocation(mTargetFile, 0, 0);
    end;
  end;
end;

end.
