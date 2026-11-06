unit Shell.Composition;

// Host-Rolle Shell: Komposition des Servers von Hand (DI-Strategie ohne Container).
// Verbindet stdin/stdout, Transport, Dispatcher, Lebenszyklus, Dokumentverwaltung,
// Syntaxdiagnosen, Nachrichtenschleife, Logging, Zeitlimit für Anfragen und
// Absturzprotokoll mit Stacktrace, Absturzfällen und Sicherheitsnetz
// (Shell.CrashCases, #1355). Jeder Ordner des Arbeitsbereichs hat
// eigene Konfiguration, eigenes Projekt und eigenen Indexaufbau
// (TShellWorkspace); der Symbolindex ist gemeinsam.
// Die Teile hält TShellParts (Shell.Composition.Parts); verdrahtet werden sie in Shell.Composition.ProtocolWiring,
// CoreWiring, FeatureWiring und CommandWiring, gestartet nach initialized in Shell.Composition.ClientStart.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Shell.CommandLine,
  Shell.CrashCases,
  Shell.Composition.Parts;

type
  TServerComposition = class
  private
    /// <summary>Alle Teile der Komposition; gibt sie beim Beenden in der richtigen Reihenfolge frei.</summary>
    FParts: TShellParts;
    function GetDocuments: IDocumentStore;
  public
    constructor Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Komposition mit stdin/stdout des Prozesses und Logging nach AOptions.</summary>
    class function CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition; static;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe und liefert den Exit-Code.</summary>
    function Run: Integer;
    /// <summary>Nachstellen eines Absturzfalls (--replay, #1355), vor Run: settings.json aus ASettingsFile ('' =
    /// keine) statt der des Benutzers; der Server sichert dabei keine Fälle und überspringt nichts.</summary>
    procedure PrepareReplay(const ASettingsFile: string);
    /// <summary>Absturzfälle und Sicherheitsnetz (#1355).</summary>
    function CrashCases: TShellCrashCases;
    /// <summary>Gemeinsamer Symbolindex; nil vor der Teilwurzel Index und nach dem Freigeben.</summary>
    function Index: ISymbolIndex;
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read GetDocuments;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Connection,
  Shell.Composition.Stdio,
  Shell.Composition.ProtocolWiring,
  Shell.Composition.CoreWiring,
  Shell.Composition.FeatureWiring,
  Shell.Composition.CommandWiring,
  Shell.Composition.ClientStart,
  Atlas.Common.Diagnostics.Contract;

{ TServerComposition }

constructor TServerComposition.Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
var
  mParts: TShellParts;
begin
  inherited Create;
  mParts := TShellParts.Create;
  FParts := mParts;
  mParts.Channel.Transport := ATransport;
  mParts.Channel.Logger := ALogger;
  TShellProtocolWiring.Protocol(mParts);
  TShellProtocolWiring.Documents(mParts);
  TShellFeatureWiring.Editing(mParts);
  TShellCoreWiring.Workspaces(mParts);
  TShellCoreWiring.Index(mParts);
  TShellFeatureWiring.Code(mParts);
  TShellFeatureWiring.Analysis(mParts);
  TShellCommandWiring.Commands(mParts);
  TShellFeatureWiring.Ide(mParts);
  mParts.Protocol.Lifecycle.OnInitialized :=
    procedure
    begin
      TShellClientStart.Initialized(mParts);
    end;
  mParts.Connection := TJsonRpcConnection.Create(mParts.Channel.Transport, mParts.Protocol.Dispatcher);
  mParts.Connection.OnError :=
    procedure(const AError: Exception)
    begin
      mParts.Channel.Logger.Error('Fehler bei der Verarbeitung: ' + mParts.Session.DescribeFailure(AError));
    end;
  mParts.Protocol.Lifecycle.OnExit :=
    procedure
    begin
      mParts.Session.EndReason := TDiagnosticEndReason.Clean;
      mParts.Connection.Stop;
    end;
end;

destructor TServerComposition.Destroy;
begin
  FreeAndNil(FParts);
  inherited;
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  mChannel: TShellStdioChannel;
  mLogger: ILogger;
begin
  mChannel := TShellStdio.Open(AOptions);
  mLogger := mChannel.Logger;
  Result := TServerComposition.Create(mChannel.Transport, mLogger);
  Result.FParts.Channel := mChannel;
  Result.FParts.Compile.Restricted := AOptions.Restricted;
  Result.FParts.Session.ClientProcessId := AOptions.ClientProcessId;
  if AOptions.Restricted then
  begin
    mLogger.Info('Eingeschränkter Modus (Arbeitsbereich nicht vertrauenswürdig): der Compiler wird nicht gestartet');
  end;
end;

procedure TServerComposition.PrepareReplay(const ASettingsFile: string);
begin
  FParts.Replay := True;
  FParts.Core.Configuration.UseReplaySettings(ASettingsFile);
  FParts.Protocol.CrashCases.Enabled := False;
  FParts.Protocol.CrashCases.SkipEnabled := False;
end;

function TServerComposition.Run: Integer;
begin
  Result := FParts.Session.Run(FParts.Connection, FParts.Protocol.Lifecycle);
end;

function TServerComposition.CrashCases: TShellCrashCases;
begin
  Result := FParts.Protocol.CrashCases;
end;

function TServerComposition.Index: ISymbolIndex;
begin
  Result := FParts.Index;
end;

function TServerComposition.GetDocuments: IDocumentStore;
begin
  Result := FParts.Documents;
end;

end.
