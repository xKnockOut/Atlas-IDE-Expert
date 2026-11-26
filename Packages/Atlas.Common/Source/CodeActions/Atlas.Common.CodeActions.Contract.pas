unit Atlas.Common.CodeActions.Contract;

// Contract des Platform-Features CodeActions: Code-Aktionen als reine Werte (Titel, Art, Edits, Befehl) und die
// Arten und Client-Befehle, die Code-Aktionen tragen. Refactorings und Prüfregeln erzeugen sie, Sprachserver, MCP
// und Schnellbefehle reichen sie weiter; keiner von ihnen muss dafür die Erzeuger einbinden.

interface

uses
  Atlas.Common.Documents.Contract;

const
  cQuickFixKind = 'quickfix';
  cRewriteKind = 'refactor.rewrite';
  /// <summary>Art der Extrahieren-Aktionen.</summary>
  cExtractKind = 'refactor.extract';
  // Für editor.codeActionsOnSave (#182).
  cOrganizeImportsKind = 'source.organizeImports';
  cFixAllKind = 'source.fixAll';
  /// <summary>Ungenutzte uses entfernen (#284).</summary>
  cRemoveUnusedKind = 'source.removeUnusedImports';
  /// <summary>Client-Befehl, der das erste Argument in die Zwischenablage legt (#312).</summary>
  cCopyTextCommand = 'atlas.copyText';
  /// <summary>Client-Befehl, der den Cursor im Dokument der Aktion auf Zeile (erstes Argument) und Zeichen
  /// (zweites Argument, beide 0-basiert) setzt (#915).</summary>
  cGoToPositionCommand = 'atlas.goToPosition';
  /// <summary>Wie GoToPositionCommand; danach öffnet der Client den Parameter-Hint an der Stelle (#1007).</summary>
  cShowSignatureHelpCommand = 'atlas.showSignatureHelp';
  /// <summary>Client-Befehl, der die Unit-Beziehungen (#593) der Datei der Aktion zeigt, z. B. „Graph zeigen“ an
  /// einem Unit-Zyklus (#896).</summary>
  cShowUnitRelationsCommand = 'atlas.showUnitRelations';
  /// <summary>Kennungen der uses-Aktionen für den Hover des Plugins (#621), in data.tag.</summary>
  cUsesRemoveTag = 'uses.remove';
  cUsesRemoveAllTag = 'uses.removeAll';
  cUsesMoveTag = 'uses.move';
  /// <summary>Fehlende Methodenrümpfe (#42) und fehlende case-Zweige (#50); „Anweisung vervollständigen“ des
  /// Plugins sucht sie (#697).</summary>
  cClassBodiesTag = 'class.bodies';
  cCaseCompleteTag = 'case.complete';
  /// <summary>Schnellkorrektur eines Regeltreffers und „für diese Zeile/Datei unterdrücken“ (#909); das Fenster
  /// „Atlas-Prüfung“ und der Befund-Hover wählen damit die Aktion zum Treffer (Regel in diagnostics[0].code).
  /// </summary>
  cRuleFixTag = 'rule.fix';
  cRuleSuppressLineTag = 'rule.suppressLine';
  cRuleSuppressFileTag = 'rule.suppressFile';

type
  /// <summary>Edits in einer anderen Datei als dem Dokument der Aktion, z. B. der Formulardatei (#309).</summary>
  TFileTextEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  /// <summary>Teil einer Code-Aktion, den der Client abwählen kann (gleiche Stellen, #2054).</summary>
  TCodeActionChoice = record
    Title: string;
    /// <summary>Stelle im Dokument, die der Teil ändert.</summary>
    Range: TTextRange;
    class function Create(const ATitle: string; const ARange: TTextRange): TCodeActionChoice; static;
  end;

  TCodeAction = record
    Title: string;
    Kind: string;
    /// <summary>Edits im Dokument der Aktion.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Edits in weiteren Dateien (#309); nil = keine.</summary>
    FileEdits: TArray<TFileTextEdits>;
    IsPreferred: Boolean;
    /// <summary>Regelkennung des behobenen Treffers, sonst ''.</summary>
    RuleId: string;
    /// <summary>Bereich des behobenen Treffers, wenn RuleId gesetzt ist.</summary>
    DiagnosticRange: TTextRange;
    /// <summary>Befehl statt oder nach den Edits, z. B. für Dateiumwandlungen; '' ohne.</summary>
    Command: string;
    CommandArguments: TArray<string>;
    /// <summary>Kennung für Clients, die eine bestimmte Aktion suchen (UsesRemoveTag, #621); '' ohne.</summary>
    Tag: string;
    /// <summary>Text, den der Client vor dem Übernehmen als Vorschau zeigt (neue Signatur, #663); '' ohne.</summary>
    Preview: string;
    /// <summary>Grund, warum die Aktion hier nicht geht (Hinweis statt Aktion, #663); '' wenn sie geht.</summary>
    Disabled: string;
    /// <summary>Abwählbare Teile (#2054); nil ohne.</summary>
    Choices: TArray<TCodeActionChoice>;
    /// <summary>Je Edit in Edits die Indizes in Choices, die alle gewählt sein müssen; fehlt der Eintrag oder ist
    /// er leer, gilt der Edit immer.</summary>
    EditChoices: TArray<TArray<Integer>>;
  end;

implementation

{ TCodeActionChoice }

class function TCodeActionChoice.Create(const ATitle: string; const ARange: TTextRange): TCodeActionChoice;
begin
  Result.Title := ATitle;
  Result.Range := ARange;
end;

end.
