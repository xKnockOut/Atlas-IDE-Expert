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
  cSource =
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

procedure TMemberTransferTests.CandidatesWithNeeds;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mItems: TArray<TTransferCandidate>;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    mItems := TMemberTransfer.Candidates(mLayout);
    Assert.AreEqual(6, Integer(Length(mItems)));
    Assert.AreEqual(Ord(TTransferKind.Field), Ord(mItems[0].Kind));
    Assert.AreEqual(Ord(TTransferKind.Property_), Ord(mItems[5].Kind));
    // Step benutzt FCount und FHidden; Run benutzt Step.
    Assert.AreEqual(2, Integer(Length(mItems[2].Needs)));
    Assert.AreEqual(2, mItems[3].Needs[0]);
    Assert.IsTrue(mItems[3].CanAbstract);
    Assert.IsFalse(mItems[4].CanAbstract);
    Assert.AreEqual('überschreibt schon eine Methode des Vorfahren', mItems[4].Reason);
    Assert.AreEqual(1, Integer(Length(TMemberTransfer.MissingNeeds(mLayout, [3], [3]))));
    Assert.AreEqual(0, Integer(Length(TMemberTransfer.MissingNeeds(mLayout, [3], [2, 3]))));
    Assert.AreEqual(4, TMemberTransfer.IndexOf(mItems, 4));
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TMemberTransferTests.RaisesOnlyWhenStillUsed;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    // FHidden (strict private) benutzt Step: bleibt Step, wird es gehoben, auch in derselben Unit.
    Assert.IsTrue(TMemberTransfer.MustRaise(mLayout, 0, [0], False, True, nil));
    Assert.IsFalse(TMemberTransfer.MustRaise(mLayout, 0, [0, 2], False, True, nil));
    // FCount (private): in derselben Unit nie, sonst wenn weiter benutzt.
    Assert.IsFalse(TMemberTransfer.MustRaise(mLayout, 1, [1], False, True, nil));
    Assert.IsTrue(TMemberTransfer.MustRaise(mLayout, 1, [1], False, False, nil));
    Assert.IsFalse(TMemberTransfer.MustRaise(mLayout, 1, [1, 2, 5], False, False, nil));
    // Abstrakt nach oben: Der Rumpf bleibt unten, also immer.
    Assert.IsTrue(TMemberTransfer.MustRaise(mLayout, 1, [1, 2, 5], True, False, nil));
    // Öffentliche nie.
    Assert.IsFalse(TMemberTransfer.MustRaise(mLayout, 3, [], True, False, nil));
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TMemberTransferTests.RewritesDeclarations;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    Assert.AreEqual('procedure Run; virtual; abstract;', TMemberTransfer.AbstractDeclaration(mLayout, 3));
    Assert.AreEqual('procedure Run; virtual;', TMemberTransfer.VirtualDeclaration(mLayout, 3));
    Assert.AreEqual('procedure Step; overload; override; deprecated;', TMemberTransfer.OverrideDeclaration(mLayout, 2));
    Assert.AreEqual('FCount: Integer;', TMemberTransfer.MemberText(mLayout, 1));
    Assert.AreEqual(1, Integer(Length(TMemberTransfer.OverrideEdits(mLayout, mLayout.Members[3].Node, True))));
    Assert.AreEqual(0, Integer(Length(TMemberTransfer.OverrideEdits(mLayout, mLayout.Members[4].Node, True))));
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

procedure TMemberTransferTests.InsertsFieldsBeforeMethods;
const
  cTarget =
    'unit U;'#10'interface'#10'type'#10 +
    '  TBar = class'#10 +
    '  public'#10 +
    '    procedure Show;'#10 +
    '  end;'#10 +
    'implementation'#10#10 +
    'procedure TBar.Show;'#10'begin'#10'end;'#10#10 +
    'end.'#10;
var
  mText, mReason: string;
begin
  mText := cTarget;
  Assert.IsTrue(TMemberTransfer.InsertInto(mText, 'TBar', [
    TTransferDeclaration.Create('procedure Run;', TClassVisibility.Public_, False),
    TTransferDeclaration.Create('FData: string;', TClassVisibility.Public_, True),
    TTransferDeclaration.Create('FHidden: Integer;', TClassVisibility.Private_, True),
    TTransferDeclaration.Create('procedure Help;', TClassVisibility.Protected_, False)],
    ['procedure TBar.Run;'#10'begin'#10'end;'], mReason), mReason);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(ContainsStr(mText, '  TBar = class'#10'  private'#10'    FHidden: Integer;'#10'  protected'#10 +
    '    procedure Help;'#10'  public'#10'    FData: string;'#10'    procedure Show;'#10'    procedure Run;'#10 +
    '  end;'), mText);
  Assert.IsTrue(ContainsStr(mText, 'procedure TBar.Show;'#10'begin'#10'end;'#10#10'procedure TBar.Run;'), mText);
  Assert.IsFalse(TMemberTransfer.InsertInto(mText, 'TNone', [], nil, mReason));
end;

procedure TMemberTransferTests.RelocatesFieldIntoNewSection;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
  mText: string;
begin
  mLayout := TMemberTransfer.ParseLayout(cSource, 'TFoo', mTree);
  try
    mText := cSource;
    Assert.IsTrue(TMemberTransfer.Relocate(mText, 'TFoo', [mLayout.Members[0], mLayout.Members[3]],
      TClassVisibility.Protected_));
  finally
    mLayout.Free;
    mTree.Free;
  end;
  Assert.IsTrue(Parses(mText), mText);
  // strict private fällt weg; protected zwischen private und public, Feld vor Methode.
  Assert.IsTrue(ContainsStr(mText, '  TFoo = class'#10'  private'#10'    FCount: Integer;'#10'  protected'#10 +
    '    FHidden: Integer;'#10'    procedure Run;'#10'  public'#10), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TMemberTransferTests);

end.
