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

// Aufbau: Knopfleiste (TAtlasWorkingCopiesButtons) und Kontextmenü
// (TAtlasWorkingCopiesMenu) sind eigene Steuerelemente; ihre Ereignisse gehen
// über den Dialog an die IDE-Schicht.

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

  TAtlasWorkingCopiesDialog = class;

  /// <summary>Kontextmenü der Tabelle: Aktualisieren, Nur diese aktualisieren, Revision festschreiben, Ordner
  /// öffnen.</summary>
  TAtlasWorkingCopiesMenu = class(TPopupMenu)
  private
    FDialog: TAtlasWorkingCopiesDialog;
    FUpdateItem: TMenuItem;
    FUpdateOnlyItem: TMenuItem;
    FPinItem: TMenuItem;
    FOpenItem: TMenuItem;
    function AddItem(const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
    procedure MenuPopup(Sender: TObject);
    /// <summary>„Aktualisieren“ und „Nur diese aktualisieren“ (Sender).</summary>
    procedure UpdateItemClick(Sender: TObject);
    procedure PinItemClick(Sender: TObject);
    procedure OpenItemClick(Sender: TObject);
  public
    constructor CreateFor(ADialog: TAtlasWorkingCopiesDialog);
    property UpdateItem: TMenuItem read FUpdateItem;
    property UpdateOnlyItem: TMenuItem read FUpdateOnlyItem;
    property PinItem: TMenuItem read FPinItem;
    property OpenItem: TMenuItem read FOpenItem;
  end;

  /// <summary>Knopfleiste unten: Server prüfen, Alle aktualisieren, Nur … aktualisieren, Schließen.</summary>
  TAtlasWorkingCopiesButtons = class(TPanel)
  private
    FDialog: TAtlasWorkingCopiesDialog;
    FCheckButton: TButton;
    FUpdateAllButton: TButton;
    FUpdateOnlyButton: TButton;
    function AddButton(ALeft, AWidth: Integer; const ACaption: string; const AOnClick: TNotifyEvent): TButton;
    procedure CheckClick(Sender: TObject);
    /// <summary>„Alle aktualisieren“ und „Nur … aktualisieren“ (Sender).</summary>
    procedure UpdateClick(Sender: TObject);
  public
    /// <summary>AName: Name der Gruppe bzw. des Projekts für „Nur … aktualisieren“.</summary>
    constructor CreateFor(ADialog: TAtlasWorkingCopiesDialog; const AName: string);
    /// <summary>Git: kein „Server prüfen“, kein „Nur … aktualisieren“; Pull statt Aktualisieren.</summary>
    procedure ShowKind(ASvn, ASeveral: Boolean);
    procedure SetReady(AReady: Boolean);
    property CheckButton: TButton read FCheckButton;
    property UpdateAllButton: TButton read FUpdateAllButton;
    property UpdateOnlyButton: TButton read FUpdateOnlyButton;
  end;

  TAtlasWorkingCopiesDialog = class(TForm)
  public const
    cColumnCount = 5;
  private
    FName: string;
    FList: TAtlasVcsWorkingCopyList;
    FHasList: Boolean;
    FChecking: TArray<Boolean>;
    FBusy: Boolean;
    FView: TListView;
    FMenu: TAtlasWorkingCopiesMenu;
    FButtons: TAtlasWorkingCopiesButtons;
    FOnCheckServer: TNotifyEvent;
    FOnUpdate: TAtlasWorkingCopyUpdateEvent;
    FOnPin: TAtlasWorkingCopyEvent;
    FOnOpenFolder: TAtlasWorkingCopyEvent;
    procedure AddHint;
    procedure AddView;
    procedure Fill;
    procedure FillRow(AIndex: Integer);
    procedure UpdateButtons;
    function Selected: Integer;
    function IsSvn: Boolean;
    procedure ViewDblClick(Sender: TObject);
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
    property Menu: TAtlasWorkingCopiesMenu read FMenu;
    property Buttons: TAtlasWorkingCopiesButtons read FButtons;
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
  cCheckWidth = 120;
  cCloseWidth = 100;
  cIndent = '    ';
  cBranchMark = #$2514' ';

{ Spalten }

/// <summary>Eingerückt: je Ebene unter der ersten vier Leerzeichen, dann „└ “.</summary>
function CopyCell(const ARow: TAtlasVcsWorkingCopyRow; const AName: string): string;
var
  mLevel: Integer;
begin
  Result := ARow.Caption(AName);
  if ARow.Depth <= 0 then
  begin
    Exit;
  end;
  Result := cBranchMark + Result;
  for mLevel := 2 to ARow.Depth do
  begin
    Result := cIndent + Result;
  end;
end;

/// <summary>Pfad: SVN ^/…, fremde Repositories mit URL; Git der Branch der Wurzel.</summary>
function PathCell(AKind: TAtlasVcsKind; const ARow: TAtlasVcsWorkingCopyRow): string;
begin
  if ARow.Url <> '' then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesForeign, [ARow.Url]);
  end
  else if (ARow.RepositoryPath <> '') and (AKind = TAtlasVcsKind.Svn) then
  begin
    Result := '^/' + ARow.RepositoryPath;
  end
  else
  begin
    Result := ARow.RepositoryPath;
  end;
