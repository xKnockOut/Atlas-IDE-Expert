unit Atlas.UI.Diagnostics.ProcessesDialog;

// Fenster „Prozesse am Projekt“ (#62), ohne Open Tools API:
//   Atlas-Server für <Gruppe>                       [Arbeitsbereich ▾] (ab zwei)
//   Index-Cache   3f9a…\Gruppe.idx
//   Sperre        LSP · Atlas IDE Expert (pid 4711)  [schreibt]
//   Stand         vor 12 s gespeichert · Format 17
//   Art | Client                         | Zustand
//   LSP | Atlas IDE Expert (pid 4711) (dieser Prozess) | baut Index
//   MCP | Claude Code (pid 5120)          | liest Cache
//   Index nur einmal aufgebaut · 412 Units                     3 Prozesse
//   Ungespeicherte Stände bleiben je Prozess getrennt
//   Datei | IDE (dieser Prozess) | MCP-Prozess
//   Claude Code sieht den gespeicherten Stand, bis die IDE speichert.
//   Protokoll (Sperr- und Cache-Ereignisse nach Zeit)
//   [Aktualisieren] [Kopieren]                                  [Schließen]
// Die Daten kommen von atlas.server.processes (TAtlasProcessesView); die
// ungespeicherten Dateien liefert die IDE-Schicht (Tests setzen eigene).
// Eine Antwort, die nach dem Schließen eintrifft, wird verworfen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Atlas.UI.Strings,
  Atlas.Core.Diagnostics.Processes;

