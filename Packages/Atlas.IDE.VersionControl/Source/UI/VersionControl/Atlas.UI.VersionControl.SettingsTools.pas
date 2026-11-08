unit Atlas.UI.VersionControl.SettingsTools;

// Versionsverwaltung: Programme git und svn mit eigenem Pfad, „…“ und „Prüfen“ (#1285, seit #1905 im Modul). Die
// Pfade (vcs.git.path, vcs.svn.path) sind gebundene Felder der Seite.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools,
  Atlas.Core.VersionControl.ToolCheck,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.UI.VersionControl.SettingsPart;

type
  /// <summary>Fundort von git bzw. svn für den eingetragenen Pfad APath (#1285), nur Dateiprüfung, kein Prozess.
  /// </summary>
  TAtlasVcsLocateEvent = reference to function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
  /// <summary>„Prüfen“ (#1285) für git bzw. svn unter APath im Hintergrund; das Ergebnis meldet VcsCheckDone.
  /// </summary>
  TAtlasVcsCheckEvent = reference to procedure(AKind: TAtlasVcsKind; const APath: string);

type
  /// <summary>Versionsverwaltung: Programme git und svn mit eigenem Pfad, „…“ und „Prüfen“ (#1285).</summary>
  TAtlasSettingsVcsToolsPart = class(TAtlasVcsSettingsPart)
  private
    FVcsPaths: array[TAtlasVcsKind] of TEdit;
    FVcsBrowse: array[TAtlasVcsKind] of TButton;
    FVcsCheck: array[TAtlasVcsKind] of TButton;
    FVcsStates: array[TAtlasVcsKind] of TLabel;
    FOnVcsLocate: TAtlasVcsLocateEvent;
    FOnVcsCheck: TAtlasVcsCheckEvent;
    procedure AddVcsTool(AKind: TAtlasVcsKind; const AKey: string; ACaption: TAtlasVcsTextId);
    procedure VcsPathChange(Sender: TObject);
    procedure VcsBrowseClick(Sender: TObject);
    procedure VcsCheckClick(Sender: TObject);
    /// <summary>Zustand ohne Prozess: welche Datei für AKind gälte (OnVcsLocate).</summary>
    procedure RefreshVcsTool(AKind: TAtlasVcsKind);
  public
    procedure Build; override;
    procedure Load(const AValues: IAtlasSettingsValues); override;
    procedure Attached(APage: TAtlasVcsSettingsOwner); override;
    /// <summary>Ergebnis von „Prüfen“ zeigen.</summary>
    procedure VcsCheckDone(const ACheck: TAtlasVcsToolCheck);
    /// <summary>Fundort als Text: „PATH“, „bekannter Ordner“, „eigener Pfad“.</summary>
    class function VcsSourceText(ASource: TAtlasVcsToolSource): string; static;
    /// <summary>Zustand ohne Prozess: „verwendet: &lt;Pfad&gt; (PATH)“, „fehlt“, „fehlt: &lt;Pfad&gt; …“.</summary>
    class function VcsLocationText(const ALocation: TAtlasVcsToolLocation): string; static;
    /// <summary>Ergebnis von „Prüfen“: „gefunden · git version 2.47.1 · &lt;Pfad&gt; (PATH)“ usw.</summary>
    class function VcsCheckText(const ACheck: TAtlasVcsToolCheck): string; static;
    function VcsPath(AKind: TAtlasVcsKind): TEdit;
    function VcsCheckButton(AKind: TAtlasVcsKind): TButton;
    function VcsState(AKind: TAtlasVcsKind): TLabel;
    /// <summary>Versionsverwaltung (#1285): Fundort ohne Prozess für den eingetragenen Pfad; nil = keine Anzeige.
    /// </summary>
    property OnVcsLocate: TAtlasVcsLocateEvent read FOnVcsLocate write FOnVcsLocate;
    /// <summary>„Prüfen“ im Hintergrund; das Ergebnis meldet VcsCheckDone.</summary>
    property OnVcsCheck: TAtlasVcsCheckEvent read FOnVcsCheck write FOnVcsCheck;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Dialogs;

