unit Atlas.Common.Lsp.LinkedEditing.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.LinkedEditing;

type
  [TestFixture]
  TLspLinkedEditingTests = class
  private
    function RangesAt(ALine, ACharacter: Integer): TArray<TTextRange>;
  public
    [Test]
    procedure LinksMethodDeclarationAndImplementation;
    [Test]
    procedure LinksFromImplementation;
    [Test]
    procedure LinksForwardRoutines;
    [Test]
    procedure NothingForOverloads;
    [Test]
    procedure NothingForOtherNames;
    [Test]
    procedure WritesJson;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser;

const
  UnitText =
    'unit Muster;'#10 +                            // 0
    'interface'#10 +                               // 1
    'type'#10 +                                    // 2
    '  TFoo = class'#10 +                          // 3
    '    procedure Lauf;'#10 +                     // 4
    '    procedure Mehr(A: Integer); overload;'#10 + // 5
    '    procedure Mehr(A: string); overload;'#10 + // 6
    '  end;'#10 +                                  // 7
    'function Hilfe: Integer;'#10 +                // 8
    'implementation'#10 +                          // 9
    'procedure TFoo.Lauf;'#10 +                    // 10
    'begin'#10 +                                   // 11
    'end;'#10 +                                    // 12
    'procedure TFoo.Mehr(A: Integer);'#10 +        // 13
    'begin'#10 +                                   // 14
    'end;'#10 +                                    // 15
    'procedure TFoo.Mehr(A: string);'#10 +         // 16
    'begin'#10 +                                   // 17
    'end;'#10 +                                    // 18
    'function Hilfe: Integer;'#10 +                // 19
    'begin'#10 +                                   // 20
    '  Result := 0;'#10 +                          // 21
    'end;'#10 +                                    // 22
    'end.';

{ TLspLinkedEditingTests }

function TLspLinkedEditingTests.RangesAt(ALine, ACharacter: Integer): TArray<TTextRange>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitText);
  try
    Result := TLspLinkedEditing.Ranges(Tree, 'C:\P\Muster.pas', TTextPosition.Create(ALine, ACharacter));
  finally
    Tree.Free;
  end;
end;

procedure TLspLinkedEditingTests.LinksMethodDeclarationAndImplementation;
var
  Ranges: TArray<TTextRange>;
begin
  Ranges := RangesAt(4, 16);
  Assert.AreEqual(2, Integer(Length(Ranges)));
  Assert.AreEqual(4, Ranges[0].StartPos.Line);
  Assert.AreEqual(14, Ranges[0].StartPos.Character);
  Assert.AreEqual(18, Ranges[0].EndPos.Character);
  Assert.AreEqual(10, Ranges[1].StartPos.Line);
  Assert.AreEqual(15, Ranges[1].StartPos.Character);
end;

procedure TLspLinkedEditingTests.LinksFromImplementation;
begin
  Assert.AreEqual(2, Integer(Length(RangesAt(10, 17))));
end;

procedure TLspLinkedEditingTests.LinksForwardRoutines;
var
  Ranges: TArray<TTextRange>;
begin
  Ranges := RangesAt(19, 10);
  Assert.AreEqual(2, Integer(Length(Ranges)));
  Assert.AreEqual(8, Ranges[0].StartPos.Line);
  Assert.AreEqual(19, Ranges[1].StartPos.Line);
end;

procedure TLspLinkedEditingTests.NothingForOverloads;
begin
  Assert.AreEqual(0, Integer(Length(RangesAt(5, 16))));
end;

procedure TLspLinkedEditingTests.NothingForOtherNames;
begin
  // Typname und Anweisungen.
  Assert.AreEqual(0, Integer(Length(RangesAt(3, 3))));
  Assert.AreEqual(0, Integer(Length(RangesAt(21, 3))));
end;

procedure TLspLinkedEditingTests.WritesJson;
var
  Json: TJSONValue;
begin
  Json := TLspLinkedEditing.ToJson(RangesAt(4, 16));
  try
    Assert.AreEqual(2, (Json as TJSONObject).GetValue<TJSONArray>('ranges').Count);
    Assert.AreEqual(TLspLinkedEditing.WordPattern, (Json as TJSONObject).GetValue<string>('wordPattern'));
  finally
    Json.Free;
  end;
  Json := TLspLinkedEditing.ToJson(nil);
  try
    Assert.IsTrue(Json is TJSONNull);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspLinkedEditingTests);

end.
