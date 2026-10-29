unit Atlas.Common.Editing.MemberTransfer.Tests;

// Tests für die gemeinsamen Schritte von #713 und #675: Kandidaten samt
// Abhängigkeiten, wann ein privates Mitglied gehoben wird, neu geschriebene
// Deklarationen (abstrakt, virtuell, überschreibend), Einfügen in eine
// vorhandene Klasse (Felder vor Methoden, Abschnitte nach Sichtbarkeit) und
// das Umsetzen in einen anderen Abschnitt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMemberTransferTests = class
  public
    [Test]
    procedure CandidatesWithNeeds;
    [Test]
    procedure RaisesOnlyWhenStillUsed;
    [Test]
    procedure RewritesDeclarations;
    [Test]
    procedure InsertsFieldsBeforeMethods;
    [Test]
    procedure RelocatesFieldIntoNewSection;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.MemberTransfer;

const
  Source =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  strict private'#10 +
    '    FHidden: Integer;'#10 +                                   // 0
    '  private'#10 +
    '    FCount: Integer;'#10 +                                    // 1
    '  public'#10 +
    '    procedure Step; overload; virtual; deprecated;'#10 +      // 2
    '    procedure Run;'#10 +                                      // 3
    '    procedure Done; override;'#10 +                           // 4
    '    property Count: Integer read FCount;'#10 +                // 5
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TFoo.Step;'#10'begin'#10'  FCount := FHidden;'#10'end;'#10#10 +
    'procedure TFoo.Run;'#10'begin'#10'  Step;'#10'end;'#10#10 +
    'procedure TFoo.Done;'#10'begin'#10'end;'#10#10 +
    'end.'#10;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TMemberTransferTests.CandidatesWithNeeds;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Items: TArray<TTransferCandidate>;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    Items := TMemberTransfer.Candidates(Layout);
    Assert.AreEqual(6, Integer(Length(Items)));
    Assert.AreEqual(Ord(TTransferKind.Field), Ord(Items[0].Kind));
    Assert.AreEqual(Ord(TTransferKind.Property_), Ord(Items[5].Kind));
    // Step benutzt FCount und FHidden; Run benutzt Step.
    Assert.AreEqual(2, Integer(Length(Items[2].Needs)));
    Assert.AreEqual(2, Items[3].Needs[0]);
    Assert.IsTrue(Items[3].CanAbstract);
    Assert.IsFalse(Items[4].CanAbstract);
    Assert.AreEqual('überschreibt schon eine Methode des Vorfahren', Items[4].Reason);
    Assert.AreEqual(1, Integer(Length(TMemberTransfer.MissingNeeds(Layout, [3], [3]))));
    Assert.AreEqual(0, Integer(Length(TMemberTransfer.MissingNeeds(Layout, [3], [2, 3]))));
    Assert.AreEqual(4, TMemberTransfer.IndexOf(Items, 4));
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TMemberTransferTests.RaisesOnlyWhenStillUsed;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    // FHidden (strict private) benutzt Step: bleibt Step, wird es gehoben, auch in derselben Unit.
    Assert.IsTrue(TMemberTransfer.MustRaise(Layout, 0, [0], False, True, nil));
    Assert.IsFalse(TMemberTransfer.MustRaise(Layout, 0, [0, 2], False, True, nil));
    // FCount (private): in derselben Unit nie, sonst wenn weiter benutzt.
    Assert.IsFalse(TMemberTransfer.MustRaise(Layout, 1, [1], False, True, nil));
    Assert.IsTrue(TMemberTransfer.MustRaise(Layout, 1, [1], False, False, nil));
    Assert.IsFalse(TMemberTransfer.MustRaise(Layout, 1, [1, 2, 5], False, False, nil));
    // Abstrakt nach oben: Der Rumpf bleibt unten, also immer.
    Assert.IsTrue(TMemberTransfer.MustRaise(Layout, 1, [1, 2, 5], True, False, nil));
    // Öffentliche nie.
    Assert.IsFalse(TMemberTransfer.MustRaise(Layout, 3, [], True, False, nil));
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TMemberTransferTests.RewritesDeclarations;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    Assert.AreEqual('procedure Run; virtual; abstract;', TMemberTransfer.AbstractDeclaration(Layout, 3));
    Assert.AreEqual('procedure Run; virtual;', TMemberTransfer.VirtualDeclaration(Layout, 3));
    Assert.AreEqual('procedure Step; overload; override; deprecated;', TMemberTransfer.OverrideDeclaration(Layout, 2));
    Assert.AreEqual('FCount: Integer;', TMemberTransfer.MemberText(Layout, 1));
    Assert.AreEqual(1, Integer(Length(TMemberTransfer.OverrideEdits(Layout, Layout.Members[3].Node, True))));
    Assert.AreEqual(0, Integer(Length(TMemberTransfer.OverrideEdits(Layout, Layout.Members[4].Node, True))));
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

procedure TMemberTransferTests.InsertsFieldsBeforeMethods;
const
  Target =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBar = class'#10 +
    '  public'#10 +
    '    procedure Show;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBar.Show;'#10'begin'#10'end;'#10#10 +
    'end.'#10;
var
  Text, Reason: string;
begin
  Text := Target;
  Assert.IsTrue(TMemberTransfer.InsertInto(Text, 'TBar', [
    TTransferDeclaration.Create('procedure Run;', TClassVisibility.Public_, False),
    TTransferDeclaration.Create('FData: string;', TClassVisibility.Public_, True),
    TTransferDeclaration.Create('FHidden: Integer;', TClassVisibility.Private_, True),
    TTransferDeclaration.Create('procedure Help;', TClassVisibility.Protected_, False)],
    ['procedure TBar.Run;'#10'begin'#10'end;'], Reason), Reason);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(ContainsStr(Text, '  TBar = class'#10'  private'#10'    FHidden: Integer;'#10'  protected'#10 +
    '    procedure Help;'#10'  public'#10'    FData: string;'#10'    procedure Show;'#10'    procedure Run;'#10 +
    '  end;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'procedure TBar.Show;'#10'begin'#10'end;'#10#10'procedure TBar.Run;'), Text);
  Assert.IsFalse(TMemberTransfer.InsertInto(Text, 'TNone', [], nil, Reason));
end;

procedure TMemberTransferTests.RelocatesFieldIntoNewSection;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Text: string;
begin
  Layout := TMemberTransfer.ParseLayout(Source, 'TFoo', Tree);
  try
    Text := Source;
    Assert.IsTrue(TMemberTransfer.Relocate(Text, 'TFoo', [Layout.Members[0], Layout.Members[3]],
      TClassVisibility.Protected_));
  finally
    Layout.Free;
    Tree.Free;
  end;
  Assert.IsTrue(Parses(Text), Text);
  // strict private fällt weg; protected zwischen private und public, Feld vor Methode.
  Assert.IsTrue(ContainsStr(Text, '  TFoo = class'#10'  private'#10'    FCount: Integer;'#10'  protected'#10 +
    '    FHidden: Integer;'#10'    procedure Run;'#10'  public'#10), Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TMemberTransferTests);

end.
