unit Atlas.Common.Lsp.SyntaxDiagnostics;

// Meldet Syntaxfehler des Parsers als textDocument/publishDiagnostics.
// Syntaxfehler, Sprachmerkmale und Treffer der Prüfregeln kommen je Dokument vom Host (Providers.Rules,
// ILspRuleDiagnostics); ohne ihn bleiben inaktive Bereiche, uses und Compilermeldungen.
// Nach didOpen und didChange wird das Dokument nach einer kurzen Verzögerung
// geparst (Debouncing beim Tippen); bei didClose werden die Meldungen gelöscht.
// Jede Meldung trägt Zeile, Spalte und Endposition in UTF-16.
// Sind die Symbole des Projekts bekannt (Providers.Defines), kommen inaktive
// {$IFDEF}-Bereiche als Hinweise mit dem Tag Unnecessary dazu; der Editor
// blendet sie ab. Ohne Projekt wird nichts abgeblendet, weil die aktiven
// Symbole dann nicht bekannt sind. Jeder Bereich nennt die Bedingung seines
// Zweigs und, mit Providers.BuildTarget, Zielplattform und Konfiguration (#615):
// „Inaktiv: Bedingung WIN64 nicht erfüllt (Zielplattform Win32 · Debug)“,
// dieselben Angaben einzeln in data.inactive.
// Ist die Delphi-Version bekannt (Providers.Version), werden Sprachmerkmale,
// die diese Version noch nicht kennt, als Warnung gemeldet.
// Meldungen des letzten Compilerlaufs (Providers.CompilerMessages, #40) kommen
// mit der Quelle "dcc" dazu, auch für Dateien, die nicht geöffnet sind.
// Include-Dateien (#264) sucht der Präprozessor über den Include-Resolver des
// gemeinsamen Baums (TSyntaxTreeCache.SetIncludeProvider, #860); deren
// $DEFINE wählen die Zweige. Baum, Syntaxfehler, Abblenden und Include-Befunde
// kommen aus demselben Präprozessor-Lauf je Dokumentversion.
// Ein Include-Zyklus ist eine Warnung, eine nicht gefundene Datei ein Hinweis.
// Mit Providers.UsesContext (#621) kommen ungenutzte uses-Einträge als Hinweise mit
// dem Tag Unnecessary dazu („Aus Vcl.Grids wird nichts verwendet“), dazu ohne
// Tag die, die wegen initialization oder "usesKeep" bleiben, und interface-
// Einträge, die nur die implementation braucht; Unit und Zustand stehen in
// data.uses. Inaktive Zweige zählen nicht. Bei Syntaxfehlern fehlen sie.
// Die Dienste (TSyntaxDiagnosticsProviders) übergibt der Konstruktor; danach
// ändern sie sich nicht, die Prüfung im Hintergrund liest sie ohne Sperre.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Lsp.Internals.Debouncer,
  Atlas.Common.Lsp.DiagnosticItems,
  Atlas.Common.Editing.Contract;

