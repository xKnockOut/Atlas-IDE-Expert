unit Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Constructors.Tests;

// Tests der Konstruktor-Untersuchung für destructor-not-nil-safe: werfende Aufrufe, ruhige Klassen, bedingtes
// Anlegen, Reihenfolge der Felder.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowDestructorConstructorsTests = class
  public
    [Test]
    procedure FieldAfterRaisingCallIsRisky;
    [Test]
    procedure QuietCreationIsNoRaiser;
    [Test]
    procedure ConditionalCreationIsRisky;
    [Test]
    procedure LaterFieldImpliesEarlier;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Constructors;

/// <summary>Unit mit TImport (Felder FStrom und FZeilen), dem Konstruktor-Rumpf AConstructor und dem
/// Destruktor-Rumpf ADestructor.</summary>
function ImportUnit(const AConstructor, ADestructor: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FStrom: TFileStream;'#10 +
    '    FZeilen: TStringList;'#10'  public'#10'    constructor Create(const Datei: string);'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'implementation'#10 +
    'constructor TImport.Create(const Datei: string);'#10'begin'#10 + AConstructor + #10'end;'#10 +
    'destructor TImport.Destroy;'#10'begin'#10 + ADestructor + #10'end;'#10'end.';
end;

/// <summary>Routinen der Unit (auf oberster Ebene des Implementierungsteils).</summary>
function Routines(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        mFound := mFound + [ANode];
        Result := TSyntaxSearchStep.Skip;
      end;
    end);
  Result := mFound;
end;

/// <summary>Untersucht den Konstruktor aus ImportUnit(AConstructor, '') und liefert die gefährdeten Felder.</summary>
function Scanned(const AConstructor: string; out AImplications: TArray<TGuardImplication>): TArray<TNilAtDestroy>;
var
  mText: string;
  mTree: TSyntaxTree;
  mRoutines: TArray<TSyntaxNode>;
  mScan: TConstructorScan;
begin
  mText := ImportUnit(AConstructor, '');
  mTree := TPascalParser.Parse(mText);
  try
    mRoutines := Routines(mTree);
    mScan := TConstructorScan.Create(mText, mTree.Root, mRoutines, False);
    try
      mScan.Start(TArray<string>.Create('FStrom', 'FZeilen'));
      mScan.Scan(mRoutines[0]);
      Result := mScan.Risky;
      AImplications := mScan.Implications;
    finally
      mScan.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TFlowDestructorConstructorsTests.FieldAfterRaisingCallIsRisky;
var
  mRisky: TArray<TNilAtDestroy>;
  mImplications: TArray<TGuardImplication>;
begin
  mRisky := Scanned('  FStrom := TFileStream.Create(Datei, fmOpenRead);'#10'  FZeilen := TStringList.Create;',
    mImplications);
  Assert.AreEqual(2, Integer(Length(mRisky)));
  Assert.AreEqual('FZeilen', mRisky[1].Field);
  Assert.AreEqual('TFileStream.Create', mRisky[1].Raiser);
end;

procedure TFlowDestructorConstructorsTests.QuietCreationIsNoRaiser;
var
  mRisky: TArray<TNilAtDestroy>;
  mImplications: TArray<TGuardImplication>;
begin
  mRisky := Scanned('  FZeilen := TStringList.Create;'#10'  FStrom := TFileStream.Create(Datei, fmOpenRead);',
    mImplications);
  Assert.AreEqual(2, Integer(Length(mRisky)));
  Assert.AreEqual('FStrom', mRisky[1].Field);
  Assert.AreEqual('TStringList.Create', mRisky[0].Raiser);
  Assert.AreEqual('TFileStream.Create', mRisky[1].Raiser);
end;

procedure TFlowDestructorConstructorsTests.ConditionalCreationIsRisky;
var
  mRisky: TArray<TNilAtDestroy>;
  mImplications: TArray<TGuardImplication>;
begin
  mRisky := Scanned('  if Datei <> '''' then'#10'    FZeilen := TStringList.Create;', mImplications);
  Assert.AreEqual(1, Integer(Length(mRisky)));
  Assert.IsTrue(mRisky[0].Conditional);
end;

procedure TFlowDestructorConstructorsTests.LaterFieldImpliesEarlier;
var
  mRisky: TArray<TNilAtDestroy>;
  mImplications: TArray<TGuardImplication>;
begin
  mRisky := Scanned('  FZeilen := TStringList.Create;'#10'  FStrom := TFileStream.Create(Datei, fmOpenRead);',
    mImplications);
  Assert.AreEqual(2, Integer(Length(mRisky)));
  Assert.AreEqual(2, Integer(Length(mImplications)));
  Assert.AreEqual('FStrom', mImplications[1].Guard);
  Assert.AreEqual(1, Integer(Length(mImplications[1].Implied)));
  Assert.AreEqual('FZeilen', mImplications[1].Implied[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowDestructorConstructorsTests);

end.
