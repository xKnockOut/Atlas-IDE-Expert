unit Atlas.Core.Debug.Restart;

// Neu starten mit einem Griff (#872), ohne IDE: Ablaufsteuerung.
// - TAtlasRestartRun plant die Schritte (Beenden nur bei laufendem Programm,
//   Bauen nur bei Änderungen, Starten, Zurück an die Stelle im Editor), führt
//   Buch über Beginn, Ende und Erfolg jedes Schritts und bricht nach einem
//   Fehler ab. Text liefert die Zeile für die Leiste:
//   "Beenden 0,3 s ✓ · Bauen 2,1 s ✓ · Starten …".
// - TAtlasRestartBreakpoints: Haltepunkte, die beim Start der Sitzung an
//   waren und jetzt aus sind (debug.restart.reenableBreakpoints).
// Zeiten in Millisekunden von außen, damit sich der Ablauf ohne Uhr testen
// lässt.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasRestartStep = (Stop, Build, Start, Return);
  TAtlasRestartState = (Waiting, Running, Done, Failed, Skipped);
  {$SCOPEDENUMS OFF}

  TAtlasRestartStepInfo = record
    Step: TAtlasRestartStep;
    State: TAtlasRestartState;
    StartedMs: UInt64;
    FinishedMs: UInt64;
    function DurationMs: UInt64;
  end;

  /// <summary>Texte der Schritte (von der UI-Schicht in der Sprache der IDE).</summary>
  TAtlasRestartCaptions = array[TAtlasRestartStep] of string;

  TAtlasRestartRun = class
  private
    FSteps: TArray<TAtlasRestartStepInfo>;
    FCurrent: Integer;
    FFailed: Boolean;
    function IndexOf(AStep: TAtlasRestartStep): Integer;
  public
    /// <summary>Schritte für ARunning (Programm läuft) und AChanged (seit dem letzten Build geändert).</summary>
    constructor Create(ARunning, AChanged: Boolean);
    /// <summary>Nächsten Schritt beginnen; False, wenn keiner mehr kommt oder der Lauf abgebrochen ist.</summary>
    function Advance(ANowMs: UInt64; out AStep: TAtlasRestartStep): Boolean;
    /// <summary>Laufenden Schritt beenden; AOk False bricht den Lauf ab.</summary>
    procedure Finish(AOk: Boolean; ANowMs: UInt64);
    /// <summary>Kommt der Schritt im Lauf vor?</summary>
    function Has(AStep: TAtlasRestartStep): Boolean;
    function Current: TAtlasRestartStep;
    function Running: Boolean;
    function Done: Boolean;
    function Failed: Boolean;
    function Steps: TArray<TAtlasRestartStepInfo>;
    /// <summary>Zeile für die Leiste; ADone und AFailed sind die Zeichen für fertig und gescheitert.</summary>
    function Text(const ACaptions: TAtlasRestartCaptions; const ADone, AFailed: string): string;
    /// <summary>Dauer als "0,3 s" (Dezimaltrenner aus AFormat).</summary>
    class function SecondsText(AMs: UInt64; const AFormat: TFormatSettings): string; static;
  end;

  TAtlasRestartBreakpoints = record
    /// <summary>Schlüssel eines Haltepunkts: Datei (groß) und Zeile.</summary>
    class function KeyOf(const AFileName: string; ALine: Integer): string; static;
    /// <summary>Haltepunkte aus AEnabledAtStart, die in ANowDisabled stehen.</summary>
    class function ToReenable(const AEnabledAtStart, ANowDisabled: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.StrUtils;

const
  cMsPerSecond = 1000;
  cTenthMs = 100;
  cStepSeparator = ' · ';
  cRunningMark = ' …';

{ TAtlasRestartStepInfo }

function TAtlasRestartStepInfo.DurationMs: UInt64;
begin
  Result := 0;
  if FinishedMs > StartedMs then
  begin
    Result := FinishedMs - StartedMs;
  end;
end;

{ TAtlasRestartRun }

constructor TAtlasRestartRun.Create(ARunning, AChanged: Boolean);
var
  mStep: TAtlasRestartStep;
  mInfo: TAtlasRestartStepInfo;
begin
  inherited Create;
  FCurrent := -1;
  for mStep := Low(TAtlasRestartStep) to High(TAtlasRestartStep) do
  begin
    if ((mStep = TAtlasRestartStep.Stop) and not ARunning) or ((mStep = TAtlasRestartStep.Build) and not AChanged) then
    begin
      Continue;
    end;
    mInfo := Default(TAtlasRestartStepInfo);
    mInfo.Step := mStep;
    FSteps := FSteps + [mInfo];
  end;
end;

function TAtlasRestartRun.IndexOf(AStep: TAtlasRestartStep): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FSteps) do
  begin
    if FSteps[mIndex].Step = AStep then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasRestartRun.Advance(ANowMs: UInt64; out AStep: TAtlasRestartStep): Boolean;
