unit Atlas.Core.Debug.ReturnFlow;

// Ablauf beim Abholen der Rückgabewerte (#844) ohne IDE. Vor dem Schritt des Benutzers stehen vorübergehende
// Haltepunkte auf den end-Zeilen der beobachteten Funktionen (TAtlasReturnWatch); dann läuft der Schritt der IDE.
// Jeder Halt kommt hier an und bekommt eine Aktion:
// - StepOver (F8 über eine Zeile, Tiefe D): Halt an einer beobachteten end-Zeile auf Tiefe D+1: Result auswerten
//   (Evaluate), danach „Bis zur Rückkehr“ (Return) zurück in die Aufrufzeile; dort den Schritt mit „Gesamte Routine“
//   fortsetzen (StepOver), denn die Zeile kann weitere Funktionen aufrufen. Tiefer (Rekursion): weiterlaufen
//   (Resume), bis der Rahmen des Schritts zurückkehrt.
// - RunUntilReturn (Umschalt+F8 in einer Funktion, Tiefe D): Halt an ihrer end-Zeile auf Tiefe D: auswerten, dann
//   „Bis zur Rückkehr“; der nächste Halt (in der Aufrufzeile) beendet den Ablauf. Tiefer: weiterlaufen.
// Jeder andere Halt (Ende des Schritts, Haltepunkt des Benutzers, unbekannte Tiefe, zu viele Runden) beendet den
// Ablauf und gehört dem Benutzer (Pass). Zeilen ab 0. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.ReturnValues;

type
  {$SCOPEDENUMS ON}
  TAtlasReturnMode = (StepOver, RunUntilReturn);
  TAtlasReturnPhase = (Idle, Stepping, Evaluating, Returning);
  /// <summary>Was mit einem Halt geschieht: Pass (Ablauf vorbei, der Halt gehört dem Benutzer), Evaluate (Result
  /// auswerten, dann Returned), Return („Bis zur Rückkehr“), Resume (weiterlaufen), StepOver („Gesamte Routine“).
  /// </summary>
  TAtlasReturnAction = (Pass, Evaluate, Return, Resume, StepOver);
  {$SCOPEDENUMS OFF}

  /// <summary>Ort und Tiefe eines Halts; Depth &lt; 0 = unbekannt.</summary>
  TAtlasReturnStop = record
    FileName: string;
    Line: Integer;
    Depth: Integer;
    class function Create(const AFileName: string; ALine, ADepth: Integer): TAtlasReturnStop; static;
  end;

  TAtlasReturnFlow = class
  public const
    /// <summary>Höchstens so viele Halte je Schritt; danach gehört der Halt dem Benutzer.</summary>
    cMaxRounds = 200;
  private
    FMode: TAtlasReturnMode;
    FPhase: TAtlasReturnPhase;
    FOrigin: TAtlasReturnStop;
    FWatches: TArray<TAtlasReturnWatch>;
    FCurrent: TAtlasReturnWatch;
    FRounds: Integer;
    function ExpectedDepth: Integer;
    function FindWatch(const AStop: TAtlasReturnStop; out AWatch: TAtlasReturnWatch): Boolean;
    function AtWatch(const AStop: TAtlasReturnStop): TAtlasReturnAction;
    function AfterReturn(const AStop: TAtlasReturnStop): TAtlasReturnAction;
    function Finish: TAtlasReturnAction;
  public
    /// <summary>Schritt AMode beginnt am Halt AOrigin (Tiefe bekannt) mit AWatches.</summary>
    procedure Start(AMode: TAtlasReturnMode; const AOrigin: TAtlasReturnStop;
      const AWatches: TArray<TAtlasReturnWatch>);
    /// <summary>Halt AStop eines laufenden Ablaufs; Pass ohne Ablauf.</summary>
    function Stopped(const AStop: TAtlasReturnStop): TAtlasReturnAction;
    /// <summary>Result von Current ausgewertet (auch wenn es nicht ging): Return.</summary>
    function Returned: TAtlasReturnAction;
    /// <summary>Ablauf abbrechen (Sitzung zu Ende, Exception, Fehler).</summary>
    procedure Cancel;
    function Active: Boolean;
    property Mode: TAtlasReturnMode read FMode;
    property Phase: TAtlasReturnPhase read FPhase;
    property Origin: TAtlasReturnStop read FOrigin;
    /// <summary>Funktion, deren Result gerade auszuwerten ist (Phase Evaluating).</summary>
    property Current: TAtlasReturnWatch read FCurrent;
    property Watches: TArray<TAtlasReturnWatch> read FWatches;
  end;

implementation

