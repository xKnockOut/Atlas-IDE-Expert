unit Atlas.Core.Results.CallDiagram;

// Aufrufdiagramm der Aufrufhierarchie (#1122), ohne VCL:
// - TAtlasCallDiagram hält die geladenen Ebenen: je Knoten ein Eintrag der
//   Hierarchie (Aufrufer bzw. Aufgerufener), seine Kinder werden erst beim
//   Aufklappen über die vorhandenen Anfragen der Aufrufhierarchie geladen
//   (SetChildren). Ein Kind, das schon auf dem Weg von der Wurzel liegt, ist
//   eine Rekursion: Es wird kein Kasten, sondern ein Pfeil zurück zum
//   Vorfahren und lässt sich nicht weiter aufklappen.
// - Mehr als MaxChildren sichtbare Kinder werden zu „+ N …“ zusammengefasst;
//   ShowAll zeigt alle.
// - „Nur Projekt-Units“ (ProjectOnly) blendet Einträge aus, deren Datei
//   IsProjectFile nicht kennt (RTL, VCL, Fremdbibliotheken).
// - Layout: Start links, je Ebene eine Spalte; Blätter untereinander, ein
//   Elternknoten mittig vor seinen Kindern. Kanten über ein Interface oder
//   eine virtuelle Methode (atlasDispatch, #1119/#1122) sind gestrichelt und
//   tragen die Zahl der Umsetzungen.
// - TAtlasCallView rechnet zwischen Lage und Bildpunkten um (Einpassen, Zoomen
//   um einen Punkt, Verschieben, Treffer), wie TAtlasArchitectureView.
// - Html schreibt die geladenen Ebenen als eigenständige HTML-Datei ohne
//   externe Verweise (Vorlage Aufrufdiagramm.html, wie die Architekturkarte
//   aus #1118); sie zeigt dasselbe Layout, klappt die geladenen Ebenen auf und
//   zu und filtert „nur Projekt-Units“.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasCallBoxKind = (Call, More);
{$SCOPEDENUMS OFF}

  TAtlasCallNode = record
    Item: TAtlasHierarchyItem;
    /// <summary>-1 bei einer Wurzel.</summary>
    Parent: Integer;
    Level: Integer;
    Children: TArray<Integer>;
    /// <summary>Kinder geladen (auch wenn es keine gibt).</summary>
    Loaded: Boolean;
    Expanded: Boolean;
    /// <summary>Alle Kinder statt „+ N …“.</summary>
    ShowAll: Boolean;
    /// <summary>Rekursion: Knoten auf dem Weg von der Wurzel, zu dem der Pfeil zurückführt; sonst -1.</summary>
    BackTo: Integer;
    /// <summary>Datei außerhalb der Projekte (RTL, VCL, Fremdbibliotheken).</summary>
    Library_: Boolean;
  end;

  TAtlasCallBox = record
    Kind: TAtlasCallBoxKind;
    /// <summary>Knoten; bei „+ N …“ der Elternknoten.</summary>
    Node: Integer;
    Column: Integer;
    Row: Double;
    /// <summary>Bei „+ N …“: N.</summary>
    Hidden: Integer;
  end;

  TAtlasCallEdge = record
    /// <summary>Kästen in TAtlasCallLayout.Boxes.</summary>
    Source: Integer;
    Target: Integer;
    /// <summary>Über Interface oder virtuelle Methode.</summary>
    Dashed: Boolean;
    Implementations: Integer;
    /// <summary>Rekursion: Pfeil zurück zu einem Vorfahren.</summary>
    Back: Boolean;
  end;

  TAtlasCallLayout = record
    Boxes: TArray<TAtlasCallBox>;
    Edges: TArray<TAtlasCallEdge>;
    Columns: Integer;
    /// <summary>Zeilen insgesamt (die letzte Zeile ist Rows - 1).</summary>
    Rows: Double;
    /// <summary>Kasten eines Knotens; -1, wenn er nicht sichtbar ist.</summary>
    function BoxOf(ANode: Integer): Integer;
  end;

  TAtlasCallDiagram = class
  public const
    MaxChildren = 8;
  private
    FDirection: TAtlasHierarchyDirection;
    FNodes: TArray<TAtlasCallNode>;
    FProjectOnly: Boolean;
    FIsProjectFile: TFunc<string, Boolean>;
    function NewNode(const AItem: TAtlasHierarchyItem; AParent: Integer): Integer;
    function IsLibrary(const AItem: TAtlasHierarchyItem): Boolean;
    function GetNode(AIndex: Integer): TAtlasCallNode;
    function GetCount: Integer;
    procedure SetProjectOnly(AValue: Boolean);
  public
    /// <summary>AIsProjectFile entscheidet über „nur Projekt-Units“; nil: alle Dateien gehören zum Projekt.</summary>
    constructor Create(const AIsProjectFile: TFunc<string, Boolean>);
    /// <summary>Neu beginnen: Wurzeln in Richtung ADirection, nichts geladen.</summary>
    procedure Reset(ADirection: TAtlasHierarchyDirection; const ARoots: TArray<TAtlasHierarchyItem>);
    /// <summary>Muss vor dem Aufklappen geladen werden (nicht geladen, keine Rekursion).</summary>
    function NeedsLoad(ANode: Integer): Boolean;
    /// <summary>Geladene Kinder eintragen und aufklappen; Rekursionen werden zu Pfeilen, doppelte Einträge
    /// (gleiche Stelle) zusammengelegt.</summary>
    procedure SetChildren(ANode: Integer; const AItems: TArray<TAtlasHierarchyItem>);
    /// <summary>Auf- bzw. zuklappen; False, wenn erst geladen werden muss oder nichts aufzuklappen ist.</summary>
    function Toggle(ANode: Integer): Boolean;
    /// <summary>Alle Kinder statt „+ N …“.</summary>
    procedure ShowAll(ANode: Integer);
    /// <summary>Sichtbare Kinder ohne Rekursionen, gekürzt auf MaxChildren; AMore = Rest.</summary>
    function VisibleChildren(ANode: Integer; out AMore: Integer): TArray<Integer>;
    /// <summary>Rekursionen unter ANode (sichtbar, ohne Filter auf Bibliotheken der Vorfahren).</summary>
    function BackLinks(ANode: Integer): TArray<Integer>;
    function Layout: TAtlasCallLayout;
    /// <summary>Daten der HTML-Datei (Format 1): alle geladenen Knoten mit Zustand.</summary>
    function Json(const ATitle: string): string;
    /// <summary>Eigenständige HTML-Datei mit Titel ATitle und den geladenen Ebenen.</summary>
    function Html(const ATitle: string): string;
    /// <summary>Gleiche Stelle: Datei, Zeile, Spalte und Name.</summary>
    class function KeyOf(const AItem: TAtlasHierarchyItem): string; static;
    /// <summary>Kastentitel: "TKunde.Laden" bzw. "Laden", aus Name und Detail ("TKunde · Kunden").</summary>
    class function Title(const AItem: TAtlasHierarchyItem): string; static;
    /// <summary>Fundstelle: "Kunden.pas:12"; '' ohne Datei.</summary>
    class function Location(const AItem: TAtlasHierarchyItem): string; static;
    property Direction: TAtlasHierarchyDirection read FDirection;
    property Nodes[AIndex: Integer]: TAtlasCallNode read GetNode; default;
    property Count: Integer read GetCount;
    property ProjectOnly: Boolean read FProjectOnly write SetProjectOnly;
    /// <summary>Wirkt auf Knoten, die danach entstehen (Reset, SetChildren).</summary>
    property IsProjectFile: TFunc<string, Boolean> read FIsProjectFile write FIsProjectFile;
  end;

  TAtlasCallView = record
  public const
    /// <summary>Lage in Einheiten bei Vergrößerung 1 (Bildpunkte bei 96 dpi).</summary>
    ColumnWidth = 250;
    BoxWidth = 200;
    RowHeight = 56;
    BoxHeight = 42;
    Margin = 16;
    MinScale = 0.2;
    MaxScale = 4.0;
  public
    Scale: Double;
    OffsetX: Double;
    OffsetY: Double;
    /// <summary>Lage eines Kastens: linke obere Ecke.</summary>
    class function BoxX(const ABox: TAtlasCallBox): Double; static;
    class function BoxY(const ABox: TAtlasCallBox): Double; static;
    /// <summary>Das Layout in AWidth × AHeight einpassen, höchstens Vergrößerung 1; zu große Diagramme oben links
    /// beginnen, wenn sie auch bei MinScale nicht passen.</summary>
    procedure Fit(const ALayout: TAtlasCallLayout; AWidth, AHeight: Integer);
    function ScreenX(AX: Double): Double;
    function ScreenY(AY: Double): Double;
    procedure ZoomAt(AFactor: Double; AX, AY: Double);
    procedure Pan(ADX, ADY: Double);
    /// <summary>Kasten unter dem Bildpunkt; -1 ohne.</summary>
    function BoxAt(const ALayout: TAtlasCallLayout; AX, AY: Double): Integer;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Results.CallDiagramTemplate,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Seite (#1458), eingesetzt in die Platzhalter {{T_…}} der Vorlage.</summary>
  TCallDiagramText = (Caption, ProjectOnly, Fit, ExpandAll, Legend, Hint, Callers, Callees, Loaded, OneImplementation,
    Implementations);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TCallDiagramText] of string = (
    ('Aufrufdiagramm',
     'nur Projekt-Units',
     'Einpassen',
     'Alle geladenen Ebenen aufklappen',
     'Gestrichelt: Aufruf über Interface oder virtuelle Methode (Zahl der Umsetzungen); Bogen zurück: Rekursion.',
     'Ziehen verschiebt, Mausrad zoomt · Klick klappt auf und zu · Doppelklick zeigt die Fundstelle',
     'Aufrufer',
     'Aufgerufene',
     'geladene Einträge',
     '1 Umsetzung',
     'Umsetzungen'),
    ('Call diagram',
     'project units only',
     'Fit',
     'Expand all loaded levels',
     'Dashed: call via interface or virtual method (number of implementations); arc back: recursion.',
     'Drag moves, mouse wheel zooms · click expands and collapses · double-click shows the location',
     'Callers',
     'Callees',
     'loaded entries',
     '1 implementation',
     'implementations'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TCallDiagramText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasCallLayout }

function TAtlasCallLayout.BoxOf(ANode: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Boxes) do
  begin
    if (Boxes[mIndex].Kind = TAtlasCallBoxKind.Call) and (Boxes[mIndex].Node = ANode) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TAtlasCallDiagram }

