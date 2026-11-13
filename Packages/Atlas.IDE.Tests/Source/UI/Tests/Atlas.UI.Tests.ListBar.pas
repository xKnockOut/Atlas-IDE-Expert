unit Atlas.UI.Tests.ListBar;

// Testlisten im Fenster „Atlas-Tests“ (#2167), reine VCL:
// - Reiter „Alle“, je Liste ein Reiter (Listen aus atlas.json mit ◆ davor)
//   und „+“ für eine neue Liste; Rechtsklick auf einen Reiter: Umbenennen,
//   Regeln bearbeiten (nur dynamische), Duplizieren, Löschen,
// - im Reiter einer Liste eine Kopfzeile mit Regeln, „X von Y Tests“ und
//   Ablage und dem Knopf „Liste ausführen“,
// - im Kontextmenü des Baums „Zu Liste hinzufügen ▸“ (feste Listen und
//   „Neue Liste …“) und im Reiter einer festen Liste „Aus … entfernen“.
// Die Steuerelemente gehören dem Frame und liegen unter den übrigen Leisten
// oben. Was eine Liste enthält und was geschieht, entscheidet die IDE-Schicht
// (Atlas.IDE.Tests.Lists) über die Ereignisse (Handlers).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.Forms;

type
  /// <summary>Ein Reiter einer Liste.</summary>
  TAtlasTestsListTab = record
    Caption: string;
    /// <summary>Liste aus atlas.json des Projekts (mit Zeichen markiert).</summary>
    InProject: Boolean;
    /// <summary>Feste Liste (Tests über das Kontextmenü des Baums).</summary>
    Fixed: Boolean;
  end;

  /// <summary>Ereignisse der Testlisten; Listen über ihren Index, -1 = „Alle“ bzw. neue Liste; nil = keins.
  /// </summary>
  TAtlasTestsListHandlers = record
    OnTab: TProc<Integer>;
    OnNew: TProc;
    /// <summary>Umbenennen bzw. Regeln bearbeiten.</summary>
    OnEdit: TProc<Integer>;
    OnDuplicate: TProc<Integer>;
    OnDelete: TProc<Integer>;
    OnRun: TProc<Integer>;
    /// <summary>Gewählte Knoten zur Liste hinzufügen; -1 = neue feste Liste.</summary>
    OnAddTo: TProc<Integer>;
    /// <summary>Gewählte Knoten aus der Liste des Reiters entfernen.</summary>
    OnRemove: TProc;
  end;

  TAtlasTestsListBar = class(TComponent)
  private
    FFrame: TCustomFrame;
    FTree: TTreeView;
    FTabs: TTabControl;
    FHeader: TPanel;
    FHeaderText: TLabel;
    FRun: TButton;
    FTabMenu: TPopupMenu;
    FEditRules: TMenuItem;
    FTreeMenu: TPopupMenu;
    FAddTo: TMenuItem;
    FRemove: TMenuItem;
    FLists: TArray<TAtlasTestsListTab>;
    FCurrent: Integer;
    FMenuList: Integer;
    FActive: Boolean;
    FHandlers: TAtlasTestsListHandlers;
    function Scaled96(AValue: Integer): Integer;
    function NewItem(AMenu: TComponent; const ACaption: string; ATag: Integer): TMenuItem;
    procedure BuildTabs(ATop: Integer);
    procedure BuildMenus;
    function TabCaption(AIndex: Integer): string;
    procedure ShowHeader;
    procedure TabChange(Sender: TObject);
    procedure TabMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TabMenuClick(Sender: TObject);
    procedure TreeMenuPopup(Sender: TObject);
    procedure AddToClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
  public
    /// <summary>Reiter und Kopfzeile unter den Leisten oben auf AFrame anlegen; Kontextmenü für ATree.</summary>
    constructor Create(AFrame: TCustomFrame; ATree: TTreeView); reintroduce;
    /// <summary>Listen und gewählter Reiter (-1 = „Alle“).</summary>
    procedure SetLists(const ALists: TArray<TAtlasTestsListTab>; ACurrent: Integer);
    /// <summary>Reiter füllen (braucht ein Fenster).</summary>
    procedure FillTabs;
    /// <summary>Text der Kopfzeile im Reiter einer Liste.</summary>
    procedure SetHeader(const AText: string);
    /// <summary>tests.lists: an zeigt Reiter und Menüs, aus nichts davon.</summary>
    procedure SetActive(AActive: Boolean);
    procedure SetBusy(ABusy: Boolean);
    property Handlers: TAtlasTestsListHandlers read FHandlers write FHandlers;
    /// <summary>Gewählte Liste; -1 = „Alle“.</summary>
    property Current: Integer read FCurrent;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  Atlas.UI.Tests.Strings;

