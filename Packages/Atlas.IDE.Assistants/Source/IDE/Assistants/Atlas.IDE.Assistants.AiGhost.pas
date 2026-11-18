unit Atlas.IDE.Assistants.AiGhost;

// KI-Schattentext (#1922): Anbieter für die Schattentext-Vorschläge von Base
// (Atlas.IDE.Contracts.GhostSuggestions). Base fragt ihn nach den gelernten
// Vorschlägen, also nur, wenn kein gelerntes Muster passt.
// - Prepare (Hauptthread): assistants.provider gesetzt, Datei nicht in
//   assistants.exclude, Schlüssel hinterlegt, Tagesgrenze nicht erreicht;
//   dann den Puffer an den Server und die Anfrage zählen.
// - Arbeit (Hintergrund): Köpfe der Klasse vom Server
//   (atlas.server.suggestionContext), Anfrage beim Anbieter, Antwort in Zeilen,
//   Prüfung beim Server (atlas.server.checkSuggestion: keine neuen
//   Syntaxfehler, nur bekannte Bezeichner). Nur geprüfte Vorschläge erscheinen.
// - Fehler des Anbieters merkt sich die Arbeit. Ohne Netz, bei Zeitgrenze oder
//   Überlast bleibt es still (der gelernte Teil läuft weiter); was nur der
//   Benutzer beheben kann (Schlüssel fehlt oder abgelehnt, Modell unbekannt,
//   Antwort verweigert) meldet das nächste Prepare im Hauptthread, je Art
//   einmal je Sitzung.
// - Tageszähler in %LOCALAPPDATA%\Atlas\ai-requests.json (TAtlasDataFile).
// - Destroy bricht laufende Anfragen ab und meldet den Anbieter bei Base ab;
//   Base wartet dabei die laufende Arbeit ab (Regel 3).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.Assistants.AiGhost,
  Atlas.IDE.Contracts.GhostSuggestions;

type
  TAtlasIdeAiGhost = class
  public const
    cTimeoutMs = 10000;
    cServerTimeoutMs = 3000;
  private
    FSessionOf: TFunc<TLspSession>;
    FHttp: IAtlasAiHttp;
    FKeys: TAtlasAiKeyReader;
    FMessage: TProc<string>;
    FProvider: IAtlasGhostProvider;
    FCount: TAtlasAiDailyCount;
    /// <summary>Datei nicht lesbar: nicht überschreiben.</summary>
    FKept: Boolean;
    /// <summary>Letzter Fehler der Arbeit (Ord von TAtlasAiError), atomar.</summary>
    FLastError: Integer;
    /// <summary>Schon gemeldete Fehlerarten und der Tag der gemeldeten Tagesgrenze.</summary>
    FReported: set of TAtlasAiError;
    FLimitDay: string;
    function Session: TLspSession;
    procedure Load;
    procedure Save;
    procedure Report(const AText: string);
    procedure ReportLastError;
    function Allowed(const AContext: TAtlasGhostContext): Boolean;
    procedure Failed(AError: TAtlasAiError);
  public
    /// <summary>ASessionOf: laufende Serversitzung oder nil; AHttp: Transport; AKeys: Schlüssel je Anbieter;
    /// AMessage: Meldung in der Meldungsansicht.</summary>
    constructor Create(const ASessionOf: TFunc<TLspSession>; const AHttp: IAtlasAiHttp;
      const AKeys: TAtlasAiKeyReader; const AMessage: TProc<string>);
    destructor Destroy; override;
    function Enabled: Boolean;
    function Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
    /// <summary>Text zum Fehler AError.</summary>
    class function ErrorText(AError: TAtlasAiError): string; static;
    class function CountFile: string; static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Text.Json,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Uris,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.AiProviders.Catalog,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Assistants.Strings;

const
  cCountFile = 'ai-requests.json';
  cCountKind = 'KI-Anfragen'; // german-ok Protokoll
  cContextCommand = 'atlas.server.suggestionContext';
  cCheckCommand = 'atlas.server.checkSuggestion';

