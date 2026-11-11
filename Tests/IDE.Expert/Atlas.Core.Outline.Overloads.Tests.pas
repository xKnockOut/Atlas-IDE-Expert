unit Atlas.Core.Outline.Overloads.Tests;

// Überladungen in der Brotkrumenleiste (#1784): Liste je Typ und Unit-Ebene,
// Zähler am Glied im interface- und implementation-Teil, Parameterliste,
// Kürzen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOverloadsTests = class
  public
    [Test]
    procedure FindsOverloadsOfTheSameOwner;
    [Test]
    procedure CrumbCountsInInterfaceAndBody;
    [Test]
    procedure NoCounterWithoutOverloadOrWhenOff;
    [Test]
    procedure ParamsAndCaption;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.Overloads;

const
  cCode =
    'unit Kunden;'#13#10 +                                              // 0
    'interface'#13#10 +                                                 // 1
    'type'#13#10 +                                                      // 2
    '  TKunde = class'#13#10 +                                          // 3
    '  public'#13#10 +                                                  // 4
    '    procedure Laden(const AName: string); overload;'#13#10 +       // 5
    '    procedure Laden(AId: Integer;'#13#10 +                         // 6
    '      AMitAdresse: Boolean); overload;'#13#10 +                    // 7
    '    procedure Laden; overload;'#13#10 +                            // 8
    '    procedure Speichern;'#13#10 +                                  // 9
    '  end;'#13#10 +                                                    // 10
    'function Summe(A, B: Integer): Integer; overload;'#13#10 +         // 11
    'function Summe(A, B: Double): Double; overload;'#13#10 +           // 12
    'implementation'#13#10 +                                            // 13
    'procedure TKunde.Laden(const AName: string);'#13#10 +              // 14
    'begin'#13#10 +                                                     // 15
    'end;'#13#10 +                                                      // 16
    'procedure TKunde.Laden(AId: Integer; AMitAdresse: Boolean);'#13#10 + // 17
    'begin'#13#10 +                                                     // 18
    'end;'#13#10 +                                                      // 19
    'procedure TKunde.Laden;'#13#10 +                                   // 20
    'begin'#13#10 +                                                     // 21
    'end;'#13#10 +                                                      // 22
    'procedure TKunde.Speichern;'#13#10 +                               // 23
    'begin'#13#10 +                                                     // 24
    'end;'#13#10 +                                                      // 25
    'function Summe(A, B: Integer): Integer;'#13#10 +                   // 26
    'begin'#13#10 +                                                     // 27
    '  Result := A + B;'#13#10 +                                        // 28
    'end;'#13#10 +                                                      // 29
    'function Summe(A, B: Double): Double;'#13#10 +                     // 30
    'begin'#13#10 +                                                     // 31
    '  Result := A + B;'#13#10 +                                        // 32
    'end;'#13#10 +                                                      // 33
    'end.';                                                             // 34