constructor TAtlasCallDiagram.Create(const AIsProjectFile: TFunc<string, Boolean>);
begin
  inherited Create;
  FIsProjectFile := AIsProjectFile;
  FProjectOnly := True;
end;

class function TAtlasCallDiagram.KeyOf(const AItem: TAtlasHierarchyItem): string;
begin
  Result := UpperCase(AItem.FileName) + '|' + IntToStr(AItem.Line) + '|' + IntToStr(AItem.Character) + '|' +
    UpperCase(AItem.Name);
end;

class function TAtlasCallDiagram.Title(const AItem: TAtlasHierarchyItem): string;
var
  mContainer: string;
  mSeparator: Integer;
begin
  // Detail des Servers: "TKunde · Kunden", "TKunde" oder nur die Unit.
  mContainer := AItem.Detail;
  mSeparator := Pos(' · ', mContainer);
  if mSeparator > 0 then
  begin
    mContainer := Copy(mContainer, 1, mSeparator - 1);
  end
  else if SameText(mContainer, ChangeFileExt(ExtractFileName(AItem.FileName), '')) then
  begin
    mContainer := '';
  end;
  if mContainer <> '' then
  begin
    Result := mContainer + '.' + AItem.Name;
  end
  else
  begin
    Result := AItem.Name;
  end;