end;

function RevisionCell(AKind: TAtlasVcsKind; const ARow: TAtlasVcsWorkingCopyRow): string;
begin
  if not ARow.Loaded then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesLoading));
  end;
  Result := ARow.Revision;
  if (Result = '') and ARow.Fixed then
  begin
    Result := ARow.FixedRevision;
  end;
  if (Result <> '') and (AKind = TAtlasVcsKind.Svn) then
  begin
    Result := 'r' + Result;
  end;
  if ARow.Fixed then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesFixed, [Result]);
  end;
end;

function ChangedCell(const ARow: TAtlasVcsWorkingCopyRow): string;
begin
  if ARow.Changed >= 0 then
  begin
    Result := IntToStr(ARow.Changed);
  end
  else if ARow.Loaded then
  begin
    Result := '';
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesLoading);
  end;
end;

/// <summary>Nur auf Klick: Bis dahin steht, dass der Server noch nicht gefragt wurde.</summary>
function IncomingCell(AKind: TAtlasVcsKind; const ARow: TAtlasVcsWorkingCopyRow; AChecking: Boolean): string;
begin
  if AChecking then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesChecking);
  end
  else if ARow.Incoming >= 0 then
  begin
    Result := IntToStr(ARow.Incoming);
  end
  else if ARow.Outcome <> TAtlasVcsOutcome.Ok then
  begin
    Result := AtlasVcsOutcomeName(ARow.Outcome);
  end
  else if (AKind = TAtlasVcsKind.Svn) and (ARow.RepositoryPath <> '') then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesNotChecked);
  end
  else
  begin
    Result := '';
  end;
end;

{ TAtlasWorkingCopiesMenu }

constructor TAtlasWorkingCopiesMenu.CreateFor(ADialog: TAtlasWorkingCopiesDialog);
begin
  inherited Create(ADialog);
  FDialog := ADialog;
  OnPopup := MenuPopup;
  FUpdateItem := AddItem(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuUpdate), UpdateItemClick);
  FUpdateOnlyItem := AddItem(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuUpdateOnly), UpdateItemClick);
  FPinItem := AddItem(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuPin), PinItemClick);
  FOpenItem := AddItem(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesMenuOpenFolder), OpenItemClick);
  FOpenItem.Default := True;
end;

