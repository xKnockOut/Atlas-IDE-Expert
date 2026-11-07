unit Atlas.UI.Settings.Page.Vcs;

// Bereich „Versionsverwaltung“ (#1285): Art (vcs.provider) und Links auf die Seiten, die die Anzeige steuern.

interface

uses
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Bereich „Versionsverwaltung“ (#1285): Art (vcs.provider) und Links auf die Seiten, die die Anzeige
  /// steuern.</summary>
  TAtlasSettingsVcsPart = class(TAtlasSettingsPagePart)
  private
    // Versionsverwaltung (#1285): Art, je Programm Pfad, „…“, „Prüfen“ und Zustand, Zeitlimit, aktuelles Projekt.
    FVcsProvider: TAtlasChoiceBox;
    FVcsLinkEditor: TButton;
    FVcsLinkWelcome: TButton;
    FVcsLinkIssues: TButton;
    function AddVcsLink(AParent: TWinControl; ALeft: Integer; ACaption: TAtlasTextId): TButton;
    procedure VcsLinkClick(Sender: TObject);
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>Links auf Seiten eines Moduls nur, wenn das Modul seine Einstellungen gebracht hat (#1456).
    /// </summary>
    procedure WindowReady; override;
    /// <summary>Art und Name der Art („Automatisch“, „Git“, „SVN“, „Aus“) zu "auto", "git", "svn", "off".
    /// </summary>
    class function VcsProviderCaption(const AProvider: string): string; static;
    /// <summary>Zum Testen: Versionsverwaltung (#1285).</summary>
    property VcsProviderChoice: TAtlasChoiceBox read FVcsProvider;
    property VcsLinkEditor: TButton read FVcsLinkEditor;
    property VcsLinkWelcome: TButton read FVcsLinkWelcome;
    property VcsLinkIssues: TButton read FVcsLinkIssues;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Vcl.Graphics,
  Atlas.UI.Settings.Page.EditorView;

const
  // Ziele der Links: Einstellungen der Module Welcome und Tracker; ohne das Modul fehlt der Link.
  cWelcomeTarget = 'WelcomePageRefreshVcs';
  cIssuesTarget = 'IssuesBranchPattern';

{ TAtlasSettingsVcsPart }

procedure TAtlasSettingsVcsPart.Build;
begin
  // Versionsverwaltung (#1285): neben dem Issue-Tracker; Verhalten unter vcs.*.
  AddSheet(TAtlasTextId.SettingsTabVcs);
  // Art (#571): Reihenfolge wie die Werte von vcs.provider (auto, git, svn, off).
  AddTitle(TAtlasTextId.SettingsVcsKindTitle);
  FVcsProvider := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProvider),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto), TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderGit),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn), TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderOff)]);
  FVcsProvider.Width := 220;
end;

procedure TAtlasSettingsVcsPart.Build2;
var
  mPanel: TWinControl;
begin
  // Seiten, die die Anzeige steuern: Verhalten unter vcs.*, dort nur, ob etwas erscheint (wie #1280).
  AddTitle(TAtlasTextId.SettingsVcsLinksTitle);
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsLinksHint)).Font.Color := clGrayText;
  mPanel := AddPanel(32);
  FVcsLinkEditor := AddVcsLink(mPanel, 0, TAtlasTextId.SettingsVcsLinkEditor);
  FVcsLinkWelcome := AddVcsLink(mPanel, 156, TAtlasTextId.SettingsVcsLinkWelcome);
  FVcsLinkIssues := AddVcsLink(mPanel, 312, TAtlasTextId.SettingsVcsLinkIssues);
end;

function TAtlasSettingsVcsPart.AddVcsLink(AParent: TWinControl; ALeft: Integer; ACaption: TAtlasTextId): TButton;
begin
  Result := TButton.Create(FPage);
  Result.Parent := AParent;
  Result.Caption := TAtlasStrings.Text(ACaption);
  Result.Left := ALeft;
  Result.Top := 3;
  Result.Width := 150;
  Result.OnClick := VcsLinkClick;
end;

procedure TAtlasSettingsVcsPart.VcsLinkClick(Sender: TObject);
begin
  if Sender = FVcsLinkEditor then
  begin
    FPage.SelectPage(FPage.PageOf(FPage.Part<TAtlasSettingsEditorViewPart>.GitGutter));
  end
  else if Sender = FVcsLinkWelcome then
  begin
    FPage.SelectSettingPage(cWelcomeTarget);
  end
  else if Sender = FVcsLinkIssues then
  begin
    FPage.SelectSettingPage(cIssuesTarget);
  end;
end;

class function TAtlasSettingsVcsPart.VcsProviderCaption(const AProvider: string): string;
begin
  case IndexText(AProvider, ['git', 'svn', 'off']) of
    0:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderGit);
    1:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn);
    2:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderOff);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto);
  end;
end;

procedure TAtlasSettingsVcsPart.BindMarks;
begin
  FPage.Marks.Bind(FVcsProvider, ['VcsProvider']);
end;

procedure TAtlasSettingsVcsPart.WindowReady;
begin
  // Die Abschnitte der Module stehen erst nach dem Aufbau der Teile von Base.
  FVcsLinkWelcome.Visible := FPage.ControlOfSetting(cWelcomeTarget) <> nil;
  FVcsLinkIssues.Visible := FPage.ControlOfSetting(cIssuesTarget) <> nil;
end;

procedure TAtlasSettingsVcsPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FVcsProvider.Choice := Max(0, IndexText(ASettings.VcsProvider, ['auto', 'git', 'svn', 'off']));
end;

procedure TAtlasSettingsVcsPart.Save(var ASettings: TAtlasPluginSettings);
begin
  case FVcsProvider.Choice of
    1:
      ASettings.VcsProvider := 'git';
    2:
      ASettings.VcsProvider := 'svn';
    3:
      ASettings.VcsProvider := 'off';
  else
    ASettings.VcsProvider := 'auto';
  end;
end;

end.
