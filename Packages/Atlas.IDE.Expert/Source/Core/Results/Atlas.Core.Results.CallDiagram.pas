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
  Atlas.Core.Results.CallDiagramTemplate;

{ TAtlasCallLayout }

function TAtlasCallLayout.BoxOf(ANode: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Boxes) do
    if (Boxes[Index].Kind = TAtlasCallBoxKind.Call) and (Boxes[Index].Node = ANode) then
      Exit(Index);
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
  Container: string;
  Separator: Integer;
begin
  // Detail des Servers: "TKunde · Kunden", "TKunde" oder nur die Unit.
  Container := AItem.Detail;
  Separator := Pos(' · ', Container);
  if Separator > 0 then
    Container := Copy(Container, 1, Separator - 1)
  else if SameText(Container, ChangeFileExt(ExtractFileName(AItem.FileName), '')) then
    Container := '';
  if Container <> '' then
    Result := Container + '.' + AItem.Name
  else
    Result := AItem.Name;
end;

class function TAtlasCallDiagram.Location(const AItem: TAtlasHierarchyItem): string;
begin
  Result := '';
  if AItem.FileName <> '' then
    Result := ExtractFileName(AItem.FileName) + ':' + IntToStr(AItem.Line + 1);
end;

function TAtlasCallDiagram.IsLibrary(const AItem: TAtlasHierarchyItem): Boolean;
begin
  if AItem.FileName = '' then
    Exit(True);
  Result := Assigned(FIsProjectFile) and not FIsProjectFile(AItem.FileName);
end;

function TAtlasCallDiagram.NewNode(const AItem: TAtlasHierarchyItem; AParent: Integer): Integer;
var
  Node: TAtlasCallNode;
begin
  Node := Default(TAtlasCallNode);
  Node.Item := AItem;
  Node.Parent := AParent;
  Node.BackTo := -1;
  if AParent >= 0 then
    Node.Level := FNodes[AParent].Level + 1;
  Node.Library_ := IsLibrary(AItem);
  Result := Length(FNodes);
  FNodes := FNodes + [Node];
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
  Item: TAtlasHierarchyItem;
begin
  FDirection := ADirection;
  FNodes := nil;
  for Item in ARoots do
    NewNode(Item, -1);
end;

function TAtlasCallDiagram.NeedsLoad(ANode: Integer): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(FNodes)) and not FNodes[ANode].Loaded and (FNodes[ANode].BackTo < 0);
end;

procedure TAtlasCallDiagram.SetChildren(ANode: Integer; const AItems: TArray<TAtlasHierarchyItem>);
var
  Item: TAtlasHierarchyItem;
  Seen: TDictionary<string, Boolean>;
  Key: string;
  Ancestor, Child: Integer;
begin
  if (ANode < 0) or (ANode > High(FNodes)) or (FNodes[ANode].BackTo >= 0) then
    Exit;
  Seen := TDictionary<string, Boolean>.Create;
  try
    FNodes[ANode].Children := nil;
    for Item in AItems do
    begin
      Key := KeyOf(Item);
      // Derselbe Aufrufer bzw. Aufgerufene kann mehrfach kommen (sicher und erschlossen, #1119): ein Kasten.
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      Child := NewNode(Item, ANode);
      Ancestor := ANode;
      while Ancestor >= 0 do
      begin
        if KeyOf(FNodes[Ancestor].Item) = Key then
        begin
          FNodes[Child].BackTo := Ancestor;
          FNodes[Child].Loaded := True;
          Break;
        end;
        Ancestor := FNodes[Ancestor].Parent;
      end;
      FNodes[ANode].Children := FNodes[ANode].Children + [Child];
    end;
  finally
    Seen.Free;
  end;
  FNodes[ANode].Loaded := True;
  FNodes[ANode].Expanded := True;
end;

function TAtlasCallDiagram.Toggle(ANode: Integer): Boolean;
begin
  Result := False;
  if (ANode < 0) or (ANode > High(FNodes)) or not FNodes[ANode].Loaded or (FNodes[ANode].BackTo >= 0) then
    Exit;
  if not FNodes[ANode].Expanded and (Length(FNodes[ANode].Children) = 0) then
    Exit;
  FNodes[ANode].Expanded := not FNodes[ANode].Expanded;
  Result := True;
end;

procedure TAtlasCallDiagram.ShowAll(ANode: Integer);
begin
  if (ANode >= 0) and (ANode <= High(FNodes)) then
    FNodes[ANode].ShowAll := True;
end;

function TAtlasCallDiagram.VisibleChildren(ANode: Integer; out AMore: Integer): TArray<Integer>;
var
  Child: Integer;
  All: TArray<Integer>;
