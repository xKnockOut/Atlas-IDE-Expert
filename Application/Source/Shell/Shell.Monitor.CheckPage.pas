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
  /// <summary>Alle Befunde der Läufe, die die Befundliste filtert.</summary>
  TMonitorFindingsFunc = reference to function: TArray<TMonitorFinding>;
  /// <summary>Doppelklick auf einen Befund.</summary>
  TMonitorFindingProc = reference to procedure(const AFinding: TMonitorFinding);

  /// <summary>Zielliste oben im Reiter „Prüfen“: an/aus, Art, Stand je Ziel; Knöpfe zum Hinzufügen, Entfernen,
  /// Speichern und Laden. Hält die Ziele, bis der Reiter sie liest.</summary>
  TMonitorTargetsView = class(TComponent)
  private
    FTargets: TMonitorTargetList;
    FList: TListView;
    FFilling: Boolean;
    FIsBusy: TFunc<Boolean>;
    FOnSelect: TProc;
    FOnInform: TProc<string>;
    procedure AddFolderClick(ASender: TObject);
    procedure AddFileClick(ASender: TObject);
    procedure RemoveClick(ASender: TObject);
    procedure SaveListClick(ASender: TObject);
    procedure LoadListClick(ASender: TObject);
    procedure TargetChecked(ASender: TObject; AItem: TListItem);
    procedure TargetSelected(ASender: TObject; AItem: TListItem; ASelected: Boolean);
  public
    /// <summary>Legt Liste und Knöpfe in AParent an. AIsBusy sperrt Entfernen und Laden während eines Laufs;
    /// AOnSelect folgt der Wahl eines Ziels.</summary>
    constructor Create(AOwner: TComponent; AParent: TWinControl; const ATargets: TMonitorTargetList;
      const AIsBusy: TFunc<Boolean>; const AOnSelect: TProc; const AOnInform: TProc<string>); reintroduce;
    /// <summary>Erst mit Fenster: Liste füllen.</summary>
    procedure Activate;
    procedure Fill;
    /// <summary>Stand je Ziel aus AQueue in die dritte Spalte.</summary>
    procedure ShowStates(const AQueue: TMonitorRunQueue);
    /// <summary>Pfad des gewählten Ziels; '' ohne Wahl.</summary>
    function SelectedPath: string;
    property Targets: TMonitorTargetList read FTargets;
  end;

  /// <summary>Ergebnis rechts im Reiter „Prüfen“: Befundliste mit Filter nach Text und Schwere oder der Text eines
  /// Laufs. Doppelklick auf einen Befund ruft AOnOpen.</summary>
  TMonitorFindingsView = class(TComponent)
  private
    FFilterEdit: TEdit;
    FLevelBox: TComboBox;
    FList: TListView;
    FTextView: TMemo;
    FShown: TArray<TMonitorFinding>;
    FAll: TMonitorFindingsFunc;
    FOnOpen: TMonitorFindingProc;
    procedure Fill;
    procedure FilterChange(ASender: TObject);
    procedure FindingData(ASender: TObject; AItem: TListItem);
    procedure FindingDblClick(ASender: TObject);
  public
    constructor Create(AOwner: TComponent; AParent: TWinControl; const AAll: TMonitorFindingsFunc;
      const AOnOpen: TMonitorFindingProc); reintroduce;
    destructor Destroy; override;
    /// <summary>Erst mit Fenster: Liste anlegen, Schweregrade füllen.</summary>
    procedure Activate;
    /// <summary>Leere Liste und leerer Text (neuer Lauf).</summary>
    procedure Clear;
    /// <summary>Befunde neu filtern und zeigen.</summary>
    procedure Refilter;
    procedure ShowList;
    procedure ShowText(const AText: string);
    function Text: string;
  end;

  /// <summary>Export der Ergebnisse: Befunde als HTML oder SARIF, Text eines Befehls, Bericht als HTML-Kopie oder
  /// über einen eigenen Lauf des Servers (Markdown, JSON) im Hintergrund.</summary>
  TMonitorCheckExport = class
  private
    FServer: string;
    FWorkFolder: string;
    FChild: TMonitorChildProcess;
    /// <summary>Ziel des laufenden Exports im Hintergrund; '' ohne.</summary>
    FFile: string;
    FOnInform: TProc<string>;
  public
    constructor Create(const AServer, AWorkFolder: string; const AOnInform: TProc<string>);
    destructor Destroy; override;
    procedure Findings(const AQueue: TMonitorRunQueue);
    procedure Text(const AQueue: TMonitorRunQueue; const AText: string);
    /// <summary>Bericht von Lauf AIndex; True, wenn ein Export im Hintergrund gestartet ist.</summary>
    function Report(const AQueue: TMonitorRunQueue; AIndex: Integer; const AOptions: TMonitorOptions): Boolean;
    /// <summary>Stand des Exports im Hintergrund; meldet sein Ende. True, solange er läuft.</summary>
    function Poll: Boolean;
    procedure Cancel;
  end;

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
    FTargets: TMonitorTargetsView;
    FFindings: TMonitorFindingsView;
    FSummary: TLabel;
    FRunButton: TButton;
    FCancelButton: TButton;
    FTimer: TTimer;
    FQueue: TMonitorRunQueue;
    FChild: TMonitorChildProcess;
    FExport: TMonitorCheckExport;
    FOnInform: TProc<string>;
    FOnConfirm: TMonitorConfirm;
    procedure BuildResults(AParent: TWinControl);
    procedure BuildToolbar(AParent: TWinControl);
    procedure UpdateTargetStates;
    procedure ShowRun(AIndex: Integer);
    function Validate: Boolean;
    procedure StartNext;
    procedure FinishRun(AIndex, AExitCode: Integer);
    procedure RunsDone;
    function SelectedRun: Integer;
    procedure OpenFinding(const AFinding: TMonitorFinding);
    procedure TimerTick(ASender: TObject);
    procedure RunClick(ASender: TObject);
    procedure CancelClick(ASender: TObject);
    procedure CopyCallClick(ASender: TObject);
    procedure ExportClick(ASender: TObject);
  public
    /// <summary>Legt den Reiter in APages an. AStatusRoot: Ordner der Statusdateien (Fortschritt); AOnInform zeigt
    /// Hinweise und ist gesetzt.</summary>
    constructor Create(AOwner: TComponent; APages: TPageControl; const AState: TMonitorCheckState;
      const AStatusRoot: string; const AOnInform: TProc<string>; const AOnConfirm: TMonitorConfirm); reintroduce;
    destructor Destroy; override;
    /// <summary>Zeigt den Reiter und füllt Listen; erst mit Fenster (CreateWnd des Formulars).</summary>
    procedure Activate;
    /// <summary>Läuft gerade ein Befehl?</summary>
    function Busy: Boolean;
    /// <summary>Bricht alle Läufe ab (Schließen des Programms).</summary>
    procedure CancelRuns;
    /// <summary>Aktueller Stand für monitor.json: Ziele der Liste, Befehl und Optionen.</summary>
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