type
  /// <summary>Symbole für das Dokument AUri; False, wenn kein Projekt sie festlegt.
  /// Wird im Hintergrund-Thread aufgerufen.</summary>
  TDefinesProvider = reference to function(const AUri: string; out ADefines: TArray<string>): Boolean;
  /// <summary>Eingestellte Delphi-Version für AUri; '' = unbekannt. Hintergrund-Thread.</summary>
  TDelphiVersionProvider = reference to function(const AUri: string): string;
  /// <summary>Gewählte Zielplattform und Konfiguration für AUri (#615); False = unbekannt.
  /// Hintergrund-Thread.</summary>
  TBuildTargetProvider = reference to function(const AUri: string; out APlatform, AConfig: string): Boolean;

  /// <summary>Meldungen des letzten Compilerlaufs zur Datei AFileName. Hintergrund-Thread.</summary>
  TCompilerMessagesProvider = reference to function(const AFileName: string): TArray<TCompilerMessage>;
  /// <summary>Index und Einstellungen für die uses-Prüfung (#284, #621); False ohne Index.</summary>
  TUsesContextProvider = reference to function(const AUri: string; out AContext: TUsesContext): Boolean;

  /// <summary>Dienste der Prüfung; der Konstruktor übernimmt sie, danach ändern sie sich nicht mehr (#1109).
  /// nil = die Prüfung entfällt (keine Symbole, keine Regeln, keine Compilermeldungen, keine uses-Diagnosen).
  /// </summary>
  TSyntaxDiagnosticsProviders = record
    /// <summary>Symbole für das Abblenden inaktiver Bereiche.</summary>
    Defines: TDefinesProvider;
    Version: TDelphiVersionProvider;
    /// <summary>Zielplattform und Konfiguration für den Hinweis inaktiver Bereiche (#615).</summary>
    BuildTarget: TBuildTargetProvider;
    /// <summary>Prüfregeln je Dokument (Host); ohne gibt es keine Treffer, auch keine Syntaxfehler.</summary>
    Rules: ILspRuleDiagnostics;
    /// <summary>Meldungen des letzten Compilerlaufs.</summary>
    CompilerMessages: TCompilerMessagesProvider;
    /// <summary>Index und usesKeep für ungenutzte uses (#621).</summary>
    UsesContext: TUsesContextProvider;
    // Die Dienste für AUri bzw. AFileName; ohne Dienst leer bzw. False.
    function CurrentDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
    function CurrentVersion(const AUri: string): string;
    function CurrentTarget(const AUri: string; out APlatform, AConfig: string): Boolean;
    function CurrentRules(const AUri: string; const ACancelled: TRuleCancelled): ILspDocumentRules;
    function CurrentCompilerMessages(const AFileName: string): TArray<TCompilerMessage>;
    function CurrentUses(const AUri: string; out AContext: TUsesContext): Boolean;
  end;

  /// <summary>Was BuildParams außer dem Dokument braucht.</summary>
  TSyntaxDiagnosticsInput = record
    /// <summary>Inaktive Bereiche mit Bedingung als Hinweise (Tag Unnecessary).</summary>
    Inactive: TArray<TLspInactiveRegion>;
    /// <summary>Sprachmerkmale, die diese Version nicht kennt, werden gemeldet; '' = unbekannt.</summary>
    DelphiVersion: string;
    /// <summary>Prüfregeln des Dokuments; nil = keine Treffer.</summary>
    Rules: ILspDocumentRules;
    /// <summary>Gewählte Zielplattform und Konfiguration (#615); '' = unbekannt.</summary>
    Platform: string;
    Config: string;
    /// <summary>Syntaxfehler nur aus aktiven Zweigen unter diesen Symbolen (leer = Vordefinitionen).</summary>
    Defines: TArray<string>;
  end;

  TLspSyntaxDiagnostics = class
  public const
    /// <summary>Verzögerung nach dem letzten Tastendruck; mit Parsen bleibt es unter 200 ms.</summary>
    cDefaultDelayMs = 100;
    /// <summary>Bündelt RefreshLater: In einer Projektgruppe melden sich viele Indexstufen kurz
    /// hintereinander, und jede Neuprüfung holt alle offenen Dokumente neu (#647).</summary>
    cRefreshDelayMs = 2000;
    cSource = TLspDiagnosticItems.cSource;
  private
    FStore: IDocumentStore;
    FTransport: IJsonRpcTransport;
    FDebouncer: TDebouncer;
    FRefreshDebouncer: TDebouncer;
    /// <summary>Hält Prüfen und Senden zusammen, damit nach dem Schließen nichts Veraltetes mehr kommt.</summary>
    FSendLock: TObject;
    FProviders: TSyntaxDiagnosticsProviders;
    FPullMode: Boolean;
    FOnPullChanged: TProc;
    FOnPullFilesChanged: TProc<TArray<string>>;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    procedure ScheduleParse(const ADocument: ITextDocument);
    procedure Publish(const ADocument: ITextDocument);
    function IsCurrent(const ADocument: ITextDocument): Boolean;
    function GetOnError: TProc<Exception>;
    procedure SetOnError(const AValue: TProc<Exception>);
    /// <summary>Auffällige uses (#621) als Darstellung der Regeln unused-uses (#1135) und
    /// uses-only-in-implementation (#1136) in AItems.</summary>
    procedure AddUnusedUses(AItems: TJSONArray; const ADocument: ITextDocument; const AInput: TSyntaxDiagnosticsInput);
  public
    /// <summary>Bei ADelayMs = 0 wird sofort im Thread der Nachrichtenschleife geparst.</summary>
    constructor Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const AProviders: TSyntaxDiagnosticsProviders; ADelayMs: Cardinal); overload;
    /// <summary>Mit DefaultDelayMs.</summary>
    constructor Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const AProviders: TSyntaxDiagnosticsProviders); overload;
    destructor Destroy; override;
    /// <summary>Meldet sich am Dokumentspeicher an.</summary>
    procedure Attach;
    /// <summary>Parameter für publishDiagnostics mit inaktiven Bereichen als Hinweise (Tag Unnecessary), und aus
    /// ARules (nil = keine) Syntaxfehlern, Sprachmerkmalen, die ADelphiVersion nicht kennt ('' = alle bekannt), und
    /// den Treffern der Prüfregeln. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildParams(const ADocument: ITextDocument; const AInactive: TArray<TTextRange>;
      const ADelphiVersion: string; const ARules: ILspDocumentRules): TJSONObject; overload; static;
    /// <summary>Wie oben mit allen Angaben aus AInput.</summary>
    class function BuildParams(const ADocument: ITextDocument; const AInput: TSyntaxDiagnosticsInput)
      : TJSONObject; overload; static;
    /// <summary>Parameter für publishDiagnostics zu ADocument (Pascal oder Formular) mit Regeln
    /// und Compilermeldungen. Threadsicher; der Aufrufer übernimmt das Objekt.</summary>
    function Compute(const ADocument: ITextDocument): TJSONObject; overload;
    /// <summary>Wie Compute; fragt ACancelled vor jeder Prüfregel und bricht dann mit
    /// ERuleCheckCancelled ab.</summary>
    function Compute(const ADocument: ITextDocument; const ACancelled: TRuleCancelled): TJSONObject; overload;
    /// <summary>Prüft alle geöffneten Dokumente neu, z. B. nach geänderten Symbolen.</summary>
    procedure Refresh;
    /// <summary>Wie Refresh, aber gebündelt: Mehrere Aufrufe innerhalb von RefreshDelayMs
    /// lösen eine Neuprüfung aus. Bei ADelayMs = 0 im Konstruktor sofort.</summary>
    procedure RefreshLater;
    /// <summary>Meldet die Compilermeldungen zu AFileNames neu: geöffnete Dokumente
    /// werden neu geprüft, für andere gehen nur die Compilermeldungen hinaus.</summary>
    procedure RefreshFiles(const AFileNames: TArray<string>);
    /// <summary>Wird bei Ausnahmen beim Parsen im Hintergrund aufgerufen.</summary>
    property OnError: TProc<Exception> read GetOnError write SetOnError;
    /// <summary>Der Client holt Diagnosen selbst ab (#82): nichts senden, bei Änderungen
    /// stattdessen OnPullChanged aufrufen.</summary>
    property PullMode: Boolean read FPullMode write FPullMode;
    property OnPullChanged: TProc read FOnPullChanged write FOnPullChanged;
    /// <summary>Im Pull-Modus statt OnPullChanged bei RefreshFiles: nur diese Dateien sind betroffen (#1247).
    /// </summary>
    property OnPullFilesChanged: TProc<TArray<string>> read FOnPullFilesChanged write FOnPullFilesChanged;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.Math,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Findings.Suppressions,
  Atlas.Common.Semantics.UsesActions;

