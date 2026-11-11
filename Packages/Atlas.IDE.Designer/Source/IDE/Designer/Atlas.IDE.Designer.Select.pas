unit Atlas.IDE.Designer.Select;

// Knopf „Gleiche auswählen“ der Designer-Leiste (#738) in der IDE: Menü mit
// gleicher Klasse, Klasse und Nachfahren, gleichem Elternelement, Kindern,
// allen Nachkommen, gleichem Eigenschaftswert und Handler (Untermenüs mit den
// Werten des Bezugs) und „Auswahl umkehren“; jeder Eintrag nennt die
// Trefferzahl. Bezug ist die zuerst gewählte Komponente. Die Komponenten
// kommen aus dem Designer (Klassenkette über RTTI, Elternelement), Werte und
// Handler aus dem Formulartext (nur gespeicherte, also keine Vorgaben). Die
// Treffer merkt sich das Menü als Namen: Beim Klick sucht Atlas die
// Komponenten neu, mit Umschalt ergänzt das Ergebnis die Auswahl.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Menus,
  Atlas.Core.Designer.Similar;

type
  TAtlasIdeDesignerSelect = class
  private
    FMenu: TPopupMenu;
    /// <summary>Treffer je Menüeintrag (Tag) als Komponentennamen.</summary>
    FHits: TArray<TArray<string>>;
    FOnMessage: TProc<string>;
    procedure Add(AParent: TMenuItem; const ACaption: string; const AItems: TArray<TAtlasSimilarItem>;
      const AQuery: TAtlasSimilarQuery);
    procedure AddValues(const AItems: TArray<TAtlasSimilarItem>; AReference: Integer; AScope: TAtlasSimilarScope);
    procedure AddHandlers(const AItems: TArray<TAtlasSimilarItem>; AReference: Integer;
      AScope: TAtlasSimilarScope);
    procedure ItemClick(Sender: TObject);
    procedure Apply(const ANames: TArray<string>; AExtend: Boolean);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Menü für das Formular im aktiven Designer an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
    /// <summary>Komponenten des Formulars mit Klassenkette, Elternelement, Werten, Handlern und Auswahl.</summary>
    class function ItemsOf(ARoot: TComponent; const AText: string;
      const ASelected: TArray<TComponent>): TArray<TAtlasSimilarItem>; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Controls,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Designer.FormModel,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

function Contains(const AList: TArray<TComponent>; AComponent: TComponent): Boolean;
var
  mItem: TComponent;
