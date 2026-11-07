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
  private type
    /// <summary>Steuerelemente des Fensters.</summary>
    TParts = record
      Heading: TLabel;
      Choice: TComboBox;
      CacheValue: TLabel;
      LockValue: TLabel;
      WriterTag: TLabel;
      StateValue: TLabel;
      List: TListView;
      BuiltOnce: TLabel;
      Count: TLabel;
      Dirty: TListView;
      DirtyNote: TLabel;
      Log: TMemo;
      Status: TLabel;
      RefreshButton: TButton;
      CopyButton: TButton;
    end;
  private
    FActions: TAtlasProcessesActions;
    FAlive: TAtlasProcessesAlive;
    FAliveRef: IInterface;
    FWorkspaces: TArray<TAtlasProcessWorkspace>;
    FMarkdown: string;
    FParts: TParts;
    /// <summary>Kopf mit Gruppe und Auswahl, darunter Cache, Sperre und Stand.</summary>
    procedure CreateTop;
    /// <summary>Fuß mit den Knöpfen und dem Status.</summary>
    procedure CreateFoot;
    /// <summary>Protokoll unten.</summary>
    procedure CreateLog;
    /// <summary>Ungespeicherte Stände über dem Protokoll.</summary>
    procedure CreateDirty;
    /// <summary>Zähler und Prozessliste, die den Rest füllt.</summary>
    procedure CreateList;
    procedure ChoiceChange(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ShowWorkspace(AIndex: Integer);
    procedure ShowDirty;
  public
    constructor CreateDialog(AOwner: TComponent; const AActions: TAtlasProcessesActions);
    destructor Destroy; override;
    /// <summary>Server fragen; die Antwort füllt das Fenster.</summary>
    procedure Reload;
    /// <summary>Antwort von atlas.server.processes anzeigen (nil: Server antwortet nicht).</summary>
    procedure ShowAnswer(const AAnswer: TJSONValue);
    class procedure Execute(const AActions: TAtlasProcessesActions); static;
    property Workspaces: TArray<TAtlasProcessWorkspace> read FWorkspaces;
    property Markdown: string read FMarkdown;
    property Heading: TLabel read FParts.Heading;
    property Choice: TComboBox read FParts.Choice;
    property CacheValue: TLabel read FParts.CacheValue;
    property LockValue: TLabel read FParts.LockValue;
    property WriterTag: TLabel read FParts.WriterTag;
    property StateValue: TLabel read FParts.StateValue;
    property List: TListView read FParts.List;
    property BuiltOnceLabel: TLabel read FParts.BuiltOnce;
    property CountLabel: TLabel read FParts.Count;
    property Dirty: TListView read FParts.Dirty;
    property DirtyNote: TLabel read FParts.DirtyNote;
    property Log: TMemo read FParts.Log;
    property StatusLabel: TLabel read FParts.Status;
    property CopyButton: TButton read FParts.CopyButton;
  end;

implementation

function NewLabel(AOwner: TComponent; AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(TAtlasProcessesDialog.Gap, 2, TAtlasProcessesDialog.Gap, 2);
  Result.Caption := ACaption;
end;

/// <summary>Zeile „Name  Wert“ ab ATop; liefert die Beschriftung des Werts.</summary>
function NewRow(AOwner: TComponent; AParent: TWinControl; ACaption: TAtlasTextId; ATop: Integer): TLabel;
var
  mName: TLabel;
begin
  mName := NewLabel(AOwner, AParent, TAtlasStrings.Text(ACaption));
  mName.SetBounds(TAtlasProcessesDialog.Gap, ATop + 2, TAtlasProcessesDialog.LabelWidth, 18);
  mName.Font.Color := clGrayText;
  Result := NewLabel(AOwner, AParent, '');
  Result.Left := TAtlasProcessesDialog.Gap + TAtlasProcessesDialog.LabelWidth + TAtlasProcessesDialog.Gap;
  Result.Top := ATop + 2;
end;

function NewButton(AOwner: TComponent; AParent: TWinControl; const ACaption: string; ALeft: Integer;
  const AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, 8, 110, 28);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function NewPanel(AOwner: TWinControl; AAlign: TAlign; AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(AOwner);
  Result.Parent := AOwner;
  Result.Align := AAlign;
  Result.Height := AHeight;
  Result.BevelOuter := bvNone;
end;

/// <summary>Liste in Berichtsansicht, nur zum Lesen.</summary>
function NewList(AOwner: TComponent; AParent: TWinControl): TListView;
begin
  Result := TListView.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.AlignWithMargins := True;
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
end;

procedure AddColumn(AList: TListView; ACaption: TAtlasTextId; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(ACaption);
  mColumn.Width := AWidth;
end;

/// <summary>Eine Zeile je Prozess: Art, Client (mit Marke für den eigenen), Zustand.</summary>
procedure FillProcesses(AList: TListView; const ARows: TArray<TAtlasProcessRow>);
var
  mRow: TAtlasProcessRow;
  mItem: TListItem;
  mClient: string;
begin
  AList.Items.BeginUpdate;
  try
    for mRow in ARows do
    begin
      mItem := AList.Items.Add;
      mItem.Caption := mRow.Kind;
      mClient := mRow.Caption;
      if mRow.Own then
      begin
        mClient := mClient + TAtlasStrings.Text(TAtlasTextId.ProcessesOwn);
      end;
      mItem.SubItems.Add(mClient);
      mItem.SubItems.Add(mRow.State);
    end;
  finally
    AList.Items.EndUpdate;
  end;
end;

{ TAtlasProcessesDialog }

constructor TAtlasProcessesDialog.CreateDialog(AOwner: TComponent; const AActions: TAtlasProcessesActions);
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
  CreateTop;
  CreateFoot;
  // Protokoll unten, darüber die ungespeicherten Stände; die Prozessliste füllt den Rest.
  CreateLog;
  CreateDirty;
  CreateList;
  ShowDirty;
end;

procedure TAtlasProcessesDialog.CreateTop;
var
  mHead, mInfo: TPanel;
begin
  // Kopf: Gruppe und (ab zwei Arbeitsbereichen) die Auswahl.
  mHead := NewPanel(Self, alTop, 36);
  FParts.Heading := NewLabel(Self, mHead, TAtlasStrings.Text(TAtlasTextId.ProcessesTitleNone));
  FParts.Heading.SetBounds(Gap, Gap + 2, 400, 20);
  FParts.Heading.Font.Style := [fsBold];
  FParts.Heading.Font.Size := FParts.Heading.Font.Size + 2;
  FParts.Choice := TComboBox.Create(Self);
  FParts.Choice.Parent := mHead;
  FParts.Choice.Style := csDropDownList;
  FParts.Choice.SetBounds(mHead.Width - 260 - Gap, Gap, 260, 24);
  FParts.Choice.Anchors := [akTop, akRight];
  FParts.Choice.Visible := False;
  FParts.Choice.OnChange := ChoiceChange;

  // Cache, Sperre, Stand.
  mInfo := NewPanel(Self, alTop, 3 * 22 + Gap);
  mInfo.Top := mHead.Top + mHead.Height;
  FParts.CacheValue := NewRow(Self, mInfo, TAtlasTextId.ProcessesCache, 0);
  FParts.LockValue := NewRow(Self, mInfo, TAtlasTextId.ProcessesLock, 22);
  FParts.WriterTag := NewLabel(Self, mInfo, TAtlasStrings.Text(TAtlasTextId.ProcessesWrites));
  FParts.WriterTag.Font.Style := [fsBold];
  FParts.WriterTag.Visible := False;
  FParts.StateValue := NewRow(Self, mInfo, TAtlasTextId.ProcessesState, 44);
end;

procedure TAtlasProcessesDialog.CreateFoot;
var
  mFoot: TPanel;
  mClose: TButton;
begin
  mFoot := NewPanel(Self, alBottom, 44);
  FParts.RefreshButton := NewButton(Self, mFoot, TAtlasStrings.Text(TAtlasTextId.ProcessesRefresh), Gap,
    RefreshClick);
  FParts.CopyButton := NewButton(Self, mFoot, TAtlasStrings.Text(TAtlasTextId.ProcessesCopy), 2 * Gap + 110,
    CopyClick);
  FParts.CopyButton.Enabled := False;
  mClose := NewButton(Self, mFoot, TAtlasStrings.Text(TAtlasTextId.ProcessesClose), mFoot.Width - 110 - Gap, nil);
  mClose.Anchors := [akTop, akRight];
  mClose.Cancel := True;
  mClose.ModalResult := mrCancel;
  FParts.Status := NewLabel(Self, mFoot, '');
  FParts.Status.SetBounds(3 * Gap + 220, 14, 300, 18);
end;

procedure TAtlasProcessesDialog.CreateLog;
var
  mBox: TPanel;
begin
  mBox := NewPanel(Self, alBottom, 150);
  NewLabel(Self, mBox, TAtlasStrings.Text(TAtlasTextId.ProcessesLog)).Align := alTop;
  FParts.Log := TMemo.Create(Self);
  FParts.Log.Parent := mBox;
  FParts.Log.Align := alClient;
  FParts.Log.AlignWithMargins := True;
  FParts.Log.Margins.SetBounds(Gap, 2, Gap, 0);
  FParts.Log.ReadOnly := True;
  FParts.Log.ScrollBars := ssBoth;
  FParts.Log.WordWrap := False;
  FParts.Log.Font.Name := 'Consolas';
  FParts.Log.Font.Size := 9;
end;

procedure TAtlasProcessesDialog.CreateDirty;
var
  mBox: TPanel;
begin
  mBox := NewPanel(Self, alBottom, 140);
  NewLabel(Self, mBox, TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyCaption)).Align := alTop;
  FParts.DirtyNote := NewLabel(Self, mBox, TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyNote));
  FParts.DirtyNote.Align := alBottom;
  FParts.Dirty := NewList(Self, mBox);
  FParts.Dirty.Margins.SetBounds(Gap, 2, Gap, 2);
  AddColumn(FParts.Dirty, TAtlasTextId.ProcessesDirtyFile, 260);
  AddColumn(FParts.Dirty, TAtlasTextId.ProcessesDirtyIde, 180);
  AddColumn(FParts.Dirty, TAtlasTextId.ProcessesDirtyMcp, 180);
end;

procedure TAtlasProcessesDialog.CreateList;
var
  mCounts: TPanel;
begin
  mCounts := NewPanel(Self, alBottom, 24);
  FParts.BuiltOnce := NewLabel(Self, mCounts, '');
  FParts.BuiltOnce.SetBounds(Gap, 4, 400, 18);
  FParts.Count := NewLabel(Self, mCounts, '');
  FParts.Count.Alignment := taRightJustify;
  FParts.Count.AutoSize := False;
  FParts.Count.SetBounds(mCounts.Width - 200 - Gap, 4, 200, 18);
  FParts.Count.Anchors := [akTop, akRight];

  FParts.List := NewList(Self, Self);
  FParts.List.Margins.SetBounds(Gap, 0, Gap, 0);
  AddColumn(FParts.List, TAtlasTextId.ProcessesColumnKind, 60);
  AddColumn(FParts.List, TAtlasTextId.ProcessesColumnClient, 380);
  AddColumn(FParts.List, TAtlasTextId.ProcessesColumnState, 160);
end;

destructor TAtlasProcessesDialog.Destroy;
begin
  // Spät eintreffende Antworten fassen das Fenster nicht mehr an.
  FAlive.Alive := False;
  FAliveRef := nil;
  FWorkspaces := nil;
  inherited Destroy;
end;

procedure TAtlasProcessesDialog.Reload;
var
  mAlive: TAtlasProcessesAlive;
  mKeep: IInterface;
begin
  FParts.Status.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesAsking);
  ShowDirty;
  if not Assigned(FActions.Fetch) then
  begin
    Exit;
  end;
  mAlive := FAlive;
  mKeep := FAliveRef;
  FActions.Fetch(
    procedure(AAnswer: TJSONValue)
    begin
      // Keep hält die Marke am Leben, bis die Antwort da ist.
      if Assigned(mKeep) and mAlive.Alive then
      begin
        ShowAnswer(AAnswer);
      end;
    end);
end;

procedure TAtlasProcessesDialog.ShowAnswer(const AAnswer: TJSONValue);
var
  mIndex: Integer;
begin
  FWorkspaces := TAtlasProcessesView.Parse(AAnswer);
  FMarkdown := TAtlasProcessesView.Markdown(AAnswer);
  FParts.CopyButton.Enabled := FMarkdown <> '';
  if AAnswer = nil then
  begin
    FParts.Status.Caption := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
  end
  else if Length(FWorkspaces) = 0 then
  begin
    FParts.Status.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesEmpty);
  end
  else
  begin
    FParts.Status.Caption := '';
  end;
  if TAtlasProcessesView.GroupName(FWorkspaces) = '' then
  begin
    FParts.Heading.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesTitleNone);
  end
  else
  begin
    FParts.Heading.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesTitle,
      [TAtlasProcessesView.GroupName(FWorkspaces)]);
  end;
  Caption := FParts.Heading.Caption;
  FParts.Choice.Items.BeginUpdate;
  try
    FParts.Choice.Items.Clear;
    for mIndex := 0 to High(FWorkspaces) do
    begin
      FParts.Choice.Items.Add(FWorkspaces[mIndex].Name);
    end;
  finally
    FParts.Choice.Items.EndUpdate;
  end;
  FParts.Choice.Visible := Length(FWorkspaces) > 1;
  if Length(FWorkspaces) > 0 then
  begin
    FParts.Choice.ItemIndex := 0;
  end;
  ShowWorkspace(0);
  ShowDirty;
