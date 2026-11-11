unit Shell.Monitor.CheckPage;

// Host-Rolle Shell von AtlasMonitor (#1900): Reiter „Prüfen“ für Läufe von AtlasServer ohne IDE über mehrere Ziele.
// Oben die Zielliste (an/aus, Art, Stand je Ziel), links die Optionen (Shell.Monitor.CheckOptions), rechts das
// Ergebnis: Befundliste mit Filter (Doppelklick öffnet die Stelle im Editor bzw. im zugeordneten Programm) oder der
// Text des Befehls; HTML-Seiten zeigt der Reiter „Bericht“. Je Ziel startet ein unsichtbarer Kindprozess
// (TMonitorChildProcess), einer nach dem anderen; Abbrechen beendet ihn, beim Schließen läuft keiner weiter. Den
// Fortschritt liest der Reiter aus der Statusdatei des Kindprozesses (#1901). Regeln, Aufrufe und Ergebnisse stehen
// in Atlas.Common.Monitor.*.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Common.Monitor.Commands,
  Atlas.Common.Monitor.Targets,
  Atlas.Common.Monitor.Runs,
  Atlas.Windows.Monitor.Adapters.Process,
  Shell.Monitor.CheckOptions,
  Shell.Monitor.ReportPage;

type
  TMonitorConfirm = reference to function(const AText: string): Boolean;

  TMonitorCheckPage = class(TComponent)
  private
    FState: TMonitorCheckState;
    FStatusRoot: string;
    FServer: string;
    FWorkFolder: string;
    FPages: TPageControl;
    FTab: TTabSheet;
    FOptions: TMonitorCheckOptions;
    FReport: TMonitorReportPage;
    FTargetList: TListView;
    FFilterEdit: TEdit;
    FLevelBox: TComboBox;
    FFindingList: TListView;
    FTextView: TMemo;
    FSummary: TLabel;
    FRunButton: TButton;
    FCancelButton: TButton;
    FTimer: TTimer;
    FQueue: TMonitorRunQueue;
    FChild: TMonitorChildProcess;
    FExportChild: TMonitorChildProcess;
    FExportFile: string;
    FShown: TArray<TMonitorFinding>;
    FFillingTargets: Boolean;
    FOnInform: TProc<string>;
    FOnConfirm: TMonitorConfirm;
    procedure BuildTargets(AParent: TWinControl);
    procedure BuildResults(AParent: TWinControl);
    procedure BuildToolbar(AParent: TWinControl);
    function AddButton(AParent: TWinControl; var ALeft: Integer; const ACaption: string;
      const AOnClick: TNotifyEvent): TButton;
    procedure FillTargets;
    procedure UpdateTargetStates;
    procedure FillFindings;
    procedure ShowRun(AIndex: Integer);
    function Validate: Boolean;
    function PrepareWorkFolder: Boolean;
    procedure StartNext;
    procedure FinishRun(AIndex, AExitCode: Integer);
    procedure ReadOutput(AIndex: Integer);
    procedure ReadProgress(AIndex: Integer);
    procedure RunsDone;
    procedure ExportFindings;
    procedure ExportReport;
    procedure ExportText;
    procedure SaveText(const AFileName, AText: string);
    function SelectedRun: Integer;
    procedure Inform(const AText: string);
    procedure TimerTick(ASender: TObject);
    procedure AddFolderClick(ASender: TObject);
    procedure AddFileClick(ASender: TObject);
    procedure RemoveClick(ASender: TObject);
    procedure SaveListClick(ASender: TObject);
    procedure LoadListClick(ASender: TObject);
    procedure RunClick(ASender: TObject);
    procedure CancelClick(ASender: TObject);
    procedure CopyCallClick(ASender: TObject);
    procedure ExportClick(ASender: TObject);
    procedure FilterChange(ASender: TObject);
    procedure TargetChecked(ASender: TObject; AItem: TListItem);
    procedure TargetSelected(ASender: TObject; AItem: TListItem; ASelected: Boolean);
    procedure FindingData(ASender: TObject; AItem: TListItem);
    procedure FindingDblClick(ASender: TObject);
  public
    /// <summary>Legt den Reiter in APages an. AStatusRoot: Ordner der Statusdateien (Fortschritt).</summary>
    constructor Create(AOwner: TComponent; APages: TPageControl; const AState: TMonitorCheckState;
      const AStatusRoot: string; const AOnInform: TProc<string>; const AOnConfirm: TMonitorConfirm); reintroduce;
    destructor Destroy; override;
    /// <summary>Zeigt den Reiter und füllt Listen; erst mit Fenster (CreateWnd des Formulars).</summary>
    procedure Activate;
    /// <summary>Läuft gerade ein Befehl?</summary>
    function Busy: Boolean;
    /// <summary>Bricht alle Läufe ab (Schließen des Programms).</summary>
    procedure CancelRuns;
    /// <summary>Aktueller Stand für monitor.json.</summary>
    function State: TMonitorCheckState;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Clipbrd,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Monitor.Results,
  Atlas.Common.Monitor.Texts,
  Atlas.Windows.Monitor.Adapters.System;