begin
  Result := nil;
  AMore := 0;
  if (ANode < 0) or (ANode > High(FNodes)) or not FNodes[ANode].Expanded then
    Exit;
  All := nil;
  for Child in FNodes[ANode].Children do
  begin
    if FNodes[Child].BackTo >= 0 then
      Continue;
    if FProjectOnly and FNodes[Child].Library_ then
      Continue;
    All := All + [Child];
  end;
  if FNodes[ANode].ShowAll or (Length(All) <= MaxChildren) then
    Exit(All);
  Result := Copy(All, 0, MaxChildren);
  AMore := Length(All) - MaxChildren;
end;

function TAtlasCallDiagram.BackLinks(ANode: Integer): TArray<Integer>;
var
  Child: Integer;
begin
  Result := nil;
  if (ANode < 0) or (ANode > High(FNodes)) or not FNodes[ANode].Expanded then
    Exit;
  for Child in FNodes[ANode].Children do
    if FNodes[Child].BackTo >= 0 then
      Result := Result + [Child];
end;

function TAtlasCallDiagram.Layout: TAtlasCallLayout;
var
  Boxes: TList<TAtlasCallBox>;
  Edges: TList<TAtlasCallEdge>;
  NextRow: Double;
  BoxOfNode: TDictionary<Integer, Integer>;
  Root, Link, Columns: Integer;
  Pending: TList<Integer>;
  Edge: TAtlasCallEdge;
  Box: TAtlasCallBox;

  function AddBox(AKind: TAtlasCallBoxKind; ANode, AColumn: Integer; ARow: Double; AHidden: Integer): Integer;
  var
    Entry: TAtlasCallBox;
  begin
    Entry.Kind := AKind;
    Entry.Node := ANode;
    Entry.Column := AColumn;
    Entry.Row := ARow;
    Entry.Hidden := AHidden;
    Result := Boxes.Add(Entry);
    if AKind = TAtlasCallBoxKind.Call then
      BoxOfNode.AddOrSetValue(ANode, Result);
  end;

  procedure AddEdge(ASource, ATarget: Integer; const ANode: TAtlasCallNode; ABack: Boolean);
  var
    Entry: TAtlasCallEdge;
  begin
    Entry.Source := ASource;
    Entry.Target := ATarget;
    Entry.Dashed := (ANode.Item.Dispatch <> '') or SameText(ANode.Item.Confidence.Reason, 'interface') or
      SameText(ANode.Item.Confidence.Reason, 'virtual');
    Entry.Implementations := ANode.Item.Implementations;
    Entry.Back := ABack;
    Edges.Add(Entry);
  end;

  // Platziert ANode und seine sichtbaren Nachfahren; liefert den Kasten von ANode.
  function Place(ANode: Integer): Integer;
  var
    Children: TArray<Integer>;
    Child, More, Own, First, Last, ChildBox: Integer;
    Row: Double;
  begin
    Children := VisibleChildren(ANode, More);
    if (Length(Children) = 0) and (More = 0) then
    begin
      Result := AddBox(TAtlasCallBoxKind.Call, ANode, FNodes[ANode].Level, NextRow, 0);
      NextRow := NextRow + 1;
      Exit;
    end;
    // Zuerst die Kinder, dann der Elternkasten mittig davor.
    Own := AddBox(TAtlasCallBoxKind.Call, ANode, FNodes[ANode].Level, 0, 0);
    First := -1;
    Last := -1;
    for Child in Children do
    begin
      ChildBox := Place(Child);
      if First < 0 then
        First := ChildBox;
      Last := ChildBox;
      AddEdge(Own, ChildBox, FNodes[Child], False);
    end;
    if More > 0 then
    begin
      ChildBox := AddBox(TAtlasCallBoxKind.More, ANode, FNodes[ANode].Level + 1, NextRow, More);
      NextRow := NextRow + 1;
      if First < 0 then
        First := ChildBox;
      Last := ChildBox;
      Edge := Default(TAtlasCallEdge);
      Edge.Source := Own;
      Edge.Target := ChildBox;
      Edges.Add(Edge);
    end;
    Row := (Boxes[First].Row + Boxes[Last].Row) / 2;
    Box := Boxes[Own];
    Box.Row := Row;
    Boxes[Own] := Box;
    Result := Own;
  end;

  procedure CollectBackLinks(ANode: Integer);
  var
    Child, More: Integer;
  begin
    Pending.Add(ANode);
    for Child in VisibleChildren(ANode, More) do
      CollectBackLinks(Child);
  end;

var
  Node: Integer;