/// <summary>Schreibt AText nach AFileName und meldet das Ergebnis an AInform.</summary>
procedure SaveText(const AFileName, AText: string; const AInform: TProc<string>);
begin
  try
    TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
    AInform(TMonitorTexts.Fmt(TMonitorText.Exported, [AFileName]));
  except
    // lsp-ignore: catch-all-without-raise -- der Hinweis nennt den Fehler
    on E: Exception do
      AInform(TMonitorTexts.Fmt(TMonitorText.SaveFailed, [E.Message]));
  end;
end;

/// <summary>Leert AFolder für die Ausgaben eines neuen Laufs; False mit dem Fehler in AError.</summary>
function PrepareWorkFolder(const AFolder: string; out AError: string): Boolean;
begin
  AError := '';
  try
    if TDirectory.Exists(AFolder) then
    begin
      TDirectory.Delete(AFolder, True);
    end;
    ForceDirectories(AFolder);
    Result := True;
  except
    // lsp-ignore: catch-all-without-raise -- der Aufrufer meldet den Fehler, der Lauf startet nicht
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

/// <summary>Ausgabe von Lauf AIndex nach seinem Ende: Fehlertext aus dem Protokoll bzw. Befunde aus SARIF.</summary>
procedure ReadOutput(var AQueue: TMonitorRunQueue; AIndex: Integer);
var
  mFindings: TArray<TMonitorFinding>;
  mError: string;
