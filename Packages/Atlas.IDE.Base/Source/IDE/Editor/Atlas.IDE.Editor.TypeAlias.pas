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
    ClientCommand = 'atlas.typeAlias';
    InlineClientCommand = 'atlas.inlineTypeAlias';
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
  Atlas.UI.Strings,
  Atlas.IDE.Editor.NamedRefactoring;

const
  ApplyCommand = 'atlas.server.typeAlias';
  InlineApplyCommand = 'atlas.server.inlineTypeAlias';

class procedure TAtlasIdeTypeAlias.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.TypeAliasTitle;
  Texts.Prompt := TAtlasTextId.TypeAliasPrompt;
  Texts.Failed := TAtlasTextId.TypeAliasFailed;
  Texts.Nothing := TAtlasTextId.TypeAliasNothing;
  Texts.PreviewHint := TAtlasTextId.TypeAliasPreviewHint;
  Texts.Apply := TAtlasTextId.TypeAliasApply;
  Texts.Done := TAtlasTextId.TypeAliasDone;
  Texts.Warning := TAtlasTextId.TypeAliasWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, ApplyCommand, Texts, APolicy, AMessage);
end;

class procedure TAtlasIdeTypeAlias.ExecuteInline(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.InlineTypeAliasTitle;
  Texts.Prompt := TAtlasTextId.InlineTypeAliasTitle;
  Texts.Failed := TAtlasTextId.InlineTypeAliasFailed;
  Texts.Nothing := TAtlasTextId.InlineTypeAliasNothing;
  Texts.PreviewHint := TAtlasTextId.TypeAliasPreviewHint;
  Texts.Apply := TAtlasTextId.InlineTypeAliasApply;
  Texts.Done := TAtlasTextId.InlineTypeAliasDone;
  Texts.Warning := TAtlasTextId.TypeAliasWarning;
  TAtlasIdeNamedRefactoring.ExecuteWithoutName(ASession, AArgumentsJson, InlineApplyCommand, Texts, APolicy,
    AMessage);
end;

end.