// Übernimmt AParams.
procedure Send(const ATransport: IJsonRpcTransport; AParams: TJSONObject);
var
  mNotification: TJSONObject;
begin
  mNotification := TJsonRpcMessages.Notification(TLspTextDocumentMethod.cPublishDiagnostics, AParams);
  try
    ATransport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

/// <summary>Parameter mit leerer Liste, z. B. nach dem Schließen.</summary>
function EmptyParams(const AUri: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  Result.AddPair('diagnostics', TJSONArray.Create);
end;

/// <summary>Inaktive Bereiche aus demselben Lauf wie der Baum in BuildParams (#860): kein zweiter
/// Präprozessor-Lauf. AIssues: Befunde des Präprozessors (Include-Dateien).</summary>
function InactiveOf(const ADocument: ITextDocument; const ADefines: TArray<string>;
  out AIssues: TArray<TPreprocessorIssue>): TArray<TLspInactiveRegion>;
var
  mShared: ISharedSyntaxTree;
begin
  mShared := TSyntaxTreeCache.GetFor(ADocument, ADefines);
  Result := TLspInactiveRegions.Regions(mShared.Processed, mShared.IncludesResolved, AIssues);
end;

/// <summary>Compilermeldungen zu Zeilen, die das Dokument hat, mit Zeilentext.</summary>
procedure AddCompilerMessages(AItems: TJSONArray; const ADocument: ITextDocument;
  const AMessages: TArray<TCompilerMessage>);
var
  mMessage: TCompilerMessage;
begin
  for mMessage in AMessages do
  begin
    if mMessage.Line < ADocument.LineCount then
    begin
      AItems.AddElement(TLspDiagnosticItems.CompilerMessageToJson(mMessage,
        ADocument.LineText(Max(mMessage.Line, 0)), True));
    end;
  end;
end;

/// <summary>Treffer der Prüfregeln ohne die bekannten der Baseline (#97). Abbruch (ERuleCheckCancelled):
/// Die bis dahin gesammelten Meldungen in AItems freigeben.</summary>
procedure AddRuleFindings(AItems: TJSONArray; const ADocument: ITextDocument; const ADefines: TArray<string>;
  const ARules: ILspDocumentRules);
var
  mFindings: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
begin
  try
    mFindings := ARules.RuleFindings(ADocument, ADefines);
  except
    AItems.Free;
    raise;
  end;
  for mFinding in mFindings do
  begin
    AItems.AddElement(TLspDiagnosticItems.FindingToJson(mFinding));
  end;
end;

{ TSyntaxDiagnosticsProviders }

function TSyntaxDiagnosticsProviders.CurrentDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  mProvider: TDefinesProvider;
begin
  mProvider := Defines;
  ADefines := nil;
  Result := Assigned(mProvider) and mProvider(AUri, ADefines);
end;

function TSyntaxDiagnosticsProviders.CurrentVersion(const AUri: string): string;
var
  mProvider: TDelphiVersionProvider;
begin
  mProvider := Version;
  if Assigned(mProvider) then
  begin
    Result := mProvider(AUri);
  end
  else
  begin
    Result := '';
  end;
end;

function TSyntaxDiagnosticsProviders.CurrentTarget(const AUri: string; out APlatform, AConfig: string): Boolean;
var
  mProvider: TBuildTargetProvider;
begin
  mProvider := BuildTarget;
  APlatform := '';
  AConfig := '';
  Result := Assigned(mProvider) and mProvider(AUri, APlatform, AConfig);
  if not Result then
  begin
    APlatform := '';
    AConfig := '';
  end;
end;

function TSyntaxDiagnosticsProviders.CurrentRules(const AUri: string;
  const ACancelled: TRuleCancelled): ILspDocumentRules;
var
  mRules: ILspRuleDiagnostics;
begin
  mRules := Rules;
  Result := nil;
  if mRules <> nil then
  begin
    Result := mRules.ForDocument(AUri, ACancelled);
  end;
end;

function TSyntaxDiagnosticsProviders.CurrentCompilerMessages(const AFileName: string): TArray<TCompilerMessage>;
var
  mProvider: TCompilerMessagesProvider;
begin
  mProvider := CompilerMessages;
  if Assigned(mProvider) then
  begin
    Result := mProvider(AFileName);
  end
  else
  begin
    Result := nil;
  end;
end;

function TSyntaxDiagnosticsProviders.CurrentUses(const AUri: string; out AContext: TUsesContext): Boolean;
var
  mProvider: TUsesContextProvider;
begin
  mProvider := UsesContext;
  AContext := Default(TUsesContext);
  Result := Assigned(mProvider) and mProvider(AUri, AContext);
end;

{ TLspSyntaxDiagnostics }

constructor TLspSyntaxDiagnostics.Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  const AProviders: TSyntaxDiagnosticsProviders; ADelayMs: Cardinal);
begin
  inherited Create;
  FStore := AStore;
  FTransport := ATransport;
  FProviders := AProviders;
  FSendLock := TObject.Create;
  FDebouncer := TDebouncer.Create(ADelayMs);
  if ADelayMs = 0 then
  begin
    FRefreshDebouncer := TDebouncer.Create(0);
  end
  else
  begin
    FRefreshDebouncer := TDebouncer.Create(cRefreshDelayMs);
  end;