type
  TAiGhostProvider = class(TInterfacedObject, IAtlasGhostProvider)
  private
    FOwner: TAtlasIdeAiGhost;
  public
    constructor Create(AOwner: TAtlasIdeAiGhost);
    function Enabled: Boolean;
    function Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
    procedure Accepted(const AProposal: TAtlasGhostProposal);
    procedure Rejected(const AProposal: TAtlasGhostProposal);
  end;

  /// <summary>Alles, was die Arbeit im Hintergrund braucht; im Hauptthread gefüllt.</summary>
  TAiGhostJob = record
    Session: TLspSession;
    Provider: IAtlasAiProvider;
    Uri: string;
    Request: TAtlasAiGhostRequest;
    TabSize: Integer;
    InsertSpaces: Boolean;
    Status: string;
    Hint: string;
  end;

{ TAiGhostProvider }

constructor TAiGhostProvider.Create(AOwner: TAtlasIdeAiGhost);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TAiGhostProvider.Enabled: Boolean;
begin
  Result := FOwner.Enabled;
end;

function TAiGhostProvider.Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
begin
  Result := FOwner.Prepare(AContext);
end;

procedure TAiGhostProvider.Accepted(const AProposal: TAtlasGhostProposal);
begin
  // Nichts zu lernen: Der Anbieter bekommt bei jeder Anfrage den Stand neu.
end;

procedure TAiGhostProvider.Rejected(const AProposal: TAtlasGhostProposal);
begin
  // Wie Accepted.
end;

{ Arbeit im Hintergrund }

/// <summary>Köpfe der Klasse an der Zeile; leer bei Zeitgrenze oder Fehler.</summary>
function DeclarationsOf(ASession: TLspSession; const AUri: string; ALine: Integer): TArray<string>;
var
  mArguments: TJSONArray;
  mValue: TJSONValue;
begin
  Result := nil;
  mArguments := TJSONArray.Create;
  try
    mArguments.AddElement(TJSONString.Create(AUri));
    mArguments.AddElement(TJSONNumber.Create(ALine));
    try
      mValue := ASession.RunCommand(cContextCommand, mArguments.ToJSON, TAtlasIdeAiGhost.cServerTimeoutMs);
    except
      on ELspClientError do
        Exit;
    end;
  finally
    mArguments.Free;
  end;
  try
    if mValue is TJSONObject then
    begin
      Result := TJsonRead.Strings(TJSONObject(mValue), 'declarations');
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Prüft ALines an ALine beim Server; False bei Zeitgrenze oder Fehler.</summary>
function Checked(ASession: TLspSession; const AUri: string; ALine: Integer; const ALines: TArray<string>): Boolean;
var
  mArguments: TJSONArray;
  mValue: TJSONValue;
begin
  Result := False;
  mArguments := TJSONArray.Create;
  try
    mArguments.AddElement(TJSONString.Create(AUri));
    mArguments.AddElement(TJSONNumber.Create(ALine));
    mArguments.AddElement(TJsonBuild.Strings(ALines));
    try
      mValue := ASession.RunCommand(cCheckCommand, mArguments.ToJSON, TAtlasIdeAiGhost.cServerTimeoutMs);
    except
      on ELspClientError do
        Exit;
    end;
  finally
    mArguments.Free;
  end;
  try
    Result := (mValue is TJSONObject) and TJSONObject(mValue).GetValue<Boolean>('valid', False);
  finally
    mValue.Free;
  end;
end;

/// <summary>Vorschlag aus den geprüften Zeilen.</summary>
function ProposalOf(const AJob: TAiGhostJob; const ALines: TArray<string>): TAtlasGhostProposal;
begin
  Result := Default(TAtlasGhostProposal);
  Result.Id := 'ai';
  Result.Lines := ALines;
  Result.CursorLine := AJob.Request.Line + High(ALines);
  Result.CursorCharacter := Length(ALines[High(ALines)]);
  Result.StatusText := AJob.Status;
  Result.Hint := AJob.Hint;
end;

