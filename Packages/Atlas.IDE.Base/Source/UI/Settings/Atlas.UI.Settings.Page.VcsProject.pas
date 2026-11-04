unit Atlas.UI.Settings.Page.VcsProject;

// Versionsverwaltung: aktuelles Projekt, beim ersten Zeigen des Reiters einmal im Hintergrund abgefragt (#1285).

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Versionsverwaltung: aktuelles Projekt, beim ersten Zeigen des Reiters einmal im Hintergrund abgefragt
  /// (#1285).</summary>
  TAtlasSettingsVcsProjectPart = class(TAtlasSettingsPagePart)
  private
    FVcsProjectInfo: TLabel;
    /// <summary>„Aktuelles Projekt“ wurde schon abgefragt (einmal je Öffnen der Seite).</summary>
    FVcsProjectAsked: Boolean;
    FOnVcsProject: TProc;
    /// <summary>Art der Arbeitskopie aus der letzten Abfrage „Aktuelles Projekt“ (für „Aktuelles Projekt
    /// hinzufügen“); None ohne.</summary>
    FVcsDetectedKind: TAtlasVcsKind;
    FVcsDetectedProject: string;
  public
    procedure Build;
    procedure SheetShown(ASheet: TTabSheet); override;
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
  Atlas.Core.Vcs.Tools,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.Vcs;

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
  BindText('VcsTimeoutSeconds', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsVcsTimeout)));
  // Aktuelles Projekt: nur Anzeige, beim ersten Zeigen der Seite einmal im Hintergrund abgefragt.
  AddTitle(TAtlasTextId.SettingsVcsProjectTitle);
  FVcsProjectInfo := AddWrappedLabel(70, TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone));
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
  if not Assigned(FOnVcsProject) then
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

procedure TAtlasSettingsVcsProjectPart.SheetShown(ASheet: TTabSheet);
var
  mParent: TControl;
begin
  if (ASheet = nil) or FVcsProjectAsked or (FPage.Part<TAtlasSettingsVcsPart>.VcsProviderChoice = nil) then
  begin
    Exit;
  end;
  mParent := FPage.Part<TAtlasSettingsVcsPart>.VcsProviderChoice;
  while (mParent <> nil) and (mParent <> ASheet) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent <> nil then
  begin
    RefreshVcsProject;
  end;
end;

end.