{ TAtlasReturnStop }

class function TAtlasReturnStop.Create(const AFileName: string; ALine, ADepth: Integer): TAtlasReturnStop;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Depth := ADepth;
end;

{ TAtlasReturnFlow }

procedure TAtlasReturnFlow.Start(AMode: TAtlasReturnMode; const AOrigin: TAtlasReturnStop;
  const AWatches: TArray<TAtlasReturnWatch>);
begin
  FMode := AMode;
  FOrigin := AOrigin;
  FWatches := Copy(AWatches);
  FCurrent := Default(TAtlasReturnWatch);
  FRounds := 0;
  FPhase := TAtlasReturnPhase.Stepping;
  if (Length(FWatches) = 0) or (AOrigin.Depth < 0) then
  begin
    Cancel;
  end;
end;

procedure TAtlasReturnFlow.Cancel;
begin
  FPhase := TAtlasReturnPhase.Idle;
  FWatches := nil;
  FCurrent := Default(TAtlasReturnWatch);
end;

function TAtlasReturnFlow.Active: Boolean;
begin
  Result := FPhase <> TAtlasReturnPhase.Idle;
end;

function TAtlasReturnFlow.Finish: TAtlasReturnAction;
begin
  Cancel;
  Result := TAtlasReturnAction.Pass;
end;

function TAtlasReturnFlow.ExpectedDepth: Integer;
begin
  // Über eine Zeile: die gerufene Funktion liegt einen Rahmen tiefer; bis zur Rückkehr: der eigene Rahmen.
  if FMode = TAtlasReturnMode.StepOver then
  begin
    Result := FOrigin.Depth + 1;
  end
  else
  begin
    Result := FOrigin.Depth;
  end;
end;

function TAtlasReturnFlow.FindWatch(const AStop: TAtlasReturnStop; out AWatch: TAtlasReturnWatch): Boolean;
var
  mWatch: TAtlasReturnWatch;
begin
  AWatch := Default(TAtlasReturnWatch);
  Result := False;
  for mWatch in FWatches do
  begin
    if (mWatch.EndLine = AStop.Line) and SameText(mWatch.FileName, AStop.FileName) then
    begin
      AWatch := mWatch;
      Exit(True);
    end;
  end;
end;

function TAtlasReturnFlow.AtWatch(const AStop: TAtlasReturnStop): TAtlasReturnAction;
var
  mWatch: TAtlasReturnWatch;
begin
  if not FindWatch(AStop, mWatch) or (AStop.Depth < ExpectedDepth) then
  begin
    Result := Finish;
  end
  else if AStop.Depth > ExpectedDepth then
  begin
    // Rekursion: Der Rahmen des Schritts kehrt später zurück.
    Result := TAtlasReturnAction.Resume;
  end
  else
  begin
    FCurrent := mWatch;
    FPhase := TAtlasReturnPhase.Evaluating;
    Result := TAtlasReturnAction.Evaluate;
  end;
end;

function TAtlasReturnFlow.AfterReturn(const AStop: TAtlasReturnStop): TAtlasReturnAction;
begin
  // Zurück in der Aufrufzeile: Sie kann weitere Funktionen aufrufen, also den Schritt fortsetzen.
  if (FMode = TAtlasReturnMode.StepOver) and (AStop.Line = FOrigin.Line) and SameText(AStop.FileName,
    FOrigin.FileName) and ((AStop.Depth < 0) or (AStop.Depth = FOrigin.Depth)) then
  begin
    FPhase := TAtlasReturnPhase.Stepping;
    Result := TAtlasReturnAction.StepOver;
  end
  else
  begin
    Result := Finish;
  end;
end;

function TAtlasReturnFlow.Stopped(const AStop: TAtlasReturnStop): TAtlasReturnAction;
begin
  Inc(FRounds);
  if not Active or (FRounds > cMaxRounds) then
  begin
    Exit(Finish);
  end;
  case FPhase of
    TAtlasReturnPhase.Stepping:
      begin
        if AStop.Depth < 0 then
        begin
          Exit(Finish);
        end;
        Result := AtWatch(AStop);
      end;
    TAtlasReturnPhase.Returning:
      Result := AfterReturn(AStop);
  else
    // Halt während der Auswertung: gehört nicht zum Ablauf.
    Result := Finish;
  end;
end;

function TAtlasReturnFlow.Returned: TAtlasReturnAction;
begin
  if FPhase <> TAtlasReturnPhase.Evaluating then
  begin
    Exit(Finish);
  end;
  FPhase := TAtlasReturnPhase.Returning;
  Result := TAtlasReturnAction.Return;
end;

end.
