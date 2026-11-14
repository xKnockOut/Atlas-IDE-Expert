unit Atlas.UI.Welcome.TestSupport;

// Gemeinsame Hilfen der Willkommens-Tests (Atlas.UI.Welcome.*.Tests).

interface

uses
  System.Classes,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Frame;

type
  /// <summary>Bereich ohne Inhalt, der seine Aktualisierungen zählt.</summary>
  TTestSection = class(TAtlasWelcomeSectionFrame)
  public
    Updates: Integer;
    procedure UpdateContent; override;
  end;

/// <summary>Meldet für jede Kennung einen TTestSection-Bereich an.</summary>
procedure RegisterViews(const AIds: array of string);

/// <summary>Bereich mit Titel „Titel &lt;Kennung&gt;“ an Reihenfolge und Spalte.</summary>
function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;

/// <summary>Meldet den Abschnitt der Willkommensseite an, wie es das Modul tut; ohne ihn fehlen dessen Zeilen auf
/// der Einstellungsseite. Der Aufrufer ruft Revoke.</summary>
function ProvideWelcomeSettings: IAtlasRegistration;

implementation

uses
  Atlas.Core.Modules.Registry,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Welcome.SettingsSection;

type
  TWelcomeSettingsProvider = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    function CreateSection: IAtlasSettingsSection;
  end;

function TWelcomeSettingsProvider.CreateSection: IAtlasSettingsSection;
var
  mSection: TAtlasWelcomeSettingsSection;
  mIssues, mSprint: TAtlasWelcomeTileSwitch;
begin
  mSection := TAtlasWelcomeSettingsSection.Create;
  Result := mSection;
  // Kacheln des Trackers wie aus dem Kachel-Vertrag (#1903).
  mIssues.Key := 'welcomePage.issues';
  mIssues.Setting := 'WelcomePageIssues';
  mIssues.SettingsKey := 'issues.tracker';
  mSprint.Key := 'welcomePage.sprint';
  mSprint.Setting := 'WelcomePageSprint';
  mSprint.SettingsKey := '';
  mSection.Hooks.TileSwitches := [mIssues, mSprint];
end;

function ProvideWelcomeSettings: IAtlasRegistration;
begin
  Result := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
    TWelcomeSettingsProvider.Create as IAtlasSettingsSectionProvider);
end;

procedure TTestSection.UpdateContent;
begin
  Inc(Updates);
  inherited;
end;

procedure RegisterViews(const AIds: array of string);
var
  mId: string;
begin
  for mId in AIds do
  begin
    TAtlasWelcomeViews.Register(mId,
      function(AOwner: TComponent): TAtlasWelcomeSectionFrame
      begin
        Result := TTestSection.Create(AOwner);
      end);
  end;
end;

function Section(const AId: string; AOrder: Integer; AColumn: TAtlasWelcomeColumn): TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(AId, 'Titel ' + AId, AOrder, AColumn, nil);
end;

end.