const
  cBasePpi = 96;
  cTabHeight = 26;
  cHeaderHeight = 28;
  cGap = 6;
  cRunWidth = 120;
  /// <summary>Zeichen vor Listen aus atlas.json.</summary>
  cProjectMark = #$25C6' ';
  cNewTab = '+';
  /// <summary>Kennungen der Einträge im Menü eines Reiters (Tag).</summary>
  cRename = 1;
  cEditRules = 2;
  cDuplicate = 3;
  cDelete = 4;

procedure FireIndex(const AProc: TProc<Integer>; AIndex: Integer);
begin
  if Assigned(AProc) then
  begin
    AProc(AIndex);
  end;
end;

{ TAtlasTestsListBar }

constructor TAtlasTestsListBar.Create(AFrame: TCustomFrame; ATree: TTreeView);
var
  mIndex, mTop: Integer;
  mControl: TControl;
begin
  inherited Create(AFrame);
  FFrame := AFrame;
  FTree := ATree;
  FCurrent := -1;
  FMenuList := -1;
  FActive := True;
  // Unter die Leisten, die schon oben liegen.
  mTop := 0;
  for mIndex := 0 to FFrame.ControlCount - 1 do
  begin
    mControl := FFrame.Controls[mIndex];
    if (mControl.Align = alTop) and (mControl.Top + mControl.Height > mTop) then
    begin
      mTop := mControl.Top + mControl.Height;
    end;
  end;
  BuildTabs(mTop);
  BuildMenus;
end;

function TAtlasTestsListBar.Scaled96(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FFrame.CurrentPPI, cBasePpi);
end;

procedure TAtlasTestsListBar.BuildTabs(ATop: Integer);
begin
  // alTop: Top und Height vor Align und Parent.
  FTabs := TTabControl.Create(FFrame);
  FTabs.Top := ATop;
  FTabs.Height := Scaled96(cTabHeight);
  FTabs.Align := alTop;
  FTabs.OnChange := TabChange;
  FTabs.OnMouseUp := TabMouseUp;
  FTabs.Parent := FFrame;
  FHeader := TPanel.Create(FFrame);
  FHeader.Top := ATop + FTabs.Height;
  FHeader.Height := Scaled96(cHeaderHeight);
  FHeader.BevelOuter := bvNone;
  FHeader.Align := alTop;
  FHeader.Visible := False;
  FHeader.Parent := FFrame;
  FRun := TButton.Create(FFrame);
  FRun.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsRun);
  FRun.Width := Scaled96(cRunWidth);
  FRun.AlignWithMargins := True;
  FRun.Align := alRight;
  FRun.OnClick := RunClick;
  FRun.Parent := FHeader;
  FHeaderText := TLabel.Create(FFrame);
  FHeaderText.AutoSize := False;
  FHeaderText.Layout := tlCenter;
  FHeaderText.EllipsisPosition := epEndEllipsis;
  FHeaderText.ShowHint := True;
  FHeaderText.AlignWithMargins := True;
  FHeaderText.Margins.Left := Scaled96(cGap);
  FHeaderText.Align := alClient;
  FHeaderText.Parent := FHeader;
end;

function TAtlasTestsListBar.NewItem(AMenu: TComponent; const ACaption: string; ATag: Integer): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  if AMenu is TPopupMenu then
  begin
    TPopupMenu(AMenu).Items.Add(Result);
  end;
end;

procedure TAtlasTestsListBar.BuildMenus;
begin
  FTabMenu := TPopupMenu.Create(FFrame);
  NewItem(FTabMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsRename), cRename).OnClick := TabMenuClick;
  FEditRules := NewItem(FTabMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsEditRules), cEditRules);
  FEditRules.OnClick := TabMenuClick;
  NewItem(FTabMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsDuplicate), cDuplicate).OnClick := TabMenuClick;
  NewItem(FTabMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsDelete), cDelete).OnClick := TabMenuClick;
  FTreeMenu := TPopupMenu.Create(FFrame);
  FTreeMenu.OnPopup := TreeMenuPopup;
  FAddTo := NewItem(FTreeMenu, TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsAddTo), 0);
  FRemove := NewItem(FTreeMenu, '', 0);
  FRemove.OnClick := RemoveClick;
  FTree.PopupMenu := FTreeMenu;
end;

function TAtlasTestsListBar.TabCaption(AIndex: Integer): string;
begin
  Result := FLists[AIndex].Caption;
  if FLists[AIndex].InProject then
  begin
    Result := cProjectMark + Result;
  end;
end;

procedure TAtlasTestsListBar.SetLists(const ALists: TArray<TAtlasTestsListTab>; ACurrent: Integer);
begin
  FLists := ALists;
  FCurrent := ACurrent;
  if (FCurrent < -1) or (FCurrent > High(FLists)) then
  begin
    FCurrent := -1;
  end;
  if FFrame.HandleAllocated then
  begin
    FillTabs;
  end;
end;

procedure TAtlasTestsListBar.FillTabs;
var
  mCaptions: TArray<string>;
  mIndex: Integer;
  mSame: Boolean;
