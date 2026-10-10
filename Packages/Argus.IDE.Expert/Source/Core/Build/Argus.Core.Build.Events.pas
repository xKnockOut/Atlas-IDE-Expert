unit Argus.Core.Build.Events;

// Compile-Ereignisse der IDE (#527), ohne Open Tools API: Die IDE-Schicht
// meldet Beginn und Ende von Gruppenlauf und Projekten, der Dienst misst die
// Dauer, verteilt die Ereignisse an die Teilnehmer und sendet sie als
// argus/compileStarted bzw. argus/compileFinished an den Server.
//
// - Vor dem Compile fragt BeforeCompile alle Teilnehmer, ob abgebrochen
//   werden soll; der erste Grund gewinnt.
// - Hintergrund-Kompilierungen der Code Insight zählen nur mit (Anzahl,
//   Dauer); sie lösen keine Teilnehmer und keine Abbrüche aus.
// - Ein Projekt, das schon läuft, beginnt nicht noch einmal (zwei Notifier
//   der IDE melden denselben Lauf).
// - Ausnahmen eines Teilnehmers gehen ins Protokoll; der Build und die
//   übrigen Teilnehmer laufen weiter.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  TArgusCompileKind = (Make, Build, Check, MakeUnit, Clean, Link);

  TArgusCompileProject = record
    FileName: string;
    Kind: TArgusCompileKind;
    Configuration: string;
    Platform: string;
    OutputFile: string;
  end;

  /// <summary>Teilnehmer an den Compile-Ereignissen; alle Methoden sind optional.</summary>
  TArgusCompileParticipant = class
  public
    procedure GroupStarted(AKind: TArgusCompileKind); virtual;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); virtual;
    /// <summary>True bricht den Compile ab; AReason erscheint im Meldungsfenster.</summary>
    function CancelCompile(const AProject: TArgusCompileProject; out AReason: string): Boolean; virtual;
    procedure ProjectStarted(const AProject: TArgusCompileProject); virtual;
    procedure ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean; ADurationMs: Int64); virtual;
  end;

  TArgusClockFunc = reference to function: Int64;
  TArgusNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);
  TArgusTextProc = reference to procedure(const AText: string);

  TArgusCompileEvents = class
  private type
    TRunning = record
      Project: TArgusCompileProject;
      Started: Int64;
    end;
  private
    FParticipants: TObjectList<TArgusCompileParticipant>;
    FRunning: TList<TRunning>;
    FClock: TArgusClockFunc;
    FOnNotify: TArgusNotifyProc;
    FOnLog: TArgusTextProc;
    FGroupStarted: Int64;
    FInGroup: Boolean;
    FCodeInsightStarted: Int64;
    FCodeInsightCount: Integer;
    FCodeInsightMs: Int64;
    function Now_: Int64;
    function RunningIndex(const AFileName: string): Integer;
    procedure Notify(const AMethod: string; AParams: TJSONObject);
    procedure Guard(const AWhat: string; const AAction: TProc);
  public
    constructor Create(const AClock: TArgusClockFunc = nil);
    destructor Destroy; override;
    /// <summary>Der Dienst übernimmt AParticipant.</summary>
    procedure Add(AParticipant: TArgusCompileParticipant);
    procedure GroupStarted(AKind: TArgusCompileKind);
    procedure GroupFinished(ASucceeded: Boolean);
    /// <summary>Vor einem Compile: True = abbrechen, AReason nennt den Grund. Code Insight bricht nie ab.</summary>
    function BeforeCompile(const AProject: TArgusCompileProject; AIsCodeInsight: Boolean; out AReason: string): Boolean;
    /// <summary>Ende einer Code-Insight-Kompilierung (nur gezählt).</summary>
    procedure CodeInsightFinished;
    procedure ProjectStarted(const AProject: TArgusCompileProject);
    procedure ProjectFinished(const AFileName: string; ASucceeded: Boolean);
    class function KindText(AKind: TArgusCompileKind): string; static;
    property CodeInsightCount: Integer read FCodeInsightCount;
    property CodeInsightMs: Int64 read FCodeInsightMs;
    property OnNotify: TArgusNotifyProc read FOnNotify write FOnNotify;
    property OnLog: TArgusTextProc read FOnLog write FOnLog;
  end;

  /// <summary>Schreibt jedes Ereignis als Zeile, z. B. ins Diagnoseprotokoll.</summary>
  TArgusCompileLog = class(TArgusCompileParticipant)
  private
    FEvents: TArgusCompileEvents;
    FWrite: TArgusTextProc;
  public
    /// <summary>AEvents liefert die Zahlen der Code-Insight-Kompilierungen.</summary>
    constructor Create(AEvents: TArgusCompileEvents; const AWrite: TArgusTextProc);
    procedure GroupStarted(AKind: TArgusCompileKind); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
    procedure ProjectStarted(const AProject: TArgusCompileProject); override;
    procedure ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

