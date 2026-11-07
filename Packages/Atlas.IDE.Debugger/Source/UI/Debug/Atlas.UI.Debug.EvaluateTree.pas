unit Atlas.UI.Debug.EvaluateTree;

// Baum des Fensters „Auswerten“ (#784): gleicht einen TTreeView mit einer
// TAtlasEvalList ab, statt ihn neu aufzubauen. Vorher baute der Frame den
// ganzen Baum neu auf, sobald sich die Aufklappbarkeit einer Zeile änderte,
// also nach fast jeder Zeitscheibe der Auswertung (alle 10 bis 40 ms), und
// suchte beim Zeichnen jeder Zeile ihren Knoten über alle Knoten der Liste.
// Das Fenster wurde dabei träge, die Bildlaufposition sprang zurück.
//
// Jetzt:
//   - Sync geht die Ebenen der Liste und des Baums gemeinsam durch: gleiche
//     Schlüssel bleiben stehen (nur Text und Darstellung ändern sich),
//     fehlende Zeilen kommen an ihrer Stelle dazu, übrige fallen weg.
//     BeginUpdate nur, wenn sich Zeilen ändern; nur geänderte Farben lassen
//     den Baum neu zeichnen.
//   - Je Baumknoten stehen Schlüssel und Darstellung (Farbe, fett) in einer
//     Tabelle, Data ist der Index + 1. Data übersteht das Neuanlegen des
//     Fensters (TTreeView sichert die Knoten mit Data); zeichnen braucht keine
//     Suche in der Liste mehr. Platzhalter haben Data = nil.
//   - Platzhalter für das Aufklappzeichen: auch während ein Wert neu
//     ausgewertet wird, solange der alte aufklappbar war (kein Flackern des
//     Zeichens bei jedem Schritt).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.ComCtrls,
  Atlas.Core.Debug.Evaluate;

type
  {$SCOPEDENUMS ON}
  /// <summary>Farbe einer Zeile: normal, seit dem letzten Halt geändert, grau (Fehler, offen, Platzhalter).</summary>
  TAtlasEvalLook = (Normal, Changed, Gray);
  {$SCOPEDENUMS OFF}

  /// <summary>Was zu einem Baumknoten gehört; Key leer bei Platzhaltern.</summary>
  TAtlasEvalItemInfo = record
    Key: string;
    Look: TAtlasEvalLook;
    Bold: Boolean;
  end;

  TAtlasEvalTreeSync = class
  public const
    /// <summary>Höchstens so viele Zeichen eines Werts im Baum; der ganze steht unten.</summary>
    cMaxTreeValue = 200;
  private
    FTree: TTreeView;
    FInfos: TArray<TAtlasEvalItemInfo>;
    FInfoCount: Integer;
    FUpdating: Boolean;
    FRepaint: Boolean;
    function InfoIndex(AItem: TTreeNode): Integer;
    function NewInfo(const AKey: string): Pointer;
    procedure Structure;
    function Insert(AParent, ABefore: TTreeNode; const AKey: string): TTreeNode;
    function DeleteItem(AItem: TTreeNode): TTreeNode;
    procedure DeleteFrom(AItem: TTreeNode);
    procedure SyncPlaceholder(AItem: TTreeNode; const AText: string);
    procedure SyncLevel(AParent: TTreeNode; const ANodes: TArray<TAtlasEvalNode>);
    procedure SyncItem(AItem: TTreeNode; ANode: TAtlasEvalNode);
    procedure SyncChildren(AItem: TTreeNode; ANode: TAtlasEvalNode);
    procedure Compact;
  public
    constructor Create(ATree: TTreeView);
    /// <summary>Baum an AList angleichen (nil: leer). Der Baum braucht ein Fenster.</summary>
    procedure Sync(AList: TAtlasEvalList);
    /// <summary>Schlüssel des Knotens; '' bei nil und Platzhaltern.</summary>
    function KeyOf(AItem: TTreeNode): string;
    /// <summary>Darstellung des Knotens; Platzhalter grau.</summary>
    function InfoOf(AItem: TTreeNode): TAtlasEvalItemInfo;
    /// <summary>Baumknoten zum Schlüssel; nil, wenn es keinen gibt.</summary>
    function ItemOf(const AKey: string): TTreeNode;
    /// <summary>Text im Baum: „Name = Wert“, Wert gekürzt und einzeilig.</summary>
    class function NodeText(ANode: TAtlasEvalNode): string; static;
    class function LookOf(ANode: TAtlasEvalNode): TAtlasEvalLook; static;
    /// <summary>Zeigt das Aufklappzeichen ohne geholte Kinder: aufklappbarer Wert oder, solange neu ausgewertet
    /// wird, aufklappbarer Wert des letzten Halts.</summary>
    class function ShowsExpander(ANode: TAtlasEvalNode): Boolean; static;
  end;

