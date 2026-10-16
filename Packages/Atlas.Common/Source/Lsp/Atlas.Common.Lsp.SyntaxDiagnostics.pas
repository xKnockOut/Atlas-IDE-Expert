unit Atlas.Common.Lsp.SyntaxDiagnostics;

// Meldet Syntaxfehler des Parsers als textDocument/publishDiagnostics.
// Nach didOpen und didChange wird das Dokument nach einer kurzen Verzögerung
// geparst (Debouncing beim Tippen); bei didClose werden die Meldungen gelöscht.
// Jede Meldung trägt Zeile, Spalte und Endposition in UTF-16.
// Sind die Symbole des Projekts bekannt (DefinesProvider), kommen inaktive
// {$IFDEF}-Bereiche als Hinweise mit dem Tag Unnecessary dazu; der Editor
// blendet sie ab. Ohne Projekt wird nichts abgeblendet, weil die aktiven
// Symbole dann nicht bekannt sind. Jeder Bereich nennt die Bedingung seines
// Zweigs und, mit BuildTargetProvider, Zielplattform und Konfiguration (#615):
// „Inaktiv: Bedingung WIN64 nicht erfüllt (Zielplattform Win32 · Debug)“,
// dieselben Angaben einzeln in data.inactive.
// Ist die Delphi-Version bekannt (VersionProvider), werden Sprachmerkmale,
// die diese Version noch nicht kennt, als Warnung gemeldet.
// Meldungen des letzten Compilerlaufs (CompilerMessagesProvider, #40) kommen
// mit der Quelle "dcc" dazu, auch für Dateien, die nicht geöffnet sind.
// Include-Dateien (#264) sucht der Präprozessor über IncludePathsProvider;
// ein Include-Zyklus ist eine Warnung, eine nicht gefundene Datei ein Hinweis.

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
  Atlas.Common.Lsp.Internals.Debouncer;

