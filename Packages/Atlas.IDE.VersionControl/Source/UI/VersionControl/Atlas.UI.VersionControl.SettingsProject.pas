unit Atlas.UI.VersionControl.SettingsProject;

// Versionsverwaltung: Zeitlimit (vcs.timeoutSeconds) und aktuelles Projekt (#1285, seit #1905 im Modul). Das Projekt
// wird erst abgefragt, wenn sein Reiter gewählt und die Zeile sichtbar ist (einmal je Öffnen; ein Zeitgeber fragt
// CheckShown): Jeder Knoten des Optionsdialogs baut die ganze Seite, ein Prozess soll nur für die gezeigte starten.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.VersionControl.SettingsPart;

type
  /// <summary>Versionsverwaltung: aktuelles Projekt, beim ersten Zeigen des Reiters einmal im Hintergrund abgefragt
  /// (#1285).</summary>
  TAtlasSettingsVcsProjectPart = class(TAtlasVcsSettingsPart)
  private
    FVcsProjectInfo: TLabel;
    FWatch: TTimer;
    /// <summary>„Aktuelles Projekt“ wurde schon abgefragt (einmal je Öffnen der Seite).</summary>
    FVcsProjectAsked: Boolean;
    FOnVcsProject: TProc;
    /// <summary>Art der Arbeitskopie aus der letzten Abfrage „Aktuelles Projekt“ (für „Aktuelles Projekt
    /// hinzufügen“); None ohne.</summary>
    FVcsDetectedKind: TAtlasVcsKind;
    FVcsDetectedProject: string;
    procedure WatchTimer(Sender: TObject);
    /// <summary>Reiter der Zeile gewählt und die Zeile samt Eltern sichtbar?</summary>
    function InfoShown: Boolean;
  public
    procedure Build; override;
    procedure Attached(APage: TAtlasVcsSettingsOwner); override;
    /// <summary>Fragt einmal ab, sobald die Zeile gezeigt wird (sonst nichts); der Zeitgeber ruft es.</summary>
    procedure CheckShown;
    /// <summary>Ergebnis der Abfrage „Aktuelles Projekt“ zeigen.</summary>
    procedure VcsProjectDone(const AState: TAtlasVcsProjectState);
    /// <summary>„Aktuelles Projekt“ jetzt abfragen (sonst beim ersten Zeigen der Seite).</summary>
    procedure RefreshVcsProject;
    /// <summary>Gruppe „Aktuelles Projekt“: Projekt, Art, Wurzel, Branch bzw. SVN-Pfad, Revision, verfolgter
    /// Branch und woher die Art kommt; mehrere Zeilen.</summary>
    class function VcsProjectText(const AState: TAtlasVcsProjectState): string; static;
    /// <summary>„Aktuelles Projekt“ im Hintergrund abfragen; das Ergebnis meldet VcsProjectDone.</summary>
    property OnVcsProject: TProc read FOnVcsProject write FOnVcsProject;
    property VcsProjectInfo: TLabel read FVcsProjectInfo;
    property VcsDetectedKind: TAtlasVcsKind read FVcsDetectedKind;
    property VcsDetectedProject: string read FVcsDetectedProject;
  end;

implementation

uses
  Vcl.Controls,
  Vcl.ComCtrls,
  Atlas.Core.VersionControl.Tools,
  Atlas.UI.Strings;

/// <summary>Woher die Art der Versionsverwaltung kommt, mit dem Hauptbranch, wenn bekannt.</summary>
function VcsSourceText(const AState: TAtlasVcsProjectState): string;
begin
  case AState.Source of
    TAtlasVcsProviderSource.Project:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsSourceProject, [AState.SourceMatch]);
    TAtlasVcsProviderSource.TeamFile:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceTeamFile);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceSetting);
  end;
  if AState.MainBranch <> '' then
  begin
    Result := Result + TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectMainBranch, [AState.MainBranch]);
  end;
end;

/// <summary>Zeile zu einem Ergebnis ohne Arbeitskopie (aus, keine, Programm fehlt, Fehler); leer bei Ok.</summary>
function VcsOutcomeText(const AState: TAtlasVcsProjectState; const AName, AKind: string): string;
begin
  case AState.Outcome of
    TAtlasVcsOutcome.Disabled:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectDisabled, [AName]);
    TAtlasVcsOutcome.NoWorkingCopy:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectNoWorkingCopy, [AName]);
    TAtlasVcsOutcome.ToolMissing:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectToolMissing,
        [AName, AKind, TAtlasVcsTools.ProgramName(AState.WorkingCopy.Kind)]);
    TAtlasVcsOutcome.Ok:
      Result := '';
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectFailed,
      [AName, AKind, AtlasVcsOutcomeName(AState.Outcome)]);
  end;
