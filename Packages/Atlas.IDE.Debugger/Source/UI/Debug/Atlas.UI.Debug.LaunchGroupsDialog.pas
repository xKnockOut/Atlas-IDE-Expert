unit Atlas.UI.Debug.LaunchGroupsDialog;

// Fenster der Startverbünde (#867), Fensterteil (nur VCL), im IDE-Thema über
// TAtlasDialog: oben die Verbünde aus .atlas, unten die Projekte des gewählten
// Verbunds in Startreihenfolge. Bearbeitet wird in .atlas („launchGroups“).
//     Atlas: Startverbünde
//     Verbund                 Projekte
//     Server + Client (aktiv) Server, Client
//     Projekt   Startprofil   Debugger   Warten danach
//     Server    Lokal         ja         Port 8080 (höchstens 20 s)
//     Client                  nein
//     [Aktiv setzen] [Starten] [In .atlas bearbeiten] [Schließen]

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Debug.LaunchGroups,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Foundation.ListView;

type
  TAtlasLaunchGroupsChoice = (None, Activate, Start, Edit);

  TAtlasLaunchGroupsDialog = class(TAtlasDialog)
  public const
    cWidth = 640;
    cGroupsHeight = 120;
    cItemsHeight = 160;
    cNoteHeight = 40;
    cNameWidth = 200;
    cProjectsMinWidth = 200;
    cProjectWidth = 160;
    cProfileWidth = 120;
    cDebugWidth = 80;
    cWaitMinWidth = 180;
    cWaitColumn = 3;
  private
    FGroups: TAtlasLaunchGroupList;
    FActive: string;
    FGroupList: TAtlasListView;
    FItemList: TAtlasListView;
    FActivate: TButton;
    FStart: TButton;
    FFilled: Boolean;
    procedure Fill;
    procedure FillItems;
    procedure GroupSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure GroupDblClick(Sender: TObject);
    function Chosen: string;
  protected
    procedure DoShow; override;
  public
    constructor CreateFor(AOwner: TComponent; const AGroups: TAtlasLaunchGroupList; const AActive: string);
    /// <summary>Zeigt die Verbünde; AChosen ist der gewählte Verbund (leer bei None oder Edit).</summary>
    class function Execute(const AGroups: TAtlasLaunchGroupList; const AActive: string;
      out AChosen: string): TAtlasLaunchGroupsChoice; static;
    /// <summary>Text der Spalte „Warten danach“.</summary>
    class function WaitText(const AItem: TAtlasLaunchItem): string; static;
    /// <summary>Projekte des Verbunds, mit Komma getrennt.</summary>
    class function ProjectsText(const AGroup: TAtlasLaunchGroup): string; static;
  end;

implementation

uses
  System.UITypes,
  Vcl.Forms,
  Atlas.UI.Debug.Strings;

{ TAtlasLaunchGroupsDialog }

constructor TAtlasLaunchGroupsDialog.CreateFor(AOwner: TComponent; const AGroups: TAtlasLaunchGroupList;
  const AActive: string);
var
  mRow, mItemsRow: TWinControl;
  mButtons: TAtlasButtonRow;
  mEdit: TButton;
begin
  inherited CreateDialog(AOwner, TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchDialogTitle), cWidth);
  FGroups := AGroups;
  FActive := AActive;
  if FGroups = nil then
  begin
    AddNote(cNoteHeight).Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchNoGroups);
  end;
  mRow := AddRow(cGroupsHeight);
  FGroupList := TAtlasListView.Create(Self);
  FGroupList.Parent := mRow;
  FGroupList.Align := alClient;
  FGroupList.ReadOnly := True;
  FGroupList.RowSelect := True;
  FGroupList.HideSelection := False;
  FGroupList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchColGroup), cNameWidth);
  FGroupList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchColProjects), cProjectsMinWidth);
  FGroupList.FillColumn(1, cProjectsMinWidth);
  FGroupList.OnSelectItem := GroupSelect;
  FGroupList.OnDblClick := GroupDblClick;
  mItemsRow := AddRow(cItemsHeight);
  FItemList := TAtlasListView.Create(Self);
  FItemList.Parent := mItemsRow;
  FItemList.Align := alClient;
  FItemList.ReadOnly := True;
  FItemList.RowSelect := True;
  FItemList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchColProject), cProjectWidth);
  FItemList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchColProfile), cProfileWidth);
  FItemList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchColDebug), cDebugWidth);
  FItemList.AddColumn(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchColWait), cWaitMinWidth);
  FItemList.FillColumn(cWaitColumn, cWaitMinWidth);
  mButtons := AddButtonRow;
  FActivate := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchActivate));
  FActivate.ModalResult := mrYes;
  FActivate.Enabled := False;
  FStart := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchStart), TAtlasButtonKind.Default);
  FStart.ModalResult := mrOk;
  FStart.Enabled := False;
  mEdit := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchEdit));
  mEdit.ModalResult := mrRetry;
  mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchClose), TAtlasButtonKind.Cancel);
  FitHeight;
  AllowResize(mItemsRow);
  ActiveControl := FGroupList;