const
  cTickMs = 500;
  cTargetsHeight = 170;
  cToolbarHeight = 40;
  cButtonWidth = 150;
  cGap = 6;
  cTargetButtonsWidth = 170;
  cLevels: array[0..3] of string = ('', 'note', 'warning', 'error');

/// <summary>AValue in Pixeln bei 96 dpi, umgerechnet auf die Auflösung des Bildschirms.</summary>
function Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

/// <summary>Ordner, in dem ein Lauf über ATarget startet: der Ordner selbst bzw. der Ordner der Datei.</summary>
function FolderOf(const ATarget: string): string;
begin
  Result := ATarget;
  if (Result <> '') and not DirectoryExists(Result) then
  begin
    Result := ExtractFileDir(Result);
  end;
  if (Result <> '') and not DirectoryExists(Result) then
  begin
    Result := '';
  end;
end;

/// <summary>Inhalt von AFileName; '' wenn sie fehlt oder nicht lesbar ist.</summary>
function ReadText(const AFileName: string): string;
begin
  Result := '';
  try
    if (AFileName <> '') and TFile.Exists(AFileName) then
    begin
      Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    end;
  except
    // lsp-ignore: catch-all-without-raise -- eine unlesbare Ausgabe zeigt der Reiter als leer
    on Exception do
      Result := '';
  end;
end;

{ TMonitorCheckPage }

constructor TMonitorCheckPage.Create(AOwner: TComponent; APages: TPageControl; const AState: TMonitorCheckState;
  const AStatusRoot: string; const AOnInform: TProc<string>; const AOnConfirm: TMonitorConfirm);
begin
  inherited Create(AOwner);
  FState := AState;
  FStatusRoot := AStatusRoot;
  FOnInform := AOnInform;
  FOnConfirm := AOnConfirm;
  FPages := APages;
  FServer := TPath.Combine(ExtractFilePath(ParamStr(0)), TMonitorSystem.cServerExe);
  FWorkFolder := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'AtlasMonitor'), IntToStr(GetCurrentProcessId));
  FTab := TTabSheet.Create(Self);
  FTab.Caption := TMonitorTexts.Text(TMonitorText.TabCheck);
  // Ohne Fenster scheitert ein sichtbarer Reiter; Activate zeigt ihn.
  FTab.TabVisible := False;
  FTab.PageControl := FPages;
  BuildTargets(FTab);
  FOptions := TMonitorCheckOptions.Create(Self, FTab);
  BuildResults(FTab);
  FReport := TMonitorReportPage.Create(Self, FPages, AOnInform);
  FChild := TMonitorChildProcess.Create;
  FExportChild := TMonitorChildProcess.Create;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TMonitorCheckPage.Destroy;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  // Kein Kindprozess überlebt den Monitor.
  FreeAndNil(FChild);
  FreeAndNil(FExportChild);
  if (FWorkFolder <> '') and TDirectory.Exists(FWorkFolder) then
  begin
    try
      TDirectory.Delete(FWorkFolder, True);
    except
      // lsp-ignore: catch-all-without-raise -- Reste im Temp-Ordner stören nicht
      on Exception do
        FWorkFolder := '';
    end;
  end;
  FShown := nil;
  inherited;
end;

