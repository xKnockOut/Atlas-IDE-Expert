unit Atlas.UI.Results.Items;

// Listen mit Kennungen im Ergebnisfenster (#1455), zuerst die persönlichen Notizen (#545): je Gruppe (etwa Datei)
// „Zeile: Titel“, verwaiste Notizen in einer Gruppe am Ende; Doppelklick oder Enter springt, das Kontextmenü
// bearbeitet oder löscht den Eintrag (Entf löscht ebenfalls). Mit OnOpen führt Doppelklick bzw. Enter eine eigene
// Aktion aus, etwa die Komponente im Designer wählen (#524).

interface

uses
  Vcl.Menus,
  Atlas.UI.Results.View;

type
  /// <summary>Eintrag einer Liste mit Kennung (etwa eine Notiz, #545) bearbeiten bzw. löschen.</summary>
  TAtlasResultsItemAction = reference to procedure(const AItemId: string);

  /// <summary>Eintrag einer Liste mit Kennung: Text, Ort für den Sprung (Line 0-basiert).</summary>
  TAtlasResultsItem = record
    Id: string;
    Caption: string;
    FileName: string;
    Line: Integer;
  end;

  /// <summary>Gruppe einer Liste mit Kennungen (etwa die Notizen einer Datei).</summary>
  TAtlasResultsItemGroup = record
    Caption: string;
    FileName: string;
    Items: TArray<TAtlasResultsItem>;
  end;

  /// <summary>Liste mit Kennungen, die ein Modul zeigt (#1455; zuerst die Notizen, #545). Owner nennt den
  /// Besitzer („notes“); EditCaption bzw. DeleteCaption '' lassen den Eintrag im Kontextmenü weg. Entf löscht,
  /// solange OnDelete gesetzt ist.</summary>
  TAtlasResultsItemList = record
    Owner: string;
    Title: string;
    Groups: TArray<TAtlasResultsItemGroup>;
    /// <summary>Diesen Eintrag wählen; '' = den ersten.</summary>
    SelectId: string;
    EditCaption: string;
    DeleteCaption: string;
    OnEdit: TAtlasResultsItemAction;
    OnDelete: TAtlasResultsItemAction;
    /// <summary>Doppelklick bzw. Enter auf einem Eintrag statt des Sprungs zu FileName und Line (etwa eine
    /// Komponente im Designer wählen, #524); nil = Sprung.</summary>
    OnOpen: TAtlasResultsItemAction;
  end;

  TAtlasResultsItemsPart = class(TAtlasResultsPart)
  private
    /// <summary>Gezeigte Liste mit Kennungen; Owner '' = keine.</summary>
    FList: TAtlasResultsItemList;
    FEditItem: TMenuItem;
    FDeleteItem: TMenuItem;
    procedure EditClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  protected
    procedure Reset; override;
    procedure Popup; override;
    function KeyDown(AKey: Word): Boolean; override;
    function Open(const AData: TAtlasResultsNode): Boolean; override;
  public
    constructor Create(AView: TAtlasResultsView);
    /// <summary>Liste mit Kennungen eines Moduls: je Gruppe ein Knoten, alles aufgeklappt.</summary>
    procedure Show(const AList: TAtlasResultsItemList);
    /// <summary>Zeigt gerade die Liste mit Kennungen von AOwner?</summary>
    function ShowsItemsOf(const AOwner: string): Boolean;
    /// <summary>Aktionen der Liste von AOwner vergessen (Modul stoppt, Regel 3); die Liste bleibt sichtbar, ohne
    /// Bearbeiten und Löschen.</summary>
    procedure Release(const AOwner: string);
    /// <summary>Kennung des gewählten Eintrags; '' ohne.</summary>
    function SelectedId: string;
    procedure EditSelected;
    procedure DeleteSelected;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.ComCtrls;

{ TAtlasResultsItemsPart }

constructor TAtlasResultsItemsPart.Create(AView: TAtlasResultsView);
begin
  inherited Create(AView);
  // Der Text kommt mit der Liste.
  FEditItem := TAtlasResultsControls.MenuItem(AView.Menu, '', EditClick);
  FDeleteItem := TAtlasResultsControls.MenuItem(AView.Menu, '', DeleteClick);
