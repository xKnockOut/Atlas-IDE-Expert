unit Atlas.UI.Vcs.WorkingCopies;

// Tabelle „Arbeitskopien“ (#1292): die Wurzel einer Gruppe und ihre
// svn:externals bzw. Git-Submodule, eingerückt unter dem Ordner darüber:
//   Arbeitskopie        Pfad im Repository         Revision        Geändert  Neu auf dem Server
//   Kasse               ^/Kasse/branches/KASSE-42  r48231          2         auf Klick
//   └ Packages\Basis    ^/Packages/Basis/trunk     r48190 · fest   0         auf Klick
// Die IDE-Schicht füllt die Zeilen nacheinander (SetList, dann SetRow je
// Zeile); bis dahin steht „wird ermittelt …“. „Neu auf dem Server“ fragt den
// Server nur auf Klick („Server prüfen“, je Zeile „prüft …“). Doppelklick
// öffnet den Ordner; das Kontextmenü bietet „Aktualisieren“ (mit den
// Externals darunter), „Nur diese aktualisieren“ (--ignore-externals),
// „Revision festschreiben …“ (nur Externals ohne feste Revision mit bekannter
// Revision) und „Ordner öffnen“. Ausgeführt wird nicht hier: Die Ereignisse
// gehen an die IDE-Schicht, die fragt, im Hintergrund arbeitet und SetBusy
// setzt. Git kennt weder „Server prüfen“ noch „Nur … aktualisieren“.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.WorkingCopies;