function TAtlasWorkingCopiesMenu.AddItem(const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(Owner);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  Items.Add(Result);
end;

procedure TAtlasWorkingCopiesMenu.MenuPopup(Sender: TObject);
var
  mRow: Integer;
  mReady: Boolean;
begin
  mRow := FDialog.Selected;
  mReady := (mRow >= 0) and not FDialog.FBusy;
  FUpdateItem.Enabled := mReady;
  FUpdateOnlyItem.Visible := FDialog.IsSvn;
  FUpdateOnlyItem.Enabled := mReady;
  FPinItem.Visible := FDialog.IsSvn;
  FPinItem.Enabled := mReady and FDialog.FList.Rows[mRow].CanPin;
  FOpenItem.Enabled := mRow >= 0;
end;

procedure TAtlasWorkingCopiesMenu.UpdateItemClick(Sender: TObject);
begin
  if not FDialog.FBusy and (FDialog.Selected >= 0) and Assigned(FDialog.FOnUpdate) then
  begin
    FDialog.FOnUpdate(FDialog, FDialog.Selected, Sender = FUpdateOnlyItem);
  end;
end;

procedure TAtlasWorkingCopiesMenu.PinItemClick(Sender: TObject);
begin
  if not FDialog.FBusy and (FDialog.Selected >= 0) and FDialog.FList.Rows[FDialog.Selected].CanPin and
    Assigned(FDialog.FOnPin) then
  begin
    FDialog.FOnPin(FDialog, FDialog.Selected);
  end;
end;

procedure TAtlasWorkingCopiesMenu.OpenItemClick(Sender: TObject);
begin
  if (FDialog.Selected >= 0) and Assigned(FDialog.FOnOpenFolder) then
  begin
    FDialog.FOnOpenFolder(FDialog, FDialog.Selected);
  end;
end;

{ TAtlasWorkingCopiesButtons }

constructor TAtlasWorkingCopiesButtons.CreateFor(ADialog: TAtlasWorkingCopiesDialog; const AName: string);
var
  mClose: TButton;
begin
  inherited Create(ADialog);
  FDialog := ADialog;
  Parent := ADialog;
  Align := alBottom;
  Height := 44;
  BevelOuter := bvNone;
  FCheckButton := AddButton(cGap, cCheckWidth, TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesCheckServer),
    CheckClick);
  FUpdateAllButton := AddButton(cCheckWidth + 2 * cGap, cButtonWidth,
    TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesUpdateAll), UpdateClick);
  FUpdateOnlyButton := AddButton(cCheckWidth + cButtonWidth + 3 * cGap, cButtonWidth,
    TAtlasStrings.Fmt(TAtlasTextId.VcsWorkingCopiesUpdateOnly, [AName]), UpdateClick);
  mClose := AddButton(Width - (cCloseWidth + cGap), cCloseWidth, TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesClose),
    nil);
  mClose.Anchors := [akTop, akRight];
  mClose.Cancel := True;
  mClose.ModalResult := mrCancel;
end;

function TAtlasWorkingCopiesButtons.AddButton(ALeft, AWidth: Integer; const ACaption: string;
  const AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Owner);
  Result.Parent := Self;
  Result.SetBounds(ALeft, 8, AWidth, 28);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

procedure TAtlasWorkingCopiesButtons.CheckClick(Sender: TObject);
begin
  if not FDialog.FBusy and Assigned(FDialog.FOnCheckServer) then
  begin
    FDialog.FOnCheckServer(FDialog);
  end;
end;

procedure TAtlasWorkingCopiesButtons.UpdateClick(Sender: TObject);
begin
  if not FDialog.FBusy and FDialog.FHasList and Assigned(FDialog.FOnUpdate) then
  begin
    FDialog.FOnUpdate(FDialog, 0, Sender = FUpdateOnlyButton);
  end;
end;

procedure TAtlasWorkingCopiesButtons.ShowKind(ASvn, ASeveral: Boolean);
begin
  FCheckButton.Visible := ASvn;
  FUpdateOnlyButton.Visible := ASvn and ASeveral;
  if ASvn then
  begin
    FUpdateAllButton.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesUpdateAll);
  end
  else
  begin
    FUpdateAllButton.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
  end;
end;

procedure TAtlasWorkingCopiesButtons.SetReady(AReady: Boolean);
begin
  FCheckButton.Enabled := AReady;
  FUpdateAllButton.Enabled := AReady;
  FUpdateOnlyButton.Enabled := AReady;
end;

{ TAtlasWorkingCopiesDialog }

constructor TAtlasWorkingCopiesDialog.CreateDialog(AOwner: TComponent; const AName: string);
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
  FButtons := TAtlasWorkingCopiesButtons.CreateFor(Self, AName);
  AddHint;
  FMenu := TAtlasWorkingCopiesMenu.CreateFor(Self);
  AddView;
  UpdateButtons;
end;

procedure TAtlasWorkingCopiesDialog.AddHint;
var
  mHint: TLabel;
