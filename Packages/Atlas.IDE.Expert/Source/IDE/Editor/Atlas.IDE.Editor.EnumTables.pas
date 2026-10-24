unit Atlas.IDE.Editor.EnumTables;

// Aufzählung mit Namenstabelle (#667): Der Server bietet „Namenstabelle
// anlegen (TTyp)“ als Client-Befehl atlas.enumTable mit URI, Position,
// vorgeschlagenem Namen und Stelle an; Atlas fragt den Namen ab und holt das
// WorkspaceEdit (atlas.server.enumTable). „Tabellen von TTyp nachziehen“ kommt
// als atlas.enumTablesSync mit URI und Position und geht ohne Namensabfrage an
// atlas.server.enumTablesSync. Ein Grund dagegen kommt als Fehler zurück.
// Vorschau mit allen Stellen und den Warnungen (geschätzte Stellen), erst
// nach Bestätigung übernommen, je Datei ein Rückgängig-Schritt; der Ablauf
// liegt in TAtlasIdeNamedRefactoring. Die Korrektur an einer einzelnen
// Tabelle trägt ihr Edit selbst und braucht diese Unit nicht. Abschaltbar
// über refactoring.enumTables. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeEnumTables = class
  public const
    ClientCommand = 'atlas.enumTable';
    SyncClientCommand = 'atlas.enumTablesSync';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, name, stelle]); ASession: laufende
    /// Sitzung oder nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
    /// <summary>Wie Execute für „Tabellen nachziehen“ ([uri, position]), ohne Namensabfrage.</summary>
    class procedure ExecuteSync(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.IDE.Editor.NamedRefactoring;

const
  ApplyCommand = 'atlas.server.enumTable';
  SyncApplyCommand = 'atlas.server.enumTablesSync';

class procedure TAtlasIdeEnumTables.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.EnumTableTitle;
  Texts.Prompt := TAtlasTextId.EnumTablePrompt;
  Texts.Failed := TAtlasTextId.EnumTableFailed;
  Texts.Nothing := TAtlasTextId.EnumTableNothing;
  Texts.PreviewHint := TAtlasTextId.EnumTablesPreviewHint;
  Texts.Apply := TAtlasTextId.EnumTableApply;
  Texts.Done := TAtlasTextId.EnumTableDone;
  Texts.Warning := TAtlasTextId.EnumTablesWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, ApplyCommand, Texts, APolicy, AMessage);
end;

class procedure TAtlasIdeEnumTables.ExecuteSync(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  Texts: TAtlasNamedRefactoringTexts;
begin
  Texts.Title := TAtlasTextId.EnumTablesSyncTitle;
  Texts.Prompt := TAtlasTextId.EnumTablesSyncTitle;
  Texts.Failed := TAtlasTextId.EnumTablesSyncFailed;
  Texts.Nothing := TAtlasTextId.EnumTablesSyncNothing;
  Texts.PreviewHint := TAtlasTextId.EnumTablesPreviewHint;
  Texts.Apply := TAtlasTextId.EnumTablesSyncApply;
  Texts.Done := TAtlasTextId.EnumTablesSyncDone;
  Texts.Warning := TAtlasTextId.EnumTablesWarning;
  TAtlasIdeNamedRefactoring.ExecuteWithoutName(ASession, AArgumentsJson, SyncApplyCommand, Texts, APolicy,
    AMessage);
end;

end.
