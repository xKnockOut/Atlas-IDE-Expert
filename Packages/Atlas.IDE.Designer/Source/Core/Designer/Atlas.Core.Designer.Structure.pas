unit Atlas.Core.Designer.Structure;

// Inhalt des Fensters „Atlas-Struktur“ (#609), ohne VCL und Windows.
// - Zeilen als flache Liste mit Ebene (Level), die Oberfläche baut daraus
//   den Baum:
//     Steuerelemente (n)               Ebene 0
//       Formular, darunter nach Parent  Ebene 1 ff.
//     Nichtvisuelle Komponenten (n)    Ebene 0
//       Gruppe „TSQLQuery (2)“          Ebene 1
//         SQLQuery1                     Ebene 2
//           → SQLConnection (leer)      Ebene 3
//           ← DataSet dsKunden          Ebene 3
// - Gruppen nach Klasse (sortiert nach Klassennamen) oder nach Art: Daten
//   (TDataSet-Nachfahren, TDataSource, Verbindungen), Aktionen und Menüs,
//   Dialoge, Bilder, Sonstiges. Gesucht wird die Klasse, dann ihre Vorfahren;
//   bekannte Klassen (TFDQuery, TOpenDialog …) stehen auch ohne Vorfahren in
//   der Tabelle. In der Gruppe nach Namen.
// - Verknüpfungen einer nichtvisuellen Komponente: → ihre Verweise auf andere
//   Komponenten (Eigenschaft und Ziel), ← Verweise anderer Komponenten auf
//   sie. Ein leerer Verweis erscheint nur bei Pflichtverweisen (Connection,
//   SQLConnection, DataSet, DataSource) und trägt den Befund Empty. Popup-
//   Menüs, Bildlisten und DataSources, auf die nichts verweist, tragen den
//   Befund Unused.
// - Filter: Name oder Klasse enthält den Text, ohne Groß-/Kleinschreibung;
//   gefilterte Steuerelemente stehen ohne Baum direkt unter dem Bereich.
// - Freie Stelle für ein neues Symbol: am unteren Rand des Formulars von
//   links, dann Reihe für Reihe darüber; belegt ist eine Stelle, deren Symbol
//   ein vorhandenes überdeckt. Alles in Pixeln der DFM (Left/Top).

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  /// <summary>Art einer nichtvisuellen Komponente (Gruppen „Nach Art“).</summary>
  TAtlasStructureKind = (Data, Actions, Dialogs, Images, Other);
  TAtlasStructureNodeKind = (Controls, NonVisual, Control, Group, Component, Link);
  TAtlasStructureFinding = (None, Empty, Unused);
{$SCOPEDENUMS OFF}

  /// <summary>Verweis einer Komponente auf eine andere über eine Eigenschaft; Target leer = nicht gesetzt.
  /// </summary>
  TAtlasStructureRef = record
    Prop: string;
    Target: string;
    class function Create(const AProp, ATarget: string): TAtlasStructureRef; static;
  end;

  TAtlasStructureItem = record
    Name: string;
    /// <summary>Klasse und Vorfahren, die Klasse zuerst.</summary>
    ClassChain: TArray<string>;
    /// <summary>Steuerelement (im Baum nach Parent) oder nichtvisuelle Komponente.</summary>
    IsControl: Boolean;
    /// <summary>Name des Elternsteuerelements; beim Formular leer.</summary>
    Parent: string;
    /// <summary>Lage des Symbols einer nichtvisuellen Komponente (Left/Top der DFM).</summary>
    Position: TPoint;
    Refs: TArray<TAtlasStructureRef>;
    function ClassName: string;
  end;

  TAtlasStructureNode = record
    Kind: TAtlasStructureNodeKind;
    Level: Integer;
    /// <summary>Komponente der Zeile; bei einer Verknüpfung ihr Ziel bzw. ihre Quelle (leer bei Empty).</summary>
    Name: string;
    /// <summary>Klasse der Komponente, bei einer Gruppe nach Klasse die Klasse der Gruppe.</summary>
    ClassName: string;
    /// <summary>Art bei einer Gruppe nach Art.</summary>
    StructureKind: TAtlasStructureKind;
    /// <summary>Zeilen eines Bereichs bzw. einer Gruppe.</summary>
    Count: Integer;
    /// <summary>Eigenschaft einer Verknüpfung.</summary>
    Prop: string;
    /// <summary>Verknüpfung „← wird verwendet von“ statt „→ verweist auf“.</summary>
    Incoming: Boolean;
    Finding: TAtlasStructureFinding;
    /// <summary>Gleichbleibender Schlüssel für den Zustand auf- bzw. zugeklappt.</summary>
    Key: string;
  end;

  TAtlasStructure = class
  public const
    /// <summary>Kantenlänge eines Symbols im Designer in Pixeln der DFM.</summary>
    cIconSize = 28;
    cGap = 8;
  public
    /// <summary>Art nach Klasse und Vorfahren.</summary>
    class function KindOf(const AClassChain: TArray<string>): TAtlasStructureKind; static;
    /// <summary>Kurzer Schlüssel der Art (data, actions, dialogs, images, other).</summary>
    class function KindKey(AKind: TAtlasStructureKind): string; static;
    /// <summary>Zeilen des Fensters. ARoot: Name des Formulars in AItems; AByKind: Gruppen nach Art statt Klasse.
    /// </summary>
    class function Nodes(const AItems: TArray<TAtlasStructureItem>; const ARoot: string; AByKind: Boolean;
      const AFilter: string): TArray<TAtlasStructureNode>; static;
    /// <summary>Verknüpfungen der Komponente AName (Ebene ALevel).</summary>
    class function Links(const AItems: TArray<TAtlasStructureItem>; const AName: string;
      ALevel: Integer): TArray<TAtlasStructureNode>; static;
    /// <summary>Befund der Komponente AName: Unused, wenn ein Popup-Menü, eine Bildliste oder DataSource von
    /// niemandem verwendet wird.</summary>
    class function FindingOf(const AItems: TArray<TAtlasStructureItem>; const AName: string): TAtlasStructureFinding;
      static;
    /// <summary>Freie Stelle für ein neues Symbol im Client AClient neben den Symbolen AOccupied.</summary>
    class function FreePosition(const AOccupied: TArray<TPoint>; const AClient: TSize): TPoint; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults,
  System.Generics.Collections;