end;

class function TAtlasCallDiagram.Location(const AItem: TAtlasHierarchyItem): string;
begin
  Result := '';
  if AItem.FileName <> '' then
  begin
    Result := ExtractFileName(AItem.FileName) + ':' + IntToStr(AItem.Line + 1);
  end;
end;

function TAtlasCallDiagram.IsLibrary(const AItem: TAtlasHierarchyItem): Boolean;
begin
  if AItem.FileName = '' then
  begin
    Exit(True);
  end;
  Result := Assigned(FIsProjectFile) and not FIsProjectFile(AItem.FileName);
end;

function TAtlasCallDiagram.NewNode(const AItem: TAtlasHierarchyItem; AParent: Integer): Integer;
var
  mNode: TAtlasCallNode;
begin
  mNode := Default(TAtlasCallNode);
  mNode.Item := AItem;
  mNode.Parent := AParent;
  mNode.BackTo := -1;
  if AParent >= 0 then
  begin
    mNode.Level := FNodes[AParent].Level + 1;
  end;
  mNode.Library_ := IsLibrary(AItem);
  Result := Length(FNodes);
  FNodes := FNodes + [mNode];
end;

function TAtlasCallDiagram.GetNode(AIndex: Integer): TAtlasCallNode;
begin
  Result := FNodes[AIndex];
