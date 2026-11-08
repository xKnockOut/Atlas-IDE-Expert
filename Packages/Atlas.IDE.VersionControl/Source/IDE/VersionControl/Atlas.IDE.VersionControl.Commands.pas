unit Atlas.IDE.VersionControl.Commands;

// Befehle des Moduls Versionsverwaltung (#1905, vorher in der Palette von Base): „Branch anlegen …“ (#1288,
// Atlas.CreateBranch, immer mit Dialog) und „Arbeitskopien“ (#1292, Atlas.WorkingCopies, sichtbar mit
// vcs.externals.show) für die Arbeitskopie des aktiven Projekts. Base fragt die Befehle bei jedem Öffnen der
// Palette bzw. des Menüs (IAtlasCommandSource); nach dem Abmelden des Moduls erreicht sie nichts mehr (Regel 3).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasVcsCommands = class(TInterfacedObject, IAtlasCommandSource)
  public const
    cCreateBranch = 'Atlas.CreateBranch';
    cWorkingCopies = 'Atlas.WorkingCopies';
  public
    function Commands: TArray<TAtlasModuleCommand>;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Contracts.VersionControl;

/// <summary>Projektdatei des aktiven Projekts mit Versionsverwaltung; '' ohne, dann die Meldung ANoVcs.</summary>
function VcsProject(ANoVcs: TAtlasVcsTextId): string;
begin
  Result := TAtlasIdeProjectSummaries.ProjectFileOf(TAtlasIdeTeamFile.ActiveProject);
  if Result = '' then
  begin
    TAtlasIdeVcs.Report(TAtlasVcsStrings.Text(ANoVcs));
  end;
end;

/// <summary>Zusammenfassung des Projekts nach einer Änderung der Arbeitskopie neu lesen.</summary>
function RefreshSummary(const AProject: string): TProc;
var
  mProject: string;
begin
  mProject := AProject;
  Result :=
    procedure
    begin
      if TAtlasIdeProjectSummaries.Current <> nil then
      begin
        TAtlasIdeProjectSummaries.Current.Refresh(mProject);
      end;
    end;
end;

procedure CreateBranch;
var
  mProject: string;
begin
  mProject := VcsProject(TAtlasVcsTextId.VcsBranchNoVcs);
  if mProject <> '' then
  begin
    TAtlasIdeVcs.Dialogs.CreateBranchFor(mProject, RefreshSummary(mProject));
  end;
end;

procedure ShowWorkingCopies;
var
  mProject: string;
begin
  mProject := VcsProject(TAtlasVcsTextId.VcsWorkingCopiesNoVcs);
  if mProject <> '' then
  begin
    TAtlasIdeVcs.Dialogs.ShowWorkingCopies(mProject, RefreshSummary(mProject));
  end;
end;

function Guarded(const AProc: TProc): TProc;
var
  mProc: TProc;
begin
  mProc := AProc;
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Palette, mProc);
    end;
end;

function WorkingCopiesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.VcsExternalsShow;
end;

function Command(const AId: string; ACaption: TAtlasVcsTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasVcsStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

{ TAtlasVcsCommands }

function TAtlasVcsCommands.Commands: TArray<TAtlasModuleCommand>;
begin
  SetLength(Result, 2);
  Result[0] := Command(cCreateBranch, TAtlasVcsTextId.VcsBranchCommand, Guarded(CreateBranch), nil);
  Result[1] := Command(cWorkingCopies, TAtlasVcsTextId.VcsWorkingCopiesCommand, Guarded(ShowWorkingCopies),
    WorkingCopiesVisible);
end;

end.