type
  TKindClass = record
    ClassName: string;
    Kind: TAtlasStructureKind;
  end;

const
  cMargin = 8;
  cMaxDepth = 64;
  /// <summary>Ebene der Verknüpfungen unter einer nichtvisuellen Komponente.</summary>
  cLinkLevel = 3;
  cKindKeys: array[TAtlasStructureKind] of string = ('data', 'actions', 'dialogs', 'images', 'other');
  cRequired: array[0..3] of string = ('Connection', 'SQLConnection', 'DataSet', 'DataSource');
  cUsedByOthers: array[0..2] of string = ('TPopupMenu', 'TCustomImageList', 'TDataSource');
  cKindClasses: array[0..33] of TKindClass = (
    // Vorfahren
    (ClassName: 'TDataSet'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TDataSource'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TCustomConnection'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TFDCustomManager'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TFDCustomTransaction'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TBasicAction'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TCustomActionList'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TCustomActionManager'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TMenu'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TMenuItem'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TCommonDialog'; Kind: TAtlasStructureKind.Dialogs),
    (ClassName: 'TCustomImageList'; Kind: TAtlasStructureKind.Images),
    (ClassName: 'TCustomImageCollection'; Kind: TAtlasStructureKind.Images),
    // Bekannte Klassen, falls die Vorfahren fehlen (Text der DFM)
    (ClassName: 'TFDQuery'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TFDTable'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TFDMemTable'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TFDStoredProc'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TFDConnection'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TFDTransaction'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TClientDataSet'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TADOQuery'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TADOConnection'; Kind: TAtlasStructureKind.Data),
    (ClassName: 'TActionList'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TActionManager'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TMainMenu'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TPopupMenu'; Kind: TAtlasStructureKind.Actions),
    (ClassName: 'TOpenDialog'; Kind: TAtlasStructureKind.Dialogs),
    (ClassName: 'TSaveDialog'; Kind: TAtlasStructureKind.Dialogs),
    (ClassName: 'TFontDialog'; Kind: TAtlasStructureKind.Dialogs),
    (ClassName: 'TColorDialog'; Kind: TAtlasStructureKind.Dialogs),
    (ClassName: 'TFileOpenDialog'; Kind: TAtlasStructureKind.Dialogs),
    (ClassName: 'TImageList'; Kind: TAtlasStructureKind.Images),
    (ClassName: 'TVirtualImageList'; Kind: TAtlasStructureKind.Images),
    (ClassName: 'TImageCollection'; Kind: TAtlasStructureKind.Images));

{ TAtlasStructureRef }

class function TAtlasStructureRef.Create(const AProp, ATarget: string): TAtlasStructureRef;
begin
  Result.Prop := AProp;
  Result.Target := ATarget;
end;

{ TAtlasStructureItem }

function TAtlasStructureItem.ClassName: string;
begin
  Result := '';
  if Length(ClassChain) > 0 then
  begin
    Result := ClassChain[0];
  end;
end;

{ Hilfen }

function InList(const AList: array of string; const AText: string): Boolean;
var
  mEntry: string;
begin
  for mEntry in AList do
  begin
    if SameText(mEntry, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Matches(const AItem: TAtlasStructureItem; const AFilter: string): Boolean;
begin
  Result := (AFilter = '') or AItem.Name.ToLower.Contains(AFilter) or AItem.ClassName.ToLower.Contains(AFilter);
end;

function ItemIndex(const AItems: TArray<TAtlasStructureItem>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function NewNode(AKind: TAtlasStructureNodeKind; ALevel: Integer; const AKey: string): TAtlasStructureNode;
begin
  Result := Default(TAtlasStructureNode);
  Result.Kind := AKind;
  Result.Level := ALevel;
  Result.Key := AKey;
end;

function ItemNode(AKind: TAtlasStructureNodeKind; ALevel: Integer;
  const AItem: TAtlasStructureItem): TAtlasStructureNode;
begin
  Result := NewNode(AKind, ALevel, 'item:' + AItem.Name.ToLower);
  Result.Name := AItem.Name;
  Result.ClassName := AItem.ClassName;
end;

/// <summary>Steuerelemente unter AParent, rekursiv; ohne Formular.</summary>
procedure AddChildren(const AItems: TArray<TAtlasStructureItem>; const AParent: string; ALevel: Integer;
  var ANodes: TArray<TAtlasStructureNode>; var ACount: Integer);
var
  mItem: TAtlasStructureItem;
begin
  if ALevel > cMaxDepth then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if mItem.IsControl and SameText(mItem.Parent, AParent) and not SameText(mItem.Name, AParent) then
    begin
      ANodes := ANodes + [ItemNode(TAtlasStructureNodeKind.Control, ALevel, mItem)];
      Inc(ACount);
      AddChildren(AItems, mItem.Name, ALevel + 1, ANodes, ACount);
    end;
  end;
end;

function ControlNodes(const AItems: TArray<TAtlasStructureItem>; const ARoot, AFilter: string;
  out ACount: Integer): TArray<TAtlasStructureNode>;
var
  mItem: TAtlasStructureItem;
  mRoot: Integer;
begin
  Result := nil;
  ACount := 0;
  if AFilter <> '' then
  begin
    // Gefiltert: Treffer ohne Baum.
    for mItem in AItems do
    begin
      if mItem.IsControl and not SameText(mItem.Name, ARoot) and Matches(mItem, AFilter) then
      begin
        Result := Result + [ItemNode(TAtlasStructureNodeKind.Control, 1, mItem)];
        Inc(ACount);
      end;
    end;
    Exit;
  end;
  mRoot := ItemIndex(AItems, ARoot);
  if mRoot >= 0 then
  begin
    Result := [ItemNode(TAtlasStructureNodeKind.Control, 1, AItems[mRoot])];
  end;
  AddChildren(AItems, ARoot, 2, Result, ACount);
end;

function GroupKeyOf(const AItem: TAtlasStructureItem; AByKind: Boolean): string;
begin
  if AByKind then
  begin
    Result := 'kind:' + TAtlasStructure.KindKey(TAtlasStructure.KindOf(AItem.ClassChain));
  end
  else
  begin
    Result := 'class:' + AItem.ClassName.ToLower;
  end;
end;

function SortedNonVisual(const AItems: TArray<TAtlasStructureItem>; AByKind: Boolean;
  const AFilter: string): TArray<TAtlasStructureItem>;
var
  mItem: TAtlasStructureItem;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if not mItem.IsControl and Matches(mItem, AFilter) then
    begin
      Result := Result + [mItem];
    end;
  end;
  TArray.Sort<TAtlasStructureItem>(Result, TComparer<TAtlasStructureItem>.Construct(
    function(const ALeft, ARight: TAtlasStructureItem): Integer
    begin
      if AByKind then
      begin
        Result := Ord(TAtlasStructure.KindOf(ALeft.ClassChain)) - Ord(TAtlasStructure.KindOf(ARight.ClassChain));
      end
      else
      begin
        Result := CompareText(ALeft.ClassName, ARight.ClassName);
      end;
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Name, ARight.Name);
      end;
    end));
end;

function GroupNode(const AItem: TAtlasStructureItem; AByKind: Boolean): TAtlasStructureNode;
begin
  Result := NewNode(TAtlasStructureNodeKind.Group, 1, GroupKeyOf(AItem, AByKind));
  Result.StructureKind := TAtlasStructure.KindOf(AItem.ClassChain);
  if not AByKind then
  begin
    Result.ClassName := AItem.ClassName;
  end;
end;

function NonVisualNodes(const AItems: TArray<TAtlasStructureItem>; AByKind: Boolean;
  const AFilter: string; out ACount: Integer): TArray<TAtlasStructureNode>;
var
  mItem: TAtlasStructureItem;
  mGroup: Integer;
  mNode: TAtlasStructureNode;
begin
  Result := nil;
  ACount := 0;
  mGroup := -1;
  for mItem in SortedNonVisual(AItems, AByKind, AFilter) do
  begin
    if (mGroup < 0) or (Result[mGroup].Key <> GroupKeyOf(mItem, AByKind)) then
    begin
      Result := Result + [GroupNode(mItem, AByKind)];
      mGroup := High(Result);
    end;
    Inc(Result[mGroup].Count);
    Inc(ACount);
    mNode := ItemNode(TAtlasStructureNodeKind.Component, 2, mItem);
    mNode.Finding := TAtlasStructure.FindingOf(AItems, mItem.Name);
    Result := Result + [mNode] + TAtlasStructure.Links(AItems, mItem.Name, cLinkLevel);
  end;
end;

function LinkNode(const AOwner: string; ALevel: Integer; const ARef: TAtlasStructureRef; AIncoming: Boolean;
  const ASource: string): TAtlasStructureNode;
const
  cDirections: array[Boolean] of string = ('>', '<');
begin
  Result := NewNode(TAtlasStructureNodeKind.Link, ALevel, 'link:' + AOwner.ToLower + ':' + cDirections[AIncoming] +
    ARef.Prop.ToLower + ':' + ASource.ToLower);
  Result.Name := ASource;
  Result.Prop := ARef.Prop;
  Result.Incoming := AIncoming;
  if ASource = '' then
  begin
    Result.Finding := TAtlasStructureFinding.Empty;
  end;
end;

function IsUsed(const AItems: TArray<TAtlasStructureItem>; const AName: string): Boolean;
var
  mItem: TAtlasStructureItem;
  mRef: TAtlasStructureRef;
begin
  for mItem in AItems do
  begin
    for mRef in mItem.Refs do
    begin
      if SameText(mRef.Target, AName) and not SameText(mItem.Name, AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

{ TAtlasStructure }

class function TAtlasStructure.KindKey(AKind: TAtlasStructureKind): string;
begin
  Result := cKindKeys[AKind];
end;

class function TAtlasStructure.KindOf(const AClassChain: TArray<string>): TAtlasStructureKind;
var
  mClass: string;
  mEntry: TKindClass;
begin
  // Die Klasse vor ihren Vorfahren: TActionManager steht vor TComponent.
  for mClass in AClassChain do
  begin
    for mEntry in cKindClasses do
    begin
      if SameText(mEntry.ClassName, mClass) then
      begin
        Exit(mEntry.Kind);
      end;
    end;
  end;
  Result := TAtlasStructureKind.Other;
end;

class function TAtlasStructure.Nodes(const AItems: TArray<TAtlasStructureItem>; const ARoot: string;
  AByKind: Boolean; const AFilter: string): TArray<TAtlasStructureNode>;
var
  mFilter: string;
  mControls, mNonVisual: TArray<TAtlasStructureNode>;
  mControlCount, mNonVisualCount: Integer;
  mSection: TAtlasStructureNode;
begin
  mFilter := AFilter.Trim.ToLower;
  mControls := ControlNodes(AItems, ARoot, mFilter, mControlCount);
  mNonVisual := NonVisualNodes(AItems, AByKind, mFilter, mNonVisualCount);
  mSection := NewNode(TAtlasStructureNodeKind.Controls, 0, 'section:controls');
  mSection.Count := mControlCount;
  Result := [mSection] + mControls;
  mSection := NewNode(TAtlasStructureNodeKind.NonVisual, 0, 'section:nonvisual');
  mSection.Count := mNonVisualCount;
  Result := Result + [mSection] + mNonVisual;
end;

class function TAtlasStructure.Links(const AItems: TArray<TAtlasStructureItem>; const AName: string;
  ALevel: Integer): TArray<TAtlasStructureNode>;
var
  mIndex, mTarget: Integer;
  mItem: TAtlasStructureItem;
  mRef: TAtlasStructureRef;
begin
  Result := nil;
  mIndex := ItemIndex(AItems, AName);
  if mIndex < 0 then
  begin
    Exit;
  end;
  for mRef in AItems[mIndex].Refs do
  begin
    if (mRef.Target <> '') or InList(cRequired, mRef.Prop) then
    begin
      Result := Result + [LinkNode(AName, ALevel, mRef, False, mRef.Target)];
    end;
  end;
  for mItem in AItems do
  begin
    for mRef in mItem.Refs do
    begin
      if SameText(mRef.Target, AName) and not SameText(mItem.Name, AName) then
      begin
        Result := Result + [LinkNode(AName, ALevel, mRef, True, mItem.Name)];
      end;
    end;
  end;
  for mIndex := 0 to High(Result) do
  begin
    mTarget := ItemIndex(AItems, Result[mIndex].Name);
    if mTarget >= 0 then
    begin
      Result[mIndex].ClassName := AItems[mTarget].ClassName;
    end;
  end;
end;

class function TAtlasStructure.FindingOf(const AItems: TArray<TAtlasStructureItem>;
  const AName: string): TAtlasStructureFinding;
var
  mIndex: Integer;
  mClass: string;
begin
  Result := TAtlasStructureFinding.None;
  mIndex := ItemIndex(AItems, AName);
  if (mIndex < 0) or IsUsed(AItems, AName) then
  begin
    Exit;
  end;
  for mClass in AItems[mIndex].ClassChain do
  begin
    if InList(cUsedByOthers, mClass) then
    begin
      Exit(TAtlasStructureFinding.Unused);
    end;
  end;
end;

function Occupied(const AOccupied: TArray<TPoint>; const APoint: TPoint): Boolean;
var
  mPoint: TPoint;
begin
  for mPoint in AOccupied do
  begin
    if (Abs(mPoint.X - APoint.X) < TAtlasStructure.cIconSize) and
      (Abs(mPoint.Y - APoint.Y) < TAtlasStructure.cIconSize) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasStructure.FreePosition(const AOccupied: TArray<TPoint>; const AClient: TSize): TPoint;
var
  mX, mY, mStep: Integer;
begin
  mStep := cIconSize + cGap;
  mY := AClient.cy - cIconSize - cMargin;
  while mY >= cMargin do
  begin
    mX := cMargin;
    while mX + cIconSize <= AClient.cx - cMargin do
    begin
      Result := TPoint.Create(mX, mY);
      if not Occupied(AOccupied, Result) then
      begin
        Exit;
      end;
      Inc(mX, mStep);
    end;
    Dec(mY, mStep);
  end;
  // Kein Platz (sehr kleines oder volles Formular): links oben.
  Result := TPoint.Create(cMargin, cMargin);
end;

end.
