unit Atlas.Common.Lsp.IndexRefresh;

// Index der aktiven Unit nach der Tipp-Pause (#492): didChange plant das
// Neueinlesen des ungespeicherten Texts; erst nach ADelayMs ohne weitere
// Änderung läuft AApply (im Hintergrund-Thread des Debouncers). So steht eine
// neue Deklaration ohne Speichern in Vervollständigung und Hover bereit.
// Beim Schließen verwirft Closed eine geplante Aktion; der Aufrufer liest die
// Datei dann wieder von der Platte ein.

interface

uses
  System.SysUtils,
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

implementation

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

end.