end;

constructor TLspSyntaxDiagnostics.Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  const AProviders: TSyntaxDiagnosticsProviders);
begin
  Create(AStore, ATransport, AProviders, cDefaultDelayMs);
end;

destructor TLspSyntaxDiagnostics.Destroy;
begin
  // Zuerst: Eine gebündelte Neuprüfung plant über FDebouncer neu.
  FRefreshDebouncer.Free;
  FDebouncer.Free;
  FSendLock.Free;
  inherited;
end;

function TLspSyntaxDiagnostics.GetOnError: TProc<Exception>;
begin
  Result := FDebouncer.OnError;
end;

procedure TLspSyntaxDiagnostics.SetOnError(const AValue: TProc<Exception>);
begin
  FDebouncer.OnError := AValue;
  FRefreshDebouncer.OnError := AValue;
end;

procedure TLspSyntaxDiagnostics.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
begin
  // JSON-Dateien wie atlas.json prüft TLspConfiguration.
  // Im Pull-Modus fragt der Client nach Änderungen selbst nach.
  if SameText(ExtractFileExt(ADocument.Uri), '.json') or FPullMode then
  begin
    Exit;
  end;
  case AKind of
    TDocumentEventKind.Opened, TDocumentEventKind.Changed:
      ScheduleParse(ADocument);
    TDocumentEventKind.Closed:
      begin
        TMonitor.Enter(FSendLock);
        try
          FDebouncer.Cancel(ADocument.Uri);
          Send(FTransport, EmptyParams(ADocument.Uri));
        finally
          TMonitor.Exit(FSendLock);
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TLspSyntaxDiagnostics.ScheduleParse(const ADocument: ITextDocument);
begin
  // Eigene Methode, damit die anonyme Methode genau diese Momentaufnahme festhält.
  FDebouncer.Schedule(ADocument.Uri,
    procedure
    begin
      Publish(ADocument);
    end);
