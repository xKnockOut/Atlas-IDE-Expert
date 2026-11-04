unit Atlas.Common.Rules.Builtin.Registration.Tests;

// Tests der Anmeldung eingebauter Regeln in drei Gruppen (Atlas.Common.Rules.Builtin.Registration1 bis 3):
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
  Atlas.Common.Rules.Builtin.Registration1,
  Atlas.Common.Rules.Builtin.Registration2,
  Atlas.Common.Rules.Builtin.Registration3;

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

function Group1: TArray<string>;
begin
  Result := GroupIds(
    procedure(const ARegistry: TRuleRegistry)
    begin
      RegisterBuiltinRules1(ARegistry);
    end);
end;

function Group2: TArray<string>;
begin
  Result := GroupIds(
    procedure(const ARegistry: TRuleRegistry)
    begin
      RegisterBuiltinRules2(ARegistry);
    end);
end;

function Group3: TArray<string>;
begin
  Result := GroupIds(
    procedure(const ARegistry: TRuleRegistry)
    begin
      RegisterBuiltinRules3(ARegistry);
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
  Assert.IsTrue(Length(Group1) > 0, 'Gruppe 1');
  Assert.IsTrue(Length(Group2) > 0, 'Gruppe 2');
  Assert.IsTrue(Length(Group3) > 0, 'Gruppe 3');
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
  mExpected := Group1 + Group2 + Group3;
  mActual := AllIds;
  Assert.AreEqual(string.Join(',', mExpected), string.Join(',', mActual));
end;

initialization
  TDUnitX.RegisterTestFixture(TBuiltinRegistrationTests);

end.