begin
  if not FActive then
  begin
    Exit;
  end;
  mCaptions := TArray<string>.Create(TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsAll));
  for mIndex := 0 to High(FLists) do
  begin
    mCaptions := mCaptions + [TabCaption(mIndex)];
  end;
  mCaptions := mCaptions + [cNewTab];
  FTabs.HandleNeeded;
  // Der Baum wird bei jeder Filteränderung neu gefüllt; die Reiter nur, wenn sich die Listen ändern.
  mSame := FTabs.Tabs.Count = Length(mCaptions);
  for mIndex := 0 to FTabs.Tabs.Count - 1 do
  begin
    mSame := mSame and (FTabs.Tabs[mIndex] = mCaptions[mIndex]);
  end;
  if not mSame then
  begin
    FTabs.Tabs.BeginUpdate;
    try
      FTabs.Tabs.Clear;
      for mIndex := 0 to High(mCaptions) do
      begin
        FTabs.Tabs.Add(mCaptions[mIndex]);
      end;
    finally
      FTabs.Tabs.EndUpdate;
    end;
  end;
  FTabs.TabIndex := FCurrent + 1;
  ShowHeader;
end;

procedure TAtlasTestsListBar.ShowHeader;
begin
  FHeader.Visible := FActive and (FCurrent >= 0);
end;

procedure TAtlasTestsListBar.SetHeader(const AText: string);
begin
  FHeaderText.Caption := AText;
  FHeaderText.Hint := AText;
end;

procedure TAtlasTestsListBar.SetActive(AActive: Boolean);
begin
  FActive := AActive;
  FTabs.Visible := AActive;
  if AActive then
  begin
    FTree.PopupMenu := FTreeMenu;
  end
  else
  begin
    FTree.PopupMenu := nil;
    FCurrent := -1;
  end;
  ShowHeader;
end;

procedure TAtlasTestsListBar.SetBusy(ABusy: Boolean);
begin
  FRun.Enabled := not ABusy;
end;

procedure TAtlasTestsListBar.TabChange(Sender: TObject);
var
  mTab: Integer;
begin
  mTab := FTabs.TabIndex;
  if mTab = FTabs.Tabs.Count - 1 then
  begin
    // „+“ ist kein Reiter zum Zeigen: zurück zum bisherigen und eine neue Liste anlegen.
    FTabs.TabIndex := FCurrent + 1;
    if Assigned(FHandlers.OnNew) then
    begin
      FHandlers.OnNew();
    end;
    Exit;
  end;
  FCurrent := mTab - 1;
  ShowHeader;
  FireIndex(FHandlers.OnTab, FCurrent);
end;

procedure TAtlasTestsListBar.TabMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mPoint: TPoint;
begin
  if Button <> mbRight then
  begin
    Exit;
  end;
  FMenuList := FTabs.IndexOfTabAt(X, Y) - 1;
  if (FMenuList < 0) or (FMenuList > High(FLists)) then
  begin
    Exit;
  end;
  FEditRules.Visible := not FLists[FMenuList].Fixed;
  mPoint := FTabs.ClientToScreen(TPoint.Create(X, Y));
  FTabMenu.Popup(mPoint.X, mPoint.Y);
end;

procedure TAtlasTestsListBar.TabMenuClick(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    cRename, cEditRules:
      FireIndex(FHandlers.OnEdit, FMenuList);
    cDuplicate:
      FireIndex(FHandlers.OnDuplicate, FMenuList);
    cDelete:
      FireIndex(FHandlers.OnDelete, FMenuList);
  end;
end;

procedure TAtlasTestsListBar.TreeMenuPopup(Sender: TObject);
var
  mIndex: Integer;
  mItem: TMenuItem;
begin
  FAddTo.Clear;
  for mIndex := 0 to High(FLists) do
  begin
    if FLists[mIndex].Fixed then
    begin
      mItem := NewItem(FAddTo, TabCaption(mIndex), mIndex);
      mItem.OnClick := AddToClick;
      FAddTo.Add(mItem);
    end;
  end;
  if FAddTo.Count > 0 then
  begin
    FAddTo.NewBottomLine;
  end;
  mItem := NewItem(FAddTo, TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsAddToNew), -1);
  mItem.OnClick := AddToClick;
  FAddTo.Add(mItem);
  FRemove.Visible := (FCurrent >= 0) and (FCurrent <= High(FLists)) and FLists[FCurrent].Fixed;
  if FRemove.Visible then
  begin
    FRemove.Caption := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsRemoveFrom, [FLists[FCurrent].Caption]);
  end;
end;

procedure TAtlasTestsListBar.AddToClick(Sender: TObject);
begin
  FireIndex(FHandlers.OnAddTo, TMenuItem(Sender).Tag);
end;

procedure TAtlasTestsListBar.RemoveClick(Sender: TObject);
begin
  if Assigned(FHandlers.OnRemove) then
  begin
    FHandlers.OnRemove();
  end;
end;

procedure TAtlasTestsListBar.RunClick(Sender: TObject);
begin
  FireIndex(FHandlers.OnRun, FCurrent);
end;

end.