type
  /// <summary>Symbole für das Dokument AUri; False, wenn kein Projekt sie festlegt.
  /// Wird im Hintergrund-Thread aufgerufen.</summary>
  TDefinesProvider = reference to function(const AUri: string; out ADefines: TArray<string>): Boolean;
  /// <summary>Suchpfade für $I-Dateien zum Dokument AUri (#264).</summary>
  TIncludePathsProvider = reference to function(const AUri: string): TArray<string>;
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
    /// <summary>Symbolindex für Regeln, die Vorfahren auflösen (#125); nil = keiner.</summary>
    Index: ISymbolIndex;
    /// <summary>Units nachladen und Namespaces für die Namensauflösung (#178).</summary>
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TArray<string>;
    /// <summary>Formulardatei neben der Unit (#123); '' ohne.</summary>
    FormText: string;
    /// <summary>Dateien neben der Unit, z. B. .dcr (#114); nil = keine.</summary>
    ReadFile: TRuleFileReader;
    /// <summary>Abbruch zwischen den Prüfregeln; nil = nie. Setzt Compute.</summary>
    Cancelled: TRuleCancelled;
  end;

  /// <summary>Regeln und Einstellungen für AUri; False = keine Regeln prüfen. Hintergrund-Thread.</summary>
  TRuleContextProvider = reference to function(const AUri: string; out AContext: TRuleCheckContext): Boolean;
  /// <summary>Meldungen des letzten Compilerlaufs zur Datei AFileName. Hintergrund-Thread.</summary>
  TCompilerMessagesProvider = reference to function(const AFileName: string): TArray<TCompilerMessage>;

  TLspSyntaxDiagnostics = class
  public const
    /// <summary>Verzögerung nach dem letzten Tastendruck; mit Parsen bleibt es unter 200 ms.</summary>
    DefaultDelayMs = 100;
    /// <summary>Bündelt RefreshLater: In einer Projektgruppe melden sich viele Indexstufen kurz
    /// hintereinander, und jede Neuprüfung holt alle offenen Dokumente neu (#647).</summary>
    RefreshDelayMs = 2000;
    Source = 'Atlas';
    CompilerSource = 'dcc';
    InactiveMessage = 'Inaktiver Bereich (bedingte Kompilierung)';
    InactiveConditionMessage = 'Inaktiv: Bedingung %s nicht erfüllt';
    InactiveTargetSuffix = ' (Zielplattform %s · %s)';
  private
    FStore: IDocumentStore;
    FTransport: IJsonRpcTransport;
    FDebouncer: TDebouncer;
    FRefreshDebouncer: TDebouncer;
    /// <summary>Hält Prüfen und Senden zusammen, damit nach dem Schließen nichts Veraltetes mehr kommt.</summary>
    FSendLock: TObject;
    FDefinesLock: TObject;
    FDefinesProvider: TDefinesProvider;
    FIncludePathsProvider: TIncludePathsProvider;
    FVersionProvider: TDelphiVersionProvider;
    FTargetProvider: TBuildTargetProvider;
    FRuleProvider: TRuleContextProvider;
    FCompilerProvider: TCompilerMessagesProvider;
    FPullMode: Boolean;
    FOnPullChanged: TProc;
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    procedure ScheduleParse(const ADocument: ITextDocument);
    procedure Publish(const ADocument: ITextDocument);
    function IsCurrent(const ADocument: ITextDocument): Boolean;
    function GetOnError: TProc<Exception>;
    procedure SetOnError(const AValue: TProc<Exception>);
    function CurrentDefines(const AUri: string; out ADefines: TArray<string>): Boolean;
    procedure SetDefinesProvider(const AValue: TDefinesProvider);
    function CurrentIncludePaths(const AUri: string): TArray<string>;
    procedure SetIncludePathsProvider(const AValue: TIncludePathsProvider);
    function CurrentVersion(const AUri: string): string;
    procedure SetVersionProvider(const AValue: TDelphiVersionProvider);
    function CurrentTarget(const AUri: string; out APlatform, AConfig: string): Boolean;
    procedure SetTargetProvider(const AValue: TBuildTargetProvider);
    function CurrentRules(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    procedure SetRuleProvider(const AValue: TRuleContextProvider);
    function CurrentCompilerMessages(const AFileName: string): TArray<TCompilerMessage>;
    procedure SetCompilerProvider(const AValue: TCompilerMessagesProvider);
  public
    /// <summary>Bei ADelayMs = 0 wird sofort im Thread der Nachrichtenschleife geparst.</summary>
    constructor Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      ADelayMs: Cardinal = DefaultDelayMs);
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
    /// <summary>Wie oben mit Bedingung je inaktivem Bereich und gewählter Zielplattform und
    /// Konfiguration (#615; '' = unbekannt).</summary>
    /// <summary>Wie unten; Syntaxfehler nur aus aktiven Zweigen unter ADefines (leer = Vordefinitionen).</summary>
    class function BuildParams(const ADocument: ITextDocument; const AInactive: TArray<TLspInactiveRegion>;
      const ADelphiVersion: string; const ARules: TRuleCheckContext; const APlatform, AConfig: string;
      const ADefines: TArray<string>): TJSONObject; overload; static;
    class function BuildParams(const ADocument: ITextDocument; const AInactive: TArray<TLspInactiveRegion>;
      const ADelphiVersion: string; const ARules: TRuleCheckContext;
      const APlatform, AConfig: string): TJSONObject; overload; static;
    /// <summary>Meldung zu einem inaktiven Bereich: mit Bedingung „Inaktiv: Bedingung X nicht erfüllt“,
    /// mit Plattform oder Konfiguration dahinter „(Zielplattform Win32 · Debug)“.</summary>
    class function InactiveMessageOf(const ACondition, APlatform, AConfig: string): string; static;
    /// <summary>Treffer der Prüfregeln aus ARules für AText (Baum ATree), ohne die Baseline abzuziehen; so prüft
    /// auch atlas.updateBaseline (#97). Leer ohne Regeln.</summary>
    class function RuleFindings(const AText: string; ATree: TSyntaxTree;
      const ARules: TRuleCheckContext): TArray<TRuleFinding>; static;
    /// <summary>Ein Regeltreffer als LSP-Diagnostic (code = Regelkennung). Der Aufrufer übernimmt das Objekt.</summary>
    class function FindingToJson(const AFinding: TRuleFinding): TJSONObject; static;
    /// <summary>Compilermeldung als LSP-Diagnostic; ALineText (falls bekannt) begrenzt den Bereich.
    /// Der Aufrufer übernimmt das Objekt.</summary>
    class function CompilerMessageToJson(const AMessage: TCompilerMessage; const ALineText: string;
      AHasLineText: Boolean): TJSONObject; static;
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
    /// <summary>Parameter mit leerer Liste, z. B. nach dem Schließen. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildEmptyParams(const AUri: string): TJSONObject; static;
    /// <summary>Wird bei Ausnahmen beim Parsen im Hintergrund aufgerufen.</summary>
    property OnError: TProc<Exception> read GetOnError write SetOnError;
    /// <summary>Liefert die Symbole für das Abblenden inaktiver Bereiche.</summary>
    property DefinesProvider: TDefinesProvider write SetDefinesProvider;
    property IncludePathsProvider: TIncludePathsProvider write SetIncludePathsProvider;
    property VersionProvider: TDelphiVersionProvider write SetVersionProvider;
    /// <summary>Zielplattform und Konfiguration für den Hinweis inaktiver Bereiche (#615).</summary>
    property BuildTargetProvider: TBuildTargetProvider write SetTargetProvider;
    /// <summary>Liefert Regeln und Einstellungen; ohne Provider laufen keine Prüfregeln.</summary>
    property RuleProvider: TRuleContextProvider write SetRuleProvider;
    /// <summary>Liefert die Meldungen des letzten Compilerlaufs; ohne Provider keine.</summary>
    property CompilerMessagesProvider: TCompilerMessagesProvider write SetCompilerProvider;
    /// <summary>Der Client holt Diagnosen selbst ab (#82): nichts senden, bei Änderungen
    /// stattdessen OnPullChanged aufrufen.</summary>
    property PullMode: Boolean read FPullMode write FPullMode;
    property OnPullChanged: TProc read FOnPullChanged write FOnPullChanged;
  end;