end;

class function TAtlasLaunchGroupsDialog.WaitText(const AItem: TAtlasLaunchItem): string;
begin
  case AItem.Wait of
    TAtlasLaunchWaitKind.Seconds:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchWaitSeconds, [AItem.Value]);
    TAtlasLaunchWaitKind.Port:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchWaitPort, [AItem.Value, AItem.TimeoutSeconds]);
    TAtlasLaunchWaitKind.Window:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchWaitWindow, [AItem.TimeoutSeconds]);
  else
    Result := '';
  end;
end;

class function TAtlasLaunchGroupsDialog.ProjectsText(const AGroup: TAtlasLaunchGroup): string;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mNames, Length(AGroup.Items));
  for mIndex := 0 to High(AGroup.Items) do
  begin
    mNames[mIndex] := AGroup.Items[mIndex].Caption;
  end;
  Result := string.Join(', ', mNames);
end;

procedure TAtlasLaunchGroupsDialog.Fill;
var
  mGroup: TAtlasLaunchGroup;
  mItem: TListItem;
  mSelect: Integer;
begin
  mSelect := 0;
  FGroupList.Items.BeginUpdate;
  try
    FGroupList.Items.Clear;
    for mGroup in FGroups do
    begin
      mItem := FGroupList.Items.Add;
      mItem.Caption := mGroup.Name;
      if SameText(mGroup.Name, FActive) then
      begin
        mItem.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LaunchActiveMark, [mGroup.Name]);
        mSelect := mItem.Index;
      end;
      mItem.SubItems.Add(ProjectsText(mGroup));
    end;
  finally
    FGroupList.Items.EndUpdate;
  end;
  if FGroupList.Items.Count > 0 then
  begin
    FGroupList.Items[mSelect].Selected := True;
    FGroupList.Items[mSelect].Focused := True;
  end;
end;

procedure TAtlasLaunchGroupsDialog.FillItems;
var
  mLaunch: TAtlasLaunchItem;
  mItem: TListItem;
begin
  FItemList.Items.BeginUpdate;
  try
    FItemList.Items.Clear;
    if FGroupList.Selected = nil then
    begin
      Exit;
    end;
    for mLaunch in FGroups[FGroupList.Selected.Index].Items do
    begin
      mItem := FItemList.Items.Add;
      mItem.Caption := mLaunch.Caption;
      mItem.SubItems.Add(mLaunch.Profile);
      if mLaunch.Debug then
      begin
        mItem.SubItems.Add(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchYes));
      end
      else
      begin
        mItem.SubItems.Add(TAtlasDebugStrings.Text(TAtlasDebugTextId.LaunchNo));
      end;
      mItem.SubItems.Add(WaitText(mLaunch));
    end;
  finally
    FItemList.Items.EndUpdate;
  end;
end;

procedure TAtlasLaunchGroupsDialog.DoShow;
begin
  inherited;
  // Die Listen brauchen ein Fenster; nach dem Thema (VisibleChanging) ist es da.
  if not FFilled then
  begin
    FFilled := True;
    Fill;
    FillItems;
  end;
end;

procedure TAtlasLaunchGroupsDialog.GroupSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  FActivate.Enabled := FGroupList.Selected <> nil;
  FStart.Enabled := FGroupList.Selected <> nil;
  FillItems;
end;

procedure TAtlasLaunchGroupsDialog.GroupDblClick(Sender: TObject);
begin
  if FGroupList.Selected <> nil then
  begin
    ModalResult := mrYes;
  end;
end;

function TAtlasLaunchGroupsDialog.Chosen: string;
begin
  Result := '';
  if FGroupList.Selected <> nil then
  begin
    Result := FGroups[FGroupList.Selected.Index].Name;
  end;
end;

class function TAtlasLaunchGroupsDialog.Execute(const AGroups: TAtlasLaunchGroupList; const AActive: string;
  out AChosen: string): TAtlasLaunchGroupsChoice;
var
  mDialog: TAtlasLaunchGroupsDialog;
begin
  Result := TAtlasLaunchGroupsChoice.None;
  AChosen := '';
  mDialog := TAtlasLaunchGroupsDialog.CreateFor(nil, AGroups, AActive);
  try
    case mDialog.ShowModal of
      mrYes:
        Result := TAtlasLaunchGroupsChoice.Activate;
      mrOk:
        Result := TAtlasLaunchGroupsChoice.Start;
      mrRetry:
        Result := TAtlasLaunchGroupsChoice.Edit;
    end;
    if Result in [TAtlasLaunchGroupsChoice.Activate, TAtlasLaunchGroupsChoice.Start] then
    begin
      AChosen := mDialog.Chosen;
      if AChosen = '' then
      begin
        Result := TAtlasLaunchGroupsChoice.None;
      end;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
