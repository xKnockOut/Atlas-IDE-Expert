unit Argus.Common.Editing.DocComments.Tests;

// Tests für das Gerüst von Dokumentationskommentaren (#88).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocCommentsTests = class
  public
    [Test]
    procedure FunctionWithGenericsAndParams;
    [Test]
    procedure ProcedureAndConstructor;
    [Test]
    procedure PropertyAndTypeOnlySummary;
    [Test]
    procedure AfterThirdSlash;
    [Test]
    procedure NothingWhenAlreadyDocumented;
    [Test]
    procedure ActionGeneratesComment;
    [Test]
    procedure ActionAddsMissingParam;
    [Test]
    procedure ActionRemovesStaleParam;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Editing.CodeActions,
  Argus.Common.Editing.DocComments;

const
  Source =
    'unit U;'#10 +                                                               // 0
    'interface'#10 +                                                             // 1
    'type'#10 +                                                                  // 2
    '  TFoo = class'#10 +                                                        // 3
    '  public'#10 +                                                              // 4
    '    %s'#10 +                                                                // 5
    '    function Foo<T>(const A: Integer; out B: string): Boolean;'#10 +        // 6
    '    procedure Bar;'#10 +                                                    // 7
    '    constructor Create(AOwner: TComponent);'#10 +                           // 8
    '    property Name: string read FName;'#10 +                                 // 9
    '  end;'#10 +                                                                // 10
    'implementation'#10 +                                                        // 11
    'end.';

function Lines(const AText: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = #10) then
    begin
      Result := Result + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
end;

function Joined(const ALines: TArray<string>): string;
var
  Line: string;
begin
  Result := '';
  for Line in ALines do
    Result := Result + Line + '|';
end;

function SkeletonAt(ALine: Integer): string;
begin
  Result := Joined(TDocComments.Skeleton(TDocComments.Signature(Lines(Format(Source, [''])), ALine), ''));
end;

procedure TDocCommentsTests.FunctionWithGenericsAndParams;
begin
  Assert.AreEqual('/// <summary></summary>|/// <typeparam name="T"></typeparam>|/// <param name="A"></param>|' +
    '/// <param name="B"></param>|/// <returns></returns>|', SkeletonAt(6));
end;

procedure TDocCommentsTests.ProcedureAndConstructor;
begin
  Assert.AreEqual('/// <summary></summary>|', SkeletonAt(7));
  Assert.AreEqual('/// <summary></summary>|/// <param name="AOwner"></param>|', SkeletonAt(8));
end;

procedure TDocCommentsTests.PropertyAndTypeOnlySummary;
begin
  Assert.AreEqual('/// <summary></summary>|', SkeletonAt(9));
  Assert.AreEqual('/// <summary></summary>|', SkeletonAt(3));
end;

procedure TDocCommentsTests.AfterThirdSlash;
var
  Text: string;
  Tree: TSyntaxTree;
  Edit: TRuleEdit;
begin
  Text := Format(Source, ['///']);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TDocComments.AfterSlash(Text, Tree, TTextPosition.Create(5, 7), Edit));
    Assert.AreEqual(5, Edit.Range.StartPos.Line);
    Assert.AreEqual(7, Edit.Range.EndPos.Character);
    Assert.AreEqual('    /// <summary></summary>'#10'    /// <typeparam name="T"></typeparam>'#10 +
      '    /// <param name="A"></param>'#10'    /// <param name="B"></param>'#10'    /// <returns></returns>',
      Edit.NewText);
    // Unter "end;" steht keine Deklaration.
    Assert.IsFalse(TDocComments.AfterSlash(Text, Tree, TTextPosition.Create(10, 0), Edit));
  finally
    Tree.Free;
  end;
end;

procedure TDocCommentsTests.NothingWhenAlreadyDocumented;
var
  Text: string;
  Tree: TSyntaxTree;
  Edit: TRuleEdit;
begin
  Text := StringReplace(Format(Source, ['///']), '  public'#10, '  public'#10'    /// <summary>X</summary>'#10, []);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsFalse(TDocComments.AfterSlash(Text, Tree, TTextPosition.Create(6, 7), Edit));
  finally
    Tree.Free;
  end;
end;

function ActionsAt(const AText: string; ALine: Integer): TArray<TCodeAction>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TDocComments.Actions(AText, Tree, ALine);
  finally
    Tree.Free;
  end;
end;

procedure TDocCommentsTests.ActionGeneratesComment;
var
  Found: TArray<TCodeAction>;
begin
  Found := ActionsAt(Format(Source, ['']), 8);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Dokumentationskommentar erzeugen', Found[0].Title);
  Assert.AreEqual('    /// <summary></summary>'#10'    /// <param name="AOwner"></param>'#10,
    Found[0].Edits[0].NewText);
  // Im Rumpf einer Routine und auf "end;" keine Aktion.
  Assert.AreEqual(0, Integer(Length(ActionsAt(Format(Source, ['']), 10))));
end;

procedure TDocCommentsTests.ActionAddsMissingParam;
var
  Text: string;
  Found: TArray<TCodeAction>;
begin
  Text := StringReplace(Format(Source, ['/// <summary>F</summary>']), '    function Foo',
    '    /// <param name="A">a</param>'#10'    function Foo', []);
  // Zeile 5 Summary, 6 param A, 7 Foo.
  Found := ActionsAt(Text, 7);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Fehlende <param> ergänzen', Found[0].Title);
  Assert.AreEqual(1, Integer(Length(Found[0].Edits)));
  Assert.AreEqual(7, Found[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual('    /// <param name="B"></param>'#10, Found[0].Edits[0].NewText);
  // Passt alles, gibt es keine Aktion.
  Text := StringReplace(Text, '<param name="A">a</param>', '<param name="A">a</param>'#10 +
    '    /// <param name="B">b</param>', []);
  Assert.AreEqual(0, Integer(Length(ActionsAt(Text, 8))));
end;

procedure TDocCommentsTests.ActionRemovesStaleParam;
var
  Text: string;
  Found: TArray<TCodeAction>;
begin
  Text := StringReplace(Format(Source, ['/// <summary>F</summary>']), '    procedure Bar',
    '    /// <param name="Alt">a</param>'#10'    procedure Bar', []);
  Found := ActionsAt(Text, 8);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Dokumentation an die Signatur anpassen', Found[0].Title);
  Assert.AreEqual('', Found[0].Edits[0].NewText);
  Assert.AreEqual(7, Found[0].Edits[0].Range.StartPos.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TDocCommentsTests);

end.