end;

procedure TAtlasProcessesDialog.ShowWorkspace(AIndex: Integer);
var
  mWorkspace: TAtlasProcessWorkspace;
  mLine: TAtlasProcessLogLine;
begin
  FParts.List.Items.BeginUpdate;
  FParts.Log.Lines.BeginUpdate;
  try
    FParts.List.Items.Clear;
    FParts.Log.Lines.Clear;
    if (AIndex < 0) or (AIndex > High(FWorkspaces)) then
    begin
      FParts.CacheValue.Caption := '';
      FParts.LockValue.Caption := '';
      FParts.StateValue.Caption := '';
      FParts.WriterTag.Visible := False;
      FParts.BuiltOnce.Caption := '';
      FParts.Count.Caption := '';
      Exit;
    end;
    mWorkspace := FWorkspaces[AIndex];
    FParts.CacheValue.Caption := mWorkspace.Cache;
    if mWorkspace.LockHolder = '' then
    begin
      FParts.LockValue.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesFree);
    end
    else
    begin
      FParts.LockValue.Caption := mWorkspace.LockHolder;
    end;
    // Marke „schreibt“ hinter dem Halter der Sperre; das Label misst sich selbst (AutoSize, ohne Fenster).
    FParts.WriterTag.Visible := mWorkspace.LockHolder <> '';
    FParts.WriterTag.Left := FParts.LockValue.Left + FParts.LockValue.Width + 2 * Gap;
    FParts.WriterTag.Top := FParts.LockValue.Top;
    FParts.StateValue.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesSaved, [mWorkspace.Saved, mWorkspace.Format]);
    FillProcesses(FParts.List, mWorkspace.Processes);
    if mWorkspace.BuiltOnce then
    begin
      FParts.BuiltOnce.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesBuiltOnce, [mWorkspace.Units]);
    end
    else
    begin
      FParts.BuiltOnce.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesUnits, [mWorkspace.Units]);
    end;
    FParts.Count.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProcessesCount, [Length(mWorkspace.Processes)]);
    for mLine in mWorkspace.Events do
    begin
      FParts.Log.Lines.Add(mLine.Time + '  ' + mLine.Text);
    end;
  finally
    FParts.Log.Lines.EndUpdate;
    FParts.List.Items.EndUpdate;
  end;