end;

procedure TLspSyntaxDiagnostics.Publish(const ADocument: ITextDocument);
var
  mParams: TJSONObject;
begin
  // Überholte Stände nicht zu Ende prüfen: Der neuere meldet selbst.
  try
    mParams := Compute(ADocument,
      function: Boolean
      begin
        Result := not IsCurrent(ADocument);
      end);
  except
    on ERuleCheckCancelled do
      Exit;
  end;
  TMonitor.Enter(FSendLock);
  try
    // Inzwischen geändert oder geschlossen: Der neuere Stand meldet selbst.
    if IsCurrent(ADocument) then
    begin
      Send(FTransport, mParams);
    end
    else
    begin
      mParams.Free;
    end;
  finally
    TMonitor.Exit(FSendLock);
  end;
end;

function TLspSyntaxDiagnostics.IsCurrent(const ADocument: ITextDocument): Boolean;
var
  mCurrent: ITextDocument;
begin
  Result := FStore.TryGet(ADocument.Uri, mCurrent) and (mCurrent.Version = ADocument.Version);
end;

procedure TLspSyntaxDiagnostics.Attach;
begin
  FStore.Subscribe(HandleDocumentEvent);
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TTextRange>; const ADelphiVersion: string; const ARules: ILspDocumentRules): TJSONObject;
var
  mInput: TSyntaxDiagnosticsInput;