implementation

uses
  Atlas.UI.Debug.Strings;

function RootsOf(AList: TAtlasEvalList): TArray<TAtlasEvalNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AList = nil then
  begin
    Exit;
  end;
  SetLength(Result, AList.Count);
  for mIndex := 0 to AList.Count - 1 do
  begin
    Result[mIndex] := AList.Roots[mIndex];
  end;
end;

function ChildrenOf(ANode: TAtlasEvalNode): TArray<TAtlasEvalNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, ANode.ChildCount);
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result[mIndex] := ANode.Children[mIndex];
  end;
end;

function FirstChildOf(ATree: TTreeView; AParent: TTreeNode): TTreeNode;
begin
  if AParent = nil then
  begin
    Result := ATree.Items.GetFirstNode;
  end
  else
  begin
    Result := AParent.getFirstChild;
  end;
end;

{ TAtlasEvalTreeSync }

constructor TAtlasEvalTreeSync.Create(ATree: TTreeView);
begin
  inherited Create;
  FTree := ATree;
end;

function TAtlasEvalTreeSync.InfoIndex(AItem: TTreeNode): Integer;
begin
  Result := -1;
  if (AItem <> nil) and (AItem.Data <> nil) and (NativeInt(AItem.Data) <= FInfoCount) then
  begin
    Result := Integer(NativeInt(AItem.Data) - 1);
  end;
end;

function TAtlasEvalTreeSync.NewInfo(const AKey: string): Pointer;
begin
  if FInfoCount = Length(FInfos) then
  begin
    SetLength(FInfos, 2 * FInfoCount + 16);
  end;
  FInfos[FInfoCount] := Default(TAtlasEvalItemInfo);
  FInfos[FInfoCount].Key := AKey;
  Inc(FInfoCount);
  Result := Pointer(NativeInt(FInfoCount));
end;

function TAtlasEvalTreeSync.KeyOf(AItem: TTreeNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := InfoIndex(AItem);
  if mIndex >= 0 then
  begin
    Result := FInfos[mIndex].Key;
  end;
end;

function TAtlasEvalTreeSync.InfoOf(AItem: TTreeNode): TAtlasEvalItemInfo;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasEvalItemInfo);
  Result.Look := TAtlasEvalLook.Gray;
  mIndex := InfoIndex(AItem);
  if mIndex >= 0 then
  begin
    Result := FInfos[mIndex];
  end;
end;

function TAtlasEvalTreeSync.ItemOf(const AKey: string): TTreeNode;
var
  mItem: TTreeNode;
begin
  Result := nil;
  if AKey = '' then
  begin
    Exit;
  end;
  mItem := FTree.Items.GetFirstNode;
  while (mItem <> nil) and (KeyOf(mItem) <> AKey) do
  begin
    mItem := mItem.GetNext;
  end;
  Result := mItem;
end;

procedure TAtlasEvalTreeSync.Structure;
begin
  // Erst bei der ersten Änderung an den Zeilen: Texte allein zeichnen nur ihre Zeile neu.
  if not FUpdating then
  begin
    FUpdating := True;
    FTree.Items.BeginUpdate;
  end;
end;

function TAtlasEvalTreeSync.Insert(AParent, ABefore: TTreeNode; const AKey: string): TTreeNode;
var
  mData: Pointer;
