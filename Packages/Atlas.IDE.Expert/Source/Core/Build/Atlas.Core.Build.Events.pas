unit Atlas.Core.Build.Events;

// Compile-Ereignisse der IDE (#527), ohne Open Tools API: Die IDE-Schicht
// meldet Beginn und Ende von Gruppenlauf und Projekten, der Dienst misst die
// Dauer, verteilt die Ereignisse an die Teilnehmer und sendet sie als
// atlas/compileStarted bzw. atlas/compileFinished an den Server.
//
// - Vor dem Compile fragt BeforeCompile alle Teilnehmer, ob abgebrochen
//   werden soll; der erste Grund gewinnt. Die Teilnehmer sehen dabei schon
//   Background und RequestedBy des beginnenden Laufs (Release-Wächter #533);
//   nach einem Abbruch erfahren alle über CompileCancelled davon (Läufer #261,
//   Schnellaktion „Öffnen und bauen“ #764).
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
  TAtlasCompileKind = (Make, Build, Check, MakeUnit, Clean, Link);

  TAtlasCompileProject = record
    FileName: string;
    Kind: TAtlasCompileKind;
    Configuration: string;
    Platform: string;
    OutputFile: string;
    /// <summary>Eigene Hintergrundprüfung von Atlas (#548), kein Build des Benutzers.</summary>
    Background: Boolean;
    /// <summary>Wer den Build angestoßen hat: '' = Benutzer, "mcp" = Claude Code über build_project (#261).
    /// </summary>
    RequestedBy: string;
    /// <summary>Dauer des Compiles in ms (#758); setzt nur der Leser des Meldungsfensters nach dem Ende, sonst 0.
    /// </summary>
    DurationMs: Int64;
    /// <summary>Dauer des ganzen Laufs (Gruppe) in ms (#758); 0 = unbekannt.</summary>
    GroupDurationMs: Int64;
  end;

  /// <summary>Teilnehmer an den Compile-Ereignissen; alle Methoden sind optional.</summary>
  TAtlasCompileParticipant = class
  public
    procedure GroupStarted(AKind: TAtlasCompileKind); virtual;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); virtual;
    /// <summary>True bricht den Compile ab; AReason erscheint im Meldungsfenster.</summary>
    function CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean; virtual;
    /// <summary>Ein Teilnehmer hat den Compile von AProject abgebrochen; AReason wie im Meldungsfenster.</summary>
    procedure CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string); virtual;
    procedure ProjectStarted(const AProject: TAtlasCompileProject); virtual;
    procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64); virtual;
  end;

  TAtlasClockFunc = reference to function: Int64;
  TAtlasNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);
  TAtlasTextProc = reference to procedure(const AText: string);

  TAtlasCompileEvents = class
  private type
    TRunning = record
      Project: TAtlasCompileProject;
      Started: Int64;
    end;
  private
    FParticipants: TObjectList<TAtlasCompileParticipant>;
    FRunning: TList<TRunning>;
    FClock: TAtlasClockFunc;
    FOnNotify: TAtlasNotifyProc;
    FOnLog: TAtlasTextProc;
    FGroupStarted: Int64;
    FInGroup: Boolean;
    FCodeInsightStarted: Int64;
    FCodeInsightCount: Integer;
    FCodeInsightMs: Int64;
    FBackground: Boolean;
    FRequestedBy: string;
    function Now_: Int64;
    function RunningIndex(const AFileName: string): Integer;
    procedure Notify(const AMethod: string; AParams: TJSONObject);
    procedure Guard(const AWhat: string; const AAction: TProc);
  public
    constructor Create(const AClock: TAtlasClockFunc = nil);
    destructor Destroy; override;
    /// <summary>Der Dienst übernimmt AParticipant.</summary>
    procedure Add(AParticipant: TAtlasCompileParticipant);
    procedure GroupStarted(AKind: TAtlasCompileKind);
    procedure GroupFinished(ASucceeded: Boolean);
    /// <summary>Vor einem Compile: True = abbrechen, AReason nennt den Grund. Code Insight bricht nie ab.</summary>
    function BeforeCompile(const AProject: TAtlasCompileProject; AIsCodeInsight: Boolean; out AReason: string): Boolean;
    /// <summary>Ende einer Code-Insight-Kompilierung (nur gezählt).</summary>
    procedure CodeInsightFinished;
    procedure ProjectStarted(const AProject: TAtlasCompileProject);
    procedure ProjectFinished(const AFileName: string; ASucceeded: Boolean);
    class function KindText(AKind: TAtlasCompileKind): string; static;
    property CodeInsightCount: Integer read FCodeInsightCount;
    property CodeInsightMs: Int64 read FCodeInsightMs;
    /// <summary>Solange True, sind beginnende Läufe Atlas-eigene Hintergrundprüfungen (#548).</summary>
    property Background: Boolean read FBackground write FBackground;
    /// <summary>Solange gesetzt, tragen beginnende Läufe diesen Auftraggeber (#261), z. B. "mcp".</summary>
    property RequestedBy: string read FRequestedBy write FRequestedBy;
    property OnNotify: TAtlasNotifyProc read FOnNotify write FOnNotify;
    property OnLog: TAtlasTextProc read FOnLog write FOnLog;
  end;

  /// <summary>Schreibt jedes Ereignis als Zeile, z. B. ins Diagnoseprotokoll.</summary>
  TAtlasCompileLog = class(TAtlasCompileParticipant)
  private
    FEvents: TAtlasCompileEvents;
    FWrite: TAtlasTextProc;
  public
    /// <summary>AEvents liefert die Zahlen der Code-Insight-Kompilierungen.</summary>
    constructor Create(AEvents: TAtlasCompileEvents; const AWrite: TAtlasTextProc);
    procedure GroupStarted(AKind: TAtlasCompileKind); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
    procedure ProjectStarted(const AProject: TAtlasCompileProject); override;
    procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