begin
  mHint := TLabel.Create(Self);
  mHint.Parent := Self;
  mHint.Align := alBottom;
  mHint.AlignWithMargins := True;
  mHint.Margins.SetBounds(cGap, 2, cGap, 2);
  mHint.WordWrap := True;
  mHint.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesHint);
end;

procedure TAtlasWorkingCopiesDialog.AddView;
var
  mColumn: TListColumn;
  mIndex: Integer;
  mWidths: TArray<Integer>;
  mCaptions: TArray<TAtlasTextId>;
begin
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
begin
  Result := TArray<string>.Create(CopyCell(ARow, AName), PathCell(AKind, ARow), RevisionCell(AKind, ARow),
    ChangedCell(ARow), IncomingCell(AKind, ARow, AChecking));
end;

procedure TAtlasWorkingCopiesDialog.Fill;
var
  mIndex: Integer;
begin
  // Die Liste braucht ein Fenster; hat der Dialog schon eines, auch die Liste anlegen.
  if not FView.HandleAllocated then
  begin
    if not HandleAllocated then
    begin
      Exit;
    end;
    FView.HandleNeeded;
  end;
  FView.Items.BeginUpdate;
  try
    FView.Items.Clear;
    if FHasList then
    begin
      for mIndex := 0 to High(FList.Rows) do
      begin
        FView.Items.Add;
        FillRow(mIndex);
      end;
    end
    else
    begin
      FView.Items.Add.Caption := TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesLoading);
    end;
  finally
    FView.Items.EndUpdate;
  end;
  if FView.Items.Count > 0 then
  begin
    FView.Items[0].Selected := True;
  end;
end;

procedure TAtlasWorkingCopiesDialog.FillRow(AIndex: Integer);
var
  mCells: TArray<string>;
  mItem: TListItem;
  mColumn: Integer;
  mChecking: Boolean;
begin
  if not FView.HandleAllocated or (AIndex < 0) or (AIndex >= FView.Items.Count) or (AIndex > High(FList.Rows)) then
  begin
    Exit;
  end;
  mChecking := (AIndex <= High(FChecking)) and FChecking[AIndex];
  mCells := Cells(FList.Kind, FList.Rows[AIndex], FName, mChecking);
  mItem := FView.Items[AIndex];
  mItem.Caption := mCells[0];
  mItem.SubItems.BeginUpdate;
  try
    mItem.SubItems.Clear;
    for mColumn := 1 to High(mCells) do
    begin
      mItem.SubItems.Add(mCells[mColumn]);
    end;
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
  FButtons.ShowKind(IsSvn, FList.Several);
  Fill;
  UpdateButtons;
end;

procedure TAtlasWorkingCopiesDialog.SetRow(AIndex: Integer; const ARow: TAtlasVcsWorkingCopyRow);
begin
  if (AIndex < 0) or (AIndex > High(FList.Rows)) then
  begin
    Exit;
  end;
  FList.Rows[AIndex] := ARow;
  FillRow(AIndex);
end;

procedure TAtlasWorkingCopiesDialog.SetChecking(AIndex: Integer; AChecking: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FChecking)) then
  begin
    Exit;
  end;
  FChecking[AIndex] := AChecking;
  FillRow(AIndex);
end;

procedure TAtlasWorkingCopiesDialog.SetBusy(ABusy: Boolean);
begin
  FBusy := ABusy;
  UpdateButtons;
end;

procedure TAtlasWorkingCopiesDialog.UpdateButtons;
begin
  FButtons.SetReady(FHasList and not FBusy and (FList.Outcome = TAtlasVcsOutcome.Ok));
end;

function TAtlasWorkingCopiesDialog.Selected: Integer;
begin
  Result := -1;
  if FHasList and (FView.Selected <> nil) and (FView.Selected.Index <= High(FList.Rows)) then
  begin
    Result := FView.Selected.Index;
  end;
end;

procedure TAtlasWorkingCopiesDialog.ViewDblClick(Sender: TObject);
begin
  if (Selected >= 0) and Assigned(FOnOpenFolder) then
  begin
    FOnOpenFolder(Self, Selected);
  end;
end;

end.