implementation

uses
  System.Diagnostics;

{ TArgusCompileLog }

constructor TArgusCompileLog.Create(AEvents: TArgusCompileEvents; const AWrite: TArgusTextProc);
begin
  inherited Create;
  FEvents := AEvents;
  FWrite := AWrite;
end;

procedure TArgusCompileLog.GroupStarted(AKind: TArgusCompileKind);
begin
  FWrite(Format('Compile: Gruppe %s beginnt', [TArgusCompileEvents.KindText(AKind)]));
end;

procedure TArgusCompileLog.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
const
  Results: array[Boolean] of string = ('fehlgeschlagen', 'erfolgreich');
begin
  FWrite(Format('Compile: Gruppe %s nach %d ms; Code Insight bisher %d-mal, %d ms',
    [Results[ASucceeded], ADurationMs, FEvents.CodeInsightCount, FEvents.CodeInsightMs]));
end;

procedure TArgusCompileLog.ProjectStarted(const AProject: TArgusCompileProject);
begin
  FWrite(Format('Compile: %s %s (%s, %s) beginnt', [TArgusCompileEvents.KindText(AProject.Kind),
    ExtractFileName(AProject.FileName), AProject.Configuration, AProject.Platform]));
end;

procedure TArgusCompileLog.ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
const
  Results: array[Boolean] of string = ('fehlgeschlagen', 'erfolgreich');
begin
  FWrite(Format('Compile: %s %s nach %d ms', [ExtractFileName(AProject.FileName), Results[ASucceeded], ADurationMs]));
end;

{ TArgusCompileParticipant }

procedure TArgusCompileParticipant.GroupStarted(AKind: TArgusCompileKind);
begin
end;

procedure TArgusCompileParticipant.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
end;

function TArgusCompileParticipant.CancelCompile(const AProject: TArgusCompileProject; out AReason: string): Boolean;
begin
  AReason := '';
  Result := False;
end;

procedure TArgusCompileParticipant.ProjectStarted(const AProject: TArgusCompileProject);
begin
end;

procedure TArgusCompileParticipant.ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
end;

{ TArgusCompileEvents }

constructor TArgusCompileEvents.Create(const AClock: TArgusClockFunc);
begin
  inherited Create;
  FParticipants := TObjectList<TArgusCompileParticipant>.Create(True);
  FRunning := TList<TRunning>.Create;
  FClock := AClock;
end;

destructor TArgusCompileEvents.Destroy;
begin
  FRunning.Free;
  FParticipants.Free;
  inherited;
end;

function TArgusCompileEvents.Now_: Int64;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

procedure TArgusCompileEvents.Add(AParticipant: TArgusCompileParticipant);
begin
  FParticipants.Add(AParticipant);
end;

class function TArgusCompileEvents.KindText(AKind: TArgusCompileKind): string;
const
  Texts: array[TArgusCompileKind] of string = ('make', 'build', 'check', 'makeUnit', 'clean', 'link');
begin
  Result := Texts[AKind];
end;

procedure TArgusCompileEvents.Notify(const AMethod: string; AParams: TJSONObject);
begin
  if Assigned(FOnNotify) then
    FOnNotify(AMethod, AParams)
  else
    AParams.Free;
end;

procedure TArgusCompileEvents.Guard(const AWhat: string; const AAction: TProc);
begin
  try
    AAction();
  except
    on E: Exception do
      if Assigned(FOnLog) then
        FOnLog(Format('Compile-Ereignis %s: %s: %s', [AWhat, E.ClassName, E.Message]));
  end;
end;

function TArgusCompileEvents.RunningIndex(const AFileName: string): Integer;
begin
  for Result := 0 to FRunning.Count - 1 do
    if SameText(FRunning[Result].Project.FileName, AFileName) then
      Exit;
  Result := -1;