implementation

uses
  System.Diagnostics;

{ TAtlasCompileLog }

constructor TAtlasCompileLog.Create(AEvents: TAtlasCompileEvents; const AWrite: TAtlasTextProc);
begin
  inherited Create;
  FEvents := AEvents;
  FWrite := AWrite;
end;

procedure TAtlasCompileLog.GroupStarted(AKind: TAtlasCompileKind);
begin
  FWrite(Format('Compile: Gruppe %s beginnt', [TAtlasCompileEvents.KindText(AKind)]));
end;

procedure TAtlasCompileLog.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
const
  Results: array[Boolean] of string = ('fehlgeschlagen', 'erfolgreich');
begin
  FWrite(Format('Compile: Gruppe %s nach %d ms; Code Insight bisher %d-mal, %d ms',
    [Results[ASucceeded], ADurationMs, FEvents.CodeInsightCount, FEvents.CodeInsightMs]));
end;

procedure TAtlasCompileLog.ProjectStarted(const AProject: TAtlasCompileProject);
begin
  FWrite(Format('Compile: %s %s (%s, %s) beginnt', [TAtlasCompileEvents.KindText(AProject.Kind),
    ExtractFileName(AProject.FileName), AProject.Configuration, AProject.Platform]));
end;

procedure TAtlasCompileLog.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
const
  Results: array[Boolean] of string = ('fehlgeschlagen', 'erfolgreich');
begin
  FWrite(Format('Compile: %s %s nach %d ms', [ExtractFileName(AProject.FileName), Results[ASucceeded], ADurationMs]));
end;

{ TAtlasCompileParticipant }

procedure TAtlasCompileParticipant.GroupStarted(AKind: TAtlasCompileKind);
begin
end;

procedure TAtlasCompileParticipant.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
end;

function TAtlasCompileParticipant.CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
begin
  AReason := '';
  Result := False;
end;

procedure TAtlasCompileParticipant.CompileCancelled(const AProject: TAtlasCompileProject; const AReason: string);
begin
end;

procedure TAtlasCompileParticipant.ProjectStarted(const AProject: TAtlasCompileProject);
begin
end;

procedure TAtlasCompileParticipant.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
end;

{ TAtlasCompileEvents }

constructor TAtlasCompileEvents.Create(const AClock: TAtlasClockFunc);
begin
  inherited Create;
  FParticipants := TObjectList<TAtlasCompileParticipant>.Create(True);
  FRunning := TList<TRunning>.Create;
  FClock := AClock;
end;

destructor TAtlasCompileEvents.Destroy;
begin
  FRunning.Free;
  FParticipants.Free;
  inherited;
end;

function TAtlasCompileEvents.Now_: Int64;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

procedure TAtlasCompileEvents.Add(AParticipant: TAtlasCompileParticipant);
begin
  FParticipants.Add(AParticipant);
end;

class function TAtlasCompileEvents.KindText(AKind: TAtlasCompileKind): string;
const
  Texts: array[TAtlasCompileKind] of string = ('make', 'build', 'check', 'makeUnit', 'clean', 'link');
begin
  Result := Texts[AKind];
end;

procedure TAtlasCompileEvents.Notify(const AMethod: string; AParams: TJSONObject);
begin
  if Assigned(FOnNotify) then
    FOnNotify(AMethod, AParams)
  else
    AParams.Free;
end;

procedure TAtlasCompileEvents.Guard(const AWhat: string; const AAction: TProc);
begin
  try
    AAction();
  except
    on E: Exception do
      if Assigned(FOnLog) then
        FOnLog(Format('Compile-Ereignis %s: %s: %s', [AWhat, E.ClassName, E.Message]));
  end;
