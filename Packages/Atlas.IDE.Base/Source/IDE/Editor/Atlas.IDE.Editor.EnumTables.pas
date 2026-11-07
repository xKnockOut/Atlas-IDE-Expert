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
  cApplyCommand = 'atlas.server.enumTable';
  cSyncApplyCommand = 'atlas.server.enumTablesSync';

class procedure TAtlasIdeEnumTables.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mTexts: TAtlasNamedRefactoringTexts;
begin
  mTexts.Title := TAtlasTextId.EnumTableTitle;
  mTexts.Prompt := TAtlasTextId.EnumTablePrompt;
  mTexts.Failed := TAtlasTextId.EnumTableFailed;
  mTexts.Nothing := TAtlasTextId.EnumTableNothing;
  mTexts.PreviewHint := TAtlasTextId.EnumTablesPreviewHint;
  mTexts.Apply := TAtlasTextId.EnumTableApply;
  mTexts.Done := TAtlasTextId.EnumTableDone;
  mTexts.Warning := TAtlasTextId.EnumTablesWarning;
  TAtlasIdeNamedRefactoring.Execute(ASession, AArgumentsJson, cApplyCommand, mTexts, APolicy, AMessage);
end;

class procedure TAtlasIdeEnumTables.ExecuteSync(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mTexts: TAtlasNamedRefactoringTexts;
begin
  mTexts.Title := TAtlasTextId.EnumTablesSyncTitle;
  mTexts.Prompt := TAtlasTextId.EnumTablesSyncTitle;
  mTexts.Failed := TAtlasTextId.EnumTablesSyncFailed;
  mTexts.Nothing := TAtlasTextId.EnumTablesSyncNothing;
  mTexts.PreviewHint := TAtlasTextId.EnumTablesPreviewHint;
  mTexts.Apply := TAtlasTextId.EnumTablesSyncApply;
  mTexts.Done := TAtlasTextId.EnumTablesSyncDone;
  mTexts.Warning := TAtlasTextId.EnumTablesWarning;
  TAtlasIdeNamedRefactoring.ExecuteWithoutName(ASession, AArgumentsJson, cSyncApplyCommand, mTexts, APolicy,
    AMessage);
end;

end.
