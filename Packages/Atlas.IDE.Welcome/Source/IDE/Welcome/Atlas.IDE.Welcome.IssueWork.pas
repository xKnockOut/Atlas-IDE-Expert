unit Atlas.IDE.Welcome.IssueWork;

// Arbeitsstand je Issue für andere Module (#2052, Vertrag
// Atlas.IDE.Contracts.IssueWork): Das Modul stellt IAtlasIssueWork über seinen
// Scope bereit; der Tracker meldet darüber den Wechsel des aktiven Issues und
// bietet nach „Beginnen“ das Wiederherstellen an. Das Objekt fragt die
// laufende Seite bei jedem Aufruf neu und tut ohne sie nichts (Regel 3).

interface

uses
  System.SysUtils,
  Atlas.IDE.Contracts.IssueWork,
  Atlas.IDE.Welcome.ContinueIssues,
  Atlas.IDE.Welcome.Commands;

type
  TAtlasWelcomeIssueWork = class(TInterfacedObject, IAtlasIssueWork)
  private
    FCurrent: TFunc<TAtlasIdeWelcome>;
    /// <summary>Arbeitsstand je Issue der laufenden Seite; nil ohne.</summary>
    function Issues: TAtlasIdeContinueIssues;
  public
    /// <summary>ACurrent: die laufende Seite, nil ohne.</summary>
    constructor Create(const ACurrent: TFunc<TAtlasIdeWelcome>);
    function Enabled: Boolean;
    procedure SaveIssue(const AProject: string; const AIssue: TAtlasIssueWorkIssue);
    function HasState(const AProject, AKey: string): Boolean;
    procedure OfferRestore(const AProject, AKey: string);
    procedure StatusesChanged;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard;

constructor TAtlasWelcomeIssueWork.Create(const ACurrent: TFunc<TAtlasIdeWelcome>);
begin
  inherited Create;
  FCurrent := ACurrent;
end;

function TAtlasWelcomeIssueWork.Issues: TAtlasIdeContinueIssues;
var
  mWelcome: TAtlasIdeWelcome;
begin
  Result := nil;
  if not Assigned(FCurrent) then
  begin
    Exit;
  end;
  mWelcome := FCurrent();
  if (mWelcome <> nil) and (mWelcome.Areas.ContinueWork <> nil) then
  begin
    Result := mWelcome.Areas.ContinueWork.Issues;
  end;
end;

function TAtlasWelcomeIssueWork.Enabled: Boolean;
var
  mIssues: TAtlasIdeContinueIssues;
begin
  mIssues := Issues;
  Result := (mIssues <> nil) and mIssues.Enabled;
end;

procedure TAtlasWelcomeIssueWork.SaveIssue(const AProject: string; const AIssue: TAtlasIssueWorkIssue);
var
  mIssues: TAtlasIdeContinueIssues;
  mProject: string;
  mIssue: TAtlasIssueWorkIssue;
begin
  mIssues := Issues;
  mProject := AProject;
  mIssue := AIssue;
  if mIssues <> nil then
  begin
    // Keine Exception zurück in den Tracker: Sein „Beginnen“ läuft weiter.
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mIssues.SaveIssue(mProject, mIssue);
      end);
  end;
end;

function TAtlasWelcomeIssueWork.HasState(const AProject, AKey: string): Boolean;
var
  mIssues: TAtlasIdeContinueIssues;
begin
  mIssues := Issues;
  Result := (mIssues <> nil) and mIssues.HasState(AProject, AKey);
end;

procedure TAtlasWelcomeIssueWork.OfferRestore(const AProject, AKey: string);
var
  mIssues: TAtlasIdeContinueIssues;
  mProject, mKey: string;
begin
  mIssues := Issues;
  mProject := AProject;
  mKey := AKey;
  if mIssues <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        mIssues.OfferRestore(mProject, mKey);
      end);
  end;
end;

procedure TAtlasWelcomeIssueWork.StatusesChanged;
var
  mIssues: TAtlasIdeContinueIssues;
begin
  mIssues := Issues;
  if mIssues <> nil then
  begin
    mIssues.StatusesChanged;
  end;
end;

end.
