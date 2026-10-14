unit Setup.Shell.MainForm;

// Installer (#495): Hauptfenster, im Code aufgebaut (kein DFM).
// - Installieren: gefundene IDEs als Kontrollkästchen; nicht angebotene
//   (nicht unterstützt, Paket fehlt) sind sichtbar, aber gesperrt. Vor dem
//   Kopieren werden laufende IDEs gemeldet, mit „Wiederholen“ und „Abbrechen“.
// - Deinstallieren (/uninstall, aus „Apps und Features“): Kontrollkästchen für
//   Einstellungen, Index und Protokolle sowie Snippets, alle aus.
// Jeder Schritt erscheint im Protokollfeld.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.CheckLst,
  Setup.Core.Contract,
  Setup.Core.Ides,
  Setup.Core.Installer;

type
  TSetupMainForm = class(TForm)
  private class var
    FConfigSystem: ISetupSystem;
    FConfigPaths: TSetupPaths;
    FConfigVersion: string;
    FConfigUninstall: Boolean;
  private
    FInstaller: TSetupInstaller;
    FIdes: TArray<TSetupIde>;
    FUninstallMode: Boolean;
    FIdeList: TCheckListBox;
    FDataBoxes: array[TSetupData] of TCheckBox;
    FLog: TMemo;
    FActionButton: TButton;
    FCloseButton: TButton;
    procedure BuildInstall(var ATop: Integer);
    procedure BuildUninstall(var ATop: Integer);
    function AddLabel(const ACaption: string; var ATop: Integer): TLabel;
    /// <summary>Ohne const: passt so zu TProc&lt;TSetupStep&gt;.</summary>
    procedure Step(AStep: TSetupStep);
    function WaitForClosedIdes(const AIdes: TArray<TSetupIde>): Boolean;
    function SelectedIdes: TArray<TSetupIde>;
    procedure ActionClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure RunInstall;
    procedure RunUninstall;
  public
    /// <summary>Für Application.CreateForm: die Werte, mit denen Create das Fenster aufbaut.</summary>
    class procedure Configure(const ASystem: ISetupSystem; const APaths: TSetupPaths; const AVersion: string;
      AUninstall: Boolean); static;
    /// <summary>Mit den Werten aus Configure.</summary>
    constructor Create(AOwner: TComponent); override;
    constructor CreateSetup(AOwner: TComponent; const ASystem: ISetupSystem; const APaths: TSetupPaths;
      const AVersion: string; AUninstall: Boolean);
    destructor Destroy; override;
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Setup.Shell.Texts;

const
  Margin = 12;
  FormWidth = 560;

{ TSetupMainForm }

class procedure TSetupMainForm.Configure(const ASystem: ISetupSystem; const APaths: TSetupPaths;
  const AVersion: string; AUninstall: Boolean);
begin
  FConfigSystem := ASystem;
  FConfigPaths := APaths;
  FConfigVersion := AVersion;
  FConfigUninstall := AUninstall;
end;

constructor TSetupMainForm.Create(AOwner: TComponent);
begin
  // Ohne DFM: nicht das geerbte Create, das eine Formularressource sucht.
  CreateSetup(AOwner, FConfigSystem, FConfigPaths, FConfigVersion, FConfigUninstall);
end;

constructor TSetupMainForm.CreateSetup(AOwner: TComponent; const ASystem: ISetupSystem;
  const APaths: TSetupPaths; const AVersion: string; AUninstall: Boolean);
var
  Top: Integer;
begin
  CreateNew(AOwner);
  FUninstallMode := AUninstall;
  FInstaller := TSetupInstaller.Create(ASystem, APaths, AVersion);
  FInstaller.OnStep := Step;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := FormWidth;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Top := Margin;
  if AUninstall then
  begin
    Caption := TSetupTexts.Get(TSetupTextId.UninstallTitle);
    BuildUninstall(Top);
  end
  else
  begin
    Caption := TSetupTexts.Fmt(TSetupTextId.Title, [AVersion]);
    BuildInstall(Top);
  end;
  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.SetBounds(Margin, Top, FormWidth - 2 * Margin, 140);
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssVertical;
  Inc(Top, FLog.Height + Margin);
  FCloseButton := TButton.Create(Self);
  FCloseButton.Parent := Self;
  FCloseButton.Caption := TSetupTexts.Get(TSetupTextId.CloseButton);
  FCloseButton.SetBounds(FormWidth - Margin - 100, Top, 100, 28);
  FCloseButton.Cancel := True;
  FCloseButton.OnClick := CloseClick;
  FActionButton.SetBounds(FCloseButton.Left - Margin - 120, Top, 120, 28);
  ClientHeight := Top + 28 + Margin;
end;

destructor TSetupMainForm.Destroy;
begin
  FInstaller.Free;
  inherited;
end;