type
  TAtlasProcessesActions = record
    /// <summary>atlas.server.processes im Hintergrund; die Antwort (nil ohne Server) kommt im Hauptthread.</summary>
    Fetch: TProc<TProc<TJSONValue>>;
    /// <summary>Geänderte, nicht gespeicherte Dateien der IDE.</summary>
    ModifiedFiles: TFunc<TArray<string>>;
    /// <summary>Text in die Zwischenablage legen.</summary>
    CopyText: TProc<string>;
  end;

  /// <summary>Lebt, solange das Fenster lebt; Antworten prüfen es vor dem Zugriff.</summary>
  TAtlasProcessesAlive = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  TAtlasProcessesDialog = class(TForm)
  public const
    Gap = 8;
    LabelWidth = 90;
  private
    FActions: TAtlasProcessesActions;
    FAlive: TAtlasProcessesAlive;
    FAliveRef: IInterface;
    FWorkspaces: TArray<TAtlasProcessWorkspace>;
    FMarkdown: string;
    FHeading: TLabel;
    FChoice: TComboBox;
    FCacheValue: TLabel;
    FLockValue: TLabel;
    FWriterTag: TLabel;
    FStateValue: TLabel;
    FList: TListView;
    FBuiltOnce: TLabel;
    FCount: TLabel;
    FDirty: TListView;
    FDirtyNote: TLabel;
    FLog: TMemo;
    FStatus: TLabel;
    FRefreshButton: TButton;
    FCopyButton: TButton;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    function AddRow(AParent: TWinControl; ACaption: TAtlasTextId; ATop: Integer): TLabel;
    function AddButton(AParent: TWinControl; const ACaption: string; ALeft: Integer;
      const AClick: TNotifyEvent): TButton;
    procedure ChoiceChange(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ShowWorkspace(AIndex: Integer);
    procedure ShowDirty;
  public
    constructor CreateDialog(AOwner: TComponent; const AActions: TAtlasProcessesActions);
    destructor Destroy; override;
    /// <summary>Server fragen; die Antwort füllt das Fenster.</summary>
    procedure Refresh;
    /// <summary>Antwort von atlas.server.processes anzeigen (nil: Server antwortet nicht).</summary>
    procedure ShowAnswer(const AAnswer: TJSONValue);
    class procedure Execute(const AActions: TAtlasProcessesActions); static;
    property Workspaces: TArray<TAtlasProcessWorkspace> read FWorkspaces;
    property Markdown: string read FMarkdown;
    property Heading: TLabel read FHeading;
    property Choice: TComboBox read FChoice;
    property CacheValue: TLabel read FCacheValue;
    property LockValue: TLabel read FLockValue;
    property WriterTag: TLabel read FWriterTag;
    property StateValue: TLabel read FStateValue;
    property List: TListView read FList;
    property BuiltOnceLabel: TLabel read FBuiltOnce;
    property CountLabel: TLabel read FCount;
    property Dirty: TListView read FDirty;
    property DirtyNote: TLabel read FDirtyNote;
    property Log: TMemo read FLog;
    property StatusLabel: TLabel read FStatus;
    property CopyButton: TButton read FCopyButton;
  end;

implementation

{ TAtlasProcessesDialog }

constructor TAtlasProcessesDialog.CreateDialog(AOwner: TComponent; const AActions: TAtlasProcessesActions);
var
  Head, Foot, Info, Counts, DirtyBox, LogBox: TPanel;
  Column: TListColumn;
  CloseButton: TButton;
begin
  inherited CreateNew(AOwner);
  FActions := AActions;
  FAlive := TAtlasProcessesAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesTitleNone);
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := 760;
  Height := 680;
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 480;

  // Kopf: Gruppe und (ab zwei Arbeitsbereichen) die Auswahl.
  Head := TPanel.Create(Self);
  Head.Parent := Self;
  Head.Align := alTop;
  Head.Height := 36;
  Head.BevelOuter := bvNone;
  FHeading := AddLabel(Head, TAtlasStrings.Text(TAtlasTextId.ProcessesTitleNone));
  FHeading.SetBounds(Gap, Gap + 2, 400, 20);
  FHeading.Font.Style := [fsBold];
  FHeading.Font.Size := FHeading.Font.Size + 2;
  FChoice := TComboBox.Create(Self);
  FChoice.Parent := Head;
  FChoice.Style := csDropDownList;
  FChoice.SetBounds(Head.Width - 260 - Gap, Gap, 260, 24);
  FChoice.Anchors := [akTop, akRight];
  FChoice.Visible := False;
  FChoice.OnChange := ChoiceChange;

  // Cache, Sperre, Stand.
  Info := TPanel.Create(Self);
  Info.Parent := Self;
  Info.Align := alTop;
  Info.Top := Head.Top + Head.Height;
  Info.Height := 3 * 22 + Gap;
  Info.BevelOuter := bvNone;
  FCacheValue := AddRow(Info, TAtlasTextId.ProcessesCache, 0);
  FLockValue := AddRow(Info, TAtlasTextId.ProcessesLock, 22);
  FWriterTag := AddLabel(Info, TAtlasStrings.Text(TAtlasTextId.ProcessesWrites));
  FWriterTag.Font.Style := [fsBold];
  FWriterTag.Visible := False;
  FStateValue := AddRow(Info, TAtlasTextId.ProcessesState, 44);

  // Fuß mit den Knöpfen.
  Foot := TPanel.Create(Self);
  Foot.Parent := Self;
  Foot.Align := alBottom;
  Foot.Height := 44;
  Foot.BevelOuter := bvNone;
  FRefreshButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ProcessesRefresh), Gap, RefreshClick);
  FCopyButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ProcessesCopy), 2 * Gap + 110, CopyClick);
  FCopyButton.Enabled := False;
  CloseButton := AddButton(Foot, TAtlasStrings.Text(TAtlasTextId.ProcessesClose), Foot.Width - 110 - Gap, nil);
  CloseButton.Anchors := [akTop, akRight];
  CloseButton.Cancel := True;
  CloseButton.ModalResult := mrCancel;
  FStatus := AddLabel(Foot, '');
  FStatus.SetBounds(3 * Gap + 220, 14, 300, 18);

  // Protokoll unten, darüber die ungespeicherten Stände; die Prozessliste füllt den Rest.
  LogBox := TPanel.Create(Self);
  LogBox.Parent := Self;
  LogBox.Align := alBottom;
  LogBox.Height := 150;
  LogBox.BevelOuter := bvNone;
  AddLabel(LogBox, TAtlasStrings.Text(TAtlasTextId.ProcessesLog)).Align := alTop;
  FLog := TMemo.Create(Self);
  FLog.Parent := LogBox;
  FLog.Align := alClient;
  FLog.AlignWithMargins := True;
  FLog.Margins.SetBounds(Gap, 2, Gap, 0);
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssBoth;
  FLog.WordWrap := False;
  FLog.Font.Name := 'Consolas';
  FLog.Font.Size := 9;

  DirtyBox := TPanel.Create(Self);
  DirtyBox.Parent := Self;
  DirtyBox.Align := alBottom;
  DirtyBox.Height := 140;
  DirtyBox.BevelOuter := bvNone;
  AddLabel(DirtyBox, TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyCaption)).Align := alTop;
  FDirtyNote := AddLabel(DirtyBox, TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyNote));
  FDirtyNote.Align := alBottom;
  FDirty := TListView.Create(Self);
  FDirty.Parent := DirtyBox;
  FDirty.Align := alClient;
  FDirty.AlignWithMargins := True;
  FDirty.Margins.SetBounds(Gap, 2, Gap, 2);
  FDirty.ViewStyle := vsReport;
  FDirty.ReadOnly := True;
  FDirty.RowSelect := True;
  Column := FDirty.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyFile);
  Column.Width := 260;
  Column := FDirty.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyIde);
  Column.Width := 180;
  Column := FDirty.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyMcp);
  Column.Width := 180;

  Counts := TPanel.Create(Self);
  Counts.Parent := Self;
  Counts.Align := alBottom;
  Counts.Height := 24;
  Counts.BevelOuter := bvNone;
  FBuiltOnce := AddLabel(Counts, '');
  FBuiltOnce.SetBounds(Gap, 4, 400, 18);
  FCount := AddLabel(Counts, '');
  FCount.Alignment := taRightJustify;
  FCount.AutoSize := False;
  FCount.SetBounds(Counts.Width - 200 - Gap, 4, 200, 18);
  FCount.Anchors := [akTop, akRight];

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, 0, Gap, 0);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesColumnKind);
  Column.Width := 60;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesColumnClient);
  Column.Width := 380;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesColumnState);
  Column.Width := 160;
  ShowDirty;
