unit Atlas.Core.Debug.EventBreakWatch;

// Ablauf von „Beim nächsten Ereignis anhalten“ (#856) ohne IDE, prüfbar (#1967): wie Atlas die Haltepunkte
// setzt (sofort, nach den sichtbaren Formularen, erst nach Pause), wann die Pause gelingt oder aufgegeben wird,
// ob ein Halt neu ist, was die Zahl der Stellen bedeutet und wie Atlas die Antworten der Auswertung liest.
// Atlas.IDE.Debug.EventBreak fragt Debugger und Server.

interface

uses
  Atlas.Core.Debug.EventBreak;

{$SCOPEDENUMS ON}

type
  TAtlasEventWatchPhase = (Idle, Pausing, Watching);

  /// <summary>Wie Atlas die Haltepunkte setzt: gleich (alle bzw. ein Formular), nach den sichtbaren Formularen
  /// des stehenden Programms, oder das laufende Programm erst anhalten.</summary>
  TAtlasEventArmWay = (Direct, VisibleNow, PauseFirst);

  TAtlasEventPauseOutcome = (Waiting, Stopped, TimedOut);

  /// <summary>Gefundene Stellen: keine, ungewöhnlich viele (Hinweis auf die Dauer), normal.</summary>
  TAtlasEventArmCount = (Empty, Many, Normal);

  TAtlasEventWatch = record
    Phase: TAtlasEventWatchPhase;
    PauseStarted: UInt64;
    SeenRunning: Boolean;
    StartFile: string;
    StartLine: Integer;
    /// <summary>Beobachtung beginnt; ohne Halt (AStopped = False) läuft das Programm schon.</summary>
    procedure Start(AStopped: Boolean; const AFileName: string; ALine: Integer);
    /// <summary>Programm läuft: Der nächste Halt ist neu.</summary>
    procedure Running;
    /// <summary>Halt an AFileName/ALine ist neu: Das Programm lief dazwischen oder steht woanders.</summary>
    function StoppedAnew(const AFileName: string; ALine: Integer): Boolean;
  end;

  TAtlasEventBreakWatch = class
  public
    class function ArmWay(AScope: TAtlasEventScope; AStopped: Boolean): TAtlasEventArmWay; static;
    class function PauseOutcome(AStopped: Boolean; AElapsedMs: UInt64; ALimitMs: Integer): TAtlasEventPauseOutcome;
      static;
    class function ArmCount(ACount: Integer): TAtlasEventArmCount; static;
    /// <summary>Zähler im Dialog: Sichtbare Formulare kennt Atlas erst beim Setzen, zählt also wie alle.</summary>
    class function CountChoice(const AChoice: TAtlasEventChoice): TAtlasEventChoice; static;
    /// <summary>Teilen sich mehrere Komponenten den Handler, entscheidet Sender.Name.</summary>
    class function NeedsSender(const ALocation: TAtlasEventLocation): Boolean; static;
    /// <summary>Anzahl der Formulare aus der Auswertung; False, wenn keine Zahl ab 0.</summary>
    class function FormCount(const AValue: string; out ACount: Integer): Boolean; static;
    /// <summary>Ergebnis der Auswertung ist „True“.</summary>
    class function IsTrue(const AValue: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasEventWatch }

procedure TAtlasEventWatch.Start(AStopped: Boolean; const AFileName: string; ALine: Integer);
begin
  Phase := TAtlasEventWatchPhase.Watching;
  SeenRunning := not AStopped;
  StartFile := '';
  StartLine := -1;
  if AStopped then
  begin
    StartFile := AFileName;
    StartLine := ALine;
  end;
end;

procedure TAtlasEventWatch.Running;
begin
  SeenRunning := True;
end;

function TAtlasEventWatch.StoppedAnew(const AFileName: string; ALine: Integer): Boolean;
begin
  Result := SeenRunning or not SameText(AFileName, StartFile) or (ALine <> StartLine);
end;

{ TAtlasEventBreakWatch }

class function TAtlasEventBreakWatch.ArmWay(AScope: TAtlasEventScope; AStopped: Boolean): TAtlasEventArmWay;
begin
  if AScope <> TAtlasEventScope.VisibleForms then
  begin
    Result := TAtlasEventArmWay.Direct;
  end
  else if AStopped then
  begin
    Result := TAtlasEventArmWay.VisibleNow;
  end
  else
  begin
    Result := TAtlasEventArmWay.PauseFirst;
  end;
end;

class function TAtlasEventBreakWatch.PauseOutcome(AStopped: Boolean; AElapsedMs: UInt64;
  ALimitMs: Integer): TAtlasEventPauseOutcome;
begin
  if AStopped then
  begin
    Result := TAtlasEventPauseOutcome.Stopped;
  end
  else if AElapsedMs >= UInt64(ALimitMs) then
  begin
    Result := TAtlasEventPauseOutcome.TimedOut;
  end
  else
  begin
    Result := TAtlasEventPauseOutcome.Waiting;
  end;
end;

class function TAtlasEventBreakWatch.ArmCount(ACount: Integer): TAtlasEventArmCount;
begin
  if ACount = 0 then
  begin
    Result := TAtlasEventArmCount.Empty;
  end
  else if ACount > TAtlasEventBreak.cManyBreakpoints then
  begin
    Result := TAtlasEventArmCount.Many;
  end
  else
  begin
    Result := TAtlasEventArmCount.Normal;
  end;
end;

class function TAtlasEventBreakWatch.CountChoice(const AChoice: TAtlasEventChoice): TAtlasEventChoice;
begin
  Result := AChoice;
  if Result.Scope = TAtlasEventScope.VisibleForms then
  begin
    Result.Scope := TAtlasEventScope.AllForms;
  end;
end;

class function TAtlasEventBreakWatch.NeedsSender(const ALocation: TAtlasEventLocation): Boolean;
begin
  Result := Length(ALocation.Handlers) > 1;
end;

class function TAtlasEventBreakWatch.FormCount(const AValue: string; out ACount: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(AValue), ACount) and (ACount >= 0);
end;

class function TAtlasEventBreakWatch.IsTrue(const AValue: string): Boolean;
begin
  Result := SameText(Trim(AValue), 'True');
end;

end.