begin
  Structure;
  mData := nil;
  if AKey <> '' then
  begin
    mData := NewInfo(AKey);
  end;
  if ABefore = nil then
  begin
    Result := FTree.Items.AddChildObject(AParent, '', mData);
  end
  else
  begin
    Result := FTree.Items.InsertObject(ABefore, '', mData);
  end;
end;

function TAtlasEvalTreeSync.DeleteItem(AItem: TTreeNode): TTreeNode;
begin
  Structure;
  Result := AItem.getNextSibling;
  AItem.Delete;
end;

procedure TAtlasEvalTreeSync.DeleteFrom(AItem: TTreeNode);
var
  mItem: TTreeNode;
begin
  mItem := AItem;
  while mItem <> nil do
  begin
    mItem := DeleteItem(mItem);
  end;
end;

procedure TAtlasEvalTreeSync.SyncPlaceholder(AItem: TTreeNode; const AText: string);
var
  mFirst: TTreeNode;
begin
  mFirst := AItem.getFirstChild;
  if (mFirst <> nil) and (mFirst.Data = nil) then
  begin
    DeleteFrom(mFirst.getNextSibling);
  end
  else
  begin
    DeleteFrom(mFirst);
    mFirst := Insert(AItem, nil, '');
  end;
  if mFirst.Text <> AText then
  begin
    mFirst.Text := AText;
  end;
end;

procedure TAtlasEvalTreeSync.SyncLevel(AParent: TTreeNode; const ANodes: TArray<TAtlasEvalNode>);
var
  mPositions: TDictionary<string, Integer>;
  mItem, mCurrent: TTreeNode;
  mIndex, mAt: Integer;
begin
  mPositions := TDictionary<string, Integer>.Create;
  try
    // Erste Stelle je Schlüssel auf dieser Ebene.
    for mIndex := High(ANodes) downto 0 do
    begin
      mPositions.AddOrSetValue(ANodes[mIndex].Key, mIndex);
    end;
    mItem := FirstChildOf(FTree, AParent);
    for mIndex := 0 to High(ANodes) do
    begin
      // Zeilen, die es nicht mehr gibt oder die weiter vorn hingehören, fallen weg (auch Platzhalter).
      while (mItem <> nil) and not (mPositions.TryGetValue(KeyOf(mItem), mAt) and (mAt >= mIndex)) do
      begin
        mItem := DeleteItem(mItem);
      end;
      if (mItem <> nil) and (KeyOf(mItem) = ANodes[mIndex].Key) then
      begin
        mCurrent := mItem;
      end
      else
      begin
        mCurrent := Insert(AParent, mItem, ANodes[mIndex].Key);
      end;
      SyncItem(mCurrent, ANodes[mIndex]);
      mItem := mCurrent.getNextSibling;
    end;
    DeleteFrom(mItem);
  finally
    mPositions.Free;
  end;
end;

procedure TAtlasEvalTreeSync.SyncChildren(AItem: TTreeNode; ANode: TAtlasEvalNode);
begin
  if ANode.ChildrenLoaded and (ANode.ChildCount = 0) then
  begin
    SyncPlaceholder(AItem, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateNoFields));
  end
  else if ANode.ChildrenLoaded then
  begin
    SyncLevel(AItem, ChildrenOf(ANode));
  end
  else if ShowsExpander(ANode) then
  begin
    // Platzhalter für das Aufklappzeichen; die Felder holt OnExpand.
    SyncPlaceholder(AItem, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePending));
  end
  else
  begin
    DeleteFrom(AItem.getFirstChild);
  end;
end;

procedure TAtlasEvalTreeSync.SyncItem(AItem: TTreeNode; ANode: TAtlasEvalNode);
var
  mText: string;
  mIndex: Integer;
  mLook: TAtlasEvalLook;
  mBold: Boolean;