function TSetupMainForm.AddLabel(const ACaption: string; var ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.Left := Margin;
  Result.Top := ATop;
  Inc(ATop, 22);
end;

procedure TSetupMainForm.BuildInstall(var ATop: Integer);
var
  Ide: TSetupIde;
  Index: Integer;
  Installed: string;
begin
  AddLabel(TSetupTexts.Fmt(TSetupTextId.TargetLabel, [FInstaller.Paths.InstallDir]), ATop);
  Installed := FInstaller.InstalledVersion;
  if Installed <> '' then
    AddLabel(TSetupTexts.Fmt(TSetupTextId.InstalledVersion, [Installed]), ATop);
  FIdes := FInstaller.Detect;
  if FIdes = nil then
    AddLabel(TSetupTexts.Get(TSetupTextId.NoIdes), ATop)
  else
    AddLabel(TSetupTexts.Get(TSetupTextId.IdesLabel), ATop);
  FIdeList := TCheckListBox.Create(Self);
  FIdeList.Parent := Self;
  FIdeList.SetBounds(Margin, ATop, FormWidth - 2 * Margin, 140);
  for Ide in FIdes do
  begin
    Index := FIdeList.Items.Add(TSetupTexts.IdeCaption(Ide));
    // Nicht angebotene Versionen sind sichtbar, lassen sich aber nicht wählen.
    FIdeList.ItemEnabled[Index] := Ide.Available;
    FIdeList.Checked[Index] := Ide.Available;
  end;
  Inc(ATop, FIdeList.Height + Margin);
  FActionButton := TButton.Create(Self);
  FActionButton.Parent := Self;
  if Installed <> '' then
    FActionButton.Caption := TSetupTexts.Get(TSetupTextId.UpdateButton)
  else
    FActionButton.Caption := TSetupTexts.Get(TSetupTextId.InstallButton);
  FActionButton.Default := True;
  FActionButton.Enabled := FIdes <> nil;
  FActionButton.OnClick := ActionClick;
end;

procedure TSetupMainForm.BuildUninstall(var ATop: Integer);
var
  Data: TSetupData;
begin
  FIdes := FInstaller.Detect;
  AddLabel(TSetupTexts.Get(TSetupTextId.DataLabel), ATop);
  for Data := Low(TSetupData) to High(TSetupData) do
  begin
    FDataBoxes[Data] := TCheckBox.Create(Self);
    FDataBoxes[Data].Parent := Self;
    FDataBoxes[Data].Caption := TSetupTexts.DataName(Data);
    FDataBoxes[Data].SetBounds(Margin + 8, ATop, FormWidth - 2 * Margin - 8, 20);
    // Benutzerdaten bleiben, wenn nicht ausdrücklich gewählt.
    FDataBoxes[Data].Checked := False;
    Inc(ATop, 24);
  end;
  Inc(ATop, Margin);
  FActionButton := TButton.Create(Self);
  FActionButton.Parent := Self;
  FActionButton.Caption := TSetupTexts.Get(TSetupTextId.UninstallButton);
  FActionButton.OnClick := ActionClick;
end;

procedure TSetupMainForm.Step(AStep: TSetupStep);
begin
  FLog.Lines.Add(TSetupTexts.StepText(AStep));
  Application.ProcessMessages;
end;

function TSetupMainForm.SelectedIdes: TArray<TSetupIde>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(FIdes) do
    if FIdeList.Checked[Index] and FIdes[Index].Available then
      Result := Result + [FIdes[Index]];
end;

function TSetupMainForm.WaitForClosedIdes(const AIdes: TArray<TSetupIde>): Boolean;
var
  Running: TArray<TSetupIde>;
  Names: string;
  Ide: TSetupIde;
begin
  repeat
    Running := FInstaller.RunningIdes(AIdes);
    if Running = nil then
      Exit(True);
    Names := '';
    for Ide in Running do
      Names := Names + sLineBreak + '  ' + Ide.Info.ProductName + ' (' +
        TSetupIdes.PlatformFolder(Ide.Platform) + ')';
    // Eine geladene BPL ist gesperrt; eine laufende IDE würde zudem die Registrierung überschreiben.
    if MessageDlg(TSetupTexts.Fmt(TSetupTextId.Running, [Names, sLineBreak, sLineBreak]), mtWarning,
      [mbRetry, mbCancel], 0) <> mrRetry then
      Exit(False);
  until False;
end;

procedure TSetupMainForm.RunInstall;
var
  Selected: TArray<TSetupIde>;
begin
  Selected := SelectedIdes;
  if Selected = nil then
  begin
    MessageDlg(TSetupTexts.Get(TSetupTextId.NothingSelected), mtInformation, [mbOK], 0);
    Exit;
  end;
  if not WaitForClosedIdes(Selected) then
    Exit;
  FActionButton.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    if FInstaller.Install(Selected) then
      FLog.Lines.Add(TSetupTexts.Get(TSetupTextId.InstallDone))
    else
    begin
      FLog.Lines.Add(TSetupTexts.Get(TSetupTextId.Aborted));
      FActionButton.Enabled := True;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TSetupMainForm.RunUninstall;
var
  Data: TSetupData;
  Chosen: TSetupDataSet;
  FromInstallDir: Boolean;
begin
  if MessageDlg(TSetupTexts.Get(TSetupTextId.ConfirmUninstall), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if not WaitForClosedIdes(FIdes) then
    Exit;
  Chosen := [];
  for Data := Low(TSetupData) to High(TSetupData) do
    if FDataBoxes[Data].Checked then
      Include(Chosen, Data);
  FromInstallDir := SameText(ExcludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0))),
    ExcludeTrailingPathDelimiter(FInstaller.Paths.InstallDir));
  FActionButton.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    if FInstaller.Uninstall(Chosen, FromInstallDir) then
      FLog.Lines.Add(TSetupTexts.Get(TSetupTextId.UninstallDone))
    else
    begin
      FLog.Lines.Add(TSetupTexts.Get(TSetupTextId.Aborted));
      FActionButton.Enabled := True;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TSetupMainForm.ActionClick(Sender: TObject);
begin
  if FUninstallMode then
    RunUninstall
  else
    RunInstall;
end;

procedure TSetupMainForm.CloseClick(Sender: TObject);
begin
  Close;
end;

end.