end;

/// <summary>Branch oder Pfad mit Revision, dazu der Upstream, wenn bekannt.</summary>
function VcsHeadText(const AState: TAtlasVcsProjectState): string;
begin
  if AState.WorkingCopy.Kind = TAtlasVcsKind.Svn then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectSvnPath,
      [AState.Head.Branch, AState.Head.ShortRevision(AState.WorkingCopy.Kind)]);
  end
  else if AState.Head.Detached then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectDetached,
      [AState.Head.ShortRevision(AState.WorkingCopy.Kind)]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectBranch,
      [AState.Head.Branch, AState.Head.ShortRevision(AState.WorkingCopy.Kind)]);
  end;
  if AState.Head.Upstream <> '' then
  begin
    Result := Result + TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectUpstream, [AState.Head.Upstream]);
  end;
end;

{ TAtlasSettingsVcsProjectPart }

procedure TAtlasSettingsVcsProjectPart.Build;
begin
  Host.AddNumber('vcs.timeoutSeconds', TAtlasStrings.Text(TAtlasTextId.SettingsVcsTimeout));
  // Aktuelles Projekt: nur Anzeige, beim ersten Zeigen einmal im Hintergrund abgefragt.
  AddTitle(TAtlasTextId.SettingsVcsProjectTitle);
  FVcsProjectInfo := AddWrappedLabel(70, TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone));
  FWatch := TTimer.Create(FPage);
  FWatch.Interval := 250;
  FWatch.OnTimer := WatchTimer;
end;

class function TAtlasSettingsVcsProjectPart.VcsProjectText(const AState: TAtlasVcsProjectState): string;
var
  mName, mKind, mSource, mProblem: string;
begin
  if AState.ProjectFile = '' then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone));
  end;
  mName := ExtractFileName(AState.ProjectFile);
  mSource := VcsSourceText(AState);
  mKind := AtlasVcsKindName(AState.WorkingCopy.Kind);
  mProblem := VcsOutcomeText(AState, mName, mKind);
  if mProblem <> '' then
  begin
    Exit(mProblem + sLineBreak + mSource);
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectLine, [mName, mKind, AState.WorkingCopy.Root]) +
    sLineBreak + VcsHeadText(AState) + sLineBreak + mSource;
end;

procedure TAtlasSettingsVcsProjectPart.RefreshVcsProject;
begin
  FVcsProjectAsked := True;
  if not Assigned(FOnVcsProject) or (FVcsProjectInfo = nil) then
  begin
    Exit;
  end;
  FVcsProjectInfo.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectQuerying);
  FOnVcsProject();
end;

procedure TAtlasSettingsVcsProjectPart.VcsProjectDone(const AState: TAtlasVcsProjectState);
begin
  if FVcsProjectInfo <> nil then
  begin
    FVcsProjectInfo.Caption := VcsProjectText(AState);
  end;
  // Für „Aktuelles Projekt hinzufügen“: die erkannte Art vorbelegen.
  FVcsDetectedProject := AState.ProjectFile;
  FVcsDetectedKind := AState.WorkingCopy.Kind;
end;

function TAtlasSettingsVcsProjectPart.InfoShown: Boolean;
var
  mControl: TControl;
begin
  Result := False;
  mControl := FVcsProjectInfo;
  while (mControl <> nil) and not (mControl is TTabSheet) do
  begin
    if not mControl.Visible then
    begin
      Exit;
    end;
    mControl := mControl.Parent;
  end;
  Result := (mControl <> nil) and (TTabSheet(mControl).PageControl <> nil) and
    (TTabSheet(mControl).PageControl.ActivePage = mControl);
end;

procedure TAtlasSettingsVcsProjectPart.CheckShown;
begin
  if FVcsProjectAsked or (FVcsProjectInfo = nil) then
  begin
    Exit;
  end;
  if InfoShown then
  begin
    RefreshVcsProject;
  end;
end;

procedure TAtlasSettingsVcsProjectPart.WatchTimer(Sender: TObject);
begin
  CheckShown;
  if FVcsProjectAsked then
  begin
    FWatch.Enabled := False;
  end;
end;

procedure TAtlasSettingsVcsProjectPart.Attached(APage: TAtlasVcsSettingsOwner);
begin
  inherited Attached(APage);
  if APage = nil then
  begin
    // Der Zeitgeber gehört dem Besitzer und geht mit ihm.
    FWatch := nil;
    FVcsProjectInfo := nil;
  end
  else
  begin
    FVcsProjectAsked := False;
  end;
end;

end.