begin
  mInput := Default(TSyntaxDiagnosticsInput);
  mInput.Inactive := TLspInactiveRegions.FromRanges(AInactive);
  mInput.DelphiVersion := ADelphiVersion;
  mInput.Rules := ARules;
  Result := BuildParams(ADocument, mInput);
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInput: TSyntaxDiagnosticsInput): TJSONObject;
var
  mFinding: TRuleFinding;
  mRegion: TLspInactiveRegion;
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  if AInput.Rules <> nil then
  begin
    // Baum nur aus den aktiven Zweigen unter AInput.Defines (#845, gemeinsamer Zwischenspeicher): Inaktive Zweige
    // erzeugen keine Syntaxfehler, und Regeln sehen den Code, den der Compiler übersetzt.
    // Syntaxfehler als Treffer der Regel "syntax" (#1022): Schweregrad und Gruppe aus der Konfiguration,
    // Code und Korrektur wie bei den übrigen Regeln. Ohne Konfiguration gilt Default = Fehler.
    for mFinding in AInput.Rules.SyntaxFindings(ADocument, AInput.Defines) do
    begin
      mItems.AddElement(TLspDiagnosticItems.FindingToJson(mFinding));
    end;
    // Merkmale in inaktiven Zweigen ({$IF CompilerVersion >= …}) sind gewollt (#109). Als Treffer der Regel
    // language-feature wie im Linter und in den MCP-Werkzeugen (#1126); DelphiVersion ist der Sprachstand.
    for mFinding in AInput.Rules.LanguageFeatureFindings(ADocument, AInput.Defines, AInput.DelphiVersion,
      TLspInactiveRegions.RangesOf(AInput.Inactive)) do
    begin
      mItems.AddElement(TLspDiagnosticItems.FindingToJson(mFinding));
    end;
    AddRuleFindings(mItems, ADocument, AInput.Defines, AInput.Rules);
  end;
  for mRegion in AInput.Inactive do
  begin
    mItems.AddElement(TLspDiagnosticItems.InactiveToJson(mRegion, AInput.Platform, AInput.Config));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('uri', ADocument.Uri);
  Result.AddPair('version', TJSONNumber.Create(ADocument.Version));
  Result.AddPair('diagnostics', mItems);
end;

procedure TLspSyntaxDiagnostics.AddUnusedUses(AItems: TJSONArray; const ADocument: ITextDocument;
  const AInput: TSyntaxDiagnosticsInput);
var
  mUses: TUsesContext;
  mTree: ISharedSyntaxTree;
  mSuppressions: TSuppressions;
  mShown: TUsesEntryStates;
begin
  // Das Abblenden ist die Darstellung von unused-uses im Editor (#1135), der Hinweis „nur in der implementation
  // gebraucht“ die von uses-only-in-implementation (#1136): Mit der Regel aus, für ausgeschlossene Dateien und
  // unter lsp-ignore bleiben sie weg wie ihre Treffer. Ohne Regelkontext gelten die Vorgaben (an).
  mShown := [TUsesEntryState.Unused, TUsesEntryState.KeptForInitialization, TUsesEntryState.KeptByAllowlist,
    TUsesEntryState.OnlyImplementation];
  if (AInput.Rules <> nil) and not AInput.Rules.UnusedUsesShown then
  begin
    mShown := mShown - [TUsesEntryState.Unused, TUsesEntryState.KeptForInitialization,
      TUsesEntryState.KeptByAllowlist];
  end;
  if (AInput.Rules <> nil) and not AInput.Rules.OnlyImplementationShown then
  begin
    mShown := mShown - [TUsesEntryState.OnlyImplementation];
  end;
  if (mShown = []) or not FProviders.CurrentUses(ADocument.Uri, mUses) then
  begin
    Exit;
  end;
  // Nicht bei Syntaxfehlern, dann fehlen Bezeichner. Entscheidend ist der Baum, nicht die Meldungen: Auch mit
  // abgeschalteter Regel "syntax" (#1022) wäre die Auswertung unsicher.
  mTree := TSyntaxTreeCache.GetFor(ADocument, AInput.Defines);
  if Length(mTree.Tree.Diagnostics) > 0 then
  begin
    Exit;
  end;
  mSuppressions := TSuppressions.Create(mTree.Tree.Tokens);
  try
    TLspDiagnosticItems.AddUses(AItems, ADocument.Text, TLspInactiveRegions.RangesOf(AInput.Inactive), mUses,
      mSuppressions, mShown);
  finally
    mSuppressions.Free;
  end;
