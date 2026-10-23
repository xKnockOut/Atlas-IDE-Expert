unit Atlas.IDE.Editor.PromoteVariable;

// Code-Aktionen „In Feld umwandeln“ und „In lokale Variable umwandeln“ (#668):
// Der Server bietet sie als Client-Befehl atlas.promoteVariable mit URI,
// Position und dem vorgeschlagenen Namen an. Atlas fragt den Namen ab, holt
// das WorkspaceEdit (atlas.server.promoteVariable; ein vergebener Name kommt
// als Fehler mit Grund zurück), zeigt die Vorschau mit den Warnungen (z. B.
// zur Lebensdauer) und übernimmt erst nach Bestätigung als ein
// Rückgängig-Schritt; der Ablauf liegt in TAtlasIdeNamedRefactoring.
// Abschaltbar über refactoring.promoteVariable. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdePromoteVariable = class
  public const
    ClientCommand = 'atlas.promoteVariable';
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
  ApplyCommand = 'atlas.server.promoteVariable';

class procedure TAtlasIdePromoteVariable.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.PromoteVariableTitle;
  Texts.Prompt := TAtlasTextId.PromoteVariablePrompt;
  Texts.Failed := TAtlasTextId.PromoteVariableFailed;
  Texts.Nothing := TAtlasTextId.PromoteVariableNothing;
  Texts.PreviewHint := TAtlasTextId.PromoteVariablePreviewHint;
  Texts.Apply := TAtlasTextId.PromoteVariableApply;
  Texts.Done := TAtlasTextId.PromoteVariableDone;
  Texts.Warning := TAtlasTextId.PromoteVariableWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, ApplyCommand, Texts, APolicy, AMessage);
end;

end.