/// <summary>Die Arbeit für AJob; Fehler des Anbieters gehen an AOwner.</summary>
function WorkOf(AOwner: TAtlasIdeAiGhost; const AJob: TAiGhostJob): TAtlasGhostWork;
var
  mJob: TAiGhostJob;
begin
  mJob := AJob;
  Result :=
    function(out AProposal: TAtlasGhostProposal): Boolean
    var
      mAnswer: TAtlasAiAnswer;
      mLines: TArray<string>;
    begin
      AProposal := Default(TAtlasGhostProposal);
      mJob.Request.Declarations := DeclarationsOf(mJob.Session, mJob.Uri, mJob.Request.Line);
      mAnswer := mJob.Provider.Complete(TAtlasAiGhost.Prompt(mJob.Request, TAtlasIdeAiGhost.cTimeoutMs));
      if not mAnswer.Ok then
      begin
        AOwner.Failed(mAnswer.Error);
        Exit(False);
      end;
      mLines := TAtlasAiGhost.LinesOf(mAnswer.Text, mJob.Request.Text, mJob.Request.Line, mJob.TabSize,
        mJob.InsertSpaces);
      Result := (Length(mLines) > 0) and Checked(mJob.Session, mJob.Uri, mJob.Request.Line, mLines);
      if Result then
      begin
        AProposal := ProposalOf(mJob, mLines);
      end;
    end;
end;

{ TAtlasIdeAiGhost }

constructor TAtlasIdeAiGhost.Create(const ASessionOf: TFunc<TLspSession>; const AHttp: IAtlasAiHttp;
  const AKeys: TAtlasAiKeyReader; const AMessage: TProc<string>);
begin
  inherited Create;
  FSessionOf := ASessionOf;
  FHttp := AHttp;
  FKeys := AKeys;
  FMessage := AMessage;
  FCount := TAtlasAiDailyCount.Create;
  Load;
  FProvider := TAiGhostProvider.Create(Self);
  TAtlasGhostProviders.Add(FProvider);
end;

destructor TAtlasIdeAiGhost.Destroy;
begin
  // Erst die laufende Anfrage abbrechen, dann abmelden: Base wartet die Arbeit ab (Regel 3).
  if FHttp <> nil then
  begin
    FHttp.Cancel;
  end;
  if FProvider <> nil then
  begin
    TAtlasGhostProviders.Remove(FProvider);
    FProvider := nil;
  end;
  Save;
  FreeAndNil(FCount);
  FHttp := nil;
  FKeys := nil;
  FSessionOf := nil;
  FMessage := nil;
  inherited Destroy;
end;

function TAtlasIdeAiGhost.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class function TAtlasIdeAiGhost.CountFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cCountFile);
end;

procedure TAtlasIdeAiGhost.Load;
var
  mLoad: TAtlasDataLoad;
  mCount: TAtlasAiDailyCount;
begin
  mCount := FCount;
  mLoad := TAtlasDataFile.Load(CountFile, cCountKind,
    function(const AText: string): Boolean
    begin
      Result := mCount.FromJson(AText);
    end);
  FKept := not TAtlasDataFile.Writable(mLoad);
  FCount.MarkSaved;
end;

procedure TAtlasIdeAiGhost.Save;
begin
  if (FCount = nil) or FKept or not FCount.Changed then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(CountFile, FCount.ToJson);
    FCount.MarkSaved;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cCountKind, E);
  end;
end;

procedure TAtlasIdeAiGhost.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

procedure TAtlasIdeAiGhost.Failed(AError: TAtlasAiError);
begin
  // Aus dem Hintergrund-Thread: nur merken, gemeldet wird im Hauptthread.
  AtomicExchange(FLastError, Ord(AError));
end;

