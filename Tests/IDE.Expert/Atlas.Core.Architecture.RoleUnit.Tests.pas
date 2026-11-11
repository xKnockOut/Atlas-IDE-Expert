unit Atlas.Core.Architecture.RoleUnit.Tests;

// Tests des Assistenten „Unit nach Architekturrolle“ (#1821): Name, Prüfung der
// Angaben, Importregel je Rolle, Gerüst, Präfixe aus "rules" und Ordner.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasRoleUnitTests = class
  public
    [Test]
    procedure NameWithAndWithoutRole;
    [Test]
    procedure ChecksInput;
    [Test]
    procedure ImportsFollowTheMatrix;
    [Test]
    procedure TextUsesOwnContract;
    [Test]
    procedure PrefixesFromRules;
    [Test]
    procedure FolderNextToRoleOrFeature;
  end;

implementation

uses
  Atlas.Core.Architecture.RoleUnit;

function Input(const APrefix, AFeature: string; ARole: TAtlasArchitectureRole;
  const AThing: string): TAtlasRoleUnitInput;
begin
  Result.Prefix := APrefix;
  Result.Feature := AFeature;
  Result.Role := ARole;
  Result.Thing := AThing;
end;

procedure Expect(AExpected, AActual: TAtlasRoleUnitProblem);
begin
  Assert.AreEqual(Ord(AExpected), Ord(AActual));
end;

procedure TAtlasRoleUnitTests.NameWithAndWithoutRole;
begin
  Assert.AreEqual('Atlas.Common.Rules.Providers.Json',
    TAtlasRoleUnit.UnitName(Input(' Atlas.Common ', 'Rules', TAtlasArchitectureRole.Providers, 'Json ')));
  Assert.AreEqual('Atlas.Common.Product.Version',
    TAtlasRoleUnit.UnitName(Input('Atlas.Common', 'Product', TAtlasArchitectureRole.Root, 'Version')));
  Assert.AreEqual('Atlas.Common.Rules.Contract',
    TAtlasRoleUnit.UnitName(Input('Atlas.Common', 'Rules', TAtlasArchitectureRole.Contract, '')));
  Assert.AreEqual('Atlas.Text.Lines', TAtlasRoleUnit.UnitName(Input('Atlas.Text', 'Lines',
    TAtlasArchitectureRole.Root, '')));
end;

procedure TAtlasRoleUnitTests.ChecksInput;
begin
  Expect(TAtlasRoleUnitProblem.None, TAtlasRoleUnit.Check(Input('Atlas.Common', 'Rules',
    TAtlasArchitectureRole.Internals, 'Builtin.Style')));
  Expect(TAtlasRoleUnitProblem.NoPrefix, TAtlasRoleUnit.Check(Input(' ', 'Rules',
    TAtlasArchitectureRole.Root, '')));
  Expect(TAtlasRoleUnitProblem.BadPrefix, TAtlasRoleUnit.Check(Input('Atlas..Common', 'Rules',
    TAtlasArchitectureRole.Root, '')));
  Expect(TAtlasRoleUnitProblem.NoFeature, TAtlasRoleUnit.Check(Input('Atlas.Common', '',
    TAtlasArchitectureRole.Root, '')));
  Expect(TAtlasRoleUnitProblem.BadFeature, TAtlasRoleUnit.Check(Input('Atlas.Common', 'Two.Parts',
    TAtlasArchitectureRole.Root, '')));
  Expect(TAtlasRoleUnitProblem.ReservedFeature, TAtlasRoleUnit.Check(Input('Atlas.Common', 'core',
    TAtlasArchitectureRole.Root, '')));
  Expect(TAtlasRoleUnitProblem.BadThing, TAtlasRoleUnit.Check(Input('Atlas.Common', 'Rules',
    TAtlasArchitectureRole.Root, '1Json')));
  Expect(TAtlasRoleUnitProblem.ReservedThing, TAtlasRoleUnit.Check(Input('Atlas.Common', 'Rules',
    TAtlasArchitectureRole.Root, 'Json.Adapters')));
end;

procedure TAtlasRoleUnitTests.ImportsFollowTheMatrix;
var
  mOwn, mForeign: TArray<TAtlasArchitectureRole>;