end;

destructor TAtlasProcessesDialog.Destroy;
begin
  // Spät eintreffende Antworten fassen das Fenster nicht mehr an.
  FAlive.Alive := False;
  FAliveRef := nil;
  FWorkspaces := nil;
  inherited Destroy;
end;

function TAtlasProcessesDialog.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, 2, Gap, 2);
  Result.Caption := ACaption;
end;

function TAtlasProcessesDialog.AddRow(AParent: TWinControl; ACaption: TAtlasTextId; ATop: Integer): TLabel;
var
  mName: TLabel;
begin
  mName := AddLabel(AParent, TAtlasStrings.Text(ACaption));
  mName.SetBounds(Gap, ATop + 2, LabelWidth, 18);
  mName.Font.Color := clGrayText;
  Result := AddLabel(AParent, '');
  Result.Left := Gap + LabelWidth + Gap;
  Result.Top := ATop + 2;
end;

function TAtlasProcessesDialog.AddButton(AParent: TWinControl; const ACaption: string; ALeft: Integer;
  const AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, 8, 110, 28);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure TAtlasProcessesDialog.Refresh;
var
  Alive: TAtlasProcessesAlive;
  Keep: IInterface;
begin
  FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesAsking);
  ShowDirty;
  if not Assigned(FActions.Fetch) then
    Exit;
  Alive := FAlive;
  Keep := FAliveRef;
  FActions.Fetch(
    procedure(AAnswer: TJSONValue)
    begin
      // Keep hält die Marke am Leben, bis die Antwort da ist.
      if Assigned(Keep) and Alive.Alive then
        ShowAnswer(AAnswer);
    end);
end;

procedure TAtlasProcessesDialog.ShowAnswer(const AAnswer: TJSONValue);
var
  Index: Integer;
begin
  FWorkspaces := TAtlasProcessesView.Parse(AAnswer);
  FMarkdown := TAtlasProcessesView.Markdown(AAnswer);
  FCopyButton.Enabled := FMarkdown <> '';
  if AAnswer = nil then
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer)
  else if Length(FWorkspaces) = 0 then
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesEmpty)
  else
    FStatus.Caption := '';
  if TAtlasProcessesView.GroupName(FWorkspaces) = '' then
    FHeading.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesTitleNone)
  else
    FHeading.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesTitle,
      [TAtlasProcessesView.GroupName(FWorkspaces)]);
  Caption := FHeading.Caption;
  FChoice.Items.BeginUpdate;
  try
    FChoice.Items.Clear;
    for Index := 0 to High(FWorkspaces) do
      FChoice.Items.Add(FWorkspaces[Index].Name);
  finally
    FChoice.Items.EndUpdate;
  end;
  FChoice.Visible := Length(FWorkspaces) > 1;
  if Length(FWorkspaces) > 0 then
    FChoice.ItemIndex := 0;
  ShowWorkspace(0);
  ShowDirty;