begin
  if AQueue.Runs[AIndex].State = TMonitorRunState.Failed then
  begin
    AQueue.Runs[AIndex].ErrorText := Trim(AQueue.Runs[AIndex].ErrorText + sLineBreak +
      ReadText(AQueue.Runs[AIndex].LogFile));
    Exit;
  end;
  if TMonitorCommands.OutputKind(AQueue.Command) <> TMonitorOutputKind.Findings then
  begin
    Exit;
  end;
  if TMonitorResults.ParseSarif(ReadText(AQueue.Runs[AIndex].OutputFile), AQueue.Runs[AIndex].Target, mFindings,
    mError) then
  begin
    AQueue.Runs[AIndex].Findings := mFindings;
  end
  else
  begin
    AQueue.Runs[AIndex].ErrorText := mError + sLineBreak + ReadText(AQueue.Runs[AIndex].LogFile);
  end;
end;

/// <summary>Fortschritt von Lauf AIndex aus der Statusdatei des Kindprozesses APid unter AStatusRoot.</summary>
procedure ReadProgress(var AQueue: TMonitorRunQueue; AIndex: Integer; const AStatusRoot: string; APid: Cardinal);
var
  mEntry: TServerStatusEntry;
begin
  for mEntry in TServerStatusFile.List(AStatusRoot, Now, nil) do
  begin
    if mEntry.Pid = APid then
    begin
      AQueue.Runs[AIndex].Done := mEntry.Done;
      AQueue.Runs[AIndex].Total := mEntry.Total;
    end;
  end;
end;

