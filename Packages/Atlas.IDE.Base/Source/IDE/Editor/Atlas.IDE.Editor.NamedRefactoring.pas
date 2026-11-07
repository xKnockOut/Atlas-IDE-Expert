unit Atlas.IDE.Editor.NamedRefactoring;

// Ablauf für Code-Aktionen, die einen Namen brauchen und projektweit ändern
// (Boolean umkehren #715, Variable und Feld umwandeln #668, anonyme Methode
// umwandeln #680, Typ-Alias einführen #681): Der Server bietet sie als
// Client-Befehl mit [uri, position, vorgeschlagener Name, weitere …] an;
// weitere Argumente (die Reichweite bei #681) gehen unverändert mit. Atlas
// fragt den Namen ab, schickt die offenen Puffer, holt die Antwort des
// Server-Befehls ({"edit", "warnings", "places", "files", optional
// "preview"}), zeigt die Vorschau wie beim
// Umbenennen mit dem Vorschautext und den Warnungen und übernimmt erst nach
// Bestätigung, je Datei ein Rückgängig-Schritt. Die Texte kommen je Aktion
// aus TAtlasNamedRefactoringTexts. Aktionen ohne Namen (Methode ohne Self
// #686) reichen ihre Argumente unverändert über ExecuteWithoutName weiter.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  /// <summary>Texte einer Aktion: Titel, Frage nach dem Namen, Fehler (%s), nichts zu tun, Hinweis der Vorschau
  /// (%d Stellen, %d Dateien), Knopf, Ergebnis (%d Änderungen, %d Dateien), Warnung (%s).</summary>
  TAtlasNamedRefactoringTexts = record
    Title: TAtlasTextId;
    Prompt: TAtlasTextId;
    Failed: TAtlasTextId;
    Nothing: TAtlasTextId;
    PreviewHint: TAtlasTextId;
    Apply: TAtlasTextId;
    Done: TAtlasTextId;
    Warning: TAtlasTextId;
  end;

  TAtlasIdeNamedRefactoring = class
  private
    /// <summary>Server-Befehl mit AApplyArguments ausführen, Vorschau zeigen und nach Bestätigung übernehmen.
    /// </summary>
    class procedure Run(ASession: TLspSession; const AApplyArguments, AApplyCommand: string;
      const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
      static;
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name, weitere …]); AApplyCommand:
    /// Befehl des Servers; ASession: laufende Sitzung oder nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson, AApplyCommand: string;
      const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
      static;
    /// <summary>Wie Execute, aber ohne Namensabfrage: AArgumentsJson geht unverändert an AApplyCommand;
    /// ATexts.Prompt bleibt ungenutzt.</summary>
    class procedure ExecuteWithoutName(ASession: TLspSession; const AArgumentsJson, AApplyCommand: string;
      const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
      static;
  end;

implementation

uses
  System.JSON,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit;

const
  // Verweise, Überschreibungen und Formulare im Projekt suchen dauert; wie beim Umbenennen.
  cTimeoutMs = 60000;

class procedure TAtlasIdeNamedRefactoring.Execute(ASession: TLspSession; const AArgumentsJson, AApplyCommand: string;
  const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mName, mApplyArguments: string;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Namen abfragen (Vorschlag des Servers) und das dritte Argument ersetzen.
  if TAtlasIdeServerEdit.AskName(AArgumentsJson, ATexts.Title, ATexts.Prompt, mName, mApplyArguments) then
  begin
    Run(ASession, mApplyArguments, AApplyCommand, ATexts, APolicy, AMessage);
  end;
end;

class procedure TAtlasIdeNamedRefactoring.ExecuteWithoutName(ASession: TLspSession; const AArgumentsJson,
  AApplyCommand: string; const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy;
  const AMessage: TProc<string>);
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Run(ASession, AArgumentsJson, AApplyCommand, ATexts, APolicy, AMessage);
end;

class procedure TAtlasIdeNamedRefactoring.Run(ASession: TLspSession; const AApplyArguments, AApplyCommand: string;
  const ATexts: TAtlasNamedRefactoringTexts; APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mReply: TAtlasServerEditReply;
  mPlaces, mFiles: Integer;
  mHint, mExplanation: string;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mPlaces := 0;
  mFiles := 0;
  mExplanation := '';
  if not TAtlasIdeServerEdit.Fetch(ASession,
    TAtlasServerEditCommand.Create(AApplyCommand, AApplyArguments, cTimeoutMs, ATexts.Failed),
    procedure(const AReply: TJSONObject)
    begin
      mPlaces := TAtlasIdeServerEdit.NumberOf(AReply, 'places');
      mFiles := TAtlasIdeServerEdit.NumberOf(AReply, 'files');
      // Erklärung des Servers, z. B. die Form der Umwandlung (#680).
      mExplanation := TAtlasIdeServerEdit.TextOf(AReply, 'preview');
    end, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(ATexts.Nothing));
    Exit;
  end;
  mHint := TAtlasStrings.Fmt(ATexts.PreviewHint, [mPlaces, mFiles]);
  if mExplanation <> '' then
  begin
    mHint := mHint + sLineBreak + mExplanation;
  end;
  mHint := mHint + TAtlasIdeServerEdit.WarningLines(mReply, ATexts.Warning);
  if TAtlasIdeServerEdit.Confirm(TAtlasStrings.Text(ATexts.Title), mHint, TAtlasStrings.Text(ATexts.Apply),
    mReply.Edit) and TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(ATexts.Title), AMessage,
    mOutcome) then
  begin
    AMessage(TAtlasStrings.Fmt(ATexts.Done, [mOutcome.Edits, mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, ATexts.Warning, AMessage);
  end;
end;

end.
