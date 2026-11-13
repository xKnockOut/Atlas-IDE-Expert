unit Atlas.Common.Rules.Builtin.Registration.Tests;

// Tests der Anmeldung eingebauter Regeln nach Themen (Atlas.Common.Rules.Builtin.Registration.Declarations,
// .Statements, .Frameworks und .Ownership):
// jede Gruppe meldet Regeln an, keine Regel steht doppelt, und BuiltinRules liefert genau die Regeln aller
// Gruppen in derselben Reihenfolge.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBuiltinRegistrationTests = class
  public
    [Test]
    procedure EveryGroupRegistersRules;
    [Test]
    procedure RuleIdsAreUnique;
    [Test]
    procedure BuiltinRulesKeepsGroupOrder;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Registration.Declarations,
  Atlas.Common.Rules.Builtin.Registration.Statements,
  Atlas.Common.Rules.Builtin.Registration.Frameworks,
  Atlas.Common.Rules.Builtin.Registration.Ownership;

type
  TRegisterProc = reference to procedure(const ARegistry: TRuleRegistry);

function GroupIds(const ARegister: TRegisterProc): TArray<string>;
var
  mRegistry: TRuleRegistry;
  mRule: IRule;
begin
  Result := nil;
  mRegistry := TRuleRegistry.Create;
  try
    ARegister(mRegistry);
    for mRule in mRegistry.Rules do
    begin
      Result := Result + [mRule.Descriptor.Id];
    end;
  finally
    mRegistry.Free;
  end;
end;

function DeclarationsGroup: TArray<string>;
begin
  Result := GroupIds(
    procedure(const ARegistry: TRuleRegistry)
    begin
      RegisterBuiltinDeclarationRules(ARegistry);
    end);
end;

function StatementsGroup: TArray<string>;
begin
  Result := GroupIds(
    procedure(const ARegistry: TRuleRegistry)
    begin
      RegisterBuiltinStatementRules(ARegistry);
    end);
end;

function FrameworksGroup: TArray<string>;
begin
  Result := GroupIds(
    procedure(const ARegistry: TRuleRegistry)
    begin
      RegisterBuiltinFrameworkRules(ARegistry);
    end);
end;

function OwnershipGroup: TArray<string>;
begin
  Result := GroupIds(
    procedure(const ARegistry: TRuleRegistry)
    begin
      RegisterBuiltinOwnershipRules(ARegistry);
    end);
end;

function AllIds: TArray<string>;
var
  mRule: IRule;
begin
  Result := nil;
  for mRule in BuiltinRules do
  begin
    Result := Result + [mRule.Descriptor.Id];
  end;
end;

procedure TBuiltinRegistrationTests.EveryGroupRegistersRules;
begin
  Assert.IsTrue(Length(DeclarationsGroup) > 0, 'Declarations');
  Assert.IsTrue(Length(StatementsGroup) > 0, 'Statements');
  Assert.IsTrue(Length(FrameworksGroup) > 0, 'Frameworks');
  Assert.IsTrue(Length(OwnershipGroup) > 0, 'Ownership');
end;

procedure TBuiltinRegistrationTests.RuleIdsAreUnique;
var
  mSeen: TList<string>;
  mId: string;
begin
  mSeen := TList<string>.Create;
  try
    for mId in AllIds do
    begin
      Assert.IsFalse(mSeen.Contains(mId), mId + ' doppelt angemeldet');
      mSeen.Add(mId);
    end;
  finally
    mSeen.Free;
  end;
end;

procedure TBuiltinRegistrationTests.BuiltinRulesKeepsGroupOrder;
var
  mExpected, mActual: TArray<string>;
begin
  mExpected := DeclarationsGroup + StatementsGroup + FrameworksGroup + OwnershipGroup;
  mActual := AllIds;
  Assert.AreEqual(string.Join(',', mExpected), string.Join(',', mActual));
end;

initialization
  TDUnitX.RegisterTestFixture(TBuiltinRegistrationTests);

end.
