unit Atlas.IDE.Editor.AnonymousMethod;

// Code-Aktion „In Methode umwandeln“ für anonyme Methoden (#680): Der Server
// bietet sie als Client-Befehl atlas.anonymousMethod mit URI, Position und
// dem vorgeschlagenen Namen an (HandleClick, CompareByName …). Atlas fragt
// den Namen ab, holt das WorkspaceEdit (atlas.server.anonymousMethod; ein
// vergebener Name kommt als Fehler mit Grund zurück), zeigt die Vorschau mit
// der Erklärung der Form (Methodenname, Weiterleitung oder Felder) und den
// Warnungen und übernimmt erst nach Bestätigung als ein Rückgängig-Schritt;
// der Ablauf liegt in TAtlasIdeNamedRefactoring. „Als anonyme Methode
// einbetten“ ist eine gewöhnliche Code-Aktion mit Vorschau. Abschaltbar über
// refactoring.anonymousMethod. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeAnonymousMethod = class
  public const
    ClientCommand = 'atlas.anonymousMethod';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.IDE.Editor.NamedRefactoring;

const
  ApplyCommand = 'atlas.server.anonymousMethod';

class procedure TAtlasIdeAnonymousMethod.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.AnonymousMethodTitle;
  Texts.Prompt := TAtlasTextId.AnonymousMethodPrompt;
  Texts.Failed := TAtlasTextId.AnonymousMethodFailed;
  Texts.Nothing := TAtlasTextId.AnonymousMethodNothing;
  Texts.PreviewHint := TAtlasTextId.AnonymousMethodPreviewHint;
  Texts.Apply := TAtlasTextId.AnonymousMethodApply;
  Texts.Done := TAtlasTextId.AnonymousMethodDone;
  Texts.Warning := TAtlasTextId.AnonymousMethodWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, ApplyCommand, Texts, APolicy, AMessage);
end;

end.
