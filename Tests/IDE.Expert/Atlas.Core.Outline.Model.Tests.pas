unit Atlas.Core.Outline.Model.Tests;

// Tests für das Gliederungsfenster (#537): Knoten aus der Antwort des Servers
// (über den echten Aufbau von documentSymbol), Rümpfe bei ihren Deklarationen,
// Filter nach Sichtbarkeit, Text und Art, Sortierung und Knoten am Cursor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOutlineModelTests = class
  public
    [Test]
    procedure ReadsMembersAndMarks;
    [Test]
    procedure BodiesBelongToTheirDeclarations;
    [Test]
    procedure PublishedFilterShowsFormFieldsAndHandlers;
    [Test]
    procedure FiltersByTextAndCategory;
    [Test]
    procedure SortsAlphabeticallyWithinParents;
    [Test]
    procedure NodeAtMapsBodiesToDeclarations;
    [Test]
    procedure EmptyResponseGivesNoNodes;
    [Test]
    procedure ConditionOfBodyGoesToDeclaration;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model;

const
  FormCode =
    'unit F;'#13#10 +                                          // 0
    'interface'#13#10 +                                        // 1
    'uses Vcl.Forms;'#13#10 +                                  // 2
    'type'#13#10 +                                             // 3
    '  TForm1 = class(TForm)'#13#10 +                          // 4
    '    Button1: TButton;'#13#10 +                            // 5
    '    procedure Button1Click(Sender: TObject);'#13#10 +     // 6
    '  private'#13#10 +                                        // 7
    '    FCount: Integer;'#13#10 +                             // 8
    '    procedure Missing;'#13#10 +                           // 9
    '    procedure Add(A: Integer); overload;'#13#10 +         // 10
    '    procedure Add(A: string); overload;'#13#10 +          // 11
    '  protected'#13#10 +                                      // 12
    '    procedure Paint; override;'#13#10 +                   // 13
    '  public'#13#10 +                                         // 14
    '    class function Make: TForm1;'#13#10 +                 // 15
    '    property Count: Integer read FCount;'#13#10 +         // 16
    '  end;'#13#10 +                                           // 17
    'const Limit = 10;'#13#10 +                                // 18
    'procedure Run;'#13#10 +                                   // 19
    'implementation'#13#10 +                                   // 20
    'procedure TForm1.Button1Click(Sender: TObject);'#13#10 +  // 21
    '  procedure Local; begin end;'#13#10 +                    // 22
    'begin'#13#10 +                                            // 23
    '  Local;'#13#10 +                                         // 24
    'end;'#13#10 +                                             // 25
    'procedure TForm1.Add(A: Integer); begin end;'#13#10 +     // 26
    'procedure TForm1.Add(A: string); begin end;'#13#10 +      // 27
    'procedure TForm1.Paint; begin end;'#13#10 +               // 28
    'class function TForm1.Make: TForm1; begin Result := nil; end;'#13#10 + // 29
    'procedure Run; begin end;'#13#10 +                        // 30
    'procedure Helper; begin end;'#13#10 +                     // 31
    'end.';                                                    // 32

function Nodes: TAtlasOutlineNodes;
var
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
begin
  Tree := TPascalParser.Parse(FormCode);
  try
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, FormCode);
  finally
    Tree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(Symbols);
  finally
    Symbols.Free;
  end;
end;

// Index des n-ten Knotens mit dem Namen (0 = erster); -1, wenn es keinen gibt.
function Find(const ANodes: TAtlasOutlineNodes; const AName: string; ANth: Integer): Integer; overload;
var
  Index: Integer;
begin
  for Index := 0 to High(ANodes) do
    if ANodes[Index].Name = AName then
    begin
      if ANth = 0 then
        Exit(Index);
      Dec(ANth);
    end;
  Result := -1;
end;

function Find(const ANodes: TAtlasOutlineNodes; const AName: string): Integer; overload;
begin
  Result := Find(ANodes, AName, 0);
end;

// Zeilen als Text: "Name" je Zeile, mit "*" für Treffer, getrennt durch Komma.
function RowText(const ANodes: TAtlasOutlineNodes; const ARows: TArray<TAtlasOutlineRow>): string;
var
  Row: TAtlasOutlineRow;
begin
  Result := '';
  for Row in ARows do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + ANodes[Row.Node].Name;
    if Row.Matched then
      Result := Result + '*';
  end;
end;

procedure TAtlasOutlineModelTests.ReadsMembersAndMarks;
var
  List: TAtlasOutlineNodes;
  Node: TAtlasOutlineNode;