function TMonitorCheckPage.AddButton(AParent: TWinControl; var ALeft: Integer; const ACaption: string;
  const AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  Result.SetBounds(ALeft, Px(cGap), Px(cButtonWidth), Px(cToolbarHeight - 2 * cGap));
  Result.Parent := AParent;
  ALeft := ALeft + Px(cButtonWidth + cGap);
end;

procedure TMonitorCheckPage.BuildTargets(AParent: TWinControl);
var
  mPanel, mButtons: TPanel;
  mTop: Integer;

  procedure AddTargetButton(const ACaption: string; const AOnClick: TNotifyEvent);
  var
    mButton: TButton;
  begin
    mButton := TButton.Create(Self);
    mButton.Caption := ACaption;
    mButton.OnClick := AOnClick;
    mButton.SetBounds(Px(cGap), mTop, Px(cTargetButtonsWidth - 2 * cGap), Px(cToolbarHeight - 2 * cGap));
    mButton.Parent := mButtons;
    mTop := mTop + Px(cToolbarHeight - cGap);
  end;

begin
  mPanel := TPanel.Create(Self);
  // Höhe vor Align und Parent, sonst kann die VCL die Reihenfolge beim Anlegen vertauschen.
  mPanel.Height := Px(cTargetsHeight);
  mPanel.Align := alTop;
  mPanel.BevelOuter := bvNone;
  mPanel.Parent := AParent;
  mButtons := TPanel.Create(Self);
  mButtons.Width := Px(cTargetButtonsWidth);
  mButtons.Align := alRight;
  mButtons.BevelOuter := bvNone;
  mButtons.Parent := mPanel;
  mTop := Px(cGap);
  AddTargetButton(TMonitorTexts.Text(TMonitorText.AddFolder), AddFolderClick);
  AddTargetButton(TMonitorTexts.Text(TMonitorText.AddFile), AddFileClick);
  AddTargetButton(TMonitorTexts.Text(TMonitorText.RemoveTarget), RemoveClick);
  AddTargetButton(TMonitorTexts.Text(TMonitorText.SaveList), SaveListClick);
  AddTargetButton(TMonitorTexts.Text(TMonitorText.LoadList), LoadListClick);
  FTargetList := TListView.Create(Self);
  FTargetList.Align := alClient;
  FTargetList.ViewStyle := vsReport;
  FTargetList.Checkboxes := True;
  FTargetList.ReadOnly := True;
  FTargetList.RowSelect := True;
  FTargetList.HideSelection := False;
  FTargetList.OnItemChecked := TargetChecked;
  FTargetList.OnSelectItem := TargetSelected;
  FTargetList.Columns.Add.Caption := TMonitorTexts.Text(TMonitorText.ColumnTarget);
  FTargetList.Columns.Add.Caption := TMonitorTexts.Text(TMonitorText.ColumnKind);
  FTargetList.Columns.Add.Caption := TMonitorTexts.Text(TMonitorText.ColumnState);
  FTargetList.Columns[0].Width := Px(420);
  FTargetList.Columns[1].Width := Px(110);
  FTargetList.Columns[2].Width := Px(200);
  FTargetList.Parent := mPanel;
end;

procedure TMonitorCheckPage.BuildToolbar(AParent: TWinControl);
var
  mBar: TPanel;
  mLeft: Integer;
begin
  mBar := TPanel.Create(Self);
  mBar.Height := Px(cToolbarHeight);
  mBar.Align := alTop;
  mBar.BevelOuter := bvNone;
  mBar.Parent := AParent;
  mLeft := Px(cGap);
  FRunButton := AddButton(mBar, mLeft, TMonitorTexts.Text(TMonitorText.Run), RunClick);
  FCancelButton := AddButton(mBar, mLeft, TMonitorTexts.Text(TMonitorText.Cancel), CancelClick);
  FCancelButton.Enabled := False;
  AddButton(mBar, mLeft, TMonitorTexts.Text(TMonitorText.CopyCall), CopyCallClick);
  AddButton(mBar, mLeft, TMonitorTexts.Text(TMonitorText.Export), ExportClick);
  FSummary := TLabel.Create(Self);
  FSummary.SetBounds(mLeft, Px(2 * cGap), Px(300), Px(cToolbarHeight - 2 * cGap));
  FSummary.Parent := mBar;
end;

procedure TMonitorCheckPage.BuildResults(AParent: TWinControl);
var
  mResults, mFilter: TPanel;
  mTitle: string;
  mColumn: TListColumn;
begin
  mResults := TPanel.Create(Self);
  mResults.Align := alClient;
  mResults.BevelOuter := bvNone;
  mResults.Parent := AParent;
  BuildToolbar(mResults);
  mFilter := TPanel.Create(Self);
  mFilter.Height := Px(cToolbarHeight - cGap);
  mFilter.Align := alTop;
  mFilter.BevelOuter := bvNone;
  mFilter.Parent := mResults;
  FFilterEdit := TEdit.Create(Self);
  FFilterEdit.TextHint := TMonitorTexts.Text(TMonitorText.Filter);
  FFilterEdit.SetBounds(Px(cGap), Px(cGap div 2), Px(300), Px(23));
  FFilterEdit.OnChange := FilterChange;
  FFilterEdit.Parent := mFilter;
  FLevelBox := TComboBox.Create(Self);
  FLevelBox.Style := csDropDownList;
  FLevelBox.SetBounds(Px(310 + cGap), Px(cGap div 2), Px(150), Px(23));
  FLevelBox.OnChange := FilterChange;
  FLevelBox.Parent := mFilter;
  FTextView := TMemo.Create(Self);
  FTextView.Align := alClient;
  FTextView.ReadOnly := True;
  FTextView.ScrollBars := ssBoth;
  FTextView.WordWrap := False;
  FTextView.Visible := False;
  FTextView.Parent := mResults;
  FFindingList := TListView.Create(Self);
  FFindingList.Align := alClient;
  FFindingList.ViewStyle := vsReport;
  FFindingList.OwnerData := True;
  FFindingList.ReadOnly := True;
  FFindingList.RowSelect := True;
  FFindingList.OnData := FindingData;
  FFindingList.OnDblClick := FindingDblClick;
  for mTitle in TMonitorResults.ColumnTitles do
  begin
    mColumn := FFindingList.Columns.Add;
    mColumn.Caption := mTitle;
    mColumn.Width := Px(90);
  end;
  FFindingList.Columns[1].Width := Px(300);
  FFindingList.Columns[4].Width := Px(400);
  FFindingList.Parent := mResults;
end;

procedure TMonitorCheckPage.Activate;
var
  I: Integer;
begin
  FTab.TabVisible := True;
  FTargetList.HandleNeeded;
  FFindingList.HandleNeeded;
  FOptions.Activate(FState);
  FLevelBox.Items.Clear;
  FLevelBox.Items.Add(TMonitorTexts.Text(TMonitorText.SeverityAll));
  for I := 1 to High(cLevels) do
  begin
    FLevelBox.Items.Add(TMonitorResults.LevelText(cLevels[I]));
  end;
  FLevelBox.ItemIndex := 0;
  FillTargets;
end;

function TMonitorCheckPage.Busy: Boolean;
begin
  Result := FQueue.Busy;
end;

function TMonitorCheckPage.State: TMonitorCheckState;
begin
  FOptions.Store(FState);
  Result := FState;
end;

procedure TMonitorCheckPage.Inform(const AText: string);
begin
  if Assigned(FOnInform) then
  begin
    FOnInform(AText);
  end;
end;

{ Ziele }

procedure TMonitorCheckPage.FillTargets;
var
  mTarget: TMonitorTarget;
  mItem: TListItem;
begin
  if not FTargetList.HandleAllocated then
  begin
    Exit;
  end;
  FFillingTargets := True;
  FTargetList.Items.BeginUpdate;
  try
    FTargetList.Items.Clear;
    for mTarget in FState.Targets.Items do
    begin
      mItem := FTargetList.Items.Add;
      mItem.Caption := mTarget.Path;
      mItem.SubItems.Add(mTarget.KindText);
      mItem.SubItems.Add('');
      mItem.Checked := mTarget.Enabled;
    end;
  finally
    FTargetList.Items.EndUpdate;
    FFillingTargets := False;
  end;
end;

/// <summary>Stand je Ziel aus der Warteschlange in die dritte Spalte.</summary>
procedure TMonitorCheckPage.UpdateTargetStates;
var
  mRun: TMonitorRun;
  mIndex: Integer;
begin
  for mRun in FQueue.Runs do
  begin
    mIndex := FState.Targets.IndexOf(mRun.Target);
    if (mIndex >= 0) and (mIndex < FTargetList.Items.Count) then
    begin
      FTargetList.Items[mIndex].SubItems[1] := TMonitorRunQueue.StateText(FQueue.Command, mRun);
    end;
  end;
  FSummary.Caption := FQueue.Summary;
end;

procedure TMonitorCheckPage.TargetChecked(ASender: TObject; AItem: TListItem);
begin
  if not FFillingTargets and (AItem.Index <= High(FState.Targets.Items)) then
  begin
    FState.Targets.Items[AItem.Index].Enabled := AItem.Checked;
  end;
end;

procedure TMonitorCheckPage.TargetSelected(ASender: TObject; AItem: TListItem; ASelected: Boolean);
begin
  if ASelected and not Busy then
  begin
    ShowRun(SelectedRun);
  end;
end;

procedure TMonitorCheckPage.AddFolderClick(ASender: TObject);
var
  mDialog: TFileOpenDialog;
begin
  mDialog := TFileOpenDialog.Create(nil);
  try
    mDialog.Title := TMonitorTexts.Text(TMonitorText.ChooseFolder);
    mDialog.Options := [fdoPickFolders, fdoPathMustExist];
    if mDialog.Execute then
    begin
      FState.Targets.Add(mDialog.FileName);
      FillTargets;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorCheckPage.AddFileClick(ASender: TObject);
var
  mDialog: TOpenDialog;
  mFile: string;
begin
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterAddFile);
    mDialog.Options := [ofFileMustExist, ofAllowMultiSelect, ofEnableSizing];
    if mDialog.Execute then
    begin
      for mFile in mDialog.Files do
      begin
        FState.Targets.Add(mFile);
      end;
      FillTargets;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorCheckPage.RemoveClick(ASender: TObject);
