unit Atlas.Common.Lsp.SyntaxDiagnostics;

// Meldet Syntaxfehler des Parsers als textDocument/publishDiagnostics.
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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Baseline,
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
  /// <summary>Gewählte Zielplattform und Konfiguration für AUri (#615); False = unbekannt. Hintergrund-Thread.</summary>
  TBuildTargetProvider = reference to function(const AUri: string; out APlatform, AConfig: string): Boolean;

  /// <summary>Was die Prüfregeln für ein Dokument brauchen.</summary>
  TRuleCheckContext = record
    Rules: TArray<IRule>;
    Settings: TServerSettings;
    /// <summary>Pfad relativ zum Ordner der Konfiguration, '' wenn unbekannt.</summary>
    RelativePath: string;
    /// <summary>Bekannte Treffer, die ausgeblendet werden (#97); nil = keine Baseline.</summary>
    Baseline: IRuleBaseline;
    /// <summary>Index, Nachladen, Unit-Suche, Packages, Projekte der Gruppe und Namenskonvention (#1112);
    /// derselbe Weg wie bei MCP und Linter.</summary>
    Services: TRuleServices;
    /// <summary>Formulardatei neben der Unit (#123); '' ohne.</summary>
    FormText: string;
    /// <summary>Pfad der Formulardatei (#309); '' ohne.</summary>
    FormFile: string;
    /// <summary>Dateien neben der Unit, z. B. .dcr (#114); nil = keine.</summary>
    ReadFile: TRuleFileReader;
    /// <summary>Gibt es eine Datei neben der Unit (#1379)? nil = unbekannt.</summary>
    FileExists: TRuleFileExists;
    /// <summary>Absoluter Pfad der Datei (#46).</summary>
    FileName: string;
    /// <summary>Anwendungsart des Projekts der Datei (#926); Unknown ohne Projekt.</summary>
    Application: TRuleApplicationKind;
    /// <summary>Name des Projekts ohne Endung (#943); '' ohne Projekt.</summary>
    ProjectName: string;
    /// <summary>Automatisch erzeugte Formulare in der Reihenfolge der .dpr (#956); nil ohne Projekt.</summary>
    AutoCreateForms: TArray<string>;
    /// <summary>Pfad der .dpr zu AutoCreateForms (#1055); '' ohne Projekt.</summary>
    ProjectMainSource: string;
    /// <summary>Abbruch zwischen den Prüfregeln; nil = nie. Setzt Compute.</summary>
    Cancelled: TRuleCancelled;
    /// <summary>Prüfung für den Editor (TRuleContext.Live, #896); die Komposition setzt es.</summary>
    Live: Boolean;
  end;

  /// <summary>Regeln und Einstellungen für AUri; False = keine Regeln prüfen. Hintergrund-Thread.</summary>
  TRuleContextProvider = reference to function(const AUri: string; out AContext: TRuleCheckContext): Boolean;
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
    /// <summary>Regeln und Einstellungen; ohne laufen keine Prüfregeln.</summary>
    Rules: TRuleContextProvider;
    /// <summary>Meldungen des letzten Compilerlaufs.</summary>
    CompilerMessages: TCompilerMessagesProvider;
    /// <summary>Index und usesKeep für ungenutzte uses (#621).</summary>
    UsesContext: TUsesContextProvider;
  end;

  /// <summary>Was BuildParams außer dem Dokument braucht.</summary>
  TSyntaxDiagnosticsInput = record
    /// <summary>Inaktive Bereiche mit Bedingung als Hinweise (Tag Unnecessary).</summary>
    Inactive: TArray<TLspInactiveRegion>;
    /// <summary>Sprachmerkmale, die diese Version nicht kennt, werden gemeldet; '' = unbekannt.</summary>
    DelphiVersion: string;
    /// <summary>Prüfregeln; ohne Regeln nur Syntax und Sprachmerkmale.</summary>
    Rules: TRuleCheckContext;
    /// <summary>Gewählte Zielplattform und Konfiguration (#615); '' = unbekannt.</summary>
    Platform: string;
    Config: string;
    /// <summary>Syntaxfehler nur aus aktiven Zweigen unter diesen Symbolen (leer = Vordefinitionen).</summary>
    Defines: TArray<string>;
  end;

  TLspSyntaxDiagnostics = class
  public const
    /// <summary>Verzögerung nach dem letzten Tastendruck; mit Parsen bleibt es unter 200 ms.</summary>
    DefaultDelayMs = 100;
    /// <summary>Bündelt RefreshLater: In einer Projektgruppe melden sich viele Indexstufen kurz
    /// hintereinander, und jede Neuprüfung holt alle offenen Dokumente neu (#647).</summary>
    RefreshDelayMs = 2000;
    Source = TLspDiagnosticItems.Source;
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
    function CurrentDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
    function CurrentVersion(const AUri: string): string;
    function CurrentTarget(const AUri: string; out APlatform, AConfig: string): Boolean;
    function CurrentRules(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    function CurrentCompilerMessages(const AFileName: string): TArray<TCompilerMessage>;
    function CurrentUses(const AUri: string; out AContext: TUsesContext): Boolean;
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
    /// <summary>Parameter für publishDiagnostics. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildParams(const ADocument: ITextDocument): TJSONObject; overload; static;
    /// <summary>Wie oben, zusätzlich mit inaktiven Bereichen als Hinweise (Tag Unnecessary).</summary>
    class function BuildParams(const ADocument: ITextDocument;
      const AInactive: TArray<TTextRange>): TJSONObject; overload; static;
    /// <summary>Wie oben, zusätzlich mit Sprachmerkmalen, die ADelphiVersion nicht kennt.</summary>
    class function BuildParams(const ADocument: ITextDocument; const AInactive: TArray<TTextRange>;
      const ADelphiVersion: string): TJSONObject; overload; static;
    /// <summary>Wie oben, zusätzlich mit den Treffern der Prüfregeln aus ARules.</summary>
    class function BuildParams(const ADocument: ITextDocument; const AInactive: TArray<TTextRange>;
      const ADelphiVersion: string; const ARules: TRuleCheckContext): TJSONObject; overload; static;
    /// <summary>Wie oben mit allen Angaben aus AInput.</summary>
    class function BuildParams(const ADocument: ITextDocument; const AInput: TSyntaxDiagnosticsInput)
      : TJSONObject; overload; static;
    /// <summary>Treffer der Prüfregeln aus ARules für AText (Baum ATree), ohne die Baseline abzuziehen; so prüft
    /// auch atlas.updateBaseline (#97). Leer ohne Regeln.</summary>
    class function RuleFindings(const AText: string; ATree: TSyntaxTree;
      const ARules: TRuleCheckContext): TArray<TRuleFinding>; static;
    /// <summary>Parameter für publishDiagnostics zu ADocument (Pascal oder Formular) mit Regeln
    /// und Compilermeldungen. Threadsicher; der Aufrufer übernimmt das Objekt.</summary>
    function Compute(const ADocument: ITextDocument): TJSONObject; overload;
    /// <summary>Wie Compute; fragt ACancelled vor jeder Prüfregel und bricht dann mit
    /// ERuleCheckCancelled ab (Diagnoselog 15.10.2026).</summary>
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
  System.Math,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Checker;

// Übernimmt AParams.
procedure Send(const ATransport: IJsonRpcTransport; AParams: TJSONObject);
var
  Notification: TJSONObject;
begin
  Notification := TJsonRpcMessages.Notification(TLspTextDocumentMethod.PublishDiagnostics, AParams);
  try
    ATransport.WriteMessage(Notification);
  finally
    Notification.Free;
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
procedure AddRuleFindings(AItems: TJSONArray; const AText: string; ATree: TSyntaxTree;
  const ARules: TRuleCheckContext);
var
  mFindings: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
begin
  try
    mFindings := TLspSyntaxDiagnostics.RuleFindings(AText, ATree, ARules);
  except
    AItems.Free;
    raise;
  end;
  // Routinen aus demselben Baum: Die Baseline braucht sie für ihren Schlüssel.
  if ARules.Baseline <> nil then
  begin
    mFindings := ARules.Baseline.Filter(ARules.RelativePath, AText, TFindingScopes.FromTree(ATree), mFindings);
  end;
  for mFinding in mFindings do
  begin
    AItems.AddElement(TLspDiagnosticItems.FindingToJson(mFinding));
  end;
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
    FRefreshDebouncer := TDebouncer.Create(RefreshDelayMs);
  end;
end;

constructor TLspSyntaxDiagnostics.Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  const AProviders: TSyntaxDiagnosticsProviders);
begin
  Create(AStore, ATransport, AProviders, DefaultDelayMs);