end;

function TAtlasCallDiagram.GetCount: Integer;
begin
  Result := Length(FNodes);
end;

procedure TAtlasCallDiagram.SetProjectOnly(AValue: Boolean);
begin
  FProjectOnly := AValue;
end;

procedure TAtlasCallDiagram.Reset(ADirection: TAtlasHierarchyDirection; const ARoots: TArray<TAtlasHierarchyItem>);
var
  mItem: TAtlasHierarchyItem;
begin
  FDirection := ADirection;
  FNodes := nil;
  for mItem in ARoots do
  begin
    NewNode(mItem, -1);
  end;
end;

function TAtlasCallDiagram.NeedsLoad(ANode: Integer): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(FNodes)) and not FNodes[ANode].Loaded and (FNodes[ANode].BackTo < 0);
end;

procedure TAtlasCallDiagram.SetChildren(ANode: Integer; const AItems: TArray<TAtlasHierarchyItem>);
var
  mItem: TAtlasHierarchyItem;
  mSeen: TDictionary<string, Boolean>;
  mKey: string;
  mAncestor, mChild: Integer;
begin
  if (ANode < 0) or (ANode > High(FNodes)) or (FNodes[ANode].BackTo >= 0) then
  begin
    Exit;
  end;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    FNodes[ANode].Children := nil;
    for mItem in AItems do
    begin
      mKey := KeyOf(mItem);
      // Derselbe Aufrufer bzw. Aufgerufene kann mehrfach kommen (sicher und erschlossen, #1119): ein Kasten.
      if mSeen.ContainsKey(mKey) then
      begin
        Continue;
      end;
      mSeen.Add(mKey, True);
      mChild := NewNode(mItem, ANode);
      mAncestor := ANode;
      while mAncestor >= 0 do
      begin
        if KeyOf(FNodes[mAncestor].Item) = mKey then
        begin
          FNodes[mChild].BackTo := mAncestor;
          FNodes[mChild].Loaded := True;
          Break;
        end;
        mAncestor := FNodes[mAncestor].Parent;
      end;
      FNodes[ANode].Children := FNodes[ANode].Children + [mChild];
    end;
  finally
    mSeen.Free;
  end;
  FNodes[ANode].Loaded := True;
  FNodes[ANode].Expanded := True;
end;

function TAtlasCallDiagram.Toggle(ANode: Integer): Boolean;
begin
  Result := False;
  if (ANode < 0) or (ANode > High(FNodes)) or not FNodes[ANode].Loaded or (FNodes[ANode].BackTo >= 0) then
  begin
    Exit;
  end;
  if not FNodes[ANode].Expanded and (Length(FNodes[ANode].Children) = 0) then
  begin
    Exit;
  end;
  FNodes[ANode].Expanded := not FNodes[ANode].Expanded;
  Result := True;
end;

procedure TAtlasCallDiagram.ShowAll(ANode: Integer);
begin
  if (ANode >= 0) and (ANode <= High(FNodes)) then
  begin
    FNodes[ANode].ShowAll := True;
  end;
end;

function TAtlasCallDiagram.VisibleChildren(ANode: Integer; out AMore: Integer): TArray<Integer>;
var
  mChild: Integer;
  mAll: TArray<Integer>;
begin
  Result := nil;
  AMore := 0;
  if (ANode < 0) or (ANode > High(FNodes)) or not FNodes[ANode].Expanded then
  begin
    Exit;
  end;
  mAll := nil;
  for mChild in FNodes[ANode].Children do
  begin
    if FNodes[mChild].BackTo >= 0 then
    begin
      Continue;
    end;
    if FProjectOnly and FNodes[mChild].Library_ then
    begin
      Continue;
    end;
    mAll := mAll + [mChild];
  end;
  if FNodes[ANode].ShowAll or (Length(mAll) <= MaxChildren) then
  begin
    Exit(mAll);
  end;
  Result := Copy(mAll, 0, MaxChildren);
  AMore := Length(mAll) - MaxChildren;
