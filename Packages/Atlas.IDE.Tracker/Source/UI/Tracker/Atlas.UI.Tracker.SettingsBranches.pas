unit Atlas.UI.Tracker.SettingsBranches;

// Unterpunkt „Versionsverwaltung“ des Issue-Trackers im Optionsdialog (#1903): „Beginnen“, Branch-Muster, Basis des
// Branchs und Commit-Präfix (issues.*, x-node issues.vcs). Sie gehören zur Arbeit an einem Issue, wirken aber nur
// mit der Versionsverwaltung. Fehlt sie, legt der Anbieter keinen Abschnitt an: Der Unterpunkt fällt weg, die
// Werte bleiben gespeichert. Ob sie da ist, fragt Available; das setzt die Composition über den Vertrag der
// Versionsverwaltung (Atlas.UI.* bindet keine Atlas.IDE-Units ein). Den Namen des Moduls kennt der Tracker nicht.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Section;

type
  TAtlasTrackerBranchSection = class(TAtlasSettingsSection)
  public const
    cCommitPatternKey = 'issues.commitPattern';
  public class var
    /// <summary>Ist die Versionsverwaltung da? Setzt die Composition; nil = nein.</summary>
    Available: TFunc<Boolean>;
  private
    FCommitPattern: TEdit;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure Save(const AValues: IAtlasSettingsValues); override;
    procedure Close; override;
    /// <summary>Meldet den Anbieter über AScope an: je Optionsseite ein Abschnitt, solange Available.</summary>
    class procedure ProvideBranches(const AScope: IAtlasModuleScope);
    class function IsAvailable: Boolean;
    property CommitPattern: TEdit read FCommitPattern;
  end;

  /// <summary>Anbieter: ein neuer Abschnitt je Seite, nil ohne Versionsverwaltung.</summary>
  TAtlasTrackerBranchProvider = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    function CreateSection: IAtlasSettingsSection;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Tracker.SettingsSection,
  Atlas.UI.Tracker.Settings.Strings;

{ TAtlasTrackerBranchSection }

function TAtlasTrackerBranchSection.OwnerId: string;
begin
  Result := TAtlasTrackerSettingsSection.cOwnerId;
end;

function TAtlasTrackerBranchSection.AreaId: string;
begin
  Result := TAtlasTrackerSettingsSection.cAreaId;
end;

class function TAtlasTrackerBranchSection.IsAvailable: Boolean;
begin
  Result := Assigned(Available) and Available();
end;

class procedure TAtlasTrackerBranchSection.ProvideBranches(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasSettingsSectionProvider, TAtlasTrackerBranchProvider.Create as IAtlasSettingsSectionProvider);
end;

procedure TAtlasTrackerBranchSection.BuildRows;
begin
  Choice('issues.start', TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesStart),
    TArray<string>.Create(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesStartBranch),
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesStartRemember)),
    TArray<string>.Create(TAtlasPluginSettings.cIssuesStartBranch, TAtlasPluginSettings.cIssuesStartRemember));
  Line('issues.branchPattern', TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesBranchPattern));
  Line('issues.branchBase', TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesBranchBase));
  FCommitPattern := Line(cCommitPatternKey, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesCommitPattern));
end;

procedure TAtlasTrackerBranchSection.Save(const AValues: IAtlasSettingsValues);
begin
  // Nicht gekürzt: Das Leerzeichen am Ende von "{kennung} " trennt Kennung und Nachricht.
  if not Closed and (FCommitPattern <> nil) then
  begin
    AValues.WriteString(cCommitPatternKey, FCommitPattern.Text);
  end;
end;

procedure TAtlasTrackerBranchSection.Close;
begin
  FCommitPattern := nil;
  inherited Close;
end;

{ TAtlasTrackerBranchProvider }

function TAtlasTrackerBranchProvider.CreateSection: IAtlasSettingsSection;
begin
  Result := nil;
  if TAtlasTrackerBranchSection.IsAvailable then
  begin
    Result := TAtlasTrackerBranchSection.Create;
  end;
end;

end.