{ TAtlasSettingsVcsToolsPart }

procedure TAtlasSettingsVcsToolsPart.Build;
begin
  // Programme: eigener Pfad mit „…“ und „Prüfen“, darunter der Zustand.
  AddTitle(TAtlasVcsTextId.SettingsVcsToolsTitle);
  AddVcsTool(TAtlasVcsKind.Git, 'vcs.git.path', TAtlasVcsTextId.SettingsVcsGitPath);
  AddVcsTool(TAtlasVcsKind.Svn, 'vcs.svn.path', TAtlasVcsTextId.SettingsVcsSvnPath);
end;

procedure TAtlasSettingsVcsToolsPart.AddVcsTool(AKind: TAtlasVcsKind; const AKey: string; ACaption: TAtlasVcsTextId);
var
  mPanel: TWinControl;
  mEdit: TEdit;
  mButton: TButton;
  mState: TLabel;
begin
  mEdit := Host.AddText(AKey, TAtlasVcsStrings.Text(ACaption)) as TEdit;
  mEdit.Anchors := [akLeft, akTop];
  mEdit.Width := 466 - 2 * 36 - 60;
  mEdit.Tag := Ord(AKind);
  mEdit.OnChange := VcsPathChange;
  mPanel := mEdit.Parent;
  mButton := TButton.Create(FPage);
  mButton.Parent := mPanel;
  mButton.Caption := '…';
  mButton.Left := mEdit.Left + mEdit.Width + 6;
  mButton.Top := 0;
  mButton.Width := 30;
  mButton.Anchors := [akTop, akRight];
  mButton.Tag := Ord(AKind);
  mButton.OnClick := VcsBrowseClick;
  FVcsBrowse[AKind] := mButton;
  mButton := TButton.Create(FPage);
  mButton.Parent := mPanel;
  mButton.Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsCheck);
  mButton.Left := FVcsBrowse[AKind].Left + 36;
  mButton.Top := 0;
  mButton.Width := 90;
  mButton.Anchors := [akTop, akRight];
  mButton.Tag := Ord(AKind);
  mButton.OnClick := VcsCheckClick;
  FVcsCheck[AKind] := mButton;
  FVcsPaths[AKind] := mEdit;
  mPanel := AddPanel(18);
  mState := TLabel.Create(FPage);
  mState.Parent := mPanel;
  mState.Left := 0;
  mState.Top := 0;
  mState.ShowAccelChar := False;
  mState.Font.Color := clGrayText;
  FVcsStates[AKind] := mState;
  Attach(mPanel, mEdit);
end;

function TAtlasSettingsVcsToolsPart.VcsPath(AKind: TAtlasVcsKind): TEdit;
begin
  Result := FVcsPaths[AKind];
end;

function TAtlasSettingsVcsToolsPart.VcsCheckButton(AKind: TAtlasVcsKind): TButton;
begin
  Result := FVcsCheck[AKind];
end;

function TAtlasSettingsVcsToolsPart.VcsState(AKind: TAtlasVcsKind): TLabel;
begin
  Result := FVcsStates[AKind];
end;

class function TAtlasSettingsVcsToolsPart.VcsSourceText(ASource: TAtlasVcsToolSource): string;
begin
  case ASource of
    TAtlasVcsToolSource.Path:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsSourcePath);
    TAtlasVcsToolSource.KnownDir:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsSourceKnownDir);
    TAtlasVcsToolSource.Configured:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsSourceConfigured);
  else
    Result := '';
  end;
end;

class function TAtlasSettingsVcsToolsPart.VcsLocationText(const ALocation: TAtlasVcsToolLocation): string;
begin
  if ALocation.Source = TAtlasVcsToolSource.ConfiguredMissing then
  begin
    Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsToolConfiguredMissing, [ALocation.Configured]);
  end
  else if ALocation.Executable = '' then
  begin
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsToolMissing);
  end
  else
  begin
    Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsToolWouldUse,
      [ALocation.Executable, VcsSourceText(ALocation.Source)]);
  end;
end;