end;

function TAtlasCompileEvents.RunningIndex(const AFileName: string): Integer;
begin
  for Result := 0 to FRunning.Count - 1 do
    if SameText(FRunning[Result].Project.FileName, AFileName) then
      Exit;
  Result := -1;
end;

procedure TAtlasCompileEvents.GroupStarted(AKind: TAtlasCompileKind);
var
  Participant: TAtlasCompileParticipant;
begin
  // Ein neuer Gruppenlauf ersetzt einen nicht beendeten (z. B. Hintergrund-Compile ohne Ende).
  FInGroup := True;
  FGroupStarted := Now_;
  for Participant in FParticipants do
    Guard(Participant.ClassName, procedure begin Participant.GroupStarted(AKind); end);
  Notify('atlas/compileStarted', TJSONObject.Create.AddPair('group', TJSONBool.Create(True))
    .AddPair('kind', KindText(AKind)));
end;

procedure TAtlasCompileEvents.GroupFinished(ASucceeded: Boolean);
var
  Participant: TAtlasCompileParticipant;
  Duration: Int64;
begin
  if not FInGroup then
    Exit;
  FInGroup := False;
  Duration := Now_ - FGroupStarted;
  for Participant in FParticipants do
    Guard(Participant.ClassName, procedure begin Participant.GroupFinished(ASucceeded, Duration); end);
  Notify('atlas/compileFinished', TJSONObject.Create.AddPair('group', TJSONBool.Create(True))
    .AddPair('success', TJSONBool.Create(ASucceeded)).AddPair('durationMs', TJSONNumber.Create(Duration)));
end;

function TAtlasCompileEvents.BeforeCompile(const AProject: TAtlasCompileProject; AIsCodeInsight: Boolean;
  out AReason: string): Boolean;
var
  Participant: TAtlasCompileParticipant;
  Cancel: Boolean;
  Reason, Text: string;
  Info: TAtlasCompileProject;
begin
  AReason := '';
  Result := False;
  if AIsCodeInsight then
  begin
    FCodeInsightStarted := Now_;
    Inc(FCodeInsightCount);
    Exit;
  end;
  // Wie ProjectStarted: Hintergrundprüfung (#548) und Auftraggeber (#261) gelten schon hier.
  Info := AProject;
  Info.Background := FBackground;
  Info.RequestedBy := FRequestedBy;
  for Participant in FParticipants do
  begin
    Cancel := False;
    Reason := '';
    Guard(Participant.ClassName, procedure begin Cancel := Participant.CancelCompile(Info, Reason); end);
    if Cancel then
    begin
      AReason := Format('%s: %s', [ExtractFileName(AProject.FileName), Reason]);
      Result := True;
      Break;
    end;
  end;
  if not Result then
    Exit;
  Text := AReason;
  for Participant in FParticipants do
    Guard(Participant.ClassName, procedure begin Participant.CompileCancelled(Info, Text); end);
end;

procedure TAtlasCompileEvents.CodeInsightFinished;
begin
  if FCodeInsightStarted <> 0 then
    Inc(FCodeInsightMs, Now_ - FCodeInsightStarted);
  FCodeInsightStarted := 0;
end;

function ProjectJson(const AProject: TAtlasCompileProject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AProject.FileName);
  Result.AddPair('kind', TAtlasCompileEvents.KindText(AProject.Kind));
  Result.AddPair('configuration', AProject.Configuration);
  Result.AddPair('platform', AProject.Platform);
  if AProject.OutputFile <> '' then
    Result.AddPair('output', AProject.OutputFile);
  if AProject.Background then
    Result.AddPair('background', TJSONBool.Create(True));
  if AProject.RequestedBy <> '' then
    Result.AddPair('requestedBy', AProject.RequestedBy);
end;

procedure TAtlasCompileEvents.ProjectStarted(const AProject: TAtlasCompileProject);
var
  Participant: TAtlasCompileParticipant;
  Running: TRunning;
begin
  if (AProject.FileName = '') or (RunningIndex(AProject.FileName) >= 0) then
    Exit;
  Running.Project := AProject;
  Running.Project.Background := FBackground;
  Running.Project.RequestedBy := FRequestedBy;
  Running.Started := Now_;
  FRunning.Add(Running);
  for Participant in FParticipants do
    Guard(Participant.ClassName, procedure begin Participant.ProjectStarted(Running.Project); end);
  Notify('atlas/compileStarted', ProjectJson(Running.Project));
end;

procedure TAtlasCompileEvents.ProjectFinished(const AFileName: string; ASucceeded: Boolean);
var
  Participant: TAtlasCompileParticipant;
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
  Notify('atlas/compileFinished', Params);
end;

end.