begin
  if (FTargetList.Selected <> nil) and not Busy then
  begin
    FState.Targets.Delete(FTargetList.Selected.Index);
    FillTargets;
  end;
end;

procedure TMonitorCheckPage.SaveListClick(ASender: TObject);
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterTargets);
    mDialog.DefaultExt := TMonitorTargetList.cFileExtension.Substring(1);
    mDialog.Options := [ofOverwritePrompt, ofEnableSizing];
    if mDialog.Execute then
    begin
      SaveText(mDialog.FileName, FState.Targets.ToText);
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorCheckPage.LoadListClick(ASender: TObject);
var
  mDialog: TOpenDialog;
begin
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterTargets);
    mDialog.Options := [ofFileMustExist, ofEnableSizing];
    if mDialog.Execute and not Busy then
    begin
      FState.Targets := TMonitorTargetList.FromText(ReadText(mDialog.FileName));
      FillTargets;
    end;
  finally
    mDialog.Free;
  end;
end;

{ Läufe }

function TMonitorCheckPage.Validate: Boolean;
var
  mMissing: TMonitorField;
  mNeedsInput: Boolean;
begin
  Result := False;
  if not FileExists(FServer) then
  begin
    Inform(TMonitorTexts.Fmt(TMonitorText.ServerMissing, [FServer]));
    Exit;
  end;
  if TMonitorCommands.NeedsTarget(FState.Command) and (FState.Targets.EnabledPaths = nil) then
  begin
    Inform(TMonitorTexts.Text(TMonitorText.NoTargets));
    Exit;
  end;
  mMissing := TMonitorField.Query;
  case FState.Command of
    TMonitorCommand.Query:
      mNeedsInput := FState.Options.Query = '';
    TMonitorCommand.ArchitectureSave, TMonitorCommand.ArchitectureCompare:
      begin
        mMissing := TMonitorField.ArchitectureFile;
        mNeedsInput := FState.Options.ArchitectureFile = '';
      end;
    TMonitorCommand.Replay:
      begin
        mMissing := TMonitorField.ReplayFile;
        mNeedsInput := FState.Options.ReplayFile = '';
      end;
  else
    mNeedsInput := False;
  end;
  if mNeedsInput then
  begin
    Inform(TMonitorTexts.Fmt(TMonitorText.MissingInput, [FOptions.FieldCaption(mMissing)]));
    Exit;
  end;
  Result := not TMonitorCommands.Writes(FState.Command, FState.Options) or FOnConfirm(TMonitorTexts.Fmt(
    TMonitorText.ConfirmWrite, [TMonitorCommands.Text(FState.Command), Length(FState.Targets.EnabledPaths)]));