begin
  for mItem in AList do
  begin
    if mItem = AComponent then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function HasText(const AList: TArray<string>; const AText: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Beschriftung im Menü: lange Werte (Hint, Text) gekürzt.</summary>
function MenuText(const AText: string): string;
const
  cMaxLength = 60;
begin
  Result := AText;
  if Length(Result) > cMaxLength then
  begin
    Result := Copy(Result, 1, cMaxLength - 1) + '…';
  end;
end;

/// <summary>Gespeicherte Werte und Handler (jeder einmal) aus dem Formulartext.</summary>
procedure TakeValues(var AItem: TAtlasSimilarItem; const AObject: TAtlasFormObject);
var
  mValue: TAtlasFormValue;
begin
  for mValue in AObject.Values do
  begin
    AItem.Values := AItem.Values + [mValue.Text];
  end;
  for mValue in AObject.Events do
  begin
    if not HasText(AItem.Handlers, mValue.Value) then
    begin
      AItem.Handlers := AItem.Handlers + [mValue.Value];
    end;
  end;
end;

function ScopeOf(const ASettings: TAtlasPluginSettings): TAtlasSimilarScope;
begin
  Result := TAtlasSimilarScope.Form;
  if SameText(ASettings.DesignerSelectScope, TAtlasPluginSettings.cDesignerScopeParent) then
  begin
    Result := TAtlasSimilarScope.Parent;
  end;
end;

{ TAtlasIdeDesignerSelect }

constructor TAtlasIdeDesignerSelect.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FMenu := TPopupMenu.Create(nil);
end;

destructor TAtlasIdeDesignerSelect.Destroy;
begin
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasIdeDesignerSelect.ItemsOf(ARoot: TComponent; const AText: string;
  const ASelected: TArray<TComponent>): TArray<TAtlasSimilarItem>;
var
  mObjects: TArray<TAtlasFormObject>;
  mIndex, mObject: Integer;
  mComponent: TComponent;
  mItem: TAtlasSimilarItem;
begin
  mObjects := TAtlasFormModel.Parse(AText);
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot.Components[mIndex];
    if mComponent.Name = '' then
    begin
      Continue;
    end;
    mItem := TAtlasSimilarItem.Create(mComponent.Name, TAtlasDesignerAccess.ClassChain(mComponent), '',
      mComponent is TControl);
    if mComponent is TControl then
    begin
      mItem.ParentName := TAtlasDesignerAccess.ParentNameOf(TControl(mComponent), ARoot);
    end;
    mItem.Selected := Contains(ASelected, mComponent);
    mObject := TAtlasFormModel.IndexOf(mObjects, mComponent.Name);
    if mObject > 0 then
    begin
      TakeValues(mItem, mObjects[mObject]);
    end;
    Result := Result + [mItem];
  end;
end;

procedure TAtlasIdeDesignerSelect.Add(AParent: TMenuItem; const ACaption: string;
  const AItems: TArray<TAtlasSimilarItem>; const AQuery: TAtlasSimilarQuery);
var
  mHits: TArray<Integer>;
  mNames: TArray<string>;
  mIndex: Integer;
  mItem: TMenuItem;
begin
  mHits := TAtlasSimilar.Find(AItems, AQuery);
  mNames := nil;
  for mIndex in mHits do
  begin
    mNames := mNames + [AItems[mIndex].Name];
  end;
  FHits := FHits + [mNames];
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSelectCount, [ACaption, Length(mHits)]);
  mItem.Tag := High(FHits);
  mItem.Enabled := Length(mHits) > 0;
  mItem.OnClick := ItemClick;
  AParent.Add(mItem);
end;

/// <summary>Untermenü mit einem Eintrag je Wert bzw. Handler; ohne Werte ein gesperrter Eintrag „(keine)“.</summary>
function SubMenu(AMenu: TPopupMenu; const ACaption: string; AEmpty: Boolean): TMenuItem;
var
  mNone: TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  AMenu.Items.Add(Result);
  if AEmpty then
  begin
    mNone := TMenuItem.Create(AMenu);
    mNone.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectNone);
    mNone.Enabled := False;
    Result.Add(mNone);
  end;
end;

procedure TAtlasIdeDesignerSelect.AddValues(const AItems: TArray<TAtlasSimilarItem>; AReference: Integer;
  AScope: TAtlasSimilarScope);
var
  mParent: TMenuItem;
  mValue: string;
  mValues: TArray<string>;
begin
  mValues := TAtlasSimilar.OfferedValues(AItems[AReference]);
  mParent := SubMenu(FMenu, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectSameValue),
    Length(mValues) = 0);
  for mValue in mValues do
  begin
    Add(mParent, MenuText(mValue), AItems, TAtlasSimilarQuery.Create(TAtlasSimilarKind.SameValue, AReference, AScope,
      mValue));
  end;
end;

procedure TAtlasIdeDesignerSelect.AddHandlers(const AItems: TArray<TAtlasSimilarItem>; AReference: Integer;
  AScope: TAtlasSimilarScope);
var
  mParent: TMenuItem;
  mHandler: string;
begin
  mParent := SubMenu(FMenu, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectSameHandler),
    Length(AItems[AReference].Handlers) = 0);
  for mHandler in AItems[AReference].Handlers do
  begin
    Add(mParent, mHandler, AItems, TAtlasSimilarQuery.Create(TAtlasSimilarKind.SameHandler, AReference, AScope,
      mHandler));
  end;
