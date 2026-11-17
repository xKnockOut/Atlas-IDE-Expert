unit Atlas.IDE.Tracker.IssuesTracking;

// Arbeit am aktuellen Issue für „Meine Issues“ (aus
// Atlas.IDE.Tracker.IssuesServices gelöst): Tracker nachführen (#1266),
// Zeiterfassung (#1267), Zustand im Statusfeld (#2124) und „Prüfen“ (#2126).
// Legt sie an, verbindet die Zeit mit Statusfeld und Beenden-Dialog (#2123),
// stellt Uhr und Statusfeld auf das aktuelle Issue und hält sie in der
// richtigen Reihenfolge an.

interface

uses
  Atlas.Core.Tracker.TimeLog,
  Atlas.IDE.Tracker.Workflow,
  Atlas.IDE.Tracker.TimeTracking,
  Atlas.IDE.Tracker.IssueState,
  Atlas.IDE.Tracker.Review,
  Atlas.IDE.Tracker.IssuesContext;

type
  TAtlasIdeIssuesTracking = class
  private
    FContext: TAtlasIdeIssuesContext;
    FSync: TAtlasIdeTrackerSync;
    FIssueState: TAtlasIdeIssueState;
    FTime: TAtlasIdeTrackerTime;
    FTimeRef: IInterface;
    FReview: TAtlasIdeIssueReview;
    FReviewRef: IInterface;
    procedure CreateTime(const AHooks: TAtlasIdeIssueStateHooks);
  public
    constructor Create(AContext: TAtlasIdeIssuesContext);
    /// <summary>Stop und Release, falls noch nicht geschehen.</summary>
    destructor Destroy; override;
    /// <summary>Alles anlegen und die Zeiterfassung starten; AHooks wie für das Statusfeld.</summary>
    procedure Start(const AHooks: TAtlasIdeIssueStateHooks);
    /// <summary>„Prüfen“, Statusfeld, Zeiterfassung und Tracker nachführen anhalten (die Zeit vor Sync: schreibt die
    /// letzte Zeit darüber).</summary>
    procedure Stop;
    /// <summary>Tracker nachführen freigeben; erst nach den Ansichten, die ihn nutzen.</summary>
    procedure Release;
    function TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
    /// <summary>Uhr der Zeiterfassung und Statusfeld auf das aktuelle Issue AKey von AProject stellen ('' = keins);
    /// AState ist sein Zustand aus „Meine Issues“ ('' unbekannt).</summary>
    procedure SyncTime(const AProject, AKey, AState: string);
    /// <summary>Befehl Atlas.IssueTimeOpen (#1267): offene Zeitbuchungen zeigen.</summary>
    procedure ShowTimeOpen;
    /// <summary>Tracker nachführen (#1266; nil vor Start bzw. nach Release).</summary>
    property Sync: TAtlasIdeTrackerSync read FSync;
    /// <summary>Zeiterfassung (#1267; nil vor Start bzw. nach Stop).</summary>
    property Time: TAtlasIdeTrackerTime read FTime;
    /// <summary>Zustand im Statusfeld (#2124; nil vor Start bzw. nach Stop).</summary>
    property IssueState: TAtlasIdeIssueState read FIssueState;
    /// <summary>„Prüfen“ (#2126; nil vor Start bzw. nach Stop).</summary>
    property Review: TAtlasIdeIssueReview read FReview;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Diagnostics.Guard;

{ TAtlasIdeIssuesTracking }

constructor TAtlasIdeIssuesTracking.Create(AContext: TAtlasIdeIssuesContext);
begin
  inherited Create;
  FContext := AContext;
end;

destructor TAtlasIdeIssuesTracking.Destroy;
begin
  Stop;
  Release;
  inherited;
end;

procedure TAtlasIdeIssuesTracking.CreateTime(const AHooks: TAtlasIdeIssueStateHooks);
var
  mOwner: TAtlasIdeIssuesTracking;