class function TAtlasSettingsVcsToolsPart.VcsCheckText(const ACheck: TAtlasVcsToolCheck): string;
begin
  case ACheck.State of
    TAtlasVcsToolState.Found:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsToolFound,
        [ACheck.Version, ACheck.Location.Executable, VcsSourceText(ACheck.Location.Source)]);
    TAtlasVcsToolState.StartFailed:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsToolStartFailed, [ACheck.ExitCode]);
    TAtlasVcsToolState.NoAnswer:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsToolNoAnswer);
    TAtlasVcsToolState.NotRecognized:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.SettingsVcsToolNotRecognized,
        [TAtlasVcsTools.ProgramName(ACheck.Kind)]);
  else
    Result := VcsLocationText(ACheck.Location);
  end;
end;

procedure TAtlasSettingsVcsToolsPart.RefreshVcsTool(AKind: TAtlasVcsKind);
begin
  if FVcsStates[AKind] = nil then
  begin
    Exit;
  end;
  if not Assigned(FOnVcsLocate) then
  begin
    FVcsStates[AKind].Caption := '';
    Exit;
  end;
  FVcsStates[AKind].Caption := VcsLocationText(FOnVcsLocate(AKind, Trim(FVcsPaths[AKind].Text)));
end;

procedure TAtlasSettingsVcsToolsPart.VcsPathChange(Sender: TObject);
begin
  // Nur Dateiprüfung; „Prüfen“ startet erst auf Klick einen Prozess.
  RefreshVcsTool(TAtlasVcsKind((Sender as TComponent).Tag));
end;

procedure TAtlasSettingsVcsToolsPart.VcsBrowseClick(Sender: TObject);
var
  mKind: TAtlasVcsKind;
  mDialog: TOpenDialog;
begin
  mKind := TAtlasVcsKind((Sender as TComponent).Tag);
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Filter := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    mDialog.FileName := Trim(FVcsPaths[mKind].Text);
    if mDialog.FileName = '' then
    begin
      mDialog.FileName := TAtlasVcsTools.ProgramName(mKind) + '.exe';
    end;
    if mDialog.Execute then
    begin
      FVcsPaths[mKind].Text := mDialog.FileName;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasSettingsVcsToolsPart.VcsCheckClick(Sender: TObject);
var
  mKind: TAtlasVcsKind;
begin
  mKind := TAtlasVcsKind((Sender as TComponent).Tag);
  if not Assigned(FOnVcsCheck) then
  begin
    Exit;
  end;
  FVcsStates[mKind].Caption := TAtlasVcsStrings.Text(TAtlasVcsTextId.SettingsVcsToolChecking);
  Allow(FVcsCheck[mKind], False);
  FOnVcsCheck(mKind, Trim(FVcsPaths[mKind].Text));
end;

procedure TAtlasSettingsVcsToolsPart.VcsCheckDone(const ACheck: TAtlasVcsToolCheck);
begin
  if (ACheck.Kind = TAtlasVcsKind.None) or (FVcsStates[ACheck.Kind] = nil) then
  begin
    Exit;
  end;
  FVcsStates[ACheck.Kind].Caption := VcsCheckText(ACheck);
  Allow(FVcsCheck[ACheck.Kind], True);
end;

procedure TAtlasSettingsVcsToolsPart.Load(const AValues: IAtlasSettingsValues);
begin
  // Die Pfade hat die Seite schon geladen; hier nur der Zustand dazu.
  RefreshVcsTool(TAtlasVcsKind.Git);
  RefreshVcsTool(TAtlasVcsKind.Svn);
end;

procedure TAtlasSettingsVcsToolsPart.Attached(APage: TAtlasVcsSettingsOwner);
var
  mKind: TAtlasVcsKind;
begin
  inherited Attached(APage);
  if APage = nil then
  begin
    for mKind := Low(TAtlasVcsKind) to High(TAtlasVcsKind) do
    begin
      FVcsPaths[mKind] := nil;
      FVcsBrowse[mKind] := nil;
      FVcsCheck[mKind] := nil;
      FVcsStates[mKind] := nil;
    end;
  end;
end;

end.