begin
  Result := Default(TAtlasCallLayout);
  Boxes := TList<TAtlasCallBox>.Create;
  Edges := TList<TAtlasCallEdge>.Create;
  BoxOfNode := TDictionary<Integer, Integer>.Create;
  Pending := TList<Integer>.Create;
  try
    NextRow := 0;
    for Root := 0 to High(FNodes) do
      if FNodes[Root].Parent < 0 then
      begin
        Place(Root);
        CollectBackLinks(Root);
      end;
    // Rekursionen: Pfeil vom Knoten zurück zum Vorfahren, wenn beide zu sehen sind.
    for Node in Pending do
      for Link in BackLinks(Node) do
        if BoxOfNode.ContainsKey(Node) and BoxOfNode.ContainsKey(FNodes[Link].BackTo) then
          AddEdge(BoxOfNode[Node], BoxOfNode[FNodes[Link].BackTo], FNodes[Link], True);
    Columns := 0;
    for Box in Boxes do
      Columns := Max(Columns, Box.Column + 1);
    Result.Boxes := Boxes.ToArray;
    Result.Edges := Edges.ToArray;
    Result.Columns := Columns;
    Result.Rows := NextRow;
  finally
    Pending.Free;
    BoxOfNode.Free;
    Edges.Free;
    Boxes.Free;
  end;
end;

function TAtlasCallDiagram.Json(const ATitle: string): string;
var
  Root, Entry: TJSONObject;
  Items: TJSONArray;
  Index: Integer;
  Node: TAtlasCallNode;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(1));
    Root.AddPair('title', ATitle);
    if FDirection = TAtlasHierarchyDirection.Incoming then
      Root.AddPair('direction', 'incoming')
    else
      Root.AddPair('direction', 'outgoing');
    Root.AddPair('projectOnly', TJSONBool.Create(FProjectOnly));
    Root.AddPair('maxChildren', TJSONNumber.Create(MaxChildren));
    Items := TJSONArray.Create;
    Root.AddPair('nodes', Items);
    for Index := 0 to High(FNodes) do
    begin
      Node := FNodes[Index];
      Entry := TJSONObject.Create;
      Items.AddElement(Entry);
      Entry.AddPair('id', TJSONNumber.Create(Index));
      Entry.AddPair('parent', TJSONNumber.Create(Node.Parent));
      Entry.AddPair('level', TJSONNumber.Create(Node.Level));
      Entry.AddPair('name', Title(Node.Item));
      Entry.AddPair('location', Location(Node.Item));
      Entry.AddPair('file', Node.Item.FileName);
      Entry.AddPair('line', TJSONNumber.Create(Node.Item.Line + 1));
      Entry.AddPair('library', TJSONBool.Create(Node.Library_));
      Entry.AddPair('dispatch', Node.Item.Dispatch);
      Entry.AddPair('implementations', TJSONNumber.Create(Node.Item.Implementations));
      Entry.AddPair('inferred', TJSONBool.Create(Node.Item.Confidence.Inferred));
      Entry.AddPair('inferredReason', Node.Item.Confidence.Reason);
      Entry.AddPair('reason', Node.Item.Confidence.Explanation);
      Entry.AddPair('backTo', TJSONNumber.Create(Node.BackTo));
      Entry.AddPair('expanded', TJSONBool.Create(Node.Expanded));
      Entry.AddPair('showAll', TJSONBool.Create(Node.ShowAll));
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function HtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function TAtlasCallDiagram.Html(const ATitle: string): string;
begin
  Result := StringReplace(CallDiagramHtml, '{{TITLE}}', HtmlEscape(ATitle), [rfReplaceAll]);
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
  Width, Height: Double;
begin
  Width := Max(1, ALayout.Columns) * ColumnWidth - (ColumnWidth - BoxWidth);
  Height := Max(1, ALayout.Rows) * RowHeight - (RowHeight - BoxHeight);
  Scale := 1;
  if (AWidth > 2 * Margin) and (AHeight > 2 * Margin) then
    Scale := Min(1, Min((AWidth - 2 * Margin) / Width, (AHeight - 2 * Margin) / Height));
  Scale := Max(MinScale, Scale);
  OffsetX := Margin;
  // Kleine Diagramme senkrecht mittig, große oben beginnen.
  OffsetY := Max(Margin, (AHeight - Height * Scale) / 2);
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
  NewScale: Double;
begin
  if Scale <= 0 then
    Scale := 1;
  NewScale := EnsureRange(Scale * AFactor, MinScale, MaxScale);
  OffsetX := AX - (AX - OffsetX) * NewScale / Scale;
  OffsetY := AY - (AY - OffsetY) * NewScale / Scale;
  Scale := NewScale;
end;

procedure TAtlasCallView.Pan(ADX, ADY: Double);
begin
  OffsetX := OffsetX + ADX;
  OffsetY := OffsetY + ADY;
end;

function TAtlasCallView.BoxAt(const ALayout: TAtlasCallLayout; AX, AY: Double): Integer;
var
  Index: Integer;
  Left, Top: Double;
begin
  for Index := High(ALayout.Boxes) downto 0 do
  begin
    Left := ScreenX(BoxX(ALayout.Boxes[Index]));
    Top := ScreenY(BoxY(ALayout.Boxes[Index]));
    if (AX >= Left) and (AX <= Left + BoxWidth * Scale) and (AY >= Top) and (AY <= Top + BoxHeight * Scale) then
      Exit(Index);
  end;
  Result := -1;
end;

end.