end;

procedure TAtlasProcessesDialog.ShowWorkspace(AIndex: Integer);
var
  Workspace: TAtlasProcessWorkspace;
  Row: TAtlasProcessRow;
  Item: TListItem;
  Line: TAtlasProcessLogLine;
  Client: string;
begin
  FList.Items.BeginUpdate;
  FLog.Lines.BeginUpdate;
  try
    FList.Items.Clear;
    FLog.Lines.Clear;
    if (AIndex < 0) or (AIndex > High(FWorkspaces)) then
    begin
      FCacheValue.Caption := '';
      FLockValue.Caption := '';
      FStateValue.Caption := '';
      FWriterTag.Visible := False;
      FBuiltOnce.Caption := '';
      FCount.Caption := '';
      Exit;
    end;
    Workspace := FWorkspaces[AIndex];
    FCacheValue.Caption := Workspace.Cache;
    if Workspace.LockHolder = '' then
      FLockValue.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesFree)
    else
      FLockValue.Caption := Workspace.LockHolder;
    // Marke „schreibt“ hinter dem Halter der Sperre; das Label misst sich selbst (AutoSize, ohne Fenster).
    FWriterTag.Visible := Workspace.LockHolder <> '';
    FWriterTag.Left := FLockValue.Left + FLockValue.Width + 2 * Gap;
    FWriterTag.Top := FLockValue.Top;
    FStateValue.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesSaved, [Workspace.Saved, Workspace.Format]);
    for Row in Workspace.Processes do
    begin
      Item := FList.Items.Add;
      Item.Caption := Row.Kind;
      Client := Row.Caption;
      if Row.Own then
        Client := Client + TAtlasStrings.Text(TAtlasTextId.ProcessesOwn);
      Item.SubItems.Add(Client);
      Item.SubItems.Add(Row.State);
    end;
    if Workspace.BuiltOnce then
      FBuiltOnce.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesBuiltOnce, [Workspace.Units])
    else
      FBuiltOnce.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesUnits, [Workspace.Units]);
    FCount.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesCount, [Length(Workspace.Processes)]);
    for Line in Workspace.Events do
      FLog.Lines.Add(Line.Time + '  ' + Line.Text);
  finally
    FLog.Lines.EndUpdate;
    FList.Items.EndUpdate;
  end;
end;

procedure TAtlasProcessesDialog.ShowDirty;
var
  Names: TArray<string>;
  mName, Mcp: string;
  Item: TListItem;
  HasMcp: Boolean;
  Workspace: TAtlasProcessWorkspace;
begin
  Names := nil;
  if Assigned(FActions.ModifiedFiles) then
    Names := TAtlasProcessesView.DirtyNames(FActions.ModifiedFiles());
  HasMcp := False;
  for Workspace in FWorkspaces do
    HasMcp := HasMcp or Workspace.HasMcp;
  // Ohne MCP-Prozess gibt es niemanden, der den gespeicherten Stand liest.
  Mcp := '';
  if HasMcp then
    Mcp := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyMcpText);
  FDirty.Items.BeginUpdate;
  try
    FDirty.Items.Clear;
    for mName in Names do
    begin
      Item := FDirty.Items.Add;
      Item.Caption := mName;
      Item.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyIdeText));
      Item.SubItems.Add(Mcp);
    end;
  finally
    FDirty.Items.EndUpdate;
  end;
  if Length(Names) = 0 then
    FDirtyNote.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyNone)
  else if HasMcp then
    FDirtyNote.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyNote)
  else
    FDirtyNote.Caption := '';
end;

procedure TAtlasProcessesDialog.ChoiceChange(Sender: TObject);
begin
  ShowWorkspace(FChoice.ItemIndex);
end;

procedure TAtlasProcessesDialog.RefreshClick(Sender: TObject);
begin
  Refresh;
end;

procedure TAtlasProcessesDialog.CopyClick(Sender: TObject);
begin
  if Assigned(FActions.CopyText) and (FMarkdown <> '') then
    FActions.CopyText(FMarkdown);
end;

class procedure TAtlasProcessesDialog.Execute(const AActions: TAtlasProcessesActions);
var
  Dialog: TAtlasProcessesDialog;
begin
  Dialog := TAtlasProcessesDialog.CreateDialog(nil, AActions);
  try
    Dialog.Refresh;
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

end.