begin
  AStep := TAtlasRestartStep.Return;
  if FFailed or (FCurrent >= High(FSteps)) then
  begin
    Exit(False);
  end;
  if (FCurrent >= 0) and (FSteps[FCurrent].State = TAtlasRestartState.Running) then
  begin
    Finish(True, ANowMs);
  end;
  Inc(FCurrent);
  FSteps[FCurrent].State := TAtlasRestartState.Running;
  FSteps[FCurrent].StartedMs := ANowMs;
  AStep := FSteps[FCurrent].Step;
  Result := True;
end;

procedure TAtlasRestartRun.Finish(AOk: Boolean; ANowMs: UInt64);
var
  mIndex: Integer;
begin
  if (FCurrent < 0) or (FCurrent > High(FSteps)) or (FSteps[FCurrent].State <> TAtlasRestartState.Running) then
  begin
    Exit;
  end;
  FSteps[FCurrent].FinishedMs := ANowMs;
  if AOk then
  begin
    FSteps[FCurrent].State := TAtlasRestartState.Done;
    Exit;
  end;
  FSteps[FCurrent].State := TAtlasRestartState.Failed;
  FFailed := True;
  for mIndex := FCurrent + 1 to High(FSteps) do
  begin
    FSteps[mIndex].State := TAtlasRestartState.Skipped;
  end;
end;

function TAtlasRestartRun.Has(AStep: TAtlasRestartStep): Boolean;
begin
  Result := IndexOf(AStep) >= 0;
end;

function TAtlasRestartRun.Current: TAtlasRestartStep;
begin
  Result := TAtlasRestartStep.Return;
  if (FCurrent >= 0) and (FCurrent <= High(FSteps)) then
  begin
    Result := FSteps[FCurrent].Step;
  end;
end;

function TAtlasRestartRun.Running: Boolean;
begin
  Result := not FFailed and not Done;
end;

function TAtlasRestartRun.Done: Boolean;
begin
  Result := (Length(FSteps) > 0) and (FSteps[High(FSteps)].State = TAtlasRestartState.Done);
end;

function TAtlasRestartRun.Failed: Boolean;
begin
  Result := FFailed;
end;

function TAtlasRestartRun.Steps: TArray<TAtlasRestartStepInfo>;
begin
  Result := Copy(FSteps);
end;

class function TAtlasRestartRun.SecondsText(AMs: UInt64; const AFormat: TFormatSettings): string;
begin
  Result := IntToStr(AMs div cMsPerSecond) + AFormat.DecimalSeparator + IntToStr((AMs mod cMsPerSecond) div cTenthMs) +
    ' s';
end;

function TAtlasRestartRun.Text(const ACaptions: TAtlasRestartCaptions; const ADone, AFailed: string): string;
var
  mInfo: TAtlasRestartStepInfo;
  mParts: TArray<string>;
  mPart: string;
begin
  mParts := nil;
  for mInfo in FSteps do
  begin
    mPart := ACaptions[mInfo.Step];
    case mInfo.State of
      TAtlasRestartState.Running:
        mPart := mPart + cRunningMark;
      TAtlasRestartState.Done:
        mPart := mPart + ' ' + SecondsText(mInfo.DurationMs, FormatSettings) + ' ' + ADone;
      TAtlasRestartState.Failed:
        mPart := mPart + ' ' + AFailed;
      TAtlasRestartState.Waiting, TAtlasRestartState.Skipped:
        Continue;
    end;
    mParts := mParts + [mPart];
  end;
  Result := string.Join(cStepSeparator, mParts);
end;

{ TAtlasRestartBreakpoints }

class function TAtlasRestartBreakpoints.KeyOf(const AFileName: string; ALine: Integer): string;
begin
  Result := UpperCase(AFileName) + ':' + IntToStr(ALine);
end;

class function TAtlasRestartBreakpoints.ToReenable(const AEnabledAtStart, ANowDisabled: TArray<string>): TArray<string>;
var
  mKey: string;
begin
  Result := nil;
  for mKey in ANowDisabled do
  begin
    if IndexText(mKey, AEnabledAtStart) >= 0 then
    begin
      Result := Result + [mKey];
    end;
  end;
end;

end.