end;

procedure TArgusCompileEvents.GroupStarted(AKind: TArgusCompileKind);
var
  Participant: TArgusCompileParticipant;
begin
  // Ein neuer Gruppenlauf ersetzt einen nicht beendeten (z. B. Hintergrund-Compile ohne Ende).
  FInGroup := True;
  FGroupStarted := Now_;
  for Participant in FParticipants do
    Guard(Participant.ClassName, procedure begin Participant.GroupStarted(AKind); end);
  Notify('argus/compileStarted', TJSONObject.Create.AddPair('group', TJSONBool.Create(True))
    .AddPair('kind', KindText(AKind)));
end;

procedure TArgusCompileEvents.GroupFinished(ASucceeded: Boolean);
var
  Participant: TArgusCompileParticipant;
  Duration: Int64;
begin
  if not FInGroup then
    Exit;
  FInGroup := False;
  Duration := Now_ - FGroupStarted;
  for Participant in FParticipants do
    Guard(Participant.ClassName, procedure begin Participant.GroupFinished(ASucceeded, Duration); end);
  Notify('argus/compileFinished', TJSONObject.Create.AddPair('group', TJSONBool.Create(True))
    .AddPair('success', TJSONBool.Create(ASucceeded)).AddPair('durationMs', TJSONNumber.Create(Duration)));
end;

function TArgusCompileEvents.BeforeCompile(const AProject: TArgusCompileProject; AIsCodeInsight: Boolean;
  out AReason: string): Boolean;
var
  Participant: TArgusCompileParticipant;
  Cancel: Boolean;
  Reason: string;
begin
  AReason := '';
  Result := False;
  if AIsCodeInsight then
  begin
    FCodeInsightStarted := Now_;
    Inc(FCodeInsightCount);
    Exit;
  end;
  for Participant in FParticipants do
  begin
    Cancel := False;
    Reason := '';
    Guard(Participant.ClassName, procedure begin Cancel := Participant.CancelCompile(AProject, Reason); end);
    if Cancel then
    begin
      AReason := Format('%s: %s', [ExtractFileName(AProject.FileName), Reason]);
      Exit(True);
    end;
  end;
end;

procedure TArgusCompileEvents.CodeInsightFinished;
begin
  if FCodeInsightStarted <> 0 then
    Inc(FCodeInsightMs, Now_ - FCodeInsightStarted);
  FCodeInsightStarted := 0;
end;

function ProjectJson(const AProject: TArgusCompileProject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AProject.FileName);
  Result.AddPair('kind', TArgusCompileEvents.KindText(AProject.Kind));
  Result.AddPair('configuration', AProject.Configuration);
  Result.AddPair('platform', AProject.Platform);
  if AProject.OutputFile <> '' then
    Result.AddPair('output', AProject.OutputFile);
end;

procedure TArgusCompileEvents.ProjectStarted(const AProject: TArgusCompileProject);
var
  Participant: TArgusCompileParticipant;
  Running: TRunning;
begin
  if (AProject.FileName = '') or (RunningIndex(AProject.FileName) >= 0) then
    Exit;
  Running.Project := AProject;
  Running.Started := Now_;
  FRunning.Add(Running);
  for Participant in FParticipants do
    Guard(Participant.ClassName, procedure begin Participant.ProjectStarted(AProject); end);
  Notify('argus/compileStarted', ProjectJson(AProject));
end;

procedure TArgusCompileEvents.ProjectFinished(const AFileName: string; ASucceeded: Boolean);
var
  Participant: TArgusCompileParticipant;
  Index: Integer;
  Running: TRunning;
  Duration: Int64;
  Params: TJSONObject;
begin
  Index := RunningIndex(AFileName);
  if Index < 0 then
    Exit;
  Running := FRunning[Index];
  FRunning.Delete(Index);
  Duration := Now_ - Running.Started;
  for Participant in FParticipants do
    Guard(Participant.ClassName,
      procedure
      begin
        Participant.ProjectFinished(Running.Project, ASucceeded, Duration);
      end);
  Params := ProjectJson(Running.Project);
  Params.AddPair('success', TJSONBool.Create(ASucceeded));
  Params.AddPair('durationMs', TJSONNumber.Create(Duration));
  Notify('argus/compileFinished', Params);
end;

end.