unit BDLsp.Common.Editing.MemberOrder.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Editing.MemberOrder;

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10 + ABody + '  end;'#10'implementation'#10'end.';
end;

/// <summary>Sortiertes Ergebnis; '' ohne Aktion.</summary>
function Sorted(const AText: string; const ASettings: TMemberOrderSettings): string; overload;
var
  Tree: TSyntaxTree;
  Edit: TRuleEdit;
  Lines: TArray<string>;
  Index, Start, Line: Integer;
begin
  Tree := TPascalParser.Parse(AText);
  try
    if not TMemberOrder.Sort(AText, Tree, 3, ASettings, Edit) then
      Exit('');
  finally
    Tree.Free;
  end;
  Lines := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = #10) then
    begin
      Lines := Lines + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
  Result := '';
  for Line := 0 to Edit.Range.StartPos.Line - 1 do
    Result := Result + Lines[Line] + #10;
  Result := Result + Edit.NewText;
  for Line := Edit.Range.EndPos.Line to High(Lines) do
    Result := Result + Lines[Line] + IfThen(Line < High(Lines), #10, '');
end;

function Sorted(const AText: string): string; overload;
begin
  Result := Sorted(AText, TMemberOrderSettings.Default);
end;

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

procedure TMemberOrderTests.SortsSectionsAndMembers;
var
  Text: string;
begin
  Text := Sorted(Wrap(
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
    '    property Name: string read FName;'#10), Text);
  Assert.IsTrue(Parses(Text), Text);
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
  Once: string;
begin
  Once := Sorted(Wrap('  public'#10'    procedure Run;'#10'    constructor Create;'#10'  private'#10 +
    '    FA: Integer;'#10));
  Assert.IsTrue(Once <> '');
  Assert.AreEqual('', Sorted(Once));
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
  Source: string;
  Settings: TMemberOrderSettings;
begin
  Source := Wrap('  published'#10'    property B: Integer read FB;'#10'    procedure Run;'#10);
  Assert.AreEqual('', Sorted(Source));
  Settings := TMemberOrderSettings.Default;
  Settings.SortPublished := True;
  Assert.AreEqual(Wrap('  published'#10'    procedure Run;'#10'    property B: Integer read FB;'#10),
    Sorted(Source, Settings));
end;

procedure TMemberOrderTests.FieldsInSeveralSectionsKeepLayout;
var
  Source: string;
  Settings: TMemberOrderSettings;
begin
  Source := Wrap('  public'#10'    FB: Integer;'#10'  private'#10'    FA: Integer;'#10);
  Assert.AreEqual('', Sorted(Source));
  Settings := TMemberOrderSettings.Default;
  Settings.SortFields := True;
  Assert.AreEqual(Wrap('  private'#10'    FA: Integer;'#10'  public'#10'    FB: Integer;'#10),
    Sorted(Source, Settings));
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

initialization
  TDUnitX.RegisterTestFixture(TMemberOrderTests);

end.