end;

function TMonitorCheckPage.PrepareWorkFolder: Boolean;
begin
  try
    if TDirectory.Exists(FWorkFolder) then
    begin
      TDirectory.Delete(FWorkFolder, True);
    end;
    ForceDirectories(FWorkFolder);
    Result := True;
  except
    // lsp-ignore: catch-all-without-raise -- der Hinweis nennt den Fehler, der Lauf startet nicht
    on E: Exception do
    begin
      Inform(TMonitorTexts.Fmt(TMonitorText.StartFailed, [E.Message]));
      Result := False;
    end;
  end;
end;

procedure TMonitorCheckPage.RunClick(ASender: TObject);
begin
  FOptions.Store(FState);
  if Busy or not Validate or not PrepareWorkFolder then
  begin
    Exit;
  end;
  FQueue := TMonitorRunQueue.Create(FState.Command, FState.Targets.EnabledPaths);
  FShown := nil;
  FillFindings;
  FTextView.Clear;
  FRunButton.Enabled := False;
  FCancelButton.Enabled := True;
  FTimer.Enabled := True;
  StartNext;
end;

procedure TMonitorCheckPage.StartNext;
var
  mIndex: Integer;
  mArgs: TArray<string>;
  mError: string;
begin
  mIndex := FQueue.NextIndex;
  if mIndex < 0 then
  begin
    if not FQueue.Busy then
    begin
      RunsDone;
    end;
    Exit;
  end;
  FQueue.Runs[mIndex].OutputFile := TPath.Combine(FWorkFolder, IntToStr(mIndex) +
    TMonitorCommands.OutputExtension(FQueue.Command));
  if FQueue.Command = TMonitorCommand.ArchitectureSave then
  begin
    FQueue.Runs[mIndex].OutputFile := FState.Options.ArchitectureFile;
  end;
  FQueue.Runs[mIndex].LogFile := TPath.Combine(FWorkFolder, IntToStr(mIndex) + '.log');
  mArgs := TMonitorCommands.Arguments(FQueue.Command, FQueue.Runs[mIndex].Target, FState.Options,
    FQueue.Runs[mIndex].OutputFile, TAtlasLocale.Code(TAtlasLocale.Language));
  if FChild.Start(FServer, mArgs, FolderOf(FQueue.Runs[mIndex].Target), FQueue.Runs[mIndex].LogFile, mError) then
  begin
    FQueue.Runs[mIndex].State := TMonitorRunState.Running;
  end
  else
  begin
    FQueue.Runs[mIndex].ErrorText := TMonitorTexts.Fmt(TMonitorText.StartFailed, [mError]);
    FQueue.Finish(mIndex, -1);
    StartNext;
  end;
  UpdateTargetStates;