end;

function TAtlasCallDiagram.BackLinks(ANode: Integer): TArray<Integer>;
var
  mChild: Integer;
begin
  Result := nil;
  if (ANode < 0) or (ANode > High(FNodes)) or not FNodes[ANode].Expanded then
  begin
    Exit;
  end;
  for mChild in FNodes[ANode].Children do
  begin
    if FNodes[mChild].BackTo >= 0 then
    begin
      Result := Result + [mChild];
    end;
  end;
end;

function TAtlasCallDiagram.Layout: TAtlasCallLayout;
var
  mBoxes: TList<TAtlasCallBox>;
  mEdges: TList<TAtlasCallEdge>;
  mNextRow: Double;
  mBoxOfNode: TDictionary<Integer, Integer>;
  mRoot, mLink, mColumns: Integer;
  mPending: TList<Integer>;
  mEdge: TAtlasCallEdge;
  mBox: TAtlasCallBox;

  function AddBox(AKind: TAtlasCallBoxKind; ANode, AColumn: Integer; ARow: Double; AHidden: Integer): Integer;
  var
    mEntry: TAtlasCallBox;
  begin
    mEntry.Kind := AKind;
    mEntry.Node := ANode;
    mEntry.Column := AColumn;
    mEntry.Row := ARow;
    mEntry.Hidden := AHidden;
    Result := mBoxes.Add(mEntry);
    if AKind = TAtlasCallBoxKind.Call then
    begin
      mBoxOfNode.AddOrSetValue(ANode, Result);
    end;
  end;

  procedure AddEdge(ASource, ATarget: Integer; const ANode: TAtlasCallNode; ABack: Boolean);
  var
    mEntry: TAtlasCallEdge;
  begin
    mEntry.Source := ASource;
    mEntry.Target := ATarget;
    mEntry.Dashed := (ANode.Item.Dispatch <> '') or SameText(ANode.Item.Confidence.Reason, 'interface') or
      SameText(ANode.Item.Confidence.Reason, 'virtual');
    mEntry.Implementations := ANode.Item.Implementations;
    mEntry.Back := ABack;
    mEdges.Add(mEntry);
  end;

  // Platziert ANode und seine sichtbaren Nachfahren; liefert den Kasten von ANode.
  function Place(ANode: Integer): Integer;
  var
    mChildren: TArray<Integer>;
    mChild, mMore, mOwn, mFirst, mLast, mChildBox: Integer;
    mRow: Double;
  begin
    mChildren := VisibleChildren(ANode, mMore);
    if (Length(mChildren) = 0) and (mMore = 0) then
    begin
      Result := AddBox(TAtlasCallBoxKind.Call, ANode, FNodes[ANode].Level, mNextRow, 0);
      mNextRow := mNextRow + 1;
      Exit;
    end;
    // Zuerst die Kinder, dann der Elternkasten mittig davor.
    mOwn := AddBox(TAtlasCallBoxKind.Call, ANode, FNodes[ANode].Level, 0, 0);
    mFirst := -1;
    mLast := -1;
    for mChild in mChildren do
    begin
      mChildBox := Place(mChild);
      if mFirst < 0 then
      begin
        mFirst := mChildBox;
      end;
      mLast := mChildBox;
      AddEdge(mOwn, mChildBox, FNodes[mChild], False);
    end;
    if mMore > 0 then
    begin
      mChildBox := AddBox(TAtlasCallBoxKind.More, ANode, FNodes[ANode].Level + 1, mNextRow, mMore);
      mNextRow := mNextRow + 1;
      if mFirst < 0 then
      begin
        mFirst := mChildBox;
      end;
      mLast := mChildBox;
      mEdge := Default(TAtlasCallEdge);
      mEdge.Source := mOwn;
      mEdge.Target := mChildBox;
      mEdges.Add(mEdge);
    end;
    mRow := (mBoxes[mFirst].Row + mBoxes[mLast].Row) / 2;
    mBox := mBoxes[mOwn];
    mBox.Row := mRow;
    mBoxes[mOwn] := mBox;
    Result := mOwn;
  end;

  procedure CollectBackLinks(ANode: Integer);
  var
    mChild, mMore: Integer;
  begin
    mPending.Add(ANode);
    for mChild in VisibleChildren(ANode, mMore) do
    begin
      CollectBackLinks(mChild);
    end;
  end;