begin
  mText := NodeText(ANode);
  if AItem.Text <> mText then
  begin
    AItem.Text := mText;
  end;
  mIndex := InfoIndex(AItem);
  mLook := LookOf(ANode);
  mBold := (ANode.Parent = nil) and ANode.Pinned;
  if (FInfos[mIndex].Look <> mLook) or (FInfos[mIndex].Bold <> mBold) then
  begin
    // Farben hängen nicht am Text: neu zeichnen.
    FInfos[mIndex].Look := mLook;
    FInfos[mIndex].Bold := mBold;
    FRepaint := True;
  end;
  SyncChildren(AItem, ANode);
  if ANode.Expanded and ANode.ChildrenLoaded and not AItem.Expanded then
  begin
    AItem.Expand(False);
  end;
end;

procedure TAtlasEvalTreeSync.Compact;
var
  mInfos: TArray<TAtlasEvalItemInfo>;
  mCount, mIndex: Integer;
  mItem: TTreeNode;
begin
  // Gelöschte Knoten lassen ihre Einträge zurück: ab der doppelten Zahl der Knoten neu nummerieren.
  if FInfoCount <= 2 * FTree.Items.Count + 64 then
  begin
    Exit;
  end;
  SetLength(mInfos, FTree.Items.Count);
  mCount := 0;
  mItem := FTree.Items.GetFirstNode;
  while mItem <> nil do
  begin
    mIndex := InfoIndex(mItem);
    if mIndex >= 0 then
    begin
      mInfos[mCount] := FInfos[mIndex];
      Inc(mCount);
      mItem.Data := Pointer(NativeInt(mCount));
    end;
    mItem := mItem.GetNext;
  end;
  FInfos := mInfos;
  FInfoCount := mCount;
end;

procedure TAtlasEvalTreeSync.Sync(AList: TAtlasEvalList);
begin
  FUpdating := False;
  FRepaint := False;
  try
    SyncLevel(nil, RootsOf(AList));
  finally
    if FUpdating then
    begin
      FTree.Items.EndUpdate;
    end;
  end;
  Compact;
  // EndUpdate zeichnet ohnehin alles neu.
  if FRepaint and not FUpdating then
  begin
    FTree.Invalidate;
  end;
end;

class function TAtlasEvalTreeSync.NodeText(ANode: TAtlasEvalNode): string;
var
  mValue: string;
begin
  case ANode.State of
    TAtlasEvalState.Pending:
      // Bis zum neuen Wert grau der des letzten Halts: kein Flackern bei jedem Schritt.
      if ANode.Value <> '' then
      begin
        mValue := ANode.Value;
      end
      else
      begin
        mValue := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluatePending);
      end;
    TAtlasEvalState.Unavailable:
      mValue := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEvaluateNotStopped);
  else
    mValue := ANode.Value;
  end;
  // Erst kürzen, dann einzeilig machen: Bei langen Werten (Strings, Listen) sonst bei jedem Abgleich der ganze
  // Wert. Aus 2 * MaxTreeValue + 1 Zeichen bleiben nach dem Ersetzen mindestens MaxTreeValue + 1.
  mValue := Copy(mValue, 1, 2 * cMaxTreeValue + 1);
  mValue := StringReplace(StringReplace(mValue, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  if Length(mValue) > cMaxTreeValue then
  begin
    mValue := Copy(mValue, 1, cMaxTreeValue) + #$2026;
  end;
  Result := ANode.Name + ' = ' + mValue;
end;

class function TAtlasEvalTreeSync.LookOf(ANode: TAtlasEvalNode): TAtlasEvalLook;
begin
  Result := TAtlasEvalLook.Normal;
  if ANode.Changed then
  begin
    Result := TAtlasEvalLook.Changed;
  end
  else if ANode.State <> TAtlasEvalState.Value then
  begin
    Result := TAtlasEvalLook.Gray;
  end;
end;

class function TAtlasEvalTreeSync.ShowsExpander(ANode: TAtlasEvalNode): Boolean;
begin
  Result := ANode.CanExpand or ((ANode.State = TAtlasEvalState.Pending) and (ANode.Value <> '') and
    not TAtlasEvalText.IsSimple(ANode.Value));
end;

end.