end;

procedure TMonitorCheckPage.ReadOutput(AIndex: Integer);
var
  mFindings: TArray<TMonitorFinding>;
  mError: string;
begin
  if FQueue.Runs[AIndex].State = TMonitorRunState.Failed then
  begin
    FQueue.Runs[AIndex].ErrorText := Trim(FQueue.Runs[AIndex].ErrorText + sLineBreak +
      ReadText(FQueue.Runs[AIndex].LogFile));
    Exit;
  end;
  if TMonitorCommands.OutputKind(FQueue.Command) <> TMonitorOutputKind.Findings then
  begin
    Exit;
  end;
  if TMonitorResults.ParseSarif(ReadText(FQueue.Runs[AIndex].OutputFile), FQueue.Runs[AIndex].Target, mFindings,
    mError) then
  begin
    FQueue.Runs[AIndex].Findings := mFindings;
  end
  else
  begin
    FQueue.Runs[AIndex].ErrorText := mError + sLineBreak + ReadText(FQueue.Runs[AIndex].LogFile);
  end;
end;

procedure TMonitorCheckPage.FinishRun(AIndex, AExitCode: Integer);
begin
  FQueue.Finish(AIndex, AExitCode);
  ReadOutput(AIndex);
  if TMonitorCommands.OutputKind(FQueue.Command) = TMonitorOutputKind.Findings then
  begin
    FShown := TMonitorResults.Filter(FQueue.AllFindings, FFilterEdit.Text, cLevels[Max(FLevelBox.ItemIndex, 0)]);
    FillFindings;
  end;
end;

procedure TMonitorCheckPage.ReadProgress(AIndex: Integer);
var
  mEntry: TServerStatusEntry;
begin
  for mEntry in TServerStatusFile.List(FStatusRoot, Now, nil) do
  begin
    if mEntry.Pid = FChild.Pid then
    begin
      FQueue.Runs[AIndex].Done := mEntry.Done;
      FQueue.Runs[AIndex].Total := mEntry.Total;
    end;
  end;
end;

procedure TMonitorCheckPage.TimerTick(ASender: TObject);
var
  mIndex: Integer;
begin
  if FExportFile <> '' then
  begin
    if FExportChild.Poll then
    begin
      Inform(TMonitorTexts.Fmt(TMonitorText.Exported, [FExportFile]));
      FExportFile := '';
    end;
  end;
  mIndex := FQueue.RunningIndex;
  if mIndex < 0 then
  begin
    FTimer.Enabled := FExportFile <> '';
    Exit;
  end;
  if FChild.Poll then
  begin
    FinishRun(mIndex, FChild.ExitCode);
    StartNext;
  end
  else
  begin
    ReadProgress(mIndex);
  end;
  UpdateTargetStates;
