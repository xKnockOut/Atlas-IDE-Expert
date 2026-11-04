unit Atlas.Common.Editing.MethodWithoutSelf.Lookup.Tests;

// Tests für die Namensauflösung von „Methode ohne Self“ (#686) ohne
// TNameResolver: Art der Namen im Rumpf (Feld, class var, class-Methode mit und
// ohne static, Konstante, Name der Unit, unbekannter Name bei fremdem
// Vorfahren), Sichtbarkeit, Mitglieder eines Interfaces, Helper der RTL und
// der erste Teil eines Namens.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodLookupTests = class
  public
    [Test]
    procedure MemberLevelFromClassInFile;
    [Test]
    procedure UnknownAncestorMakesNamesUnknown;
    [Test]
    procedure InterfaceMemberFromFile;
    [Test]
    procedure RtlHelperNeedsSysUtils;
    [Test]
    procedure HeadNameCutsGenericsAndMembers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup;

const
  cLager =
    'unit Lager;'#10 +
    'interface'#10 +
    'uses System.SysUtils;'#10 +
    'type'#10 +
    '  IZaehler = interface'#10 +
    '    function Anzahl: Integer;'#10 +
    '  end;'#10 +
    '  TLager = class'#10 +
    '  strict private'#10 +
    '    FMenge: Integer;'#10 +
    '  private'#10 +
    '    class var FAnzahl: Integer;'#10 +
    '  public const'#10 +
    '    Grenze = 3;'#10 +
    '  public'#10 +
    '    class function Neu: Integer;'#10 +
    '    class function Leer: Boolean; static;'#10 +
    '    procedure Fuelle;'#10 +
    '  end;'#10 +
    'procedure Frei;'#10 +
    'implementation'#10 +
    'procedure Frei;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TLager.Fuelle;'#10 +
    'begin'#10 +
    '  FMenge := FAnzahl + Grenze + Neu;'#10 +
    '  Leer;'#10 +
    '  Frei;'#10 +
    '  Unbekannt;'#10 +
    'end;'#10 +
    'end.'#10;

/// <summary>Bezeichner AName im Rumpf von TLager.Fuelle.</summary>
function IdentifierIn(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
var
  mName: string;
begin
  mName := AName;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, mName) and
        (ANode.StartPos.Line >= 26) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

function LevelOf(const ALookup: TMethodLookup; ATree: TSyntaxTree; const AName: string;
  out AVisibility: TIndexVisibility): TMemberLevel;
var
  mNode: TSyntaxNode;
begin
  mNode := IdentifierIn(ATree, AName);
  Assert.IsNotNull(mNode, AName);
  Result := ALookup.MemberLevel(mNode, AVisibility);
end;

procedure TMethodLookupTests.MemberLevelFromClassInFile;
var
  mTree: TSyntaxTree;
  mLookup: TMethodLookup;
  mVisibility: TIndexVisibility;
begin
  mTree := TPascalParser.Parse(cLager);
  try
    mLookup := TMethodLookup.FromTree(mTree);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'FMenge', mVisibility) = TMemberLevel.Instance);
    Assert.IsTrue(mVisibility = TIndexVisibility.StrictPrivate);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'FAnzahl', mVisibility) = TMemberLevel.StaticLevel);
    Assert.IsTrue(mVisibility = TIndexVisibility.Private);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'Grenze', mVisibility) = TMemberLevel.StaticLevel);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'Neu', mVisibility) = TMemberLevel.ClassLevel);
    Assert.IsTrue(mVisibility = TIndexVisibility.Public);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'Leer', mVisibility) = TMemberLevel.StaticLevel);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'Frei', mVisibility) = TMemberLevel.NotMember);
    // Ohne fremden Vorfahren kennt die Datei alle Mitglieder.
    Assert.IsTrue(LevelOf(mLookup, mTree, 'Unbekannt', mVisibility) = TMemberLevel.NotMember);
  finally
    mTree.Free;
  end;
end;

procedure TMethodLookupTests.UnknownAncestorMakesNamesUnknown;
var
  mTree: TSyntaxTree;
  mLookup: TMethodLookup;
  mVisibility: TIndexVisibility;
begin
  mTree := TPascalParser.Parse(StringReplace(cLager, '  TLager = class'#10, '  TLager = class(TBasis)'#10, []));
  try
    mLookup := TMethodLookup.FromTree(mTree);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'Unbekannt', mVisibility) = TMemberLevel.Unknown);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'Frei', mVisibility) = TMemberLevel.NotMember);
    Assert.IsTrue(LevelOf(mLookup, mTree, 'FMenge', mVisibility) = TMemberLevel.Instance);
  finally
    mTree.Free;
  end;
end;

procedure TMethodLookupTests.InterfaceMemberFromFile;
var
  mTree: TSyntaxTree;
  mLookup: TMethodLookup;
begin
  mTree := TPascalParser.Parse(cLager);
  try
    mLookup := TMethodLookup.FromTree(mTree);
    Assert.IsTrue(mLookup.InterfaceMember('IZaehler', 'Anzahl', 0));
    Assert.IsFalse(mLookup.InterfaceMember('IZaehler', 'Fuelle', 0));
    Assert.IsFalse(mLookup.InterfaceMember('IAnderes', 'Anzahl', 0));
  finally
    mTree.Free;
  end;
end;

procedure TMethodLookupTests.RtlHelperNeedsSysUtils;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cLager);
  try
    Assert.AreEqual('TStringHelper', TMethodLookup.FromTree(mTree).VisibleHelper('string', 0));
    Assert.AreEqual('', TMethodLookup.FromTree(mTree).VisibleHelper('TDateTime', 0));
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(StringReplace(cLager, 'uses System.SysUtils;'#10, '', []));
  try
    Assert.AreEqual('', TMethodLookup.FromTree(mTree).VisibleHelper('string', 0));
  finally
    mTree.Free;
  end;
end;

procedure TMethodLookupTests.HeadNameCutsGenericsAndMembers;
begin
  Assert.AreEqual('TInner', TMethodLookup.HeadName('TInner<X>'));
  Assert.AreEqual('A', TMethodLookup.HeadName('A.B'));
  Assert.AreEqual('Name', TMethodLookup.HeadName(' Name '));
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodLookupTests);

end.