/// <summary>Knopf ACaption in der Leiste AParent ab ALeft; ALeft rückt hinter ihn.</summary>
function AddButton(AOwner: TComponent; AParent: TWinControl; var ALeft: Integer; const ACaption: string;
  const AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  Result.SetBounds(ALeft, Px(cGap), Px(cButtonWidth), Px(cToolbarHeight - 2 * cGap));
  Result.Parent := AParent;
  ALeft := ALeft + Px(cButtonWidth + cGap);
end;

{ TMonitorTargetsView }

constructor TMonitorTargetsView.Create(AOwner: TComponent; AParent: TWinControl; const ATargets: TMonitorTargetList;
  const AIsBusy: TFunc<Boolean>; const AOnSelect: TProc; const AOnInform: TProc<string>);
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
  inherited Create(AOwner);
  FTargets := ATargets;
  FIsBusy := AIsBusy;
  FOnSelect := AOnSelect;
  FOnInform := AOnInform;
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
  FList := TListView.Create(Self);
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnItemChecked := TargetChecked;
  FList.OnSelectItem := TargetSelected;
  FList.Columns.Add.Caption := TMonitorTexts.Text(TMonitorText.ColumnTarget);
  FList.Columns.Add.Caption := TMonitorTexts.Text(TMonitorText.ColumnKind);
  FList.Columns.Add.Caption := TMonitorTexts.Text(TMonitorText.ColumnState);
  FList.Columns[0].Width := Px(420);
  FList.Columns[1].Width := Px(110);
  FList.Columns[2].Width := Px(200);
  FList.Parent := mPanel;
end;

procedure TMonitorTargetsView.Activate;
begin
  FList.HandleNeeded;
  Fill;
end;

procedure TMonitorTargetsView.Fill;
var
  mTarget: TMonitorTarget;
  mItem: TListItem;
begin
  if not FList.HandleAllocated then
  begin
    Exit;
  end;
  FFilling := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mTarget in FTargets.Items do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := mTarget.Path;
      mItem.SubItems.Add(mTarget.KindText);
      mItem.SubItems.Add('');
      mItem.Checked := mTarget.Enabled;
    end;
  finally
    FList.Items.EndUpdate;
    FFilling := False;
  end;
end;

procedure TMonitorTargetsView.ShowStates(const AQueue: TMonitorRunQueue);
var
  mRun: TMonitorRun;
  mIndex: Integer;
begin
  for mRun in AQueue.Runs do
  begin
    mIndex := FTargets.IndexOf(mRun.Target);
    if (mIndex >= 0) and (mIndex < FList.Items.Count) then
    begin
      FList.Items[mIndex].SubItems[1] := TMonitorRunQueue.StateText(AQueue.Command, mRun);
    end;
  end;
end;

function TMonitorTargetsView.SelectedPath: string;
begin
  Result := '';
  if FList.Selected <> nil then
  begin
    Result := FList.Selected.Caption;
  end;
end;

procedure TMonitorTargetsView.TargetChecked(ASender: TObject; AItem: TListItem);
begin
  if not FFilling and (AItem.Index <= High(FTargets.Items)) then
  begin
    FTargets.Items[AItem.Index].Enabled := AItem.Checked;
  end;
end;

procedure TMonitorTargetsView.TargetSelected(ASender: TObject; AItem: TListItem; ASelected: Boolean);
begin
  if ASelected then
  begin
    FOnSelect();
  end;
end;

procedure TMonitorTargetsView.AddFolderClick(ASender: TObject);
var
  mDialog: TFileOpenDialog;
begin
  mDialog := TFileOpenDialog.Create(nil);
  try
    mDialog.Title := TMonitorTexts.Text(TMonitorText.ChooseFolder);
    mDialog.Options := [fdoPickFolders, fdoPathMustExist];
    if mDialog.Execute then
    begin
      FTargets.Add(mDialog.FileName);
      Fill;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorTargetsView.AddFileClick(ASender: TObject);
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
        FTargets.Add(mFile);
      end;
      Fill;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorTargetsView.RemoveClick(ASender: TObject);
begin
  if (FList.Selected <> nil) and not FIsBusy() then
  begin
    FTargets.Delete(FList.Selected.Index);
    Fill;
  end;
end;

procedure TMonitorTargetsView.SaveListClick(ASender: TObject);
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
      SaveText(mDialog.FileName, FTargets.ToText, FOnInform);
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorTargetsView.LoadListClick(ASender: TObject);
var
  mDialog: TOpenDialog;
begin
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterTargets);
    mDialog.Options := [ofFileMustExist, ofEnableSizing];
    if mDialog.Execute and not FIsBusy() then
    begin
      FTargets := TMonitorTargetList.FromText(ReadText(mDialog.FileName));
      Fill;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TMonitorFindingsView }

constructor TMonitorFindingsView.Create(AOwner: TComponent; AParent: TWinControl; const AAll: TMonitorFindingsFunc;
  const AOnOpen: TMonitorFindingProc);
var
  mFilter: TPanel;
  mTitle: string;
  mColumn: TListColumn;
begin
  inherited Create(AOwner);
  FAll := AAll;
  FOnOpen := AOnOpen;
  mFilter := TPanel.Create(Self);
  mFilter.Height := Px(cToolbarHeight - cGap);
  mFilter.Align := alTop;
  mFilter.BevelOuter := bvNone;
  mFilter.Parent := AParent;
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
  FTextView.Parent := AParent;
  FList := TListView.Create(Self);
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.OnData := FindingData;
  FList.OnDblClick := FindingDblClick;
  for mTitle in TMonitorResults.ColumnTitles do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := mTitle;
    mColumn.Width := Px(90);
  end;
  FList.Columns[1].Width := Px(300);
  FList.Columns[4].Width := Px(400);
  FList.Parent := AParent;
end;

destructor TMonitorFindingsView.Destroy;
begin
  FShown := nil;
  inherited;
end;

procedure TMonitorFindingsView.Activate;
var
  I: Integer;
begin
  FList.HandleNeeded;
  FLevelBox.Items.Clear;
  FLevelBox.Items.Add(TMonitorTexts.Text(TMonitorText.SeverityAll));
  for I := 1 to High(cLevels) do
  begin
    FLevelBox.Items.Add(TMonitorResults.LevelText(cLevels[I]));
  end;
  FLevelBox.ItemIndex := 0;
end;