begin
  mOwner := Self;
  FTime := TAtlasIdeTrackerTime.Create(FSync, AHooks.Provider, AHooks.Report, TAtlasTimeFile.DefaultPath);
  FTimeRef := FTime;
  // Die Zeit zeigt das Feld des Zustands (#2124) mit an.
  FTime.OnStatus :=
    procedure(const AField: TAtlasIdeTimeField)
    begin
      if mOwner.FIssueState <> nil then
      begin
        mOwner.FIssueState.TimeChanged(AField);
      end;
    end;
  FSync.TimeText :=
    function(const AKey: string): string
    begin
      Result := '';
      if mOwner.FTime <> nil then
      begin
        Result := mOwner.FTime.TimeText(AKey);
      end;
    end;
  // Zeit im Beenden-Dialog (#2123).
  FSync.TimeSeconds :=
    function(const AKey: string): Int64
    begin
      Result := 0;
      if mOwner.FTime <> nil then
      begin
        Result := mOwner.FTime.Seconds(AKey);
      end;
    end;
  FSync.TimeBooked :=
    procedure(const AKey: string; ASeconds: Int64)
    begin
      if mOwner.FTime <> nil then
      begin
        mOwner.FTime.Booked(AKey, ASeconds);
      end;
    end;
end;

procedure TAtlasIdeIssuesTracking.Start(const AHooks: TAtlasIdeIssueStateHooks);
begin
  FSync := TAtlasIdeTrackerSync.Create(AHooks.Transport, AHooks.Report);
  FSync.CommentAssist := AHooks.Assist;
  FIssueState := TAtlasIdeIssueState.Create(FSync, AHooks);
  CreateTime(AHooks);
  FReview := TAtlasIdeIssueReview.Create(FContext, FSync);
  FReviewRef := FReview;
  FTime.Start;
end;

procedure TAtlasIdeIssuesTracking.Stop;
begin
  // „Prüfen“ vor Sync: Sein Dialog schreibt über Sync.
  if FReview <> nil then
  begin
    FReview.Stop;
  end;
  FReview := nil;
  FReviewRef := nil;
  if FIssueState <> nil then
  begin
    FIssueState.Stop;
  end;
  if FTime <> nil then
  begin
    FTime.Stop;
  end;
  FTime := nil;
  FTimeRef := nil;
  if FSync <> nil then
  begin
    FSync.Stop;
  end;
  // Nach Sync.Stop kommt keine Antwort eines Übergangs mehr an.
  FreeAndNil(FIssueState);
end;

procedure TAtlasIdeIssuesTracking.Release;
begin
  FreeAndNil(FSync);
end;

function TAtlasIdeIssuesTracking.TimeIssueOf(const AProject, AKey: string): TAtlasTimeIssue;
var
  mTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTimeIssue.None;
  if (AProject = '') or (AKey = '') then
  begin
    Exit;
  end;
  mTarget := FContext.TargetOf(AProject);
  Result := TAtlasTimeIssue.Create(mTarget.Provider, mTarget.Url, mTarget.Project, AKey);
end;

procedure TAtlasIdeIssuesTracking.SyncTime(const AProject, AKey, AState: string);
begin
  // Zuerst das Feld: Die Uhr meldet ihre Zeit gleich dorthin.
  if FIssueState <> nil then
  begin
    FIssueState.SetIssue(TimeIssueOf(AProject, AKey), AState);
  end;
  if FTime <> nil then
  begin
    FTime.SetIssue(TimeIssueOf(AProject, AKey));
  end;
end;

procedure TAtlasIdeIssuesTracking.ShowTimeOpen;
begin
  TAtlasGuard.Run(TAtlasFeature.Tracker,
    procedure
    begin
      if FContext.Started and (FTime <> nil) and TAtlasIdeTrackerTime.Active then
      begin
        FTime.ShowOpen;
      end;
    end);
end;

end.
