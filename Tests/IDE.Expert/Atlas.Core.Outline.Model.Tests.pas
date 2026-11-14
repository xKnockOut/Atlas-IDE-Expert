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
  cFormCode =
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
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cFormCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cFormCode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

// Index des n-ten Knotens mit dem Namen (0 = erster); -1, wenn es keinen gibt.
function Find(const ANodes: TAtlasOutlineNodes; const AName: string; ANth: Integer): Integer; overload;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if ANodes[mIndex].Name = AName then
    begin
      if ANth = 0 then
      begin
        Exit(mIndex);
      end;
      Dec(ANth);
    end;
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
  mRow: TAtlasOutlineRow;
begin
  Result := '';
  for mRow in ARows do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + ANodes[mRow.Node].Name;
    if mRow.Matched then
    begin
      Result := Result + '*';
    end;
  end;
end;

procedure TAtlasOutlineModelTests.ReadsMembersAndMarks;
var
  mList: TAtlasOutlineNodes;
  mNode: TAtlasOutlineNode;
begin
  mList := Nodes;
  Assert.AreEqual(-1, Find(mList, 'F'), 'die Unit selbst ist kein Eintrag');
  mNode := mList[Find(mList, 'TForm1')];
  Assert.AreEqual<TAtlasOutlineCategory>(TAtlasOutlineCategory.TypeDecl, mNode.Category);
  Assert.AreEqual(4, mNode.NameLine);
  mNode := mList[Find(mList, 'Button1')];
  Assert.AreEqual<TAtlasOutlineCategory>(TAtlasOutlineCategory.Field, mNode.Category);
  Assert.AreEqual<TAtlasOutlineVisibility>(TAtlasOutlineVisibility.Published, mNode.Visibility);
  Assert.AreEqual(5, mNode.NameLine);
  mNode := mList[Find(mList, 'Button1Click')];
  Assert.AreEqual<TAtlasOutlineCategory>(TAtlasOutlineCategory.Method, mNode.Category);
  Assert.AreEqual<TAtlasOutlineVisibility>(TAtlasOutlineVisibility.Published, mNode.Visibility);
  Assert.IsFalse(mNode.Unimplemented);
  mNode := mList[Find(mList, 'Missing')];
  Assert.AreEqual<TAtlasOutlineVisibility>(TAtlasOutlineVisibility.Private, mNode.Visibility);
  Assert.IsTrue(mNode.Unimplemented, 'Missing hat keinen Rumpf');
  mNode := mList[Find(mList, 'Paint')];
  Assert.AreEqual<TAtlasOutlineVisibility>(TAtlasOutlineVisibility.Protected, mNode.Visibility);
  Assert.IsTrue(mNode.IsOverride);
  mNode := mList[Find(mList, 'Make')];
  Assert.IsTrue(mNode.ClassMember);
  Assert.AreEqual<TAtlasOutlineVisibility>(TAtlasOutlineVisibility.Public, mNode.Visibility);
  Assert.AreEqual<TAtlasOutlineCategory>(TAtlasOutlineCategory.PropertyDecl, mList[Find(mList, 'Count')].Category);
  Assert.AreEqual<TAtlasOutlineCategory>(TAtlasOutlineCategory.Constant, mList[Find(mList, 'Limit')].Category);
  mNode := mList[Find(mList, 'Run')];
  Assert.AreEqual<TAtlasOutlineCategory>(TAtlasOutlineCategory.Routine, mNode.Category);
  Assert.AreEqual<TAtlasOutlineVisibility>(TAtlasOutlineVisibility.None, mNode.Visibility);
  Assert.AreEqual('+', TAtlasOutline.VisibilityMark(TAtlasOutlineVisibility.Public));
  Assert.AreEqual('', TAtlasOutline.VisibilityMark(TAtlasOutlineVisibility.None));
end;

procedure TAtlasOutlineModelTests.BodiesBelongToTheirDeclarations;
var
  mList: TAtlasOutlineNodes;
  mText: string;
  mFirst, mSecond: Integer;
begin
  mList := Nodes;
  mText := RowText(mList, TAtlasOutline.Rows(mList, TAtlasOutlineFilter.All, TAtlasOutlineSort.Source));
  Assert.AreEqual('interface,TForm1*,Button1*,Button1Click*,FCount*,Missing*,Add*,Add*,Paint*,Make*,Count*,' +
    'Limit*,Run*,implementation,Helper*', mText);
  mFirst := Find(mList, 'Add', 0);
  mSecond := Find(mList, 'Add', 1);
  // Überladungen in Reihenfolge.
  Assert.AreEqual(26, mList[mList[mFirst].Body].StartLine);
  Assert.AreEqual(27, mList[mList[mSecond].Body].StartLine);
  Assert.AreEqual(mFirst, mList[mList[mFirst].Body].Declaration);
  Assert.AreEqual(30, mList[mList[Find(mList, 'Run')].Body].StartLine, 'Routine aus dem interface');
  Assert.AreEqual(-1, mList[Find(mList, 'Missing')].Body);
  Assert.AreEqual(-1, mList[Find(mList, 'Helper')].Declaration);