end;

destructor TLspSyntaxDiagnostics.Destroy;
begin
  // Zuerst: Eine gebündelte Neuprüfung plant über FDebouncer neu.
  FRefreshDebouncer.Free;
  FDebouncer.Free;
  FSendLock.Free;
  inherited;
end;

procedure TLspSyntaxDiagnostics.Attach;
begin
  FStore.Subscribe(HandleDocumentEvent);
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

function TLspSyntaxDiagnostics.CurrentDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  Provider: TDefinesProvider;
begin
  Provider := FProviders.Defines;
  ADefines := nil;
  Result := Assigned(Provider) and Provider(AUri, ADefines);
end;

function TLspSyntaxDiagnostics.CurrentVersion(const AUri: string): string;
var
  Provider: TDelphiVersionProvider;
begin
  Provider := FProviders.Version;
  if Assigned(Provider) then
  begin
    Result := Provider(AUri);
  end
  else
  begin
    Result := '';
  end;
end;

function TLspSyntaxDiagnostics.CurrentTarget(const AUri: string; out APlatform, AConfig: string): Boolean;
var
  Provider: TBuildTargetProvider;
begin
  Provider := FProviders.BuildTarget;
  APlatform := '';
  AConfig := '';
  Result := Assigned(Provider) and Provider(AUri, APlatform, AConfig);
  if not Result then
  begin
    APlatform := '';
    AConfig := '';
  end;
