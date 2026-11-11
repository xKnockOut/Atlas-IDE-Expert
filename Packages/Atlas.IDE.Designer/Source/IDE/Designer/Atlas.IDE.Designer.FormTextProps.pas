unit Atlas.IDE.Designer.FormTextProps;

// Texte der Komponenten eines Formulars für „Texte des Formulars“ (#728)
// über RTTI lesen und schreiben. Ein Text hat einen Pfad ab der Komponente:
//   Caption, Text, Hint, TextHint, Title          String-Eigenschaften
//   Items[3], Lines[0]                            Zeilen von TStrings
//   EditLabel.Caption                             Unterobjekt
//   Columns[2].Title.Caption, Panels[0].Text      Sammlungen
// Leere Texte und ausgeschlossene Eigenschaften (designer.textTable.
// excludeProperties) fehlen. „Text“ entfällt neben „Lines“ (Memo).
// Abgeschnitten misst die Textbreite mit der Schrift der Komponente bei
// Labels ohne AutoSize und WordWrap, Knöpfen, Check- und RadioBoxen.

interface

uses
  System.Classes,
  Atlas.Core.Designer.FormTexts;

type
  TAtlasFormTextProps = class
  public
    /// <summary>Alle Texte von ARoot und seinen Komponenten in Komponentenreihenfolge.</summary>
    class function Collect(ARoot: TComponent; const AExcluded: string): TArray<TAtlasTextEntry>; static;
    /// <summary>Text unter APath von AComponent lesen.</summary>
    class function Read(AComponent: TComponent; const APath: string; out AText: string): Boolean; static;
    /// <summary>Text unter APath von AComponent setzen.</summary>
    class function Write(AComponent: TComponent; const APath, AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Menus,
  Vcl.StdCtrls;

const
  cTextProps: array [0 .. 4] of string = ('Caption', 'Text', 'Hint', 'TextHint', 'Title');
  cListProps: array [0 .. 1] of string = ('Items', 'Lines');
  cCollections: array [0 .. 2] of string = ('Columns', 'Panels', 'Sections');
  cItemProps: array [0 .. 2] of string = ('Caption', 'Text', 'Title.Caption');
  cButtonMargin = 8;
  cBoxMargin = 20;

/// <summary>Teil „Name[3]“ in Name und Index zerlegen; Index -1 ohne.</summary>
procedure SplitPart(const APart: string; out AName: string; out AIndex: Integer);
var
  mOpen: Integer;
begin
  mOpen := Pos('[', APart);
  AIndex := -1;
  AName := APart;
  if mOpen > 0 then
  begin
    AName := Copy(APart, 1, mOpen - 1);
    AIndex := StrToIntDef(Copy(APart, mOpen + 1, Length(APart) - mOpen - 1), -1);
  end;
end;

/// <summary>Objekt-Eigenschaft AName von AObject, bei AIndex >= 0 das Element der Sammlung.</summary>
function Child(AObject: TObject; const AName: string; AIndex: Integer): TObject;
var
  mInfo: PPropInfo;
begin
  Result := nil;
  mInfo := GetPropInfo(AObject, AName);
  if (mInfo = nil) or (mInfo^.PropType^.Kind <> tkClass) then
  begin
    Exit;
  end;
  Result := GetObjectProp(AObject, mInfo);
  if AIndex >= 0 then
  begin
    if (Result is TCollection) and (AIndex < TCollection(Result).Count) then
    begin
      Result := TCollection(Result).Items[AIndex];
    end
    else
    begin
      Result := nil;
    end;
  end;
end;

/// <summary>Objekt und letzten Teil von APath: Name und Index (-1 bei String-Eigenschaft).</summary>
function Resolve(AComponent: TComponent; const APath: string; out AObject: TObject; out AName: string;
  out AIndex: Integer): Boolean;
var
  mParts: TArray<string>;
  mPart: Integer;
begin
  mParts := APath.Split(['.']);
  AObject := AComponent;
  for mPart := 0 to High(mParts) - 1 do
  begin
    SplitPart(mParts[mPart], AName, AIndex);
    AObject := Child(AObject, AName, AIndex);
    if AObject = nil then
    begin
      Exit(False);
    end;
  end;
  SplitPart(mParts[High(mParts)], AName, AIndex);
  Result := Length(mParts) > 0;
end;

function IsText(AObject: TObject; const AName: string): Boolean;
var
  mInfo: PPropInfo;
begin
  mInfo := GetPropInfo(AObject, AName);
  Result := (mInfo <> nil) and (mInfo^.PropType^.Kind in [tkString, tkLString, tkUString, tkWString]) and
    (mInfo^.SetProc <> nil);
end;

function ListOf(AObject: TObject; const AName: string): TStrings;
var
  mChild: TObject;
begin
  Result := nil;
  mChild := Child(AObject, AName, -1);
  if mChild is TStrings then
  begin
    Result := TStrings(mChild);
  end;
end;

class function TAtlasFormTextProps.Read(AComponent: TComponent; const APath: string; out AText: string): Boolean;
var
  mObject: TObject;
  mName: string;
  mIndex: Integer;
  mList: TStrings;
begin
  AText := '';
  Result := Resolve(AComponent, APath, mObject, mName, mIndex);
  if Result and (mIndex >= 0) then
  begin
    mList := ListOf(mObject, mName);
    Result := (mList <> nil) and (mIndex < mList.Count);
    if Result then
    begin
      AText := mList[mIndex];
    end;
  end
  else if Result then
  begin
    Result := IsText(mObject, mName);
    if Result then
    begin
      AText := GetStrProp(mObject, mName);
    end;
  end;
end;

class function TAtlasFormTextProps.Write(AComponent: TComponent; const APath, AText: string): Boolean;
var
  mObject: TObject;
  mName: string;
  mIndex: Integer;
  mList: TStrings;
begin
  Result := Resolve(AComponent, APath, mObject, mName, mIndex);
  if Result and (mIndex >= 0) then
  begin
    mList := ListOf(mObject, mName);
    Result := (mList <> nil) and (mIndex < mList.Count);
    if Result then
    begin
      mList[mIndex] := AText;
    end;
  end
  else if Result then
  begin
    Result := IsText(mObject, mName);
    if Result then
    begin
      SetStrProp(mObject, mName, AText);
    end;
  end;
end;

/// <summary>Gruppe für Tastenkürzel: Parent bzw. Menüebene; leer, wenn Kürzel keine Rolle spielen.</summary>
function GroupOf(AComponent, ARoot: TComponent): string;
begin
  Result := '';
  if AComponent = ARoot then
  begin
    Exit;
  end;
  if (AComponent is TMenuItem) and (TMenuItem(AComponent).Parent <> nil) then
  begin
    Result := 'menu:' + TMenuItem(AComponent).Parent.Name;
    if TMenuItem(AComponent).Parent.Name = '' then
    begin
      Result := 'menu:' + TMenuItem(AComponent).GetParentMenu.Name;
    end;
  end
  else if (AComponent is TControl) and (TControl(AComponent).Parent <> nil) then
  begin
    Result := TControl(AComponent).Parent.Name;
  end;
end;

function HasFocusControl(AObject: TObject): Boolean;
begin
  Result := IsPublishedProp(AObject, 'FocusControl') and (PropType(AObject, 'FocusControl') = tkClass) and
    (GetObjectProp(AObject, 'FocusControl') <> nil);
end;

function TextWidth(AControl: TControl; const AText: string): Integer;
var
  mBitmap: TBitmap;
  mFont: TObject;
begin
  mBitmap := TBitmap.Create;
  try
    mFont := Child(AControl, 'Font', -1);
    if mFont is TFont then
    begin
      mBitmap.Canvas.Font.Assign(TFont(mFont));
    end;
    Result := mBitmap.Canvas.TextWidth(StripHotkey(AText));
  finally
    mBitmap.Free;
  end;
end;

function FlagOf(AObject: TObject; const AName: string): Boolean;
begin
  Result := IsPublishedProp(AObject, AName) and (PropType(AObject, AName) = tkEnumeration) and
    (GetOrdProp(AObject, AName) <> 0);
end;

/// <summary>Platz für die Caption; -1, wenn die Breite nicht fest ist.</summary>
function RoomOf(AControl: TControl): Integer;
begin
  Result := -1;
  if AControl is TCustomLabel then
  begin
    if not FlagOf(AControl, 'AutoSize') and not FlagOf(AControl, 'WordWrap') then
    begin
      Result := AControl.Width;
    end;
  end
  else if (AControl is TCustomCheckBox) or (AControl is TRadioButton) then
  begin
    Result := AControl.Width - cBoxMargin;
  end
  else if AControl is TButton then
  begin
    Result := AControl.Width - cButtonMargin;
  end;
end;

function Truncated(AComponent: TComponent; const AText: string): Boolean;
var
  mRoom: Integer;
begin
  Result := False;
  if AComponent is TControl then
  begin
    mRoom := RoomOf(TControl(AComponent));
    Result := (mRoom >= 0) and (TextWidth(TControl(AComponent), AText) > mRoom);
  end;
end;

procedure AddEntry(var AEntries: TArray<TAtlasTextEntry>; AComponent, ARoot: TComponent; const APath, AText: string);
var
  mEntry: TAtlasTextEntry;
begin
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mEntry := TAtlasTextEntry.Create(AComponent.Name, AComponent.ClassName, APath, AText, '');
  if APath = 'Caption' then
  begin
    mEntry.Group := GroupOf(AComponent, ARoot);
    mEntry.NeedsColon := HasFocusControl(AComponent);
    mEntry.Truncated := Truncated(AComponent, AText);
  end
  else if APath = 'EditLabel.Caption' then
  begin
    mEntry.Group := GroupOf(AComponent, ARoot);
    mEntry.NeedsColon := True;
  end;
  AEntries := AEntries + [mEntry];
end;

procedure AddPath(var AEntries: TArray<TAtlasTextEntry>; AComponent, ARoot: TComponent; const APath: string);
var
  mText: string;
begin
  if TAtlasFormTextProps.Read(AComponent, APath, mText) then
  begin
    AddEntry(AEntries, AComponent, ARoot, APath, mText);
  end;
end;

procedure AddLists(var AEntries: TArray<TAtlasTextEntry>; AComponent, ARoot: TComponent; const AExcluded: string);
var
  mName: string;
  mList: TStrings;
  mLine: Integer;
begin
  for mName in cListProps do
  begin
    mList := ListOf(AComponent, mName);
    if (mList = nil) or TAtlasFormTexts.Excluded(mName, AExcluded) then
    begin
      Continue;
    end;
    for mLine := 0 to mList.Count - 1 do
    begin
      AddEntry(AEntries, AComponent, ARoot, mName + '[' + IntToStr(mLine) + ']', mList[mLine]);
    end;
  end;
end;

procedure AddCollections(var AEntries: TArray<TAtlasTextEntry>; AComponent, ARoot: TComponent;
  const AExcluded: string);
var
  mName, mItemProp: string;
  mCollection: TObject;
  mItem: Integer;
begin
  for mName in cCollections do
  begin
    mCollection := Child(AComponent, mName, -1);
    if not (mCollection is TCollection) or TAtlasFormTexts.Excluded(mName, AExcluded) then
    begin
      Continue;
    end;
    for mItem := 0 to TCollection(mCollection).Count - 1 do
    begin
      for mItemProp in cItemProps do
      begin
        AddPath(AEntries, AComponent, ARoot, mName + '[' + IntToStr(mItem) + '].' + mItemProp);
      end;
    end;
  end;
end;

procedure AddComponent(var AEntries: TArray<TAtlasTextEntry>; AComponent, ARoot: TComponent; const AExcluded: string);
var
  mName: string;
begin
  for mName in cTextProps do
  begin
    if TAtlasFormTexts.Excluded(mName, AExcluded) or ((mName = 'Text') and (ListOf(AComponent, 'Lines') <> nil)) then
    begin
      Continue;
    end;
    AddPath(AEntries, AComponent, ARoot, mName);
  end;
  if not TAtlasFormTexts.Excluded('EditLabel', AExcluded) then
  begin
    AddPath(AEntries, AComponent, ARoot, 'EditLabel.Caption');
  end;
  AddLists(AEntries, AComponent, ARoot, AExcluded);
  AddCollections(AEntries, AComponent, ARoot, AExcluded);
end;

class function TAtlasFormTextProps.Collect(ARoot: TComponent; const AExcluded: string): TArray<TAtlasTextEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  AddComponent(Result, ARoot, ARoot, AExcluded);
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if ARoot.Components[mIndex].Name <> '' then
    begin
      AddComponent(Result, ARoot.Components[mIndex], ARoot, AExcluded);
    end;
  end;
end;

end.
