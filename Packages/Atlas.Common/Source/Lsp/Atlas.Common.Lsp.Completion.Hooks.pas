unit Atlas.Common.Lsp.Completion.Hooks;

// Rückrufe und Schalter der Vervollständigung, die die Komposition setzt (Einstellungen je Dokument, Lesen von
// Dateien, Benachrichtigungen, Angebote aus anderen Teilen des Servers). Aus Atlas.Common.Lsp.Completion
// herausgelöst; die Fälle der Vervollständigung lesen sie über TCompletionAnswer.Hooks.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.ConditionalSymbols,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.IdeTypes,
  Atlas.Common.Lsp.Completion.Names,
  Atlas.Common.Lsp.Completion.Postfix;

type
  TPostfixOptionsFunc = reference to function(const AUri: string): TPostfixOptions;

  TCompletionMatchingFunc = reference to function(const AUri: string): TCompletionMatching;

  /// <summary>Einstellungen der Vervollständigung je Dokument (#466, #480).</summary>
  TCompletionSettingsFunc = reference to function(const AUri: string): TCompletionSettings;

  /// <summary>Sendet eine Benachrichtigung an den Client (z. B. $/progress); übernimmt AParams.</summary>
  TCompletionNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);

  /// <summary>Zeitmessung je Anfrage (#616), z. B. für ILogger.Debug.</summary>
  TCompletionLogProc = reference to procedure(const AText: string);

  /// <summary>Ist eine Funktion für das Dokument eingeschaltet (z. B. completeBlocks.docComment, #88)?</summary>
  TCompletionEnabledFunc = reference to function(const AUri: string): Boolean;
  /// <summary>„with auflösen“ über Strg+Leer auf with (#50): Änderungen für die with-Anweisung am Cursor; False
  /// ohne Angebot.</summary>
  TCompletionWithFunc = reference to function(ARequest: TCompletionRequest; out AEdits: TArray<TTextEdit>): Boolean;
  /// <summary>„Methode aus Aufruf anlegen“ (#472): Titel, Kopf und Änderungen für den Aufruf am Cursor; False ohne
  /// Angebot (bekannter Name, kein Aufruf, abgeschaltet).</summary>
  TCompletionCreateFunc = reference to function(ARequest: TCompletionRequest; out ATitle, ADetail: string;
    out AEdits: TArray<TTextEdit>): Boolean;

  /// <summary>Typen aus den Packages der IDE (atlas/ideTypes) für die Vervollständigung.</summary>
  TCompletionIdeTypesFunc = reference to function: TArray<TIdeTypeEntry>;

  /// <summary>Rückrufe und Schalter einer TLspCompletion. Die Felder setzt die Komposition vor der ersten Anfrage;
  /// Namensräume und eigene Postfix-Vorlagen können sich danach ändern und sind gesperrt.</summary>
  TCompletionHooks = class
  private
    FNamespaces: TArray<string>;
    // Eigene Postfix-Vorlagen (#188); unter FLock.
    FCustomPostfix: TArray<TPostfixTemplate>;
    FLock: TObject;
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie beim Laden
    /// eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    /// <summary>Liest Dateien für completionItem/resolve; ohne Zuweisung keine Details.</summary>
    ReadText: TCompletionReadText;
    /// <summary>Auswahl je Dokument; ohne Zuweisung unscharf.</summary>
    MatchingFor: TCompletionMatchingFunc;
    /// <summary>Abschnitt für Interface-Methoden (#466), Typumwandlung von Sender (#480); ohne Zuweisung die
    /// Standardwerte.</summary>
    SettingsFor: TCompletionSettingsFunc;
    /// <summary>Schnellbefehle nach "/" am Zeilenanfang (#293); ohne Zuweisung alle eingeschaltet.</summary>
    SlashCommandsFor: TSlashCommandsProvider;
    /// <summary>Regeln, die in einer Zeile treffen, für /ignore (#297); ohne Zuweisung der ganze Katalog.</summary>
    RuleIdsFor: TSlashRuleIdsFunc;
    /// <summary>Postfix-Vorlagen je Dokument (#188); ohne Zuweisung an und mit Inline-Variable.</summary>
    PostfixFor: TPostfixOptionsFunc;
    /// <summary>„with auflösen“ auf dem Wort with (#50); ohne Zuweisung kein Eintrag.</summary>
    WithFor: TCompletionWithFunc;
    /// <summary>„Methode aus Aufruf anlegen“ (#472); ohne Zuweisung kein Eintrag.</summary>
    CreateFor: TCompletionCreateFunc;
    /// <summary>Präfix der Namensvorschläge (#452); ohne gilt NamingPrefix über den Index der Anfrage.</summary>
    NamingFor: TCompletionNamingFunc;
    /// <summary>Anzeige von XMLDoc (#654) als data.atlas.xmlDoc; ohne Zuweisung fehlt das Feld.</summary>
    HintsFor: TDocHintsProvider;
    /// <summary>„Parameter abgleichen“ in ///-Blöcken (#88); ohne Zuweisung eingeschaltet.</summary>
    DocCommentsFor: TCompletionEnabledFunc;
    /// <summary>Bedingte Symbole in Direktiven und Schalter directives.completion (#102); ohne Zuweisung an,
    /// nur mit den Symbolen der Datei.</summary>
    SymbolsFor: TConditionalContextFunc;
    /// <summary>Typen aus den Packages der IDE, auch ohne Quelltext; ohne Zuweisung keine.</summary>
    IdeTypesFor: TCompletionIdeTypesFunc;
    /// <summary>Für Teilergebnisse über $/progress (#616); ohne Zuweisung kommt alles in der Antwort.</summary>
    Notify: TCompletionNotifyProc;
    /// <summary>Zeiten je Anfrage (#616); ohne Zuweisung keine Messung.</summary>
    Log: TCompletionLogProc;
    /// <summary>Client versteht Snippets (#51); sonst gehen Vorlagen als Klartext. Aus initialize.</summary>
    SnippetSupport: Boolean;
    /// <summary>Client zeigt Markdown in documentation (#31); sonst Klartext. Aus initialize.</summary>
    DocumentationMarkdown: Boolean;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Eigene Postfix-Vorlagen vom Plugin (#188) ersetzen.</summary>
    procedure SetCustomPostfix(const ATemplates: TArray<TPostfixTemplate>);
    /// <summary>Die eigenen Postfix-Vorlagen vom Plugin (#188).</summary>
    function CustomPostfix: TArray<TPostfixTemplate>;
    /// <summary>Einstellungen für AUri über SettingsFor, ohne Zuweisung die Standardwerte.</summary>
    function SettingsOf(const AUri: string): TCompletionSettings;
    /// <summary>Auswahl für AUri über MatchingFor, ohne Zuweisung unscharf.</summary>
    function MatchingOf(const AUri: string): TCompletionMatching;
    /// <summary>Postfix-Optionen für AUri über PostfixFor (ohne Zuweisung die Vorgabe), mit Snippets und den
    /// eigenen Vorlagen.</summary>
    function PostfixOf(const AUri: string): TPostfixOptions;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces;

{ TCompletionHooks }

constructor TCompletionHooks.Create;
begin
  inherited Create;
  FLock := TObject.Create;
end;

destructor TCompletionHooks.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TCompletionHooks.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TCompletionHooks.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

procedure TCompletionHooks.SetCustomPostfix(const ATemplates: TArray<TPostfixTemplate>);
begin
  System.TMonitor.Enter(FLock);
  try
    FCustomPostfix := ATemplates;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCompletionHooks.CustomPostfix: TArray<TPostfixTemplate>;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FCustomPostfix;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCompletionHooks.SettingsOf(const AUri: string): TCompletionSettings;
begin
  Result := TCompletionSettings.Default;
  if Assigned(SettingsFor) then
  begin
    Result := SettingsFor(AUri);
  end;
end;

function TCompletionHooks.MatchingOf(const AUri: string): TCompletionMatching;
begin
  Result := TCompletionMatching.Fuzzy;
  if Assigned(MatchingFor) then
  begin
    Result := MatchingFor(AUri);
  end;
end;

function TCompletionHooks.PostfixOf(const AUri: string): TPostfixOptions;
begin
  Result := TPostfixOptions.Default;
  if Assigned(PostfixFor) then
  begin
    Result := PostfixFor(AUri);
  end;
  Result.Snippet := SnippetSupport;
  Result.Custom := CustomPostfix;
end;

end.
