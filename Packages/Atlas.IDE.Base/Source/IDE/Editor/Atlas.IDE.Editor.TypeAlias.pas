unit Atlas.IDE.Editor.TypeAlias;

// Typ-Alias einführen und auflösen (#681): Der Server bietet „Typ-Alias
// einführen (Ausdruck)“ als Client-Befehl atlas.typeAlias mit URI, Position,
// vorgeschlagenem Namen und Reichweite an; Atlas fragt den Namen ab und holt
// das WorkspaceEdit (atlas.server.typeAlias). „Alias auflösen (X)“ kommt als
// atlas.inlineTypeAlias mit URI und Position und geht ohne Namensabfrage an
// atlas.server.inlineTypeAlias. Ein Grund dagegen kommt als Fehler zurück.
// Vorschau mit allen Stellen und den Warnungen, erst nach Bestätigung
// übernommen, je Datei ein Rückgängig-Schritt; der Ablauf liegt in
// TAtlasIdeNamedRefactoring. Abschaltbar über refactoring.typeAlias. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeTypeAlias = class
  public const
    cClientCommand = 'atlas.typeAlias';
    cInlineClientCommand = 'atlas.inlineTypeAlias';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name, reichweite]); ASession: laufende
    /// Sitzung oder nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
    /// <summary>Wie Execute für „Alias auflösen“ ([uri, position]), ohne Namensabfrage.</summary>
    class procedure ExecuteInline(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  Atlas.IDE.Editor.NamedRefactoring,
  Atlas.UI.Editor.Strings;

const
  cApplyCommand = 'atlas.server.typeAlias';
  cInlineApplyCommand = 'atlas.server.inlineTypeAlias';

{ TAtlasIdeTypeAlias }

class procedure TAtlasIdeTypeAlias.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mTexts: TAtlasNamedRefactoringTexts;
begin
  mTexts.Title := TAtlasEditorTextId.TypeAliasTitle;
  mTexts.Prompt := TAtlasEditorTextId.TypeAliasPrompt;
  mTexts.Failed := TAtlasEditorTextId.TypeAliasFailed;
  mTexts.Nothing := TAtlasEditorTextId.TypeAliasNothing;
  mTexts.PreviewHint := TAtlasEditorTextId.TypeAliasPreviewHint;
  mTexts.Apply := TAtlasEditorTextId.TypeAliasApply;
  mTexts.Done := TAtlasEditorTextId.TypeAliasDone;
  mTexts.Warning := TAtlasEditorTextId.TypeAliasWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, cApplyCommand, mTexts, APolicy, AMessage);
end;

class procedure TAtlasIdeTypeAlias.ExecuteInline(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mTexts: TAtlasNamedRefactoringTexts;
begin
  mTexts.Title := TAtlasEditorTextId.InlineTypeAliasTitle;
  mTexts.Prompt := TAtlasEditorTextId.InlineTypeAliasTitle;
  mTexts.Failed := TAtlasEditorTextId.InlineTypeAliasFailed;
  mTexts.Nothing := TAtlasEditorTextId.InlineTypeAliasNothing;
  mTexts.PreviewHint := TAtlasEditorTextId.TypeAliasPreviewHint;
  mTexts.Apply := TAtlasEditorTextId.InlineTypeAliasApply;
  mTexts.Done := TAtlasEditorTextId.InlineTypeAliasDone;
  mTexts.Warning := TAtlasEditorTextId.TypeAliasWarning;
  TAtlasIdeNamedRefactoring.ExecuteWithoutName(ASession, AArgumentsJson, cInlineApplyCommand, mTexts, APolicy,
    AMessage);
end;

end.