begin
  List := Nodes;
  Assert.AreEqual(-1, Find(List, 'F'), 'die Unit selbst ist kein Eintrag');
  Node := List[Find(List, 'TForm1')];
  Assert.IsTrue(Node.Category = TAtlasOutlineCategory.TypeDecl);
  Assert.AreEqual(4, Node.NameLine);
  Node := List[Find(List, 'Button1')];
  Assert.IsTrue(Node.Category = TAtlasOutlineCategory.Field);
  Assert.IsTrue(Node.Visibility = TAtlasOutlineVisibility.Published);
  Assert.AreEqual(5, Node.NameLine);
  Node := List[Find(List, 'Button1Click')];
  Assert.IsTrue(Node.Category = TAtlasOutlineCategory.Method);
  Assert.IsTrue(Node.Visibility = TAtlasOutlineVisibility.Published);
  Assert.IsFalse(Node.Unimplemented);
  Node := List[Find(List, 'Missing')];
  Assert.IsTrue(Node.Visibility = TAtlasOutlineVisibility.Private);
  Assert.IsTrue(Node.Unimplemented, 'Missing hat keinen Rumpf');
  Node := List[Find(List, 'Paint')];
  Assert.IsTrue(Node.Visibility = TAtlasOutlineVisibility.Protected);
  Assert.IsTrue(Node.IsOverride);
  Node := List[Find(List, 'Make')];
  Assert.IsTrue(Node.ClassMember);
  Assert.IsTrue(Node.Visibility = TAtlasOutlineVisibility.Public);
  Assert.IsTrue(List[Find(List, 'Count')].Category = TAtlasOutlineCategory.PropertyDecl);
  Assert.IsTrue(List[Find(List, 'Limit')].Category = TAtlasOutlineCategory.Constant);
  Node := List[Find(List, 'Run')];
  Assert.IsTrue(Node.Category = TAtlasOutlineCategory.Routine);
  Assert.IsTrue(Node.Visibility = TAtlasOutlineVisibility.None);
  Assert.AreEqual('+', TAtlasOutline.VisibilityMark(TAtlasOutlineVisibility.Public));
  Assert.AreEqual('', TAtlasOutline.VisibilityMark(TAtlasOutlineVisibility.None));
end;

procedure TAtlasOutlineModelTests.BodiesBelongToTheirDeclarations;
var
  List: TAtlasOutlineNodes;
  Text: string;
  First, Second: Integer;
begin
  List := Nodes;
  Text := RowText(List, TAtlasOutline.Rows(List, TAtlasOutlineFilter.All, TAtlasOutlineSort.Source));
  Assert.AreEqual('interface,TForm1*,Button1*,Button1Click*,FCount*,Missing*,Add*,Add*,Paint*,Make*,Count*,' +
    'Limit*,Run*,implementation,Helper*', Text);
  First := Find(List, 'Add', 0);
  Second := Find(List, 'Add', 1);
  // Überladungen in Reihenfolge.
  Assert.AreEqual(26, List[List[First].Body].StartLine);
  Assert.AreEqual(27, List[List[Second].Body].StartLine);
  Assert.AreEqual(First, List[List[First].Body].Declaration);
  Assert.AreEqual(30, List[List[Find(List, 'Run')].Body].StartLine, 'Routine aus dem interface');
  Assert.AreEqual(-1, List[Find(List, 'Missing')].Body);
  Assert.AreEqual(-1, List[Find(List, 'Helper')].Declaration);
end;

procedure TAtlasOutlineModelTests.PublishedFilterShowsFormFieldsAndHandlers;
var
  List: TAtlasOutlineNodes;
  Filter: TAtlasOutlineFilter;
begin
  List := Nodes;
  Filter := TAtlasOutlineFilter.All;
  Filter.Visibilities := [TAtlasOutlineVisibility.Published];
  Assert.IsFalse(Filter.AllVisibilities);
  // TForm1 bleibt als Rahmen, Abschnitte ohne Treffer entfallen.
  Assert.AreEqual('interface,TForm1,Button1*,Button1Click*',
    RowText(List, TAtlasOutline.Rows(List, Filter, TAtlasOutlineSort.Source)));
  Filter.Visibilities := [TAtlasOutlineVisibility.Private];
  Assert.AreEqual('interface,TForm1,FCount*,Missing*,Add*,Add*',
    RowText(List, TAtlasOutline.Rows(List, Filter, TAtlasOutlineSort.Source)));
end;

procedure TAtlasOutlineModelTests.FiltersByTextAndCategory;
var
  List: TAtlasOutlineNodes;
  Filter: TAtlasOutlineFilter;
