unit Atlas.IDE.Editor.MethodKind;

// Code-Aktionen für Methoden ohne Self (#686): Der Server bietet „In
// class-Methode umwandeln“, „In freie Routine umwandeln“ und „In Record-Helper
// verschieben“ als Client-Befehl atlas.methodKind mit URI, Position und Art
// der Umwandlung an. Atlas holt das WorkspaceEdit (atlas.server.methodKind;
// ein Grund gegen die Umwandlung kommt als Fehler zurück), zeigt die Vorschau
// mit der Erklärung (geänderte Aufrufe) und den Warnungen und übernimmt erst
// nach Bestätigung, je Datei ein Rückgängig-Schritt; der Ablauf liegt in
// TAtlasIdeNamedRefactoring, hier ohne Namensabfrage. Abschaltbar über
// refactoring.methodKind. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeMethodKind = class
  public const
    ClientCommand = 'atlas.methodKind';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, Umwandlung]); ASession: laufende
    /// Sitzung oder nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.IDE.Editor.NamedRefactoring;

const
  ApplyCommand = 'atlas.server.methodKind';

class procedure TAtlasIdeMethodKind.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.MethodKindTitle;
  Texts.Prompt := TAtlasTextId.MethodKindTitle;
  Texts.Failed := TAtlasTextId.MethodKindFailed;
  Texts.Nothing := TAtlasTextId.MethodKindNothing;
  Texts.PreviewHint := TAtlasTextId.MethodKindPreviewHint;
  Texts.Apply := TAtlasTextId.MethodKindApply;
  Texts.Done := TAtlasTextId.MethodKindDone;
  Texts.Warning := TAtlasTextId.MethodKindWarning;
  TAtlasIdeNamedRefactoring.ExecuteWithoutName(ASession, AArgumentsJson, ApplyCommand, Texts, APolicy, AMessage);
end;

end.
