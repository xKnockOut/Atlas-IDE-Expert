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
    cClientCommand = 'atlas.promoteVariable';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  Atlas.IDE.Editor.NamedRefactoring,
  Atlas.UI.Editor.Strings;

const
  cApplyCommand = 'atlas.server.promoteVariable';

{ TAtlasIdePromoteVariable }

class procedure TAtlasIdePromoteVariable.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mTexts: TAtlasNamedRefactoringTexts;
begin
  mTexts.Title := TAtlasEditorTextId.PromoteVariableTitle;
  mTexts.Prompt := TAtlasEditorTextId.PromoteVariablePrompt;
  mTexts.Failed := TAtlasEditorTextId.PromoteVariableFailed;
  mTexts.Nothing := TAtlasEditorTextId.PromoteVariableNothing;
  mTexts.PreviewHint := TAtlasEditorTextId.PromoteVariablePreviewHint;
  mTexts.Apply := TAtlasEditorTextId.PromoteVariableApply;
  mTexts.Done := TAtlasEditorTextId.PromoteVariableDone;
  mTexts.Warning := TAtlasEditorTextId.PromoteVariableWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, cApplyCommand, mTexts, APolicy, AMessage);
end;

end.