var
  mNode: Integer;
begin
  Result := Default(TAtlasCallLayout);
  mBoxes := TList<TAtlasCallBox>.Create;
  mEdges := TList<TAtlasCallEdge>.Create;
  mBoxOfNode := TDictionary<Integer, Integer>.Create;
  mPending := TList<Integer>.Create;
  try
    mNextRow := 0;
    for mRoot := 0 to High(FNodes) do
    begin
      if FNodes[mRoot].Parent < 0 then
      begin
        Place(mRoot);
        CollectBackLinks(mRoot);
      end;
    end;
    // Rekursionen: Pfeil vom Knoten zurück zum Vorfahren, wenn beide zu sehen sind.
    for mNode in mPending do
    begin
      for mLink in BackLinks(mNode) do
      begin
        if mBoxOfNode.ContainsKey(mNode) and mBoxOfNode.ContainsKey(FNodes[mLink].BackTo) then
        begin
          AddEdge(mBoxOfNode[mNode], mBoxOfNode[FNodes[mLink].BackTo], FNodes[mLink], True);
        end;
      end;
    end;
    mColumns := 0;
    for mBox in mBoxes do
    begin
      mColumns := Max(mColumns, mBox.Column + 1);
    end;
    Result.Boxes := mBoxes.ToArray;
    Result.Edges := mEdges.ToArray;
    Result.Columns := mColumns;
    Result.Rows := mNextRow;
  finally
    mPending.Free;
    mBoxOfNode.Free;
    mEdges.Free;
    mBoxes.Free;
  end;
end;

function TAtlasCallDiagram.Json(const ATitle: string): string;
var
  mRoot, mEntry: TJSONObject;
  mItems: TJSONArray;
  mIndex: Integer;
  mNode: TAtlasCallNode;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(1));
    mRoot.AddPair('title', ATitle);
    if FDirection = TAtlasHierarchyDirection.Incoming then
    begin
      mRoot.AddPair('direction', 'incoming');
    end
    else
    begin
      mRoot.AddPair('direction', 'outgoing');
    end;
    mRoot.AddPair('projectOnly', TJSONBool.Create(FProjectOnly));
    mRoot.AddPair('maxChildren', TJSONNumber.Create(MaxChildren));
    mItems := TJSONArray.Create;
    mRoot.AddPair('nodes', mItems);
    for mIndex := 0 to High(FNodes) do
    begin
      mNode := FNodes[mIndex];
      mEntry := TJSONObject.Create;
      mItems.AddElement(mEntry);
      mEntry.AddPair('id', TJSONNumber.Create(mIndex));
      mEntry.AddPair('parent', TJSONNumber.Create(mNode.Parent));
      mEntry.AddPair('level', TJSONNumber.Create(mNode.Level));
      mEntry.AddPair('name', Title(mNode.Item));
      mEntry.AddPair('location', Location(mNode.Item));
      mEntry.AddPair('file', mNode.Item.FileName);
      mEntry.AddPair('line', TJSONNumber.Create(mNode.Item.Line + 1));
      mEntry.AddPair('library', TJSONBool.Create(mNode.Library_));
      mEntry.AddPair('dispatch', mNode.Item.Dispatch);
      mEntry.AddPair('implementations', TJSONNumber.Create(mNode.Item.Implementations));
      mEntry.AddPair('inferred', TJSONBool.Create(mNode.Item.Confidence.Inferred));
      mEntry.AddPair('inferredReason', mNode.Item.Confidence.Reason);
      mEntry.AddPair('reason', mNode.Item.Confidence.Explanation);
      mEntry.AddPair('backTo', TJSONNumber.Create(mNode.BackTo));
      mEntry.AddPair('expanded', TJSONBool.Create(mNode.Expanded));
      mEntry.AddPair('showAll', TJSONBool.Create(mNode.ShowAll));
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function HtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