type
  TAtlasWorkingCopyEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TAtlasWorkingCopyUpdateEvent = procedure(Sender: TObject; AIndex: Integer; AIgnoreExternals: Boolean) of object;

  TAtlasWorkingCopiesDialog = class(TForm)
  public const
    ColumnCount = 5;
  private
    FName: string;
    FList: TAtlasVcsWorkingCopyList;
    FHasList: Boolean;
    FChecking: TArray<Boolean>;
    FBusy: Boolean;
    FView: TListView;
    FMenu: TPopupMenu;
    FUpdateItem: TMenuItem;
    FUpdateOnlyItem: TMenuItem;
    FPinItem: TMenuItem;
    FOpenItem: TMenuItem;
    FCheckButton: TButton;
    FUpdateAllButton: TButton;
    FUpdateOnlyButton: TButton;
    FHint: TLabel;
    FOnCheckServer: TNotifyEvent;
    FOnUpdate: TAtlasWorkingCopyUpdateEvent;
    FOnPin: TAtlasWorkingCopyEvent;
    FOnOpenFolder: TAtlasWorkingCopyEvent;
    procedure Fill;
    procedure FillRow(AIndex: Integer);
    procedure UpdateButtons;
    function Selected: Integer;
    function IsSvn: Boolean;
    procedure ViewDblClick(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure UpdateAllClick(Sender: TObject);
    procedure UpdateOnlyClick(Sender: TObject);
    procedure UpdateItemClick(Sender: TObject);
    procedure UpdateOnlyItemClick(Sender: TObject);
    procedure PinItemClick(Sender: TObject);
    procedure OpenItemClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    /// <summary>AName: Name der Gruppe bzw. des Projekts (Zeile der Wurzel, Titel).</summary>
    constructor CreateDialog(AOwner: TComponent; const AName: string);
    /// <summary>Zeilen aus Collect; Revisionen und Änderungen der Externals folgen mit SetRow.</summary>
    procedure SetList(const AList: TAtlasVcsWorkingCopyList);
    /// <summary>Zeile AIndex neu (Revision, Änderungen, „Neu auf dem Server“).</summary>
    procedure SetRow(AIndex: Integer; const ARow: TAtlasVcsWorkingCopyRow);
    /// <summary>„prüft …“ in der Spalte „Neu auf dem Server“ von AIndex.</summary>
    procedure SetChecking(AIndex: Integer; AChecking: Boolean);
    /// <summary>Während eines Laufs (Aktualisieren, Festschreiben, Server prüfen) sind die Knöpfe gesperrt.
    /// </summary>
    procedure SetBusy(ABusy: Boolean);
    /// <summary>Texte der Spalten einer Zeile.</summary>
    class function Cells(AKind: TAtlasVcsKind; const ARow: TAtlasVcsWorkingCopyRow; const AName: string;
      AChecking: Boolean): TArray<string>; static;
    property List: TAtlasVcsWorkingCopyList read FList;
    property Busy: Boolean read FBusy;
    property View: TListView read FView;
    property Menu: TPopupMenu read FMenu;
    property UpdateItem: TMenuItem read FUpdateItem;
    property UpdateOnlyItem: TMenuItem read FUpdateOnlyItem;
    property PinItem: TMenuItem read FPinItem;
    property OpenItem: TMenuItem read FOpenItem;
    property CheckButton: TButton read FCheckButton;
    property UpdateAllButton: TButton read FUpdateAllButton;
    property UpdateOnlyButton: TButton read FUpdateOnlyButton;
    property OnCheckServer: TNotifyEvent read FOnCheckServer write FOnCheckServer;
    /// <summary>AIndex: Zeile (0 = Wurzel); AIgnoreExternals: ohne die Externals darunter.</summary>
    property OnUpdate: TAtlasWorkingCopyUpdateEvent read FOnUpdate write FOnUpdate;
    property OnPin: TAtlasWorkingCopyEvent read FOnPin write FOnPin;
    property OnOpenFolder: TAtlasWorkingCopyEvent read FOnOpenFolder write FOnOpenFolder;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  cGap = 8;
  cButtonWidth = 180;
  cIndent = '    ';
  cBranchMark = #$2514' ';

constructor TAtlasWorkingCopiesDialog.CreateDialog(AOwner: TComponent; const AName: string);
var
  mBottom: TPanel;
  mClose: TButton;
  mColumn: TListColumn;
  mIndex: Integer;
  mWidths: TArray<Integer>;
  mCaptions: TArray<TAtlasTextId>;
begin
  inherited CreateNew(AOwner);
  FName := AName;
  FList := TAtlasVcsWorkingCopyList.Empty;
  Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesTitle, [AName]);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Width := 860;
  Height := 380;
  Constraints.MinWidth := 560;
  Constraints.MinHeight := 240;

  // Unten zuerst: die Knöpfe bleiben beim Verkleinern sichtbar.
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := 44;
  mBottom.BevelOuter := bvNone;
  FCheckButton := TButton.Create(Self);
  FCheckButton.Parent := mBottom;
  FCheckButton.SetBounds(cGap, 8, 120, 28);
  FCheckButton.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesCheckServer);
  FCheckButton.OnClick := CheckClick;
  FUpdateAllButton := TButton.Create(Self);
  FUpdateAllButton.Parent := mBottom;
  FUpdateAllButton.SetBounds(120 + 2 * cGap, 8, cButtonWidth, 28);
  FUpdateAllButton.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesUpdateAll);
  FUpdateAllButton.OnClick := UpdateAllClick;
  FUpdateOnlyButton := TButton.Create(Self);
  FUpdateOnlyButton.Parent := mBottom;
  FUpdateOnlyButton.SetBounds(120 + cButtonWidth + 3 * cGap, 8, cButtonWidth, 28);
  FUpdateOnlyButton.Caption := TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesUpdateOnly, [AName]);
  FUpdateOnlyButton.OnClick := UpdateOnlyClick;
  mClose := TButton.Create(Self);
  mClose.Parent := mBottom;
  mClose.SetBounds(mBottom.Width - (100 + cGap), 8, 100, 28);
  mClose.Anchors := [akTop, akRight];
  mClose.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesClose);
  mClose.Cancel := True;
  mClose.ModalResult := mrCancel;

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alBottom;
  FHint.AlignWithMargins := True;
  FHint.Margins.SetBounds(cGap, 2, cGap, 2);
  FHint.WordWrap := True;
  FHint.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesHint);

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FUpdateItem := TMenuItem.Create(Self);
  FUpdateItem.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuUpdate);
  FUpdateItem.OnClick := UpdateItemClick;
  FMenu.Items.Add(FUpdateItem);
  FUpdateOnlyItem := TMenuItem.Create(Self);
  FUpdateOnlyItem.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuUpdateOnly);
  FUpdateOnlyItem.OnClick := UpdateOnlyItemClick;
  FMenu.Items.Add(FUpdateOnlyItem);
  FPinItem := TMenuItem.Create(Self);
  FPinItem.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuPin);
  FPinItem.OnClick := PinItemClick;
  FMenu.Items.Add(FPinItem);
  FOpenItem := TMenuItem.Create(Self);
  FOpenItem.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuOpenFolder);
  FOpenItem.Default := True;
  FOpenItem.OnClick := OpenItemClick;
  FMenu.Items.Add(FOpenItem);

  FView := TListView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.AlignWithMargins := True;
  FView.Margins.SetBounds(cGap, cGap, cGap, 0);
  FView.ViewStyle := vsReport;
  FView.ReadOnly := True;
  FView.RowSelect := True;
  FView.HideSelection := False;
  FView.PopupMenu := FMenu;
  FView.OnDblClick := ViewDblClick;
  mCaptions := TArray<TAtlasTextId>.Create(TAtlasTextId.VcsWorkingCopiesColumnCopy,
    TAtlasTextId.VcsWorkingCopiesColumnPath, TAtlasTextId.VcsWorkingCopiesColumnRevision,
    TAtlasTextId.VcsWorkingCopiesColumnChanged, TAtlasTextId.VcsWorkingCopiesColumnIncoming);
  mWidths := TArray<Integer>.Create(200, 260, 120, 70, 130);
  for mIndex := 0 to High(mCaptions) do
  begin
    mColumn := FView.Columns.Add;
    mColumn.Caption := TAtlasStrings.Text(mCaptions[mIndex]);
    mColumn.Width := mWidths[mIndex];
  end;
  UpdateButtons;