function Lines: TArray<string>;
begin
  Result := cCode.Split([#13#10]);
end;

function Nodes: TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

/// <summary>Sichtbare Knoten namens AName in Quelltextreihenfolge.</summary>
function NodesNamed(const AName: string): TArray<Integer>;
var
  mNodes: TAtlasOutlineNodes;
  mIndex: Integer;
begin
  mNodes := Nodes;
  Result := nil;
  for mIndex := 0 to High(mNodes) do
  begin
    if not mNodes[mIndex].Hidden and (mNodes[mIndex].Name = AName) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function LastCrumb(ALine, ACharacter: Integer; AParts: TAtlasCrumbParts): TAtlasCrumb;
var
  mCrumbs: TAtlasCrumbs;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines, TAtlasCrumbRequest.Create(ALine, ACharacter, 'Kunden', True, AParts));
  Result := mCrumbs[High(mCrumbs)];
end;

procedure TAtlasOverloadsTests.FindsOverloadsOfTheSameOwner;
var
  mLaden, mSumme: TArray<Integer>;
begin
  mLaden := NodesNamed('Laden');
  Assert.AreEqual(3, Integer(Length(mLaden)));
  Assert.AreEqual(3, Integer(Length(TAtlasOverloads.Find(Nodes, mLaden[1]))));
  Assert.AreEqual(mLaden[2], TAtlasOverloads.Find(Nodes, mLaden[0])[2], 'Quelltextreihenfolge');
  mSumme := NodesNamed('Summe');
  Assert.AreEqual(2, Integer(Length(TAtlasOverloads.Find(Nodes, mSumme[0]))), 'Unit-Ebene');
  Assert.AreEqual(0, Integer(Length(TAtlasOverloads.Find(Nodes, NodesNamed('Speichern')[0]))), 'ohne Überladung');
  Assert.AreEqual(0, Integer(Length(TAtlasOverloads.Find(Nodes, NodesNamed('TKunde')[0]))), 'kein Routine');
end;

procedure TAtlasOverloadsTests.CrumbCountsInInterfaceAndBody;
var
  mCrumb: TAtlasCrumb;
begin
  mCrumb := LastCrumb(6, 16, [TAtlasCrumbPart.Overloads]);
  Assert.AreEqual('Laden', mCrumb.Text);
  Assert.AreEqual(3, Integer(Length(mCrumb.Overloads)));
  Assert.AreEqual(1, mCrumb.Overload, 'Deklaration 2/3');
  mCrumb := LastCrumb(21, 0, [TAtlasCrumbPart.Overloads]);
  Assert.AreEqual(2, mCrumb.Overload, 'im Rumpf 3/3');
  mCrumb := LastCrumb(28, 2, [TAtlasCrumbPart.Overloads]);
  Assert.AreEqual(2, Integer(Length(mCrumb.Overloads)), 'Routine der Unit');
  Assert.AreEqual(0, mCrumb.Overload);
  mCrumb := LastCrumb(32, 2, [TAtlasCrumbPart.Overloads]);
  Assert.AreEqual(1, mCrumb.Overload);
end;

procedure TAtlasOverloadsTests.NoCounterWithoutOverloadOrWhenOff;
var
  mCrumb: TAtlasCrumb;
begin
  mCrumb := LastCrumb(24, 0, [TAtlasCrumbPart.Overloads]);
  Assert.AreEqual('Speichern', mCrumb.Text);
  Assert.AreEqual(0, Integer(Length(mCrumb.Overloads)));
  Assert.AreEqual(-1, mCrumb.Overload);
  mCrumb := LastCrumb(21, 0, []);
  Assert.AreEqual(0, Integer(Length(mCrumb.Overloads)), 'ausgeschaltet');
  Assert.AreEqual(-1, mCrumb.Overload);
end;

procedure TAtlasOverloadsTests.ParamsAndCaption;
var
  mLaden: TArray<Integer>;
begin
  mLaden := NodesNamed('Laden');
  Assert.AreEqual('(const AName: string)', TAtlasOverloads.ParamsOf(Nodes, Lines, mLaden[0]));
  Assert.AreEqual('(AId: Integer; AMitAdresse: Boolean)', TAtlasOverloads.ParamsOf(Nodes, Lines, mLaden[1]),
    'über zwei Zeilen');
  Assert.AreEqual('()', TAtlasOverloads.ParamsOf(Nodes, Lines, mLaden[2]), 'ohne Parameter');
  Assert.AreEqual('', TAtlasOverloads.ParamsOf(Nodes, Lines, NodesNamed('TKunde')[0]), 'kein Routine');
  Assert.AreEqual('Laden(const AName: string)', TAtlasOverloads.Caption(Nodes, Lines, mLaden[0], 60));
  Assert.AreEqual('Laden(AId: Integer; AMi…', TAtlasOverloads.Caption(Nodes, Lines, mLaden[1], 24));
  Assert.AreEqual('kurz', TAtlasOverloads.Shorten('kurz', 4));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOverloadsTests);

end.
