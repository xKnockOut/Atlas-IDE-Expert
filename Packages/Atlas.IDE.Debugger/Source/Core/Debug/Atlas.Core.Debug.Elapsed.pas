unit Atlas.Core.Debug.Elapsed;

// Laufzeit zwischen Haltepunkten (#579) ohne IDE: Die Phasen der Debug-Sitzung messen, wie lange der Prozess vor
// einem Halt lief (TAtlasDebugPhases.RunTimeBeforeStop, angehaltene Zeit zählt nicht). TAtlasElapsed nimmt je
// gemeldeten Halt diese Zeit mit dem Ort des Halts an, merkt die letzten Messungen mit Start- und Zielzeile und
// entscheidet, ob am Zeilenende „+124 ms“ steht: an einem Haltepunkt immer, bei Schritten und Pausen erst ab der
// Schwelle (1 ms). Zeilen ab 0. Nur im Hauptthread verwenden.

interface

type
  /// <summary>Eine Messung: Laufzeit in Mikrosekunden vom Halt in FromFile/FromLine bis zum Halt in
  /// ToFile/ToLine (Zeilen ab 0); FromFile '' = seit dem Start des Programms.</summary>
  TAtlasElapsedEntry = record
    Micros: Int64;
    FromFile: string;
    FromLine: Integer;
    ToFile: string;
    ToLine: Integer;
    AtBreakpoint: Boolean;
  end;

  TAtlasElapsed = class
  public const
    /// <summary>So viele Messungen bleiben im Verlauf.</summary>
    cMaxEntries = 20;
    /// <summary>Schwelle für Schritte und Pausen in Mikrosekunden (1 ms).</summary>
    cStepThresholdMicros = 1000;
  private
    FEntries: TArray<TAtlasElapsedEntry>;
    FLastFile: string;
    FLastLine: Integer;
    FShown: Boolean;
  public
    constructor Create;
    /// <summary>Neue Sitzung: Verlauf und Anzeige verwerfen.</summary>
    procedure Clear;
    /// <summary>Halt in AFile/ALine (ab 0) nach AMicros Laufzeit; AAtBreakpoint: Dort steht ein Haltepunkt.
    /// Ergebnis: Steht die Zeit jetzt am Zeilenende?</summary>
    function Add(AMicros: Int64; const AFile: string; ALine: Integer; AAtBreakpoint: Boolean): Boolean;
    /// <summary>Weitergelaufen bzw. Sitzung beendet: nichts mehr am Zeilenende, der Verlauf bleibt.</summary>
    procedure Hide;
    /// <summary>Text am Ende der Zeile ALine (ab 0) von AFile; '' ohne.</summary>
    function LineText(const AFile: string; ALine: Integer): string;
    /// <summary>Messungen, die jüngste zuerst.</summary>
    function Entries: TArray<TAtlasElapsedEntry>;
    function Count: Integer;
    /// <summary>Wird die Messung angezeigt? Am Haltepunkt immer, sonst ab cStepThresholdMicros.</summary>
    class function Shown(AMicros: Int64; AAtBreakpoint: Boolean): Boolean; static;
    /// <summary>„+124 ms“, „+&lt;1 ms“, „+12 s“, „+2 min 5 s“.</summary>
    class function Format(AMicros: Int64): string; static;
    /// <summary>Zeile im Verlauf: „+124 ms  Unit1.pas 117 → 123“, über Dateien „Unit1.pas 117 → Unit2.pas 40“,
    /// ohne Start „→ Unit1.pas 12“ (Zeilen ab 1).</summary>
    class function HistoryLine(const AEntry: TAtlasElapsedEntry): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cMicrosPerMs = 1000;
  cMsPerSecond = 1000;
  cSecondsPerMinute = 60;
  /// <summary>Ab dieser Laufzeit in Millisekunden ganze Sekunden statt Millisekunden.</summary>
  cSecondsFromMs = 10000;

{ TAtlasElapsed }

constructor TAtlasElapsed.Create;
begin
  inherited Create;
  Clear;
end;

procedure TAtlasElapsed.Clear;
begin
  FEntries := nil;
  FLastFile := '';
  FLastLine := -1;
  FShown := False;
end;

function TAtlasElapsed.Add(AMicros: Int64; const AFile: string; ALine: Integer; AAtBreakpoint: Boolean): Boolean;
var
  mEntry: TAtlasElapsedEntry;
begin
  mEntry := Default(TAtlasElapsedEntry);
  if AMicros > 0 then
  begin
    mEntry.Micros := AMicros;
  end;
  mEntry.FromFile := FLastFile;
  mEntry.FromLine := FLastLine;
  mEntry.ToFile := AFile;
  mEntry.ToLine := ALine;
  mEntry.AtBreakpoint := AAtBreakpoint;
  // Jüngste zuerst; höchstens cMaxEntries.
  Insert(mEntry, FEntries, 0);
  if Length(FEntries) > cMaxEntries then
  begin
    SetLength(FEntries, cMaxEntries);
  end;
  FLastFile := AFile;
  FLastLine := ALine;
  FShown := (AFile <> '') and (ALine >= 0) and Shown(mEntry.Micros, AAtBreakpoint);
  Result := FShown;
end;

procedure TAtlasElapsed.Hide;
begin
  FShown := False;
end;

function TAtlasElapsed.LineText(const AFile: string; ALine: Integer): string;
begin
  Result := '';
  if FShown and (Length(FEntries) > 0) and (FEntries[0].ToLine = ALine) and SameText(FEntries[0].ToFile, AFile) then
  begin
    Result := Format(FEntries[0].Micros);
  end;
end;

function TAtlasElapsed.Entries: TArray<TAtlasElapsedEntry>;
begin
  Result := Copy(FEntries);
end;

function TAtlasElapsed.Count: Integer;
begin
  Result := Length(FEntries);
end;

class function TAtlasElapsed.Shown(AMicros: Int64; AAtBreakpoint: Boolean): Boolean;
begin
  Result := AAtBreakpoint or (AMicros >= cStepThresholdMicros);
end;

class function TAtlasElapsed.Format(AMicros: Int64): string;
var
  mMs, mSeconds: Int64;
begin
  mMs := AMicros div cMicrosPerMs;
  if mMs < 1 then
  begin
    Exit('+<1 ms');
  end;
  if mMs < cSecondsFromMs then
  begin
    Exit('+' + IntToStr(mMs) + ' ms');
  end;
  mSeconds := mMs div cMsPerSecond;
  if mSeconds < cSecondsPerMinute then
  begin
    Exit('+' + IntToStr(mSeconds) + ' s');
  end;
  Result := '+' + IntToStr(mSeconds div cSecondsPerMinute) + ' min ' + IntToStr(mSeconds mod cSecondsPerMinute) +
    ' s';
end;

class function TAtlasElapsed.HistoryLine(const AEntry: TAtlasElapsedEntry): string;
var
  mTarget: string;
begin
  mTarget := IntToStr(AEntry.ToLine + 1);
  if (AEntry.FromFile = '') or not SameText(AEntry.FromFile, AEntry.ToFile) then
  begin
    mTarget := ExtractFileName(AEntry.ToFile) + ' ' + mTarget;
  end;
  if AEntry.FromFile = '' then
  begin
    Result := Format(AEntry.Micros) + '  → ' + mTarget;
  end
  else
  begin
    Result := Format(AEntry.Micros) + '  ' + ExtractFileName(AEntry.FromFile) + ' ' + IntToStr(AEntry.FromLine + 1) +
      ' → ' + mTarget;
  end;
end;

end.