class function TAtlasIdeAiGhost.ErrorText(AError: TAtlasAiError): string;
begin
  case AError of
    TAtlasAiError.NoKey:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorNoKey);
    TAtlasAiError.Unreachable:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorUnreachable);
    TAtlasAiError.Timeout:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorTimeout);
    TAtlasAiError.Unauthorized:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorUnauthorized);
    TAtlasAiError.ModelMissing:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorModelMissing);
    TAtlasAiError.RateLimited:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorRateLimited);
    TAtlasAiError.ServerError:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorServerError);
    TAtlasAiError.BadAnswer:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorBadAnswer);
    TAtlasAiError.Cancelled:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorCancelled);
    TAtlasAiError.Refused:
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.AiErrorRefused);
  else
    Result := '';
  end;
end;

procedure TAtlasIdeAiGhost.ReportLastError;
var
  mError: TAtlasAiError;
begin
  mError := TAtlasAiError(AtomicExchange(FLastError, Ord(TAtlasAiError.None)));
  // Netz, Zeitgrenze, Überlast und Abbruch beim Tippen behebt niemand in den Einstellungen: still.
  if (mError in [TAtlasAiError.None, TAtlasAiError.Cancelled, TAtlasAiError.Timeout, TAtlasAiError.Unreachable,
    TAtlasAiError.RateLimited, TAtlasAiError.ServerError, TAtlasAiError.BadAnswer]) or (mError in FReported) then
  begin
    Exit;
  end;
  Include(FReported, mError);
  Report(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.GhostFailed, [ErrorText(mError)]));
end;

function TAtlasIdeAiGhost.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.AssistantsInlineSuggestions and
    not SameText(mSettings.AssistantsProvider, TAtlasAiProviders.cNone);
end;

function TAtlasIdeAiGhost.Allowed(const AContext: TAtlasGhostContext): Boolean;
var
  mSettings: TAtlasPluginSettings;
  mDay: string;
begin
  Result := False;
  mSettings := TAtlasIdeSettings.Current;
  if TAtlasAiGhost.Excluded(AContext.FileName, mSettings.AssistantsExclude) then
  begin
    Exit;
  end;
  if TAtlasAiProviders.NeedsKey(mSettings.AssistantsProvider) and
    ((not Assigned(FKeys)) or (FKeys(mSettings.AssistantsProvider) = '')) then
  begin
    if not (TAtlasAiError.NoKey in FReported) then
    begin
      Include(FReported, TAtlasAiError.NoKey);
      Report(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.GhostNoKey, [mSettings.AssistantsProvider]));
    end;
    Exit;
  end;
  mDay := FormatDateTime('yyyy"-"mm"-"dd', Date);
  if not FCount.TryTake(mDay, mSettings.AssistantsDailyLimit) then
  begin
    if FLimitDay <> mDay then
    begin
      FLimitDay := mDay;
      Report(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.GhostLimit, [mSettings.AssistantsDailyLimit]));
    end;
    Exit;
  end;
  Save;
  Result := True;
end;

function TAtlasIdeAiGhost.Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
var
  mSettings: TAtlasPluginSettings;
  mJob: TAiGhostJob;
begin
  Result := nil;
  ReportLastError;
  mSettings := TAtlasIdeSettings.Current;
  mJob := Default(TAiGhostJob);
  mJob.Session := Session;
  if (mJob.Session = nil) or not mJob.Session.Initialized then
  begin
    Exit;
  end;
  mJob.Provider := TAtlasAiProviders.Create(mSettings.AssistantsProvider, mSettings.AssistantsModel, FHttp, FKeys);
  if (mJob.Provider = nil) or not Allowed(AContext) then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mJob.Session.Sync(AContext.FileName, AContext.Text);
  mJob.Uri := TLspUris.FromPath(AContext.FileName);
  mJob.Request.FileName := AContext.FileName;
  mJob.Request.Line := AContext.Line;
  mJob.Request.Text := AContext.Text;
  mJob.Request.ContextLines := mSettings.AssistantsContextLines;
  mJob.TabSize := AContext.TabSize;
  mJob.InsertSpaces := AContext.InsertSpaces;
  mJob.Status := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.GhostStatus);
  mJob.Hint := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.GhostHint,
    [mSettings.AssistantsModel, FCount.CountOn(FormatDateTime('yyyy"-"mm"-"dd', Date))]);
  Result := WorkOf(Self, mJob);
end;

end.