end;

procedure TAtlasProcessesDialog.ShowDirty;
var
  mNames: TArray<string>;
  mName, mMcp: string;
  mItem: TListItem;
  mHasMcp: Boolean;
  mWorkspace: TAtlasProcessWorkspace;
begin
  mNames := nil;
  if Assigned(FActions.ModifiedFiles) then
  begin
    mNames := TAtlasProcessesView.DirtyNames(FActions.ModifiedFiles());
  end;
  mHasMcp := False;
  for mWorkspace in FWorkspaces do
  begin
    mHasMcp := mHasMcp or mWorkspace.HasMcp;
  end;
  // Ohne MCP-Prozess gibt es niemanden, der den gespeicherten Stand liest.
  mMcp := '';
  if mHasMcp then
  begin
    mMcp := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyMcpText);
  end;
  FParts.Dirty.Items.BeginUpdate;
  try
    FParts.Dirty.Items.Clear;
    for mName in mNames do
    begin
      mItem := FParts.Dirty.Items.Add;
      mItem.Caption := mName;
      mItem.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyIdeText));
      mItem.SubItems.Add(mMcp);
    end;
  finally
    FParts.Dirty.Items.EndUpdate;
  end;
  if Length(mNames) = 0 then
  begin
    FParts.DirtyNote.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyNone);
  end
  else if mHasMcp then
  begin
    FParts.DirtyNote.Caption := TAtlasStrings.Text(TAtlasTextId.ProcessesDirtyNote);
  end
  else
  begin
    FParts.DirtyNote.Caption := '';
  end;
end;

procedure TAtlasProcessesDialog.ChoiceChange(Sender: TObject);
begin
  ShowWorkspace(FParts.Choice.ItemIndex);
end;

procedure TAtlasProcessesDialog.RefreshClick(Sender: TObject);
begin
  Reload;
end;

procedure TAtlasProcessesDialog.CopyClick(Sender: TObject);
begin
  if Assigned(FActions.CopyText) and (FMarkdown <> '') then
  begin
    FActions.CopyText(FMarkdown);
  end;
end;

class procedure TAtlasProcessesDialog.Execute(const AActions: TAtlasProcessesActions);
var
  mDialog: TAtlasProcessesDialog;
begin
  mDialog := TAtlasProcessesDialog.CreateDialog(nil, AActions);
  try
    mDialog.Reload;
    mDialog.ShowModal;
  finally
    mDialog.Free;
  end;
end;

end.