end;

procedure TAtlasWorkingCopiesDialog.CreateWnd;
begin
  inherited;
  // Zeilen einer Liste brauchen ein Fenster: hier (und bei jedem neuen Fenster) füllen.
  Fill;
end;

function TAtlasWorkingCopiesDialog.IsSvn: Boolean;
begin
  Result := FList.Kind = TAtlasVcsKind.Svn;
end;

class function TAtlasWorkingCopiesDialog.Cells(AKind: TAtlasVcsKind; const ARow: TAtlasVcsWorkingCopyRow;
  const AName: string; AChecking: Boolean): TArray<string>;
var
  mCopy, mPath, mRevision, mChanged, mIncoming: string;
  mLevel: Integer;
begin
  // Eingerückt: je Ebene unter der ersten vier Leerzeichen, dann „└ “.
  mCopy := ARow.Caption(AName);
  if ARow.Depth > 0 then
  begin
    mCopy := cBranchMark + mCopy;
    for mLevel := 2 to ARow.Depth do
      mCopy := cIndent + mCopy;
  end;
  // Pfad: SVN ^/…, fremde Repositories mit URL; Git der Branch der Wurzel.
  mPath := '';
  if ARow.Url <> '' then
    mPath := TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesForeign, [ARow.Url])
  else if (ARow.RepositoryPath <> '') and (AKind = TAtlasVcsKind.Svn) then
    mPath := '^/' + ARow.RepositoryPath
  else
    mPath := ARow.RepositoryPath;
  if not ARow.Loaded then
    mRevision := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesLoading)
  else
  begin
    mRevision := ARow.Revision;
    if (mRevision = '') and ARow.Fixed then
      mRevision := ARow.FixedRevision;
    if (mRevision <> '') and (AKind = TAtlasVcsKind.Svn) then
      mRevision := 'r' + mRevision;
    if ARow.Fixed then
      mRevision := TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesFixed, [mRevision]);
  end;
  if ARow.Changed >= 0 then
    mChanged := IntToStr(ARow.Changed)
  else if ARow.Loaded then
    mChanged := ''
  else
    mChanged := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesLoading);
  // Nur auf Klick: Bis dahin steht, dass der Server noch nicht gefragt wurde.
  if AChecking then
    mIncoming := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesChecking)
  else if ARow.Incoming >= 0 then
    mIncoming := IntToStr(ARow.Incoming)
  else if ARow.Outcome <> TAtlasVcsOutcome.Ok then
    mIncoming := AtlasVcsOutcomeName(ARow.Outcome)
  else if (AKind = TAtlasVcsKind.Svn) and (ARow.RepositoryPath <> '') then
    mIncoming := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesNotChecked)
  else
    mIncoming := '';
  Result := TArray<string>.Create(mCopy, mPath, mRevision, mChanged, mIncoming);
end;

procedure TAtlasWorkingCopiesDialog.Fill;
var
  mIndex: Integer;
begin
  if not FView.HandleAllocated then
    Exit;
  FView.Items.BeginUpdate;
  try
    FView.Items.Clear;
    if FHasList then
      for mIndex := 0 to High(FList.Rows) do
      begin
        FView.Items.Add;
        FillRow(mIndex);
      end
    else
      FView.Items.Add.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesLoading);
  finally
    FView.Items.EndUpdate;
  end;
  if FView.Items.Count > 0 then
    FView.Items[0].Selected := True;
end;

procedure TAtlasWorkingCopiesDialog.FillRow(AIndex: Integer);
var
  mCells: TArray<string>;
  mItem: TListItem;
  mColumn: Integer;
  mChecking: Boolean;
begin
  if not FView.HandleAllocated or (AIndex < 0) or (AIndex >= FView.Items.Count) or (AIndex > High(FList.Rows)) then
    Exit;
  mChecking := (AIndex <= High(FChecking)) and FChecking[AIndex];
  mCells := Cells(FList.Kind, FList.Rows[AIndex], FName, mChecking);
  mItem := FView.Items[AIndex];
  mItem.Caption := mCells[0];
  mItem.SubItems.BeginUpdate;
  try
    mItem.SubItems.Clear;
    for mColumn := 1 to High(mCells) do
      mItem.SubItems.Add(mCells[mColumn]);
  finally
    mItem.SubItems.EndUpdate;
  end;