end;

function TLspSyntaxDiagnostics.CurrentRules(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  Provider: TRuleContextProvider;
begin
  Provider := FProviders.Rules;
  AContext := Default(TRuleCheckContext);
  Result := Assigned(Provider) and Provider(AUri, AContext);
end;

function TLspSyntaxDiagnostics.CurrentUses(const AUri: string; out AContext: TUsesContext): Boolean;
var
  Provider: TUsesContextProvider;
begin
  Provider := FProviders.UsesContext;
  AContext := Default(TUsesContext);
  Result := Assigned(Provider) and Provider(AUri, AContext);
end;

function TLspSyntaxDiagnostics.CurrentCompilerMessages(const AFileName: string): TArray<TCompilerMessage>;
var
  Provider: TCompilerMessagesProvider;
begin
  Provider := FProviders.CompilerMessages;
  if Assigned(Provider) then
  begin
    Result := Provider(AFileName);
  end
  else
  begin
    Result := nil;
  end;
end;

procedure TLspSyntaxDiagnostics.RefreshFiles(const AFileNames: TArray<string>);
var
  FileName, Uri: string;
  Document: ITextDocument;
  Item: TCompilerMessage;
  Items: TJSONArray;
  Params: TJSONObject;
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
  for FileName in AFileNames do
  begin
    Uri := TDocumentUris.FromPath(FileName);
    if FStore.TryGet(Uri, Document) then
    begin
      ScheduleParse(Document);
      Continue;
    end;
    Items := TJSONArray.Create;
    for Item in CurrentCompilerMessages(FileName) do
    begin
      Items.AddElement(TLspDiagnosticItems.CompilerMessageToJson(Item, '', False));
    end;
    Params := TJSONObject.Create;
    Params.AddPair('uri', Uri);
    Params.AddPair('diagnostics', Items);
    TMonitor.Enter(FSendLock);
    try
      // Inzwischen geöffnet: Das Dokument meldet selbst, mit Zeilentext.
      if FStore.TryGet(Uri, Document) then
      begin
        Params.Free;
        ScheduleParse(Document);
      end
      else
      begin
        Send(FTransport, Params);
      end;
    finally
      TMonitor.Exit(FSendLock);
    end;
  end;
end;

procedure TLspSyntaxDiagnostics.Refresh;
var
  Document: ITextDocument;
begin
  if FPullMode then
  begin
    if Assigned(FOnPullChanged) then
    begin
      FOnPullChanged();
    end;
    Exit;
  end;
  for Document in FStore.Documents do
  begin
    if not SameText(ExtractFileExt(Document.Uri), '.json') then
    begin
      ScheduleParse(Document);
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

function TLspSyntaxDiagnostics.IsCurrent(const ADocument: ITextDocument): Boolean;
var
  Current: ITextDocument;
begin
  Result := FStore.TryGet(ADocument.Uri, Current) and (Current.Version = ADocument.Version);
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
  mUses: TUsesContext;
begin
  if TLspDiagnosticItems.TryFormParams(ADocument.Uri, ADocument.Text, Result) then
  begin
    Exit;
  end;
  mInput := Default(TSyntaxDiagnosticsInput);
  mIssues := nil;
  if CurrentDefines(ADocument.Uri, mInput.Defines) then
  begin
    mInput.Inactive := InactiveOf(ADocument, mInput.Defines, mIssues);
  end;
  if not CurrentRules(ADocument.Uri, mInput.Rules) then
  begin
    mInput.Rules := Default(TRuleCheckContext);
  end;
  mInput.Rules.Cancelled := ACancelled;
  mInput.DelphiVersion := CurrentVersion(ADocument.Uri);
  CurrentTarget(ADocument.Uri, mInput.Platform, mInput.Config);
  Result := BuildParams(ADocument, mInput);
  mItems := Result.GetValue('diagnostics') as TJSONArray;
  for mIssue in mIssues do
  begin
    mItems.AddElement(TLspDiagnosticItems.IssueToJson(mIssue));
  end;
  // Ungenutzte uses (#621): nicht bei Syntaxfehlern, dann fehlen Bezeichner. Entscheidend ist der Baum, nicht
  // die Meldungen: Auch mit abgeschalteter Regel "syntax" (#1022) wäre die Auswertung unsicher.
  if CurrentUses(ADocument.Uri, mUses) and
    (Length(TSyntaxTreeCache.GetFor(ADocument, mInput.Defines).Tree.Diagnostics) = 0) then
  begin
    TLspDiagnosticItems.AddUses(mItems, ADocument.Text, TLspInactiveRegions.RangesOf(mInput.Inactive), mUses);
  end;
  AddCompilerMessages(mItems, ADocument, CurrentCompilerMessages(TDocumentUris.ToPath(ADocument.Uri)));
end;

procedure TLspSyntaxDiagnostics.Publish(const ADocument: ITextDocument);
var
  Params: TJSONObject;
begin
  // Überholte Stände nicht zu Ende prüfen: Der neuere meldet selbst.
  try
    Params := Compute(ADocument,
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
      Send(FTransport, Params);
    end
    else
    begin
      Params.Free;
    end;
  finally
    TMonitor.Exit(FSendLock);
  end;
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument): TJSONObject;
begin
  Result := BuildParams(ADocument, nil);
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TTextRange>): TJSONObject;
begin
  Result := BuildParams(ADocument, AInactive, '');
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TTextRange>; const ADelphiVersion: string): TJSONObject;
begin
  Result := BuildParams(ADocument, AInactive, ADelphiVersion, Default(TRuleCheckContext));
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TTextRange>; const ADelphiVersion: string; const ARules: TRuleCheckContext): TJSONObject;
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
  mTree: TSyntaxTree;
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  // Baum nur aus den aktiven Zweigen (#845): Inaktive Zweige erzeugen keine Syntaxfehler, und Regeln
  // sehen den Code, den der Compiler übersetzt. Mit den Symbolen des Projekts ist es der Baum aus Get.
  mTree := TSyntaxTreeCache.GetFor(ADocument, AInput.Defines).Tree;
  // Syntaxfehler als Treffer der Regel "syntax" (#1022): Schweregrad und Gruppe aus der Konfiguration,
  // Code und Korrektur wie bei den übrigen Regeln. Ohne Konfiguration gilt Default = Fehler.
  for mFinding in TFileChecker.SyntaxFindings(mTree.Diagnostics, AInput.Rules.Settings) do
  begin
    mItems.AddElement(TLspDiagnosticItems.FindingToJson(mFinding));
  end;
  // Merkmale in inaktiven Zweigen ({$IF CompilerVersion >= …}) sind gewollt (#109). Als Treffer der Regel
  // language-feature wie im Linter und in den MCP-Werkzeugen (#1126); DelphiVersion ist der Sprachstand.
  for mFinding in TFileChecker.LanguageFeatureFindings(mTree, AInput.Rules.Settings, AInput.DelphiVersion,
    TLspInactiveRegions.RangesOf(AInput.Inactive)) do
  begin
    mItems.AddElement(TLspDiagnosticItems.FindingToJson(mFinding));
  end;
  if Length(AInput.Rules.Rules) > 0 then
  begin
    AddRuleFindings(mItems, ADocument.Text, mTree, AInput.Rules);
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

class function TLspSyntaxDiagnostics.RuleFindings(const AText: string; ATree: TSyntaxTree;
  const ARules: TRuleCheckContext): TArray<TRuleFinding>;
var
  Context: TRuleContext;
begin
  if Length(ARules.Rules) = 0 then
  begin
    Exit(nil);
  end;
  Context := Default(TRuleContext);
  Context.RelativePath := ARules.RelativePath;
  Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARules.RelativePath, '/', '\', [rfReplaceAll])), '');
  Context.Text := AText;
  Context.Tree := ATree;
  ARules.Services.ApplyTo(Context);
  Context.FormText := ARules.FormText;
  Context.FormFile := ARules.FormFile;
  Context.ReadFile := ARules.ReadFile;
  Context.FileExists := ARules.FileExists;
  Context.FileName := ARules.FileName;
  Context.Application := ARules.Application;
  Context.ProjectName := ARules.ProjectName;
  Context.AutoCreateForms := ARules.AutoCreateForms;
  Context.ProjectMainSource := ARules.ProjectMainSource;
  Context.Cancelled := ARules.Cancelled;
  Context.Live := ARules.Live;
  Result := TRuleEngine.Run(ARules.Rules, ARules.Settings, Context);
end;

end.
