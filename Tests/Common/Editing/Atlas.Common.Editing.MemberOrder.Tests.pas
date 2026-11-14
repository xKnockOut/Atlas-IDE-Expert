unit Atlas.Common.Editing.MemberOrder.Tests;

// Tests für "Klassenmitglieder ordnen" (#89).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMemberOrderTests = class
  public
    [Test]
    procedure SortsSectionsAndMembers;
    [Test]
    procedure CommentsAndAttributesMoveWithMember;
    [Test]
    procedure SecondRunChangesNothing;
    [Test]
    procedure DirectiveAcrossSectionsBlocks;
    [Test]
    procedure DirectiveInsideSectionStaysUnit;
    [Test]
    procedure PackedRecordAndPackedClassUnchanged;
    [Test]
    procedure PublishedOnlyWithOption;
    [Test]
    procedure FieldsInSeveralSectionsKeepLayout;
    [Test]
    procedure NestedTypesKeepPlace;
    [Test]
    procedure AlignOffBlocksSort;
    [Test]
    procedure ClassVarSectionKeepsPlace;
    [Test]
    procedure UnchangedReturnsFalse;
    [Test]
    procedure CrlfIsPreserved;
    [Test]
    procedure UnknownMemberKindRanksLast;
    [Test]
    procedure MultiNameFieldStaysTogether;
    [Test]
    procedure DirectiveUnbalancedInSectionBlocks;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.MemberOrder;

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10 + ABody + '  end;'#10'implementation'#10'end.';
end;

/// <summary>Sortiertes Ergebnis; '' ohne Aktion.</summary>
function Sorted(const AText: string; const ASettings: TMemberOrderSettings): string; overload;
var
  mTree: TSyntaxTree;
  mEdit: TRuleEdit;
  mLines: TArray<string>;
  mIndex, mStart, mLine: Integer;