implementation

uses
  System.Math,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Lsp.FormFiles;

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

{ TLspSyntaxDiagnostics }

constructor TLspSyntaxDiagnostics.Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  ADelayMs: Cardinal);
begin
  inherited Create;
  FStore := AStore;
  FTransport := ATransport;
  FSendLock := TObject.Create;
  FDefinesLock := TObject.Create;
  FDebouncer := TDebouncer.Create(ADelayMs);
  if ADelayMs = 0 then
    FRefreshDebouncer := TDebouncer.Create(0)
  else
    FRefreshDebouncer := TDebouncer.Create(RefreshDelayMs);
end;

destructor TLspSyntaxDiagnostics.Destroy;
begin
  // Zuerst: Eine gebündelte Neuprüfung plant über FDebouncer neu.
  FRefreshDebouncer.Free;
  FDebouncer.Free;
  FSendLock.Free;
  FDefinesLock.Free;
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
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FDefinesProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  ADefines := nil;
  Result := Assigned(Provider) and Provider(AUri, ADefines);
end;

procedure TLspSyntaxDiagnostics.SetDefinesProvider(const AValue: TDefinesProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FDefinesProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

function TLspSyntaxDiagnostics.CurrentIncludePaths(const AUri: string): TArray<string>;
var
  Provider: TIncludePathsProvider;
begin
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FIncludePathsProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  if Assigned(Provider) then
    Result := Provider(AUri)
  else
    Result := nil;
end;

procedure TLspSyntaxDiagnostics.SetIncludePathsProvider(const AValue: TIncludePathsProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FIncludePathsProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

function TLspSyntaxDiagnostics.CurrentVersion(const AUri: string): string;
var
  Provider: TDelphiVersionProvider;
begin
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FVersionProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  if Assigned(Provider) then
    Result := Provider(AUri)
  else
    Result := '';
end;

procedure TLspSyntaxDiagnostics.SetVersionProvider(const AValue: TDelphiVersionProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FVersionProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

function TLspSyntaxDiagnostics.CurrentTarget(const AUri: string; out APlatform, AConfig: string): Boolean;
var
  Provider: TBuildTargetProvider;
begin
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FTargetProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  APlatform := '';
  AConfig := '';
  Result := Assigned(Provider) and Provider(AUri, APlatform, AConfig);
  if not Result then
  begin
    APlatform := '';
    AConfig := '';
  end;
end;

procedure TLspSyntaxDiagnostics.SetTargetProvider(const AValue: TBuildTargetProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FTargetProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

function TLspSyntaxDiagnostics.CurrentRules(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  Provider: TRuleContextProvider;
begin
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FRuleProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  AContext := Default(TRuleCheckContext);
  Result := Assigned(Provider) and Provider(AUri, AContext);
end;

procedure TLspSyntaxDiagnostics.SetRuleProvider(const AValue: TRuleContextProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FRuleProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

function TLspSyntaxDiagnostics.CurrentCompilerMessages(const AFileName: string): TArray<TCompilerMessage>;
var
  Provider: TCompilerMessagesProvider;
begin
  TMonitor.Enter(FDefinesLock);
  try
    Provider := FCompilerProvider;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
  if Assigned(Provider) then
    Result := Provider(AFileName)
  else
    Result := nil;
end;

procedure TLspSyntaxDiagnostics.SetCompilerProvider(const AValue: TCompilerMessagesProvider);
begin
  TMonitor.Enter(FDefinesLock);
  try
    FCompilerProvider := AValue;
  finally
    TMonitor.Exit(FDefinesLock);
  end;
end;

class function TLspSyntaxDiagnostics.CompilerMessageToJson(const AMessage: TCompilerMessage;
  const ALineText: string; AHasLineText: Boolean): TJSONObject;
var
  Range: TTextRange;
  First, Last: Integer;
  Severity: Integer;
begin
  Range.StartPos := TTextPosition.Create(Max(AMessage.Line, 0), 0);
  Range.EndPos := TTextPosition.Create(Max(AMessage.Line, 0) + 1, 0);
  if AHasLineText then
  begin
    if AMessage.Column >= 0 then
    begin
      // Ab der Spalte bis zum Ende des Bezeichners, mindestens ein Zeichen.
      First := Min(AMessage.Column, Length(ALineText));
      Last := First + 1;
      while (Last < Length(ALineText)) and CharInSet(ALineText[Last + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(Last);
    end
    else
    begin
      // Ganze Zeile ohne Einrückung.
      First := 0;
      while (First < Length(ALineText)) and CharInSet(ALineText[First + 1], [' ', #9]) do
        Inc(First);
      Last := Length(ALineText);
    end;
    Range.StartPos := TTextPosition.Create(Range.StartPos.Line, First);
    Range.EndPos := TTextPosition.Create(Range.StartPos.Line, Max(Last, First));
  end
  else if AMessage.Column >= 0 then
  begin
    Range.StartPos := TTextPosition.Create(Range.StartPos.Line, AMessage.Column);
    Range.EndPos := TTextPosition.Create(Range.StartPos.Line, AMessage.Column + 1);
  end;
  case AMessage.Severity of
    TCompilerSeverity.Hint:
      Severity := TLspDiagnosticSeverity.Hint;
    TCompilerSeverity.Warning:
      Severity := TLspDiagnosticSeverity.Warning;
  else
    Severity := TLspDiagnosticSeverity.Error;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(Range));
  Result.AddPair('severity', TJSONNumber.Create(Severity));
  if AMessage.Code <> '' then
    Result.AddPair('code', AMessage.Code);
  Result.AddPair('source', CompilerSource);
  Result.AddPair('message', AMessage.Text);
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
    if Assigned(FOnPullChanged) then
      FOnPullChanged();
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
      Items.AddElement(CompilerMessageToJson(Item, '', False));
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
        Send(FTransport, Params);
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
      FOnPullChanged();
    Exit;
  end;
  for Document in FStore.Documents do
    if not SameText(ExtractFileExt(Document.Uri), '.json') then
      ScheduleParse(Document);
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
    Exit;
  case AKind of
    TDocumentEventKind.Opened, TDocumentEventKind.Changed:
      ScheduleParse(ADocument);
    TDocumentEventKind.Closed:
      begin
        TMonitor.Enter(FSendLock);
        try
          FDebouncer.Cancel(ADocument.Uri);
          Send(FTransport, BuildEmptyParams(ADocument.Uri));
        finally
          TMonitor.Exit(FSendLock);
        end;
      end;
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
  Defines: TArray<string>;
  Inactive: TArray<TLspInactiveRegion>;
  Rules: TRuleCheckContext;
  Platform, Config: string;
  Items: TJSONArray;
  Compiled: TCompilerMessage;
  Form: TDfmDocument;
  Issues: TArray<TPreprocessorIssue>;
  Issue: TPreprocessorIssue;
  Item: TJSONObject;
begin
  // Formulardateien (#44): nur Lesefehler der DFM, keine Pascal-Prüfungen.
  if TDfmParser.IsFormFile(ADocument.Uri) then
  begin
    Form := TDfmParser.Parse(ADocument.Text);
    try
      Result := TJSONObject.Create;
      Result.AddPair('uri', ADocument.Uri);
      // Binär gespeichert (#122): ein Hinweis statt Lesefehlern.
      if TFormModel.IsBinary(ADocument.Text) then
        Result.AddPair('diagnostics', TLspFormFiles.BinaryDiagnostics)
      else
        Result.AddPair('diagnostics', TLspFormFiles.BuildDiagnostics(Form));
    finally
      Form.Free;
    end;
    Exit;
  end;
  Inactive := nil;
  Issues := nil;
  if CurrentDefines(ADocument.Uri, Defines) then
    Inactive := TLspInactiveRegions.Regions(ADocument.Text, Defines, TDocumentUris.ToPath(ADocument.Uri),
      TIncludeFiles.Resolver(CurrentIncludePaths(ADocument.Uri)), Issues)
  else
    Defines := nil;
  if not CurrentRules(ADocument.Uri, Rules) then
    Rules := Default(TRuleCheckContext);
  Rules.Cancelled := ACancelled;
  CurrentTarget(ADocument.Uri, Platform, Config);
  Result := BuildParams(ADocument, Inactive, CurrentVersion(ADocument.Uri), Rules, Platform, Config, Defines);
  Items := Result.GetValue('diagnostics') as TJSONArray;
  for Issue in Issues do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Issue.Range));
    if Issue.Kind = TPreprocessorIssueKind.IncludeCycle then
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Warning))
    else
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Hint));
    Item.AddPair('source', Source);
    Item.AddPair('message', Issue.Message);
    Items.AddElement(Item);
  end;
  for Compiled in CurrentCompilerMessages(TDocumentUris.ToPath(ADocument.Uri)) do
    if Compiled.Line < ADocument.LineCount then
      Items.AddElement(CompilerMessageToJson(Compiled, ADocument.LineText(Max(Compiled.Line, 0)), True));
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
      Send(FTransport, Params)
    else
      Params.Free;
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

class function TLspSyntaxDiagnostics.FindingToJson(const AFinding: TRuleFinding): TJSONObject;
var
  Severity: Integer;
begin
  case AFinding.Severity of
    TRuleSeverity.Error:
      Severity := TLspDiagnosticSeverity.Error;
    TRuleSeverity.Warning:
      Severity := TLspDiagnosticSeverity.Warning;
    TRuleSeverity.Information:
      Severity := TLspDiagnosticSeverity.Information;
  else
    Severity := TLspDiagnosticSeverity.Hint;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AFinding.Range));
  Result.AddPair('severity', TJSONNumber.Create(Severity));
  Result.AddPair('code', AFinding.RuleId);
  Result.AddPair('codeDescription', TJSONObject.Create(
    TJSONPair.Create('href', TRuleCatalog.HelpUri(AFinding.RuleId))));
  Result.AddPair('source', Source);
  // Konfidenz als eigenes Feld, der Meldungstext bleibt unverändert (#144).
  Result.AddPair('message', AFinding.Message);
  Result.AddPair('data', TJSONObject.Create(TJSONPair.Create('confidence', ConfidenceName(AFinding.Confidence))));
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TTextRange>; const ADelphiVersion: string; const ARules: TRuleCheckContext): TJSONObject;
begin
  Result := BuildParams(ADocument, TLspInactiveRegions.FromRanges(AInactive), ADelphiVersion, ARules, '', '');