end;

procedure TMonitorCheckPage.RunsDone;
var
  mIndex: Integer;
begin
  FRunButton.Enabled := True;
  FCancelButton.Enabled := False;
  UpdateTargetStates;
  // Ergebnis des ersten Ziels zeigen; ein Klick auf ein Ziel zeigt dessen.
  mIndex := SelectedRun;
  if mIndex < 0 then
  begin
    mIndex := 0;
  end;
  ShowRun(mIndex);
end;

procedure TMonitorCheckPage.CancelRuns;
begin
  FChild.Terminate;
  FExportChild.Terminate;
  FExportFile := '';
  FQueue.CancelAll;
end;

procedure TMonitorCheckPage.CancelClick(ASender: TObject);
begin
  CancelRuns;
  RunsDone;
end;

{ Ergebnisse }

function TMonitorCheckPage.SelectedRun: Integer;
var
  I: Integer;
begin
  Result := -1;
  if FTargetList.Selected = nil then
  begin
    Exit;
  end;
  for I := 0 to High(FQueue.Runs) do
  begin
    if SameText(FQueue.Runs[I].Target, FTargetList.Selected.Caption) then
    begin
      Result := I;
    end;
  end;
end;

/// <summary>Zeigt das Ergebnis von Lauf AIndex: Befundliste aller Läufe, Text des Laufs oder seine HTML-Seite.
/// </summary>
procedure TMonitorCheckPage.ShowRun(AIndex: Integer);
var
  mKind: TMonitorOutputKind;
  mRun: TMonitorRun;
begin
  if (AIndex < 0) or (AIndex > High(FQueue.Runs)) then
  begin
    Exit;
  end;
  mRun := FQueue.Runs[AIndex];
  mKind := TMonitorCommands.OutputKind(FQueue.Command);
  FFindingList.Visible := (mKind = TMonitorOutputKind.Findings) and (mRun.ErrorText = '');
  FTextView.Visible := not FFindingList.Visible;
  if FFindingList.Visible then
  begin
    Exit;
  end;
  FTextView.Text := Trim(TMonitorRunQueue.StateText(FQueue.Command, mRun) + sLineBreak + mRun.ErrorText +
    sLineBreak + ReadText(mRun.OutputFile) + sLineBreak + ReadText(TMonitorCommands.TimingsFileOf(mRun.OutputFile)));
  if (mKind = TMonitorOutputKind.Html) and (mRun.State = TMonitorRunState.Done) then
  begin
    FTextView.Text := TMonitorRunQueue.StateText(FQueue.Command, mRun);
    FReport.ShowFile(mRun.OutputFile);
  end;
end;

procedure TMonitorCheckPage.FillFindings;
begin
  if FFindingList.HandleAllocated then
  begin
    FFindingList.Items.Count := Length(FShown);
    FFindingList.Invalidate;
  end;
end;

procedure TMonitorCheckPage.FilterChange(ASender: TObject);
begin
  FShown := TMonitorResults.Filter(FQueue.AllFindings, FFilterEdit.Text, cLevels[Max(FLevelBox.ItemIndex, 0)]);
  FillFindings;
end;

procedure TMonitorCheckPage.FindingData(ASender: TObject; AItem: TListItem);
var
  mCells: TArray<string>;
  I: Integer;
begin
  if AItem.Index > High(FShown) then
  begin
    Exit;
  end;
  mCells := TMonitorResults.Columns(FShown[AItem.Index]);
  AItem.Caption := mCells[0];
  AItem.SubItems.Clear;
  for I := 1 to High(mCells) do
  begin
    AItem.SubItems.Add(mCells[I]);
  end;
end;

procedure TMonitorCheckPage.FindingDblClick(ASender: TObject);
var
  mFinding: TMonitorFinding;
  mCommand: string;
begin
  if (FFindingList.Selected = nil) or (FFindingList.Selected.Index > High(FShown)) then
  begin
    Exit;
  end;
  mFinding := FShown[FFindingList.Selected.Index];
  FOptions.Store(FState);
  mCommand := TMonitorCheckState.EditorCommand(FState.Editor, mFinding.FileName, mFinding.Line, mFinding.Column);
  if mCommand <> '' then
  begin
    TMonitorSystem.Launch(mCommand);
  end
  else
  begin
    TMonitorSystem.OpenFile(mFinding.FileName);
  end;