procedure TMonitorFindingsView.Clear;
begin
  FShown := nil;
  Fill;
  FTextView.Clear;
end;

procedure TMonitorFindingsView.Refilter;
begin
  FShown := TMonitorResults.Filter(FAll(), FFilterEdit.Text, cLevels[Max(FLevelBox.ItemIndex, 0)]);
  Fill;
end;

procedure TMonitorFindingsView.ShowList;
begin
  FList.Visible := True;
  FTextView.Visible := False;
end;

procedure TMonitorFindingsView.ShowText(const AText: string);
begin
  FList.Visible := False;
  FTextView.Visible := True;
  FTextView.Text := AText;
end;

function TMonitorFindingsView.Text: string;
begin
  Result := FTextView.Text;
end;

procedure TMonitorFindingsView.Fill;
begin
  if FList.HandleAllocated then
  begin
    FList.Items.Count := Length(FShown);
    FList.Invalidate;
  end;
end;

procedure TMonitorFindingsView.FilterChange(ASender: TObject);
begin
  Refilter;
end;

procedure TMonitorFindingsView.FindingData(ASender: TObject; AItem: TListItem);
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

procedure TMonitorFindingsView.FindingDblClick(ASender: TObject);
begin
  if (FList.Selected <> nil) and (FList.Selected.Index <= High(FShown)) then
  begin
    FOnOpen(FShown[FList.Selected.Index]);
  end;
end;

{ TMonitorCheckExport }

constructor TMonitorCheckExport.Create(const AServer, AWorkFolder: string; const AOnInform: TProc<string>);
begin
  inherited Create;
  FServer := AServer;
  FWorkFolder := AWorkFolder;
  FOnInform := AOnInform;
  FChild := TMonitorChildProcess.Create;
end;

destructor TMonitorCheckExport.Destroy;
begin
  // Kein Kindprozess überlebt den Monitor.
  FreeAndNil(FChild);
  inherited;
end;

procedure TMonitorCheckExport.Findings(const AQueue: TMonitorRunQueue);
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
      for mRun in AQueue.Runs do
      begin
        mTexts := mTexts + [ReadText(mRun.OutputFile)];
      end;
      SaveText(mDialog.FileName, TMonitorResults.MergeSarif(mTexts), FOnInform);
    end
    else
    begin
      SaveText(mDialog.FileName, TMonitorResults.Html(AQueue.AllFindings, TMonitorCommands.Text(AQueue.Command)),
        FOnInform);
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TMonitorCheckExport.Text(const AQueue: TMonitorRunQueue; const AText: string);
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TMonitorTexts.Text(TMonitorText.FilterText);
    mDialog.DefaultExt := TMonitorCommands.OutputExtension(AQueue.Command).Substring(1);
    mDialog.Options := [ofOverwritePrompt, ofEnableSizing];
    if mDialog.Execute then
    begin
      SaveText(mDialog.FileName, AText, FOnInform);
    end;
  finally
    mDialog.Free;
  end;
end;

// HTML-Seite des Laufs kopieren; Markdown und JSON schreibt ein eigener Lauf des Servers.
function TMonitorCheckExport.Report(const AQueue: TMonitorRunQueue; AIndex: Integer;
  const AOptions: TMonitorOptions): Boolean;
var
  mDialog: TSaveDialog;
  mError: string;
begin
  Result := False;
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
      SaveText(mDialog.FileName, ReadText(AQueue.Runs[AIndex].OutputFile), FOnInform);
    end
    else if FChild.Start(FServer, TMonitorCommands.Arguments(AQueue.Command, AQueue.Runs[AIndex].Target,
      AOptions, mDialog.FileName, TAtlasLocale.Code(TAtlasLocale.Language)),
      FolderOf(AQueue.Runs[AIndex].Target), TPath.Combine(FWorkFolder, 'export.log'), mError) then
    begin
      FFile := mDialog.FileName;
      Result := True;
    end
    else
    begin
      FOnInform(TMonitorTexts.Fmt(TMonitorText.StartFailed, [mError]));
    end;
  finally
    mDialog.Free;
  end;
end;