begin
  mTree := TPascalParser.Parse(AText);
  try
    if not TMemberOrder.Sort(AText, mTree, 3, ASettings, mEdit) then
    begin
      Exit('');
    end;
  finally
    mTree.Free;
  end;
  mLines := nil;
  mStart := 1;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or (AText[mIndex] = #10) then
    begin
      mLines := mLines + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  Result := '';
  for mLine := 0 to mEdit.Range.StartPos.Line - 1 do
  begin
    Result := Result + mLines[mLine] + #10;
  end;
  Result := Result + mEdit.NewText;
  for mLine := mEdit.Range.EndPos.Line to High(mLines) do
  begin
    Result := Result + mLines[mLine] + IfThen(mLine < High(mLines), #10, '');
  end;
end;

function Sorted(const AText: string): string; overload;
begin
  Result := Sorted(AText, TMemberOrderSettings.Default);
end;

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

procedure TMemberOrderTests.SortsSectionsAndMembers;
var
  mText: string;
begin
  mText := Sorted(Wrap(
    '  public'#10 +
    '    property Name: string read FName;'#10 +
    '    procedure Run;'#10 +
    '    constructor Create;'#10 +
    '  private'#10 +
    '    FName: string;'#10));
  Assert.AreEqual(Wrap(
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Run;'#10 +
    '    property Name: string read FName;'#10), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TMemberOrderTests.CommentsAndAttributesMoveWithMember;
begin
  Assert.AreEqual(Wrap(
    '  public'#10 +
    '    /// <summary>Neu</summary>'#10 +
    '    constructor Create;'#10 +
    '    // Läuft'#10 +
    '    [Weak]'#10 +
    '    procedure Run;'#10 +
    '      deprecated;'#10), Sorted(Wrap(
    '  public'#10 +
    '    // Läuft'#10 +
    '    [Weak]'#10 +
    '    procedure Run;'#10 +
    '      deprecated;'#10 +
    '    /// <summary>Neu</summary>'#10 +
    '    constructor Create;'#10)));
end;

procedure TMemberOrderTests.SecondRunChangesNothing;
var
  mOnce: string;
begin
  mOnce := Sorted(Wrap('  public'#10'    procedure Run;'#10'    constructor Create;'#10'  private'#10 +
    '    FA: Integer;'#10));
  Assert.AreNotEqual('', mOnce);
  Assert.AreEqual('', Sorted(mOnce));
end;

procedure TMemberOrderTests.DirectiveAcrossSectionsBlocks;
begin
  Assert.AreEqual('', Sorted(Wrap(
    '  public'#10 +
    '    procedure Run;'#10 +
    '{$IFDEF DEBUG}'#10 +
    '  private'#10 +
    '    FA: Integer;'#10 +
    '{$ENDIF}'#10)));
end;

procedure TMemberOrderTests.DirectiveInsideSectionStaysUnit;
begin
  // Der Abschnitt mit {$IFDEF} bleibt, wie er ist; die Abschnitte werden trotzdem geordnet.
  Assert.AreEqual(Wrap(
    '  private'#10 +
    '    FA: Integer;'#10 +
    '  public'#10 +
    '{$IFDEF DEBUG}'#10 +
    '    procedure Dump;'#10 +
    '{$ENDIF}'#10 +
    '    constructor Create;'#10), Sorted(Wrap(
    '  public'#10 +
    '{$IFDEF DEBUG}'#10 +
    '    procedure Dump;'#10 +
    '{$ENDIF}'#10 +
    '    constructor Create;'#10 +
    '  private'#10 +
    '    FA: Integer;'#10)));
end;

procedure TMemberOrderTests.PackedRecordAndPackedClassUnchanged;
begin
  Assert.AreEqual('', Sorted('unit U;'#10'interface'#10'type'#10'  TRec = packed record'#10'  public'#10 +
    '    procedure Run;'#10'    B: Byte;'#10'  end;'#10'implementation'#10'end.'));
  Assert.AreEqual('', Sorted('unit U;'#10'interface'#10'type'#10'  TFoo = packed class'#10'  public'#10 +
    '    procedure Run;'#10'  private'#10'    B: Byte;'#10'  end;'#10'implementation'#10'end.'));
  Assert.AreEqual('', Sorted('unit U;'#10'interface'#10'{$A-}'#10'type'#10'  TFoo = class'#10'  public'#10 +
    '    procedure Run;'#10'  private'#10'    B: Byte;'#10'  end;'#10'implementation'#10'end.'));
end;

procedure TMemberOrderTests.PublishedOnlyWithOption;
var
  mSource: string;
  mSettings: TMemberOrderSettings;
begin
  mSource := Wrap('  published'#10'    property B: Integer read FB;'#10'    procedure Run;'#10);
  Assert.AreEqual('', Sorted(mSource));
  mSettings := TMemberOrderSettings.Default;
  mSettings.SortPublished := True;
  Assert.AreEqual(Wrap('  published'#10'    procedure Run;'#10'    property B: Integer read FB;'#10),
    Sorted(mSource, mSettings));
end;

procedure TMemberOrderTests.FieldsInSeveralSectionsKeepLayout;
var
  mSource: string;
  mSettings: TMemberOrderSettings;
begin
  mSource := Wrap('  public'#10'    FB: Integer;'#10'  private'#10'    FA: Integer;'#10);
  Assert.AreEqual('', Sorted(mSource));
  mSettings := TMemberOrderSettings.Default;
  mSettings.SortFields := True;
  Assert.AreEqual(Wrap('  private'#10'    FA: Integer;'#10'  public'#10'    FB: Integer;'#10),
    Sorted(mSource, mSettings));
end;

procedure TMemberOrderTests.NestedTypesKeepPlace;
begin
  // Mit verschachteltem Typ werden Abschnitte nicht verschoben, Mitglieder anderer Abschnitte schon.
  Assert.AreEqual(Wrap(
    '  public'#10 +
    '    type'#10 +
    '      TKind = (kA, kB);'#10 +
    '  private'#10 +
    '    FKind: TKind;'#10 +
    '    procedure Run;'#10), Sorted(Wrap(
    '  public'#10 +
    '    type'#10 +
    '      TKind = (kA, kB);'#10 +
    '  private'#10 +
    '    procedure Run;'#10 +
    '    FKind: TKind;'#10)));
end;

procedure TMemberOrderTests.AlignOffBlocksSort;
const
  cBody = 'type'#10'  TFoo = class'#10'  public'#10'    procedure Run;'#10'  private'#10'    B: Byte;'#10'  end;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual('', Sorted('unit U;'#10'interface'#10'{$ALIGN OFF}'#10 + cBody));
  Assert.AreEqual('', Sorted('unit U;'#10'interface'#10'{$A1}'#10 + cBody));
end;

procedure TMemberOrderTests.ClassVarSectionKeepsPlace;
begin
  // Der Abschnitt mit class var wird weder umsortiert noch verschoben: nichts zu tun.
  Assert.AreEqual('', Sorted(Wrap(
    '  public'#10 +
    '    class var Count: Integer;'#10 +
    '    procedure Run;'#10 +
    '    constructor Create;'#10 +
    '  private'#10 +
    '    procedure Stop;'#10)));
end;

procedure TMemberOrderTests.UnchangedReturnsFalse;
var
  mSource: string;
  mTree: TSyntaxTree;
  mEdit: TRuleEdit;
begin
  mSource := Wrap('  private'#10'    FA: Integer;'#10'  public'#10'    constructor Create;'#10'    procedure Run;'#10);
  mTree := TPascalParser.Parse(mSource);
  try
    Assert.IsFalse(TMemberOrder.Sort(mSource, mTree, 3, TMemberOrderSettings.Default, mEdit));
  finally
    mTree.Free;
  end;
end;

procedure TMemberOrderTests.CrlfIsPreserved;
var
  mSource: string;
  mTree: TSyntaxTree;
  mEdit: TRuleEdit;
begin
  mSource := StringReplace(Wrap('  public'#10'    procedure Run;'#10'    constructor Create;'#10), #10, #13#10,
    [rfReplaceAll]);
  mTree := TPascalParser.Parse(mSource);
  try
    Assert.IsTrue(TMemberOrder.Sort(mSource, mTree, 3, TMemberOrderSettings.Default, mEdit));
  finally
    mTree.Free;
  end;
  Assert.AreEqual('  public'#13#10'    constructor Create;'#13#10'    procedure Run;'#13#10, mEdit.NewText);
  Assert.AreEqual(0, Pos(#10, StringReplace(mEdit.NewText, #13#10, '', [rfReplaceAll])));
end;

procedure TMemberOrderTests.UnknownMemberKindRanksLast;
var
  mSettings: TMemberOrderSettings;
begin
  mSettings := TMemberOrderSettings.Default;
  mSettings.Members := ['field', 'constructor', 'destructor', 'method'];
  Assert.AreEqual(Wrap(
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Run;'#10 +
    '    property B: Integer read FB;'#10), Sorted(Wrap(
    '  public'#10 +
    '    property B: Integer read FB;'#10 +
    '    procedure Run;'#10 +
    '    constructor Create;'#10), mSettings));
end;

procedure TMemberOrderTests.MultiNameFieldStaysTogether;
begin
  Assert.AreEqual(Wrap(
    '  private'#10 +
    '    A, B: Integer;'#10 +
    '    procedure Run;'#10), Sorted(Wrap(
    '  private'#10 +
    '    procedure Run;'#10 +
    '    A, B: Integer;'#10)));
end;

procedure TMemberOrderTests.DirectiveUnbalancedInSectionBlocks;
begin
  Assert.AreEqual('', Sorted(Wrap(
    '  public'#10 +
    '{$IFDEF DEBUG}'#10 +
    '    procedure Run;'#10 +
    '    constructor Create;'#10)));
end;

initialization
  TDUnitX.RegisterTestFixture(TMemberOrderTests);

end.
