unit Atlas.UI.VersionControl.SettingsKind;

// Bereich „Versionsverwaltung“ (#1285): Art (vcs.provider) und Links auf die Seiten, die die
// Anzeige steuern (Editor, Willkommensseite, Issue-Tracker); ein Link erscheint nur, wenn es die Einstellung im
// Dialog gibt (Host.Shows).

interface

uses
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.VersionControl.SettingsPart;

type
  TAtlasSettingsVcsPart = class(TAtlasVcsSettingsPart)
  public const
    /// <summary>Ziele der Links: Rinne im Editor (Base), Einstellungen der Module Willkommensseite und Tracker.
    /// </summary>
    cEditorTarget = 'editor.gitGutter';
    cWelcomeTarget = 'welcomePage.refreshVcs';
    cIssuesTarget = 'issues.branchPattern';
  private
    FVcsProvider: TAtlasChoiceBox;
    FVcsLinkEditor: TButton;
    FVcsLinkWelcome: TButton;
    FVcsLinkIssues: TButton;
    function AddVcsLink(AParent: TWinControl; ALeft: Integer; ACaption: TAtlasVcsTextId): TButton;
    procedure VcsLinkClick(Sender: TObject);
  public
    procedure Build; override;
    /// <summary>Links, nachdem die übrigen Teile stehen.</summary>
    procedure Build2;
    procedure WindowReady; override;
    procedure Attached(APage: TAtlasVcsSettingsOwner); override;
    /// <summary>Name der Art („Automatisch“, „Git“, „SVN“, „Aus“) zu "auto", "git", "svn", "off".</summary>
    class function VcsProviderCaption(const AProvider: string): string; static;
    property VcsProviderChoice: TAtlasChoiceBox read FVcsProvider;
    property VcsLinkEditor: TButton read FVcsLinkEditor;
    property VcsLinkWelcome: TButton read FVcsLinkWelcome;
    property VcsLinkIssues: TButton read FVcsLinkIssues;
  end;

implementation

uses
  System.StrUtils,
  Vcl.Graphics;

{ TAtlasSettingsVcsPart }

procedure TAtlasSettingsVcsPart.Build;
begin
  // Art (#571): Reihenfolge wie die Werte von vcs.provider (auto, git, svn, off).
  AddTitle(TAtlasVcsTextId.SettingsVcsKindTitle);
  FVcsProvider := AddChoice('vcs.provider', TAtlasVcsTextId.SettingsVcsProvider,
    [TAtlasVcsTextId.SettingsVcsProviderAuto, TAtlasVcsTextId.SettingsVcsProviderGit,
    TAtlasVcsTextId.SettingsVcsProviderSvn, TAtlasVcsTextId.SettingsVcsProviderOff],
    TArray<string>.Create('auto', 'git', 'svn', 'off'));
  FVcsProvider.Width := FVcsProvider.ScaleValue(220);
end;

procedure TAtlasSettingsVcsPart.Build2;
var
  mPanel: TWinControl;
begin
  // Seiten, die die Anzeige steuern: Verhalten unter vcs.*, dort nur, ob etwas erscheint (wie #1280).
  AddTitle(TAtlasVcsTextId.SettingsVcsLinksTitle);
  AddWrappedLabel(36, TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsLinksHint)).Font.Color := clGrayText;
  mPanel := AddPanel(32);
  FVcsLinkEditor := AddVcsLink(mPanel, 0, TAtlasVcsTextId.SettingsVcsLinkEditor);
  FVcsLinkWelcome := AddVcsLink(mPanel, 156, TAtlasVcsTextId.SettingsVcsLinkWelcome);
  FVcsLinkIssues := AddVcsLink(mPanel, 312, TAtlasVcsTextId.SettingsVcsLinkIssues);
end;

function TAtlasSettingsVcsPart.AddVcsLink(AParent: TWinControl; ALeft: Integer; ACaption: TAtlasVcsTextId): TButton;
begin
  Result := TButton.Create(FPage);
  Result.Parent := AParent;
  Result.Caption := TAtlasVcsStrings.Text(ACaption);
  Result.Left := ALeft;
  Result.Top := Result.ScaleValue(3);
  Result.Width := Result.ScaleValue(150);
  Result.OnClick := VcsLinkClick;
end;

procedure TAtlasSettingsVcsPart.VcsLinkClick(Sender: TObject);
begin
  if FPage = nil then
  begin
    Exit;
  end;
  if Sender = FVcsLinkEditor then
  begin
    Host.Reveal(cEditorTarget);
  end
  else if Sender = FVcsLinkWelcome then
  begin
    Host.Reveal(cWelcomeTarget);
  end
  else if Sender = FVcsLinkIssues then
  begin
    Host.Reveal(cIssuesTarget);
  end;
end;

class function TAtlasSettingsVcsPart.VcsProviderCaption(const AProvider: string): string;
begin
  case IndexText(AProvider, ['git', 'svn', 'off']) of
    0:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderGit);
    1:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderSvn);
    2:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderOff);
  else
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsProviderAuto);
  end;
end;

procedure TAtlasSettingsVcsPart.WindowReady;
begin
  // Erst jetzt stehen die Abschnitte aller Module.
  FVcsLinkEditor.Visible := Host.Shows(cEditorTarget);
  FVcsLinkWelcome.Visible := Host.Shows(cWelcomeTarget);
  FVcsLinkIssues.Visible := Host.Shows(cIssuesTarget);
end;

procedure TAtlasSettingsVcsPart.Attached(APage: TAtlasVcsSettingsOwner);
begin
  inherited Attached(APage);
  if APage = nil then
  begin
    FVcsProvider := nil;
    FVcsLinkEditor := nil;
    FVcsLinkWelcome := nil;
    FVcsLinkIssues := nil;
  end;
end;

end.