end;

procedure TAtlasWorkingCopiesDialog.SetList(const AList: TAtlasVcsWorkingCopyList);
begin
  FList := AList;
  FList.Rows := Copy(AList.Rows);
  FHasList := True;
  SetLength(FChecking, Length(FList.Rows));
  // Git: kein „Server prüfen“, kein „Nur … aktualisieren“; Pull statt Aktualisieren.
  FCheckButton.Visible := IsSvn;
  FUpdateOnlyButton.Visible := IsSvn and FList.Several;
  if IsSvn then
    FUpdateAllButton.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesUpdateAll)
  else
    FUpdateAllButton.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
  Fill;
  UpdateButtons;
end;

procedure TAtlasWorkingCopiesDialog.SetRow(AIndex: Integer; const ARow: TAtlasVcsWorkingCopyRow);
begin
  if (AIndex < 0) or (AIndex > High(FList.Rows)) then
    Exit;
  FList.Rows[AIndex] := ARow;
  FillRow(AIndex);
end;

procedure TAtlasWorkingCopiesDialog.SetChecking(AIndex: Integer; AChecking: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FChecking)) then
    Exit;
  FChecking[AIndex] := AChecking;
  FillRow(AIndex);
end;

procedure TAtlasWorkingCopiesDialog.SetBusy(ABusy: Boolean);
begin
  FBusy := ABusy;
  UpdateButtons;
end;

procedure TAtlasWorkingCopiesDialog.UpdateButtons;
var
  mReady: Boolean;
begin
  mReady := FHasList and not FBusy and (FList.Outcome = TAtlasVcsOutcome.Ok);
  FCheckButton.Enabled := mReady;
  FUpdateAllButton.Enabled := mReady;
  FUpdateOnlyButton.Enabled := mReady;
end;

function TAtlasWorkingCopiesDialog.Selected: Integer;
begin
  Result := -1;
  if FHasList and (FView.Selected <> nil) and (FView.Selected.Index <= High(FList.Rows)) then
    Result := FView.Selected.Index;
end;

procedure TAtlasWorkingCopiesDialog.MenuPopup(Sender: TObject);
var
  mRow: Integer;
  mReady: Boolean;
begin
  mRow := Selected;
  mReady := (mRow >= 0) and not FBusy;
  FUpdateItem.Enabled := mReady;
  FUpdateOnlyItem.Visible := IsSvn;
  FUpdateOnlyItem.Enabled := mReady;
  FPinItem.Visible := IsSvn;
  FPinItem.Enabled := mReady and FList.Rows[mRow].CanPin;
  FOpenItem.Enabled := mRow >= 0;
end;

procedure TAtlasWorkingCopiesDialog.ViewDblClick(Sender: TObject);
begin
  if (Selected >= 0) and Assigned(FOnOpenFolder) then
    FOnOpenFolder(Self, Selected);
end;

procedure TAtlasWorkingCopiesDialog.CheckClick(Sender: TObject);
begin
  if not FBusy and Assigned(FOnCheckServer) then
    FOnCheckServer(Self);
end;

procedure TAtlasWorkingCopiesDialog.UpdateAllClick(Sender: TObject);
begin
  if not FBusy and FHasList and Assigned(FOnUpdate) then
    FOnUpdate(Self, 0, False);
end;

procedure TAtlasWorkingCopiesDialog.UpdateOnlyClick(Sender: TObject);
begin
  if not FBusy and FHasList and Assigned(FOnUpdate) then
    FOnUpdate(Self, 0, True);
end;

procedure TAtlasWorkingCopiesDialog.UpdateItemClick(Sender: TObject);
begin
  if not FBusy and (Selected >= 0) and Assigned(FOnUpdate) then
    FOnUpdate(Self, Selected, False);
end;

procedure TAtlasWorkingCopiesDialog.UpdateOnlyItemClick(Sender: TObject);
begin
  if not FBusy and (Selected >= 0) and Assigned(FOnUpdate) then
    FOnUpdate(Self, Selected, True);
end;

procedure TAtlasWorkingCopiesDialog.PinItemClick(Sender: TObject);
begin
  if not FBusy and (Selected >= 0) and FList.Rows[Selected].CanPin and Assigned(FOnPin) then
    FOnPin(Self, Selected);
end;

procedure TAtlasWorkingCopiesDialog.OpenItemClick(Sender: TObject);
begin
  if (Selected >= 0) and Assigned(FOnOpenFolder) then
    FOnOpenFolder(Self, Selected);
end;

end.
