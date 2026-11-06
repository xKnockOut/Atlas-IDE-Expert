unit Atlas.IDE.Editor.InvertBoolean;

// Code-Aktion „Bedeutung umkehren (X → Y)“ (#715): Der Server bietet sie als
// Client-Befehl atlas.invertBoolean mit URI, Position und dem vorgeschlagenen
// Namen an. Atlas fragt den Namen ab, holt das WorkspaceEdit
// (atlas.server.invertBoolean), zeigt die Vorschau wie beim Umbenennen mit den
// Warnungen des Servers (var/out-Übergaben, @X, Zeichenketten für RTTI,
// published Properties) und übernimmt erst nach Bestätigung; der Ablauf liegt
// in TAtlasIdeNamedRefactoring. Abschaltbar über refactoring.invertBoolean:
// Dann bietet der Server die Aktion nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeInvertBoolean = class
  public const
    ClientCommand = 'atlas.invertBoolean';
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
  ApplyCommand = 'atlas.server.invertBoolean';

class procedure TAtlasIdeInvertBoolean.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.InvertBooleanTitle;
  Texts.Prompt := TAtlasTextId.InvertBooleanPrompt;
  Texts.Failed := TAtlasTextId.InvertBooleanFailed;
  Texts.Nothing := TAtlasTextId.InvertBooleanNothing;
  Texts.PreviewHint := TAtlasTextId.InvertBooleanPreviewHint;
  Texts.Apply := TAtlasTextId.InvertBooleanApply;
  Texts.Done := TAtlasTextId.InvertBooleanDone;
  Texts.Warning := TAtlasTextId.InvertBooleanWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, ApplyCommand, Texts, APolicy, AMessage);
end;

end.