end;

procedure TAtlasOutlineModelTests.PublishedFilterShowsFormFieldsAndHandlers;
var
  mList: TAtlasOutlineNodes;
  mFilter: TAtlasOutlineFilter;
begin
  mList := Nodes;
  mFilter := TAtlasOutlineFilter.All;
  mFilter.Visibilities := [TAtlasOutlineVisibility.Published];
  Assert.IsFalse(mFilter.AllVisibilities);
  // TForm1 bleibt als Rahmen, Abschnitte ohne Treffer entfallen.
  Assert.AreEqual('interface,TForm1,Button1*,Button1Click*',
    RowText(mList, TAtlasOutline.Rows(mList, mFilter, TAtlasOutlineSort.Source)));
  mFilter.Visibilities := [TAtlasOutlineVisibility.Private];
  Assert.AreEqual('interface,TForm1,FCount*,Missing*,Add*,Add*',
    RowText(mList, TAtlasOutline.Rows(mList, mFilter, TAtlasOutlineSort.Source)));
end;

procedure TAtlasOutlineModelTests.FiltersByTextAndCategory;
var
  mList: TAtlasOutlineNodes;
  mFilter: TAtlasOutlineFilter;
begin
  mList := Nodes;
  mFilter := TAtlasOutlineFilter.All;
  mFilter.Text := 'BuCl';
  Assert.AreEqual('interface,TForm1,Button1Click*', RowText(mList, TAtlasOutline.Rows(mList, mFilter,
    TAtlasOutlineSort.Source)));
  mFilter := TAtlasOutlineFilter.All;
  mFilter.Categories := [TAtlasOutlineCategory.PropertyDecl, TAtlasOutlineCategory.Constant];
  Assert.IsFalse(mFilter.AllCategories);
  Assert.AreEqual('interface,TForm1,Count*,Limit*', RowText(mList, TAtlasOutline.Rows(mList, mFilter,
    TAtlasOutlineSort.Source)));
  mFilter.Text := 'zzz';
  Assert.AreEqual(0, Integer(Length(TAtlasOutline.Rows(mList, mFilter, TAtlasOutlineSort.Source))));
end;

procedure TAtlasOutlineModelTests.SortsAlphabeticallyWithinParents;
var
  mList: TAtlasOutlineNodes;
begin
  mList := Nodes;
  Assert.AreEqual('interface,Limit*,Run*,TForm1*,Add*,Add*,Button1*,Button1Click*,Count*,FCount*,Make*,' +
    'Missing*,Paint*,implementation,Helper*',
    RowText(mList, TAtlasOutline.Rows(mList, TAtlasOutlineFilter.All, TAtlasOutlineSort.Alphabetical)));
end;

procedure TAtlasOutlineModelTests.NodeAtMapsBodiesToDeclarations;
var
  mList: TAtlasOutlineNodes;
begin
  mList := Nodes;
  Assert.AreEqual(Find(mList, 'Missing'), TAtlasOutline.NodeAt(mList, 9, 8));
  Assert.AreEqual(Find(mList, 'TForm1'), TAtlasOutline.NodeAt(mList, 7, 2), 'zwischen Mitgliedern: der Typ');
  Assert.AreEqual(Find(mList, 'Button1Click'), TAtlasOutline.NodeAt(mList, 24, 2), 'Rumpf zur Deklaration');
  Assert.AreEqual(Find(mList, 'Button1Click'), TAtlasOutline.NodeAt(mList, 22, 14), 'lokale Routine');
  Assert.AreEqual(Find(mList, 'Add', 1), TAtlasOutline.NodeAt(mList, 27, 40));
  Assert.AreEqual(Find(mList, 'Helper'), TAtlasOutline.NodeAt(mList, 31, 20));
  Assert.AreEqual(-1, TAtlasOutline.NodeAt(mList, 2, 4), 'uses');
end;

procedure TAtlasOutlineModelTests.ConditionOfBodyGoesToDeclaration;
const
  cResponse =
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
  mValue: TJSONValue;
  mList: TAtlasOutlineNodes;
begin
  // #845: Steht nur der Rumpf im {$IFDEF}-Zweig, trägt die sichtbare Deklaration dessen Bedingung.
  mValue := TJSONObject.ParseJSONValue(cResponse);
  try
    mList := TAtlasOutline.FromJson(mValue);
  finally
    mValue.Free;
  end;
  Assert.AreEqual('CPUX64', mList[Find(mList, 'Foo', 0)].Condition);
  Assert.IsTrue(mList[Find(mList, 'Foo', 1)].Hidden);
  // Eine eigene Bedingung der Deklaration bleibt.
  Assert.AreEqual('DEBUG', mList[Find(mList, 'Log', 0)].Condition);
end;

procedure TAtlasOutlineModelTests.EmptyResponseGivesNoNodes;
var
  mValue: TJSONValue;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasOutline.FromJson(nil))));
  mValue := TJSONObject.ParseJSONValue('[]');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasOutline.FromJson(mValue))));
  finally
    mValue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOutlineModelTests);

end.