end;

procedure TAtlasResultsItemsPart.Reset;
begin
  FList := Default(TAtlasResultsItemList);
end;

procedure TAtlasResultsItemsPart.Show(const AList: TAtlasResultsItemList);
var
  mGroup: TAtlasResultsItemGroup;
  mItem: TAtlasResultsItem;
  mData: TAtlasResultsNode;
  mGroupNode, mNode, mSelected: TTreeNode;
begin
  View.Clear(AList.Title);
  FList := AList;
  mSelected := nil;
  View.Tree.Items.BeginUpdate;
  try
    for mGroup in AList.Groups do
    begin
      mData := TAtlasResultsNode.Create(TAtlasResultsNodeKind.Group);
      mData.FileName := mGroup.FileName;
      mGroupNode := View.AddNode(nil, mGroup.Caption, mData);
      for mItem in mGroup.Items do
      begin
        mData := TAtlasResultsNode.Place(TAtlasResultsNodeKind.Item, mItem.FileName, mItem.Line, 0);
        mData.ItemId := mItem.Id;
        mNode := View.AddNode(mGroupNode, mItem.Caption, mData);
        if (AList.SelectId <> '') and (mItem.Id = AList.SelectId) then
        begin
          mSelected := mNode;
        end;
      end;
      mGroupNode.Expand(False);
    end;
  finally
    View.Tree.Items.EndUpdate;
  end;
  View.Select(mSelected);
end;

function TAtlasResultsItemsPart.ShowsItemsOf(const AOwner: string): Boolean;
begin
  Result := (AOwner <> '') and SameText(FList.Owner, AOwner);
end;

procedure TAtlasResultsItemsPart.Release(const AOwner: string);
begin
  if not ShowsItemsOf(AOwner) then
  begin
    Exit;
  end;
  FList.OnEdit := nil;
  FList.OnDelete := nil;
  FList.OnOpen := nil;
end;

function TAtlasResultsItemsPart.SelectedId: string;
begin
  Result := View.DataOf(View.Tree.Selected).ItemId;
end;

procedure TAtlasResultsItemsPart.EditSelected;
var
  mId: string;
begin
  mId := SelectedId;
  if (mId <> '') and Assigned(FList.OnEdit) then
  begin
    FList.OnEdit(mId);
  end;
end;

procedure TAtlasResultsItemsPart.DeleteSelected;
var
  mId: string;
begin
  mId := SelectedId;
  if (mId <> '') and Assigned(FList.OnDelete) then
  begin
    FList.OnDelete(mId);
  end;
end;

procedure TAtlasResultsItemsPart.Popup;
begin
  FEditItem.Caption := FList.EditCaption;
  FDeleteItem.Caption := FList.DeleteCaption;
  FEditItem.Visible := (FList.Owner <> '') and (FList.EditCaption <> '') and Assigned(FList.OnEdit);
  FDeleteItem.Visible := (FList.Owner <> '') and (FList.DeleteCaption <> '') and Assigned(FList.OnDelete);
  FEditItem.Enabled := SelectedId <> '';
  FDeleteItem.Enabled := SelectedId <> '';
end;

function TAtlasResultsItemsPart.KeyDown(AKey: Word): Boolean;
begin
  Result := (AKey = VK_DELETE) and (FList.Owner <> '') and Assigned(FList.OnDelete);
  if Result then
  begin
    DeleteSelected;
  end;
end;

function TAtlasResultsItemsPart.Open(const AData: TAtlasResultsNode): Boolean;
begin
  Result := (AData <> nil) and (AData.Kind = TAtlasResultsNodeKind.Item) and (AData.ItemId <> '') and
    Assigned(FList.OnOpen);
  if Result then
  begin
    FList.OnOpen(AData.ItemId);
  end;
end;

procedure TAtlasResultsItemsPart.EditClick(Sender: TObject);
begin
  EditSelected;
end;

procedure TAtlasResultsItemsPart.DeleteClick(Sender: TObject);
begin
  DeleteSelected;
end;

end.