function TMonitorCheckExport.Poll: Boolean;
begin
  if (FFile <> '') and FChild.Poll then
  begin
    FOnInform(TMonitorTexts.Fmt(TMonitorText.Exported, [FFile]));
    FFile := '';
  end;
  Result := FFile <> '';
end;

procedure TMonitorCheckExport.Cancel;
begin
  FChild.Terminate;
  FFile := '';
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
  // Anonyme Methoden statt Methoden: TFunc/TProc passen nicht zu const-Parametern, Delphi riefe Busy sonst auf.
  FTargets := TMonitorTargetsView.Create(Self, FTab, AState.Targets,
    function: Boolean
    begin
      Result := Busy;
    end,
    procedure
    begin
      if not Busy then
      begin
        ShowRun(SelectedRun);
      end;
    end, AOnInform);
  FOptions := TMonitorCheckOptions.Create(Self, FTab);
  BuildResults(FTab);
  FReport := TMonitorReportPage.Create(Self, FPages, AOnInform);
  FChild := TMonitorChildProcess.Create;
  FExport := TMonitorCheckExport.Create(FServer, FWorkFolder, AOnInform);
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
  FreeAndNil(FExport);
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
  inherited;
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
  FRunButton := AddButton(Self, mBar, mLeft, TMonitorTexts.Text(TMonitorText.Run), RunClick);
  FCancelButton := AddButton(Self, mBar, mLeft, TMonitorTexts.Text(TMonitorText.Cancel), CancelClick);
  FCancelButton.Enabled := False;
  AddButton(Self, mBar, mLeft, TMonitorTexts.Text(TMonitorText.CopyCall), CopyCallClick);
  AddButton(Self, mBar, mLeft, TMonitorTexts.Text(TMonitorText.Export), ExportClick);
  FSummary := TLabel.Create(Self);
  FSummary.SetBounds(mLeft, Px(2 * cGap), Px(300), Px(cToolbarHeight - 2 * cGap));
  FSummary.Parent := mBar;
end;

procedure TMonitorCheckPage.BuildResults(AParent: TWinControl);
var
  mResults: TPanel;
begin
  mResults := TPanel.Create(Self);
  mResults.Align := alClient;
  mResults.BevelOuter := bvNone;
  mResults.Parent := AParent;
  BuildToolbar(mResults);
  FFindings := TMonitorFindingsView.Create(Self, mResults,
    function: TArray<TMonitorFinding>
    begin
      Result := FQueue.AllFindings;
    end, OpenFinding);
end;

procedure TMonitorCheckPage.Activate;
begin
  FTab.TabVisible := True;
  FTargets.Activate;
  FFindings.Activate;
  FOptions.Activate(FState);
end;

function TMonitorCheckPage.Busy: Boolean;
begin
  Result := FQueue.Busy;
end;

function TMonitorCheckPage.State: TMonitorCheckState;
begin
  FOptions.Store(FState);
  FState.Targets := FTargets.Targets;
  Result := FState;
end;


procedure TMonitorCheckPage.UpdateTargetStates;
begin
  FTargets.ShowStates(FQueue);
  FSummary.Caption := FQueue.Summary;
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
    FOnInform(TMonitorTexts.Fmt(TMonitorText.ServerMissing, [FServer]));
    Exit;
  end;
  if TMonitorCommands.NeedsTarget(FState.Command) and (FState.Targets.EnabledPaths = nil) then
  begin
    FOnInform(TMonitorTexts.Text(TMonitorText.NoTargets));
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
    FOnInform(TMonitorTexts.Fmt(TMonitorText.MissingInput, [FOptions.FieldCaption(mMissing)]));
    Exit;
  end;
  Result := not TMonitorCommands.Writes(FState.Command, FState.Options) or FOnConfirm(TMonitorTexts.Fmt(
    TMonitorText.ConfirmWrite, [TMonitorCommands.Text(FState.Command), Length(FState.Targets.EnabledPaths)]));
end;

procedure TMonitorCheckPage.RunClick(ASender: TObject);
var
  mError: string;
