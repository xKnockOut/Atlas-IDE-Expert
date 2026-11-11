unit Shell.Composition.Parts;

// Teile der Komposition: alle Teilwurzeln, Verbindung und Kanal an einer Stelle. Die Verdrahtung
// (Shell.Composition.ProtocolWiring, CoreWiring, FeatureWiring, CommandWiring) füllt die Felder nacheinander;
// ihre Closures fragen die Teile deshalb erst beim Aufruf. Destroy hält die Reihenfolge des Beendens.

interface

uses
  System.JSON,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.Lsp.TextDocumentSync,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Editing.Contract,
  Shell.Composition.Stdio,
  Shell.Composition.Core,
  Shell.Composition.Protocol,
  Shell.Composition.Session,
  Shell.Composition.DiagnosticsArea,
  Shell.Composition.CodeArea,
  Shell.Composition.CommandArea,
  Shell.Composition.AnalysisArea,
  Shell.Composition.IdeArea,
  Shell.Composition.EditingArea,
  Shell.Composition.IndexArea,
  Shell.Composition.Compile;

type
  /// <summary>Hält die Teile der Komposition; öffentliche Felder, weil nur Komposition und Verdrahtung sie
  /// setzen.</summary>
  TShellParts = class
  public const
    /// <summary>Anfragen, die länger laufen, werden abgebrochen und gemeldet.</summary>
    cRequestTimeoutMs = 10000;
  private
    /// <summary>Teil von Destroy: gibt Features, Ordner und Index frei.</summary>
    procedure FreeFeatures;
  public
    /// <summary>Logger, Transport, Mitschnitt (--trace), letzte Logzeilen (#108) und Anonymisierer (#647, #1356).
    /// Die Komposition setzt Logger und Transport; Mitschnitt, Logzeilen und Anonymisierer nur CreateForStdio,
    /// sonst nil. Der Mitschnitt liegt nicht besitzend im Transport.</summary>
    Channel: TShellStdioChannel;
    /// <summary>Teilwurzel Protokoll: Verteiler, Statistik, letzte Nachrichten, Lebenszyklus, Absturzfälle.</summary>
    Protocol: TShellProtocol;
    /// <summary>Teilwurzel Sitzung: Diagnoselog, Wächter des Editor-Prozesses, Client, Endgrund, Zeitlimit.</summary>
    Session: TShellSession;
    /// <summary>--replay (#1355): Einstellungen aus dem Fall, keine eigenen Fälle.</summary>
    Replay: Boolean;
    Documents: IDocumentStore;
    TextDocumentSync: TLspTextDocumentSync;
    /// <summary>Teilwurzel Diagnosen: Syntaxprüfung, Pull-Diagnosen und Projektprüfung.</summary>
    DiagnosticsArea: TShellDiagnosticsArea;
    /// <summary>Teilwurzel Code: Navigation, Refactorings, Vervollständigung, Code-Aktionen und Testunits.</summary>
    CodeArea: TShellCodeArea;
    /// <summary>Teilwurzel Befehle: workspace/executeCommand mit allen Befehlen.</summary>
    CommandArea: TShellCommandArea;
    /// <summary>Teilwurzel Analyse: Analysen, Übersichten, Baselines und betroffene Tests.</summary>
    AnalysisArea: TShellAnalysisArea;
    /// <summary>Teilwurzel IDE: Nachrichten aus der IDE, Dateiänderungen und Projektwahl.</summary>
    IdeArea: TShellIdeArea;
    /// <summary>Teilwurzel Bearbeiten: Gliederung, Formatieren, Erzeugen-Menü und Host der Schnellbefehle.</summary>
    EditingArea: TShellEditingArea;
    /// <summary>Teilwurzel Index: Symbolindex, Uses-Graph, Ordner des Arbeitsbereichs und Ereignisse des
    /// Aufbaus.</summary>
    IndexArea: TShellIndexArea;
    Connection: TJsonRpcConnection;
    /// <summary>Arbeitsbereiche, Einstellungen, Ordner und was je Datei aus ihnen folgt.</summary>
    Core: TShellCore;
    CompilerProcess: ICompilerProcess;
    /// <summary>Compilerläufe (#40, #261): höchstens ein Lauf zugleich, ein weiterer wird vorgemerkt.</summary>
    Compile: TShellCompileHost;
    /// <summary>Der Client hat keinen brauchbaren Ordner gemeldet (RAD Studio, #175):
    /// Ordner werden aus den geöffneten Dateien abgeleitet.</summary>
    DeriveWorkspaces: Boolean;
    /// <summary>Hält Wächter, Verbindung, Compiler und Index-Threads an und gibt alle Teile rückwärts frei.</summary>
    destructor Destroy; override;
    /// <summary>Schickt eine Benachrichtigung an den Client.</summary>
    procedure NotifyClient(const AMethod: string; AParams: TJSONObject);
    /// <summary>Zeitlimit einer Anfrage aus den Einstellungen; vor der Sitzung die Vorgabe.</summary>
    function CurrentRequestTimeout: Cardinal;
    /// <summary>Gemeinsamer Symbolindex; nil vor der Teilwurzel Index und nach dem Freigeben.</summary>
    function Index: ISymbolIndex;
    /// <summary>Text einer Quelldatei; geöffnete Dokumente haben Vorrang vor der Platte.</summary>
    function ReadSourceText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Muster, Ordner und Testprogramm für Testunits zur Datei (#274, #189).</summary>
    function TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
    /// <summary>Index und usesKeep für /sortuses (#297) und die uses-Diagnosen (#621); False, solange die
    /// Code-Aktionen fehlen.</summary>
    function UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Lsp.ServerActivity,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Shell.Platform;

destructor TShellParts.Destroy;
var
  mUnfinished: Boolean;
begin
  // Vor allem anderen: Der Takt der Statusdatei fragt sonst Teile ab, die gleich freigegeben werden (#1901).
  TServerActivity.Shared.SetDetails(nil);
  TPascalPreprocessor.SetDeclaredProvider(nil);
  // Zuerst: Eine laufende Übernahme greift auf die Ordner zu.
  if IdeArea <> nil then
  begin
    IdeArea.FileChanges.StopRefresh;
  end;
  // Vor der Verbindung: Beide Wächter rufen Connection.
  if Core <> nil then
  begin
    Core.Configuration.StopWatching;
  end;
  if Session <> nil then
  begin
    Session.StopWatchingParent;
  end;
  // Liefen beim Ende noch Handler, die ihr Abbruchsignal nicht prüfen, nutzen sie
  // Features und Ordner weiter.
  mUnfinished := (Connection <> nil) and Connection.UnfinishedWork;
  FreeAndNil(Connection);
  if Protocol <> nil then
  begin
    Protocol.Dispatcher.Watchdog := nil;
  end;
  // Compiler und Index-Threads anhalten, solange Diagnoselog und Syntaxprüfung noch leben:
  // Ein abgebrochener Aufbau meldet sich über OnIndexEvent im Diagnoselog, ein Compilerlauf über die
  // Syntaxprüfung.
  if Compile <> nil then
  begin
    Compile.Stop;
  end;
  if Core <> nil then
  begin
    Core.StopIndexThreads;
  end;
  // Der Baum-Cache ist global; ohne Projekte gelten wieder die Vordefinitionen (#845).
  TSyntaxTreeCache.SetDefinesProvider(nil);
  TSyntaxTreeCache.SetIncludeProvider(nil);
  // Erst jetzt meldet sich niemand mehr beim Diagnoselog.
  if Protocol <> nil then
  begin
    Protocol.Dispatcher.Observer := nil;
  end;
  FreeAndNil(Session);
  if mUnfinished then
  begin
    // Der Prozess endet gleich: Speicher stehen lassen, statt ihn unter einem laufenden Handler freizugeben.
    Channel.Logger.Warning('Beim Beenden liefen noch Anfragen; ihre Objekte werden nicht freigegeben');
  end
  else
  begin
    FreeFeatures;
  end;
  if Channel.Tracing <> nil then
  begin
    Channel.Tracing.OnFailed := nil;
  end;
  // Statusdatei für get_server_status (#1356) gehört nur dem laufenden Server.
  TServerStatusFile.Delete(TIndexCacheDirectory.DefaultRoot, TShellPlatform.CurrentProcessId);
  Channel := Default(TShellStdioChannel);
  inherited;
end;

procedure TShellParts.FreeFeatures;
begin
  // Absicherung: Bricht das Anlegen ab, fehlen spätere Teile.
  // Vor den Ordnern: der Hintergrund-Thread der Syntaxprüfung fragt ihre Symbole ab.
  if DiagnosticsArea <> nil then
  begin
    DiagnosticsArea.FreeChecks;
  end;
  // Ordner vor dem Index: ihre Index-Threads laufen noch.
  if Core <> nil then
  begin
    Core.FreeWorkspaces;
  end;
  // Nach den Ordnern: Ihre Index-Threads melden Projektstufe und Ende.
  FreeAndNil(DiagnosticsArea);
  FreeAndNil(Core);
  FreeAndNil(IndexArea);
  // Danach die Features in umgekehrter Reihenfolge ihrer Gruppen; Protokoll und Absturzfälle zuletzt.
  FreeAndNil(AnalysisArea);
  FreeAndNil(CodeArea);
  FreeAndNil(CommandArea);
  // Nach allen Nutzern des Hosts der Schnellbefehle: Er ruft dessen Methoden.
  FreeAndNil(EditingArea);
  FreeAndNil(Compile);
  CompilerProcess := nil;
  FreeAndNil(IdeArea);
  FreeAndNil(TextDocumentSync);
  Documents := nil;
  // Nach der Verbindung und dem Watchdog: Niemand meldet mehr einen Absturz.
  FreeAndNil(Protocol);
end;

procedure TShellParts.NotifyClient(const AMethod: string; AParams: TJSONObject);
var
  mNotification: TJSONObject;
begin
  mNotification := TJsonRpcMessages.Notification(AMethod, AParams);
  try
    Channel.Transport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

function TShellParts.CurrentRequestTimeout: Cardinal;
begin
  Result := cRequestTimeoutMs;
  if Session <> nil then
  begin
    Result := Session.RequestTimeout;
  end;
end;

function TShellParts.Index: ISymbolIndex;
begin
  Result := nil;
  if IndexArea <> nil then
  begin
    Result := IndexArea.Index;
  end;
end;

function TShellParts.ReadSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := Core.ReadText(AFileName, AText);
end;

function TShellParts.TestUnitContextFor(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  Result := (CodeArea <> nil) and CodeArea.TestUnits.ContextFor(AUri, AContext);
end;

function TShellParts.UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  Result := (CodeArea <> nil) and CodeArea.UsesContextFor(AUri, AContext);
end;

end.
