unit Atlas.Common.Lsp.IndexRefresh;

// Index der aktiven Unit nach der Tipp-Pause (#492): didChange plant das
// Neueinlesen des ungespeicherten Texts; erst nach ADelayMs ohne weitere
// Änderung läuft AApply (im Hintergrund-Thread des Debouncers). So steht eine
// neue Deklaration ohne Speichern in Vervollständigung und Hover bereit.
// Beim Schließen verwirft Closed eine geplante Aktion; der Aufrufer liest die
// Datei dann wieder von der Platte ein.
// TLspUsesChanges (#896) merkt je Datei die uses-Listen des zuletzt
// übernommenen Texts: Ändern sie sich, prüft der Aufrufer die übrigen offenen
// Units neu, denn ihr Unit-Zyklus (uses-cycle) kann über die geänderte Unit
// laufen. Änderungen außerhalb der uses lösen das nicht aus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Lsp.Internals.Debouncer;

type
  /// <summary>Ungespeicherten Text von AFileName in den Index übernehmen.</summary>
  TIndexTextApply = reference to procedure(const AFileName, AText: string);

  TLspIndexRefresh = class
  public const
    DefaultDelayMs = 500;
  private
    FDebouncer: TDebouncer;
    FApply: TIndexTextApply;
    function GetOnError: TProc<Exception>;
    procedure SetOnError(const AValue: TProc<Exception>);
  public
    /// <summary>Bei ADelayMs = 0 läuft AApply sofort im aufrufenden Thread (Tests).</summary>
    constructor Create(ADelayMs: Cardinal; const AApply: TIndexTextApply);
    /// <summary>Verwirft Geplantes und wartet auf eine laufende Übernahme.</summary>
    destructor Destroy; override;
    /// <summary>Text einer Pascal-Quelle hat sich geändert; andere Dateien werden ignoriert.</summary>
    procedure Changed(const AFileName, AText: string);
    procedure Closed(const AFileName: string);
    /// <summary>Gehört AFileName zu den Units, die beim Tippen neu eingelesen werden?</summary>
    class function Applies(const AFileName: string): Boolean; static;
    property OnError: TProc<Exception> read GetOnError write SetOnError;
  end;

  /// <summary>uses-Listen je Datei seit der letzten Übernahme (#896). Threadsicher.</summary>
  TLspUsesChanges = class
  private
    FLock: TObject;
    /// <summary>Datei (groß) -> Signatur der uses-Listen.</summary>
    FSignatures: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Haben sich die uses-Listen von AFileName gegenüber dem letzten Aufruf geändert? Beim ersten
    /// Aufruf je Datei True (der Stand davor ist unbekannt).</summary>
    function Changed(const AFileName, AText: string): Boolean;
    /// <summary>Datei geschlossen: Der nächste Changed gilt wieder als erster.</summary>
    procedure Forget(const AFileName: string);
    /// <summary>Abschnitt und Name jedes uses-Eintrags in Reihenfolge, z. B. "I:SYSUTILS|M:UKUNDE".</summary>
    class function Signature(const AText: string): string; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause;

constructor TLspIndexRefresh.Create(ADelayMs: Cardinal; const AApply: TIndexTextApply);
begin
  inherited Create;
  FApply := AApply;
  FDebouncer := TDebouncer.Create(ADelayMs);
end;

destructor TLspIndexRefresh.Destroy;
begin
  FDebouncer.Free;
  inherited;
end;

class function TLspIndexRefresh.Applies(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr');
end;

procedure TLspIndexRefresh.Changed(const AFileName, AText: string);
var
  Apply: TIndexTextApply;
begin
  if not Applies(AFileName) or not Assigned(FApply) then
    Exit;
  Apply := FApply;
  FDebouncer.Schedule(AnsiUpperCase(AFileName),
    procedure
    begin
      Apply(AFileName, AText);
    end);
end;

procedure TLspIndexRefresh.Closed(const AFileName: string);
begin
  FDebouncer.Cancel(AnsiUpperCase(AFileName));
end;

function TLspIndexRefresh.GetOnError: TProc<Exception>;
begin
  Result := FDebouncer.OnError;
end;

procedure TLspIndexRefresh.SetOnError(const AValue: TProc<Exception>);
begin
  FDebouncer.OnError := AValue;
end;

{ TLspUsesChanges }

constructor TLspUsesChanges.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FSignatures := TDictionary<string, string>.Create;
end;

destructor TLspUsesChanges.Destroy;
begin
  FSignatures.Free;
  FLock.Free;
  inherited;
end;

class function TLspUsesChanges.Signature(const AText: string): string;
var
  Reference: TUsesReference;
begin
  Result := '';
  for Reference in TUsesClauses.References(TPascalLexer.Tokenize(AText)) do
  begin
    if Result <> '' then
      Result := Result + '|';
    if Reference.InInterface then
      Result := Result + 'I:'
    else
      Result := Result + 'M:';
    Result := Result + UpperCase(Reference.Name);
  end;
end;

function TLspUsesChanges.Changed(const AFileName, AText: string): Boolean;
var
  Current, Previous: string;
begin
  Current := Signature(AText);
  System.TMonitor.Enter(FLock);
  try
    Result := not FSignatures.TryGetValue(UpperCase(AFileName), Previous) or (Previous <> Current);
    FSignatures.AddOrSetValue(UpperCase(AFileName), Current);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TLspUsesChanges.Forget(const AFileName: string);
begin
  System.TMonitor.Enter(FLock);
  try
    FSignatures.Remove(UpperCase(AFileName));
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