begin
  FState := State;
  if Busy or not Validate then
  begin
    Exit;
  end;
  if not PrepareWorkFolder(FWorkFolder, mError) then
  begin
    FOnInform(TMonitorTexts.Fmt(TMonitorText.StartFailed, [mError]));
    Exit;
  end;
  FQueue := TMonitorRunQueue.Create(FState.Command, FState.Targets.EnabledPaths);
  FFindings.Clear;
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

procedure TMonitorCheckPage.FinishRun(AIndex, AExitCode: Integer);
begin
  FQueue.Finish(AIndex, AExitCode);
  ReadOutput(FQueue, AIndex);
  if TMonitorCommands.OutputKind(FQueue.Command) = TMonitorOutputKind.Findings then
  begin
    FFindings.Refilter;
  end;
end;

procedure TMonitorCheckPage.TimerTick(ASender: TObject);
var
  mIndex: Integer;
  mExporting: Boolean;
begin
  mExporting := FExport.Poll;
  mIndex := FQueue.RunningIndex;
  if mIndex < 0 then
  begin
    FTimer.Enabled := mExporting;
    Exit;
  end;
  if FChild.Poll then
  begin
    FinishRun(mIndex, FChild.ExitCode);
    StartNext;
  end
  else
  begin
    ReadProgress(FQueue, mIndex, FStatusRoot, FChild.Pid);
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
  FExport.Cancel;
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
  mPath: string;
begin
  Result := -1;
  mPath := FTargets.SelectedPath;
  if mPath = '' then
  begin
    Exit;
  end;
  for I := 0 to High(FQueue.Runs) do
  begin
    if SameText(FQueue.Runs[I].Target, mPath) then
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
  mText: string;
begin
  if (AIndex < 0) or (AIndex > High(FQueue.Runs)) then
  begin
    Exit;
  end;
  mRun := FQueue.Runs[AIndex];
  mKind := TMonitorCommands.OutputKind(FQueue.Command);
  if (mKind = TMonitorOutputKind.Findings) and (mRun.ErrorText = '') then
  begin
    FFindings.ShowList;
    Exit;
  end;
  mText := Trim(TMonitorRunQueue.StateText(FQueue.Command, mRun) + sLineBreak + mRun.ErrorText +
    sLineBreak + ReadText(mRun.OutputFile) + sLineBreak + ReadText(TMonitorCommands.TimingsFileOf(mRun.OutputFile)));
  if (mKind = TMonitorOutputKind.Html) and (mRun.State = TMonitorRunState.Done) then
  begin
    mText := TMonitorRunQueue.StateText(FQueue.Command, mRun);
    FReport.ShowFile(mRun.OutputFile);
  end;
  FFindings.ShowText(mText);
end;

/// <summary>Doppelklick auf einen Befund: Stelle im Editor bzw. im zugeordneten Programm öffnen.</summary>
procedure TMonitorCheckPage.OpenFinding(const AFinding: TMonitorFinding);
var
  mCommand: string;
begin
  FOptions.Store(FState);
  mCommand := TMonitorCheckState.EditorCommand(FState.Editor, AFinding.FileName, AFinding.Line, AFinding.Column);
  if mCommand <> '' then
  begin
    TMonitorSystem.Launch(mCommand);
  end
  else
  begin
    TMonitorSystem.OpenFile(AFinding.FileName);
  end;
end;

procedure TMonitorCheckPage.CopyCallClick(ASender: TObject);
var
  mLines: TStringList;
  mTarget: string;
  mTargets: TArray<string>;
begin
  FState := State;
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
  FOnInform(TMonitorTexts.Text(TMonitorText.CallCopied));
end;

procedure TMonitorCheckPage.ExportClick(ASender: TObject);
begin
  if Busy or (FQueue.Runs = nil) then
  begin
    Exit;
  end;
  case TMonitorCommands.OutputKind(FQueue.Command) of
    TMonitorOutputKind.Findings:
      FExport.Findings(FQueue);
    TMonitorOutputKind.Html:
      if FExport.Report(FQueue, Max(SelectedRun, 0), FState.Options) then
      begin
        FTimer.Enabled := True;
      end;
  else
    FExport.Text(FQueue, FFindings.Text);
  end;
end;

end.