/// <summary>Setzt Sprache und Texte der Seite (#1458) in die Platzhalter {{LANG}} und {{T_…}} ein.</summary>
function Localized(const AHtml: string): string;
const
  cKeys: array[TCallDiagramText] of string = ('{{T_CAPTION}}', '{{T_PROJECT}}', '{{T_FIT}}', '{{T_EXPAND}}',
    '{{T_LEGEND}}', '{{T_HINT}}', '{{T_CALLERS}}', '{{T_CALLEES}}', '{{T_LOADED}}', '{{T_IMPL1}}', '{{T_IMPLS}}');
  cLang: array[TAtlasLanguage] of string = ('de', 'en');
var
  mText: TCallDiagramText;
begin
  Result := StringReplace(AHtml, '{{LANG}}', cLang[TAtlasTextLanguage.Current], [rfReplaceAll]);
  for mText := Low(TCallDiagramText) to High(TCallDiagramText) do
  begin
    Result := StringReplace(Result, cKeys[mText], HtmlEscape(UiText(mText)), [rfReplaceAll]);
  end;
end;

function TAtlasCallDiagram.Html(const ATitle: string): string;
begin
  Result := StringReplace(Localized(CallDiagramHtml), '{{TITLE}}', HtmlEscape(ATitle), [rfReplaceAll]);
  // Die Daten stehen in einem script-Element: "</" darf es nicht beenden.
  Result := StringReplace(Result, '{{DATA}}', StringReplace(Json(ATitle), '</', '<\/', [rfReplaceAll]), []);
end;

{ TAtlasCallView }

class function TAtlasCallView.BoxX(const ABox: TAtlasCallBox): Double;
begin
  Result := ABox.Column * ColumnWidth;
end;

class function TAtlasCallView.BoxY(const ABox: TAtlasCallBox): Double;
begin
  Result := ABox.Row * RowHeight;
end;

procedure TAtlasCallView.Fit(const ALayout: TAtlasCallLayout; AWidth, AHeight: Integer);
var
  mWidth, mHeight: Double;
begin
  mWidth := Max(1, ALayout.Columns) * ColumnWidth - (ColumnWidth - BoxWidth);
  mHeight := Max(1, ALayout.Rows) * RowHeight - (RowHeight - BoxHeight);
  Scale := 1;
  if (AWidth > 2 * Margin) and (AHeight > 2 * Margin) then
  begin
    Scale := Min(1, Min((AWidth - 2 * Margin) / mWidth, (AHeight - 2 * Margin) / mHeight));
  end;
  Scale := Max(MinScale, Scale);
  OffsetX := Margin;
  // Kleine Diagramme senkrecht mittig, große oben beginnen.
  OffsetY := Max(Margin, (AHeight - mHeight * Scale) / 2);
end;

function TAtlasCallView.ScreenX(AX: Double): Double;
begin
  Result := AX * Scale + OffsetX;
end;

function TAtlasCallView.ScreenY(AY: Double): Double;
begin
  Result := AY * Scale + OffsetY;
end;

procedure TAtlasCallView.ZoomAt(AFactor: Double; AX, AY: Double);
var
  mNewScale: Double;
begin
  if Scale <= 0 then
  begin
    Scale := 1;
  end;
  mNewScale := EnsureRange(Scale * AFactor, MinScale, MaxScale);
  OffsetX := AX - (AX - OffsetX) * mNewScale / Scale;
  OffsetY := AY - (AY - OffsetY) * mNewScale / Scale;
  Scale := mNewScale;
end;

procedure TAtlasCallView.Pan(ADX, ADY: Double);
begin
  OffsetX := OffsetX + ADX;
  OffsetY := OffsetY + ADY;
end;

function TAtlasCallView.BoxAt(const ALayout: TAtlasCallLayout; AX, AY: Double): Integer;
var
  mIndex: Integer;
  mLeft, mTop: Double;
begin
  for mIndex := High(ALayout.Boxes) downto 0 do
  begin
    mLeft := ScreenX(BoxX(ALayout.Boxes[mIndex]));
    mTop := ScreenY(BoxY(ALayout.Boxes[mIndex]));
    if (AX >= mLeft) and (AX <= mLeft + BoxWidth * Scale) and (AY >= mTop) and (AY <= mTop + BoxHeight * Scale) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Results.CallDiagram', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