end;

procedure TAtlasIdeDesignerSelect.Popup(const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mItems: TArray<TAtlasSimilarItem>;
  mReference: Integer;
  mScope: TAtlasSimilarScope;
  mSettings: TAtlasPluginSettings;
  mNote: TMenuItem;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not mSettings.DesignerSelectSimilar or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mItems := ItemsOf(mRoot, TAtlasDesignerAccess.FormText(mRoot, TAtlasDesignerAccess.DesignerOf(mEditor)),
    TAtlasDesignerAccess.Selection(mEditor, mRoot));
  mReference := TAtlasSimilar.Reference(mItems);
  if mReference < 0 then
  begin
    if Assigned(FOnMessage) then
    begin
      FOnMessage(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerBarNoSelection));
    end;
    Exit;
  end;
  mScope := ScopeOf(mSettings);
  FMenu.Items.Clear;
  FHits := nil;
  Add(FMenu.Items, TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSelectSameClass,
    [mItems[mReference].Classes[0]]), mItems, TAtlasSimilarQuery.Create(TAtlasSimilarKind.SameClass, mReference,
    mScope));
  if mSettings.DesignerSelectDescendants then
  begin
    Add(FMenu.Items, TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSelectDescendants,
      [TAtlasSimilar.CommonBase(mItems, mReference)]), mItems,
      TAtlasSimilarQuery.Create(TAtlasSimilarKind.ClassAndDescendants, mReference, mScope));
  end;
  Add(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectSameParent), mItems,
    TAtlasSimilarQuery.Create(TAtlasSimilarKind.SameParent, mReference, mScope));
  Add(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectChildren), mItems,
    TAtlasSimilarQuery.Create(TAtlasSimilarKind.Children, mReference, mScope));
  Add(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectAllChildren), mItems,
    TAtlasSimilarQuery.Create(TAtlasSimilarKind.AllChildren, mReference, mScope));
  FMenu.Items.Add(NewLine);
  AddValues(mItems, mReference, mScope);
  AddHandlers(mItems, mReference, mScope);
  FMenu.Items.Add(NewLine);
  Add(FMenu.Items, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectInvert), mItems,
    TAtlasSimilarQuery.Create(TAtlasSimilarKind.Invert, mReference, mScope));
  FMenu.Items.Add(NewLine);
  mNote := TMenuItem.Create(FMenu);
  mNote.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectExtendHint);
  mNote.Enabled := False;
  FMenu.Items.Add(mNote);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeDesignerSelect.ItemClick(Sender: TObject);
var
  mTag: Integer;
  mExtend: Boolean;
begin
  mTag := TMenuItem(Sender).Tag;
  // Umschalt beim Klick: zur bisherigen Auswahl hinzufügen.
  mExtend := GetKeyState(VK_SHIFT) < 0;
  if (mTag < 0) or (mTag > High(FHits)) then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      Apply(FHits[mTag], mExtend);
    end);
end;

procedure TAtlasIdeDesignerSelect.Apply(const ANames: TArray<string>; AExtend: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mDesigner: IDesigner;
  mWanted: TArray<TComponent>;
  mName: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if mDesigner = nil then
  begin
    Exit;
  end;
  mWanted := nil;
  if AExtend then
  begin
    mWanted := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  end;
  // Umbenannt oder gelöscht, seit das Menü offen war: fällt heraus.
  for mName in ANames do
  begin
    mComponent := mRoot.FindComponent(mName);
    if (mComponent <> nil) and not Contains(mWanted, mComponent) then
    begin
      mWanted := mWanted + [mComponent];
    end;
  end;
  if Length(mWanted) = 0 then
  begin
    Exit;
  end;
  TAtlasDesignerAccess.Select(mDesigner, mRoot, mWanted);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSelectDone, [Length(mWanted)]));
  end;
end;

end.
