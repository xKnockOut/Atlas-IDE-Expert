unit Atlas.IDE.Designer.SearchItems;

// Komponenten des Formulars für das Fenster „Komponenten suchen“ (#1442):
// Name, Klasse, Art, Elternelement, Lage, Caption/Text, gesetzte Eigenschaften
// für die Vorschau und belegte Ereignisse mit den Handlernamen des Designers.
// RootItem liefert das Formular selbst für „Im Designer zeigen“ (#511).
// Nur im Hauptthread.

interface

uses
  System.Classes,
  DesignIntf,
  Atlas.Core.Designer.Components;

type
  TAtlasDesignerSearchItems = class
  public
    class function ItemsOf(ARoot: TComponent; const ADesigner: IDesigner): TArray<TAtlasDesignerItem>; static;
    /// <summary>Das Formular selbst als Eintrag, samt seiner belegten Ereignisse (#511).</summary>
    class function RootItem(ARoot: TComponent; const ADesigner: IDesigner): TAtlasDesignerItem; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  Vcl.Controls,
  Atlas.IDE.Designer.Access;

const
  /// <summary>Eigenschaften für die Vorschau im Suchfenster, sofern gesetzt.</summary>
  cPreviewProperties: array[0..9] of string = ('Caption', 'Text', 'Align', 'Visible', 'Enabled', 'TabOrder', 'Hint',
    'Action', 'DataSource', 'DataField');

/// <summary>Gesetzte Eigenschaften für die Vorschau; Vorgaben zeigen nichts Neues.</summary>
function PreviewOf(AComponent: TComponent): TArray<string>;
var
  mName, mText: string;
begin
  Result := nil;
  for mName in cPreviewProperties do
  begin
    if not TAtlasDesignerAccess.PropText(AComponent, mName, mText) then
    begin
      Continue;
    end;
    if (SameText(mName, 'Align') and SameText(mText, 'alNone')) or
      ((SameText(mName, 'Visible') or SameText(mName, 'Enabled')) and SameText(mText, 'True')) then
    begin
      Continue;
    end;
    Result := Result + [mName + ' = ' + mText];
  end;
end;

/// <summary>Belegte Ereignisse als „OnClick = Button1Click“.</summary>
function EventsOf(AComponent: TComponent; const ADesigner: IDesigner): TArray<string>;
var
  mProp, mCount: Integer;
  mList: PPropList;
  mMethod: TMethod;
  mText: string;
begin
  Result := nil;
  mCount := GetPropList(PTypeInfo(AComponent.ClassInfo), [tkMethod], nil);
  if mCount <= 0 then
  begin
    Exit;
  end;
  GetMem(mList, mCount * SizeOf(PPropInfo));
  try
    GetPropList(PTypeInfo(AComponent.ClassInfo), [tkMethod], mList);
    for mProp := 0 to mCount - 1 do
    begin
      mMethod := GetMethodProp(AComponent, mList^[mProp]);
      if mMethod.Code = nil then
      begin
        Continue;
      end;
      mText := ADesigner.GetMethodName(mMethod);
      if mText <> '' then
      begin
        Result := Result + [string(mList^[mProp]^.Name) + ' = ' + mText];
      end;
    end;
  finally
    FreeMem(mList);
  end;
end;

function ItemOf(AComponent, ARoot: TComponent; const ADesigner: IDesigner): TAtlasDesignerItem;
var
  mText: string;
begin
  Result := TAtlasDesignerItem.Create(AComponent.Name, AComponent.ClassName, AComponent is TControl);
  if AComponent is TControl then
  begin
    Result.Container := (AComponent is TWinControl) and (csAcceptsControls in TControl(AComponent).ControlStyle);
    Result.ParentName := TAtlasDesignerAccess.ParentNameOf(TControl(AComponent), ARoot);
    if ARoot is TWinControl then
    begin
      Result.Bounds := TAtlasDesignerAccess.BoundsInRoot(TControl(AComponent), TWinControl(ARoot));
    end;
  end;
  if TAtlasDesignerAccess.PropText(AComponent, 'Caption', mText) or
    TAtlasDesignerAccess.PropText(AComponent, 'Text', mText) then
  begin
    Result.Caption := mText;
  end;
  Result.Properties := Result.Properties + PreviewOf(AComponent);
  if ADesigner <> nil then
  begin
    Result.Events := Result.Events + EventsOf(AComponent, ADesigner);
  end;
end;

class function TAtlasDesignerSearchItems.ItemsOf(ARoot: TComponent;
  const ADesigner: IDesigner): TArray<TAtlasDesignerItem>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if ARoot.Components[mIndex].Name <> '' then
    begin
      Result := Result + [ItemOf(ARoot.Components[mIndex], ARoot, ADesigner)];
    end;
  end;
end;

class function TAtlasDesignerSearchItems.RootItem(ARoot: TComponent; const ADesigner: IDesigner): TAtlasDesignerItem;
begin
  Result := TAtlasDesignerItem.Create(ARoot.Name, ARoot.ClassName, False);
  if ADesigner <> nil then
  begin
    Result.Events := EventsOf(ARoot, ADesigner);
  end;
end;

end.