end;

procedure TMonitorCheckPage.CopyCallClick(ASender: TObject);
var
  mLines: TStringList;
  mTarget: string;
  mTargets: TArray<string>;
begin
  FOptions.Store(FState);
  mTargets := FState.Targets.EnabledPaths;
  if not TMonitorCommands.NeedsTarget(FState.Command) then
  begin
    mTargets := TArray<string>.Create('');
  end;
  mLines := TStringList.Create;
  try
    for mTarget in mTargets do
    begin
      mLines.Add(TMonitorCommands.CommandLine(FServer, TMonitorCommands.Arguments(FState.Command, mTarget,
        FState.Options, '', '')));
    end;
    Clipboard.AsText := mLines.Text;
  finally
    mLines.Free;
  end;
  Inform(TMonitorTexts.Text(TMonitorText.CallCopied));
end;

{ Export }

procedure TMonitorCheckPage.SaveText(const AFileName, AText: string);
begin
  try
    TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
    Inform(TMonitorTexts.Fmt(TMonitorText.Exported, [AFileName]));
  except
    // lsp-ignore: catch-all-without-raise -- der Hinweis nennt den Fehler
    on E: Exception do
      Inform(TMonitorTexts.Fmt(TMonitorText.SaveFailed, [E.Message]));
  end;
end;

procedure TMonitorCheckPage.ExportFindings;
var
  mDialog: TSaveDialog;
  mTexts: TArray<string>;
  mRun: TMonitorRun;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterFindings);
    mDialog.DefaultExt := 'html';
    mDialog.Options := [ofOverwritePrompt, ofEnableSizing];
    if not mDialog.Execute then
    begin
      Exit;
    end;
    if SameText(ExtractFileExt(mDialog.FileName), '.sarif') then
    begin
      mTexts := nil;
      for mRun in FQueue.Runs do
      begin
        mTexts := mTexts + [ReadText(mRun.OutputFile)];
      end;
      SaveText(mDialog.FileName, TMonitorResults.MergeSarif(mTexts));
    end
    else
    begin
      SaveText(mDialog.FileName, TMonitorResults.Html(FQueue.AllFindings, TMonitorCommands.Text(FQueue.Command)));
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorCheckPage.ExportText;
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterText);
    mDialog.DefaultExt := TMonitorCommands.OutputExtension(FQueue.Command).Substring(1);
    mDialog.Options := [ofOverwritePrompt, ofEnableSizing];
    if mDialog.Execute then
    begin
      SaveText(mDialog.FileName, FTextView.Text);
    end;
  finally
    mDialog.Free;
  end;
end;

/// <summary>HTML-Seite des gewählten Ziels kopieren; Markdown und JSON schreibt ein eigener Lauf des Servers.
/// </summary>
procedure TMonitorCheckPage.ExportReport;
var
  mDialog: TSaveDialog;
  mIndex: Integer;
  mError: string;
begin
  mIndex := Max(SelectedRun, 0);
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterReport);
    mDialog.DefaultExt := 'html';
    mDialog.Options := [ofOverwritePrompt, ofEnableSizing];
    if not mDialog.Execute then
    begin
      Exit;
    end;
    if SameText(ExtractFileExt(mDialog.FileName), '.html') then
    begin
      SaveText(mDialog.FileName, ReadText(FQueue.Runs[mIndex].OutputFile));
    end
    else if FExportChild.Start(FServer, TMonitorCommands.Arguments(FQueue.Command, FQueue.Runs[mIndex].Target,
      FState.Options, mDialog.FileName, TAtlasLocale.Code(TAtlasLocale.Language)),
      FolderOf(FQueue.Runs[mIndex].Target), TPath.Combine(FWorkFolder, 'export.log'), mError) then
    begin
      FExportFile := mDialog.FileName;
      FTimer.Enabled := True;
    end
    else
    begin
      Inform(TMonitorTexts.Fmt(TMonitorText.StartFailed, [mError]));
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorCheckPage.ExportClick(ASender: TObject);
begin
  if Busy or (FQueue.Runs = nil) then
  begin
    Exit;
  end;
  case TMonitorCommands.OutputKind(FQueue.Command) of
    TMonitorOutputKind.Findings:
      ExportFindings;
    TMonitorOutputKind.Html:
      ExportReport;
  else
    ExportText;
  end;
end;

end.