end;

class function TLspSyntaxDiagnostics.InactiveMessageOf(const ACondition, APlatform, AConfig: string): string;
var
  Platform, Config: string;
begin
  if ACondition = '' then
    Exit(InactiveMessage);
  Result := Format(InactiveConditionMessage, [ACondition]);
  if (APlatform = '') and (AConfig = '') then
    Exit;
  Platform := APlatform;
  Config := AConfig;
  if Platform = '' then
    Platform := '?';
  if Config = '' then
    Config := '?';
  Result := Result + Format(InactiveTargetSuffix, [Platform, Config]);
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TLspInactiveRegion>; const ADelphiVersion: string; const ARules: TRuleCheckContext;
  const APlatform, AConfig: string): TJSONObject;
begin
  Result := BuildParams(ADocument, AInactive, ADelphiVersion, ARules, APlatform, AConfig, nil);
end;

class function TLspSyntaxDiagnostics.BuildParams(const ADocument: ITextDocument;
  const AInactive: TArray<TLspInactiveRegion>; const ADelphiVersion: string; const ARules: TRuleCheckContext;
  const APlatform, AConfig: string; const ADefines: TArray<string>): TJSONObject;
var
  Syntax: TArray<TSyntaxDiagnostic>;
  RuleFinding: TRuleFinding;
  Findings: TArray<TRuleFinding>;