begin
  TAtlasRoleUnit.Imports(TAtlasArchitectureRole.Contract, mOwn, mForeign);
  Assert.AreEqual('Contract', TAtlasRoleUnit.RoleList(mOwn, 'Root'));
  Assert.AreEqual('Contract', TAtlasRoleUnit.RoleList(mForeign, 'Root'));
  TAtlasRoleUnit.Imports(TAtlasArchitectureRole.Internals, mOwn, mForeign);
  Assert.AreEqual('Contract, Internals', TAtlasRoleUnit.RoleList(mOwn, 'Root'));
  Assert.AreEqual('Contract, Wurzel', TAtlasRoleUnit.RoleList(mForeign, 'Wurzel'));
  TAtlasRoleUnit.Imports(TAtlasArchitectureRole.Providers, mOwn, mForeign);
  Assert.AreEqual('Contract, Internals, Root', TAtlasRoleUnit.RoleList(mOwn, 'Root'));
  TAtlasRoleUnit.Imports(TAtlasArchitectureRole.Composition, mOwn, mForeign);
  Assert.AreEqual('Contract, Providers, Adapters, Root, Composition', TAtlasRoleUnit.RoleList(mOwn, 'Root'));
  TAtlasRoleUnit.Imports(TAtlasArchitectureRole.Hosting, mOwn, mForeign);
  Assert.AreEqual(6, Integer(Length(mOwn)));
end;

procedure TAtlasRoleUnitTests.TextUsesOwnContract;
var
  mText: string;
begin
  mText := TAtlasRoleUnit.UnitText(Input('Atlas.Common', 'Rules', TAtlasArchitectureRole.Providers, 'Json'), True,
    'Eigenes Feature: Contract', 'Fremde Features: Contract', #10);
  Assert.AreEqual('unit Atlas.Common.Rules.Providers.Json;'#10#10'// Eigenes Feature: Contract'#10 +
    '// Fremde Features: Contract'#10#10'interface'#10#10'uses'#10'  Atlas.Common.Rules.Contract;'#10#10 +
    'implementation'#10#10'end.'#10, mText);
  mText := TAtlasRoleUnit.UnitText(Input('Atlas.Common', 'Rules', TAtlasArchitectureRole.Contract, ''), True, '',
    '', #10);
  Assert.AreEqual('unit Atlas.Common.Rules.Contract;'#10#10'interface'#10#10'implementation'#10#10'end.'#10, mText,
    'die Contract-Unit verwendet sich nicht selbst');
  mText := TAtlasRoleUnit.UnitText(Input('Atlas.Common', 'Rules', TAtlasArchitectureRole.Root, 'Text'), False, '',
    '', #10);
  Assert.AreEqual(0, Pos('uses', mText), 'ohne Contract im Projekt kein uses');
end;

procedure TAtlasRoleUnitTests.PrefixesFromRules;
var
  mPrefixes: TArray<string>;
begin
  mPrefixes := TAtlasRoleUnit.Prefixes('{"architecture-role-import": {"severity": "warning", ' +
    '"prefixes": ["Atlas.Common", " ", "Atlas.Common.Rules", 3]}}');
  Assert.AreEqual(2, Integer(Length(mPrefixes)));
  Assert.AreEqual('Atlas.Common.Rules', TAtlasRoleUnit.PrefixOf('atlas.common.rules.Contract', mPrefixes));
  Assert.AreEqual('Atlas.Common', TAtlasRoleUnit.PrefixOf('Atlas.Common.Lsp.Hover', mPrefixes));
  Assert.AreEqual('', TAtlasRoleUnit.PrefixOf('Atlas.CommonX.Lsp', mPrefixes));
  Assert.AreEqual(0, Integer(Length(TAtlasRoleUnit.Prefixes('{"architecture-role-import": "warning"}'))));
  Assert.AreEqual(0, Integer(Length(TAtlasRoleUnit.Prefixes('kaputt'))));
  Assert.AreEqual(0, Integer(Length(TAtlasRoleUnit.Prefixes(''))));
end;

procedure TAtlasRoleUnitTests.FolderNextToRoleOrFeature;
var
  mFiles: TArray<string>;
begin
  mFiles := ['C:\P\Main.dpr', 'C:\P\Source\Rules\Atlas.Common.Rules.Engine.pas',
    'C:\P\Source\Rules\Providers\Atlas.Common.Rules.Providers.Xml.pas'];
  Assert.AreEqual('C:\P\Source\Rules\Providers\', TAtlasRoleUnit.FolderFor(Input('Atlas.Common', 'Rules',
    TAtlasArchitectureRole.Providers, 'Json'), mFiles, 'C:\P'));
  Assert.AreEqual('C:\P\Source\Rules\', TAtlasRoleUnit.FolderFor(Input('Atlas.Common', 'Rules',
    TAtlasArchitectureRole.Adapters, 'Http'), mFiles, 'C:\P'));
  Assert.AreEqual('C:\P\', TAtlasRoleUnit.FolderFor(Input('Atlas.Common', 'Lsp', TAtlasArchitectureRole.Root,
    'Hover'), mFiles, 'C:\P\'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRoleUnitTests);

end.