begin
  List := Nodes;
  Filter := TAtlasOutlineFilter.All;
  Filter.Text := 'BuCl';
  Assert.AreEqual('interface,TForm1,Button1Click*', RowText(List, TAtlasOutline.Rows(List, Filter,
    TAtlasOutlineSort.Source)));
  Filter := TAtlasOutlineFilter.All;
  Filter.Categories := [TAtlasOutlineCategory.PropertyDecl, TAtlasOutlineCategory.Constant];
  Assert.IsFalse(Filter.AllCategories);
  Assert.AreEqual('interface,TForm1,Count*,Limit*', RowText(List, TAtlasOutline.Rows(List, Filter,
    TAtlasOutlineSort.Source)));
  Filter.Text := 'zzz';
  Assert.AreEqual(0, Integer(Length(TAtlasOutline.Rows(List, Filter, TAtlasOutlineSort.Source))));
end;

procedure TAtlasOutlineModelTests.SortsAlphabeticallyWithinParents;
var
  List: TAtlasOutlineNodes;
begin
  List := Nodes;
  Assert.AreEqual('interface,Limit*,Run*,TForm1*,Add*,Add*,Button1*,Button1Click*,Count*,FCount*,Make*,' +
    'Missing*,Paint*,implementation,Helper*',
    RowText(List, TAtlasOutline.Rows(List, TAtlasOutlineFilter.All, TAtlasOutlineSort.Alphabetical)));
end;

procedure TAtlasOutlineModelTests.NodeAtMapsBodiesToDeclarations;
var
  List: TAtlasOutlineNodes;
begin
  List := Nodes;
  Assert.AreEqual(Find(List, 'Missing'), TAtlasOutline.NodeAt(List, 9, 8));
  Assert.AreEqual(Find(List, 'TForm1'), TAtlasOutline.NodeAt(List, 7, 2), 'zwischen Mitgliedern: der Typ');
  Assert.AreEqual(Find(List, 'Button1Click'), TAtlasOutline.NodeAt(List, 24, 2), 'Rumpf zur Deklaration');
  Assert.AreEqual(Find(List, 'Button1Click'), TAtlasOutline.NodeAt(List, 22, 14), 'lokale Routine');
  Assert.AreEqual(Find(List, 'Add', 1), TAtlasOutline.NodeAt(List, 27, 40));
  Assert.AreEqual(Find(List, 'Helper'), TAtlasOutline.NodeAt(List, 31, 20));
  Assert.AreEqual(-1, TAtlasOutline.NodeAt(List, 2, 4), 'uses');
end;

procedure TAtlasOutlineModelTests.ConditionOfBodyGoesToDeclaration;
const
  Response =
    '[{"name":"U","kind":2,"range":{"start":{"line":0,"character":0},"end":{"line":20,"character":0}},' +
    '"children":[' +
    '{"name":"interface","kind":3,"range":{"start":{"line":1,"character":0},"end":{"line":3,"character":0}},' +
    '"children":[{"name":"Foo","kind":12,"range":{"start":{"line":2,"character":0},"end":{"line":2,"character":14}}},' +
    '{"name":"Log","kind":12,"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":14}},' +
    '"atlas":{"condition":"DEBUG"}}]},' +
    '{"name":"implementation","kind":3,"range":{"start":{"line":4,"character":0},"end":{"line":19,"character":0}},' +
    '"children":[{"name":"Foo","kind":12,"range":{"start":{"line":5,"character":0},"end":{"line":10,"character":4}},' +
    '"atlas":{"condition":"CPUX64"}},' +
    '{"name":"Log","kind":12,"range":{"start":{"line":11,"character":0},"end":{"line":13,"character":4}}}]}]}]';
var
  Value: TJSONValue;
  List: TAtlasOutlineNodes;
begin
  // #845: Steht nur der Rumpf im {$IFDEF}-Zweig, trägt die sichtbare Deklaration dessen Bedingung.
  Value := TJSONObject.ParseJSONValue(Response);
  try
    List := TAtlasOutline.FromJson(Value);
  finally
    Value.Free;
  end;
  Assert.AreEqual('CPUX64', List[Find(List, 'Foo', 0)].Condition);
  Assert.IsTrue(List[Find(List, 'Foo', 1)].Hidden);
  // Eine eigene Bedingung der Deklaration bleibt.
  Assert.AreEqual('DEBUG', List[Find(List, 'Log', 0)].Condition);
end;

procedure TAtlasOutlineModelTests.EmptyResponseGivesNoNodes;
var
  Value: TJSONValue;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasOutline.FromJson(nil))));
  Value := TJSONObject.ParseJSONValue('[]');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasOutline.FromJson(Value))));
  finally
    Value.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOutlineModelTests);

end.