var
  Finding: TLanguageFeatureFinding;
  Region: TLspInactiveRegion;
  Data: TJSONObject;
  Tags: TJSONArray;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Diagnostic: TSyntaxDiagnostic;
  Items: TJSONArray;
  Item: TJSONObject;
begin
  Items := TJSONArray.Create;
  Shared := TSyntaxTreeCache.Get(ADocument);
  Tree := Shared.Tree;
  // Inaktive Zweige der bedingten Kompilierung erzeugen keine Syntaxfehler.
  if not TPascalParser.ActiveDiagnostics(ADocument.Text, ADefines, Syntax) then
    Syntax := Tree.Diagnostics;
  for Diagnostic in Syntax do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(Diagnostic.StartPos, Diagnostic.EndPos)));
    Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Error));
    Item.AddPair('source', Source);
    Item.AddPair('message', Diagnostic.Message);
    Items.AddElement(Item);
  end;
  // Merkmale in inaktiven Zweigen ({$IF CompilerVersion >= …}) sind gewollt (#109).
  for Finding in TLanguageFeatures.Check(Tree, ADelphiVersion, TLspInactiveRegions.RangesOf(AInactive)) do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(TTextRange.Create(Finding.StartPos, Finding.EndPos)));
    Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Warning));
    Item.AddPair('source', Source);
    Item.AddPair('message', Finding.Message);
    Items.AddElement(Item);
  end;
  if Length(ARules.Rules) > 0 then
  begin
    // Abbruch (ERuleCheckCancelled): Die bis dahin gesammelten Meldungen freigeben.
    try
      Findings := RuleFindings(ADocument.Text, Tree, ARules);
    except
      Items.Free;
      raise;
    end;
    // Routinen aus demselben Baum: Die Baseline (#97) braucht sie für ihren Schlüssel.
    if ARules.Baseline <> nil then
      Findings := ARules.Baseline.Filter(ARules.RelativePath, ADocument.Text, TFindingScopes.FromTree(Tree), Findings);
    for RuleFinding in Findings do
      Items.AddElement(FindingToJson(RuleFinding));
  end;
  for Region in AInactive do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Region.Range));
    Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Hint));
    Item.AddPair('source', Source);
    Item.AddPair('message', InactiveMessageOf(Region.Condition, APlatform, AConfig));
    Tags := TJSONArray.Create;
    // DiagnosticTag.Unnecessary
    Tags.Add(1);
    Item.AddPair('tags', Tags);
    // Einzeln für Clients, die den Hinweis selbst setzen (Plugin, übersetzt).
    Data := TJSONObject.Create;
    Data.AddPair('condition', Region.Condition);
    Data.AddPair('platform', APlatform);
    Data.AddPair('config', AConfig);
    Item.AddPair('data', TJSONObject.Create(TJSONPair.Create('inactive', Data)));
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('uri', ADocument.Uri);
  Result.AddPair('version', TJSONNumber.Create(ADocument.Version));
  Result.AddPair('diagnostics', Items);
end;

class function TLspSyntaxDiagnostics.RuleFindings(const AText: string; ATree: TSyntaxTree;
  const ARules: TRuleCheckContext): TArray<TRuleFinding>;
var
  Context: TRuleContext;
begin
  if Length(ARules.Rules) = 0 then
    Exit(nil);
  Context := Default(TRuleContext);
  Context.RelativePath := ARules.RelativePath;
  Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARules.RelativePath, '/', '\', [rfReplaceAll])), '');
  Context.Text := AText;
  Context.Tree := ATree;
  Context.Index := ARules.Index;
  Context.EnsureUnit := ARules.EnsureUnit;
  Context.Namespaces := ARules.Namespaces;
  Context.FormText := ARules.FormText;
  Context.ReadFile := ARules.ReadFile;
  Context.Cancelled := ARules.Cancelled;
  Result := TRuleEngine.Run(ARules.Rules, ARules.Settings, Context);
end;

class function TLspSyntaxDiagnostics.BuildEmptyParams(const AUri: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  Result.AddPair('diagnostics', TJSONArray.Create);
end;

end.