end;

function TLspSyntaxDiagnostics.Compute(const ADocument: ITextDocument): TJSONObject;
begin
  Result := Compute(ADocument, nil);
end;

function TLspSyntaxDiagnostics.Compute(const ADocument: ITextDocument; const ACancelled: TRuleCancelled): TJSONObject;
var
  mInput: TSyntaxDiagnosticsInput;
  mIssues: TArray<TPreprocessorIssue>;
  mIssue: TPreprocessorIssue;
  mItems: TJSONArray;
begin
  if TLspDiagnosticItems.TryFormParams(ADocument.Uri, ADocument.Text, Result) then
  begin
    Exit;
  end;
  mInput := Default(TSyntaxDiagnosticsInput);
  mIssues := nil;
  if FProviders.CurrentDefines(ADocument.Uri, mInput.Defines) then
  begin
    mInput.Inactive := InactiveOf(ADocument, mInput.Defines, mIssues);
  end;
  mInput.Rules := FProviders.CurrentRules(ADocument.Uri, ACancelled);
  mInput.DelphiVersion := FProviders.CurrentVersion(ADocument.Uri);
  FProviders.CurrentTarget(ADocument.Uri, mInput.Platform, mInput.Config);
  Result := BuildParams(ADocument, mInput);
  mItems := Result.GetValue('diagnostics') as TJSONArray;
  for mIssue in mIssues do
  begin
    mItems.AddElement(TLspDiagnosticItems.IssueToJson(mIssue));
  end;
  AddUnusedUses(mItems, ADocument, mInput);
  AddCompilerMessages(mItems, ADocument, FProviders.CurrentCompilerMessages(TDocumentUris.ToPath(ADocument.Uri)));
end;

procedure TLspSyntaxDiagnostics.Refresh;
var
  mDocument: ITextDocument;
begin
  if FPullMode then
  begin
    if Assigned(FOnPullChanged) then
    begin
      FOnPullChanged();
    end;
    Exit;
  end;
  for mDocument in FStore.Documents do
  begin
    if not SameText(ExtractFileExt(mDocument.Uri), '.json') then
    begin
      ScheduleParse(mDocument);
    end;
  end;
end;

procedure TLspSyntaxDiagnostics.RefreshLater;
begin
  FRefreshDebouncer.Schedule('refresh',
    procedure
    begin
      Refresh;
    end);
end;

procedure TLspSyntaxDiagnostics.RefreshFiles(const AFileNames: TArray<string>);
var
  mFileName, mUri: string;
  mDocument: ITextDocument;
  mItem: TCompilerMessage;
  mItems: TJSONArray;
  mParams: TJSONObject;
begin
  if FPullMode then
  begin
    if Assigned(FOnPullFilesChanged) then
    begin
      FOnPullFilesChanged(AFileNames);
    end
    else if Assigned(FOnPullChanged) then
    begin
      FOnPullChanged();
    end;
    Exit;
  end;
  for mFileName in AFileNames do
  begin
    mUri := TDocumentUris.FromPath(mFileName);
    if FStore.TryGet(mUri, mDocument) then
    begin
      ScheduleParse(mDocument);
      Continue;
    end;
    mItems := TJSONArray.Create;
    for mItem in FProviders.CurrentCompilerMessages(mFileName) do
    begin
      mItems.AddElement(TLspDiagnosticItems.CompilerMessageToJson(mItem, '', False));
    end;
    mParams := TJSONObject.Create;
    mParams.AddPair('uri', mUri);
    mParams.AddPair('diagnostics', mItems);
    TMonitor.Enter(FSendLock);
    try
      // Inzwischen geöffnet: Das Dokument meldet selbst, mit Zeilentext.
      if FStore.TryGet(mUri, mDocument) then
      begin
        mParams.Free;
        ScheduleParse(mDocument);
      end
      else
      begin
        Send(FTransport, mParams);
      end;
    finally
      TMonitor.Exit(FSendLock);
    end;
  end;
end;

end.
