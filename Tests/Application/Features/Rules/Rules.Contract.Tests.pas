unit Rules.Contract.Tests;

// Tests der Hilfen am Regelkontext (TRuleContext).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleContextTests = class
  public
    [Test]
    procedure ResolverFileNamePrefersFileName;
    [Test]
    procedure ResolverFileNameFallsBackToRelativePath;
    [Test]
    procedure ResolverFileNameFallsBackToUnitName;
    [Test]
    procedure IncludeLowersConfidence;
    [Test]
    procedure ProjectKindKeys;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Rules.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract.Group;

{ TRuleContextTests }

procedure TRuleContextTests.ResolverFileNamePrefersFileName;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.UnitName := 'Kunden';
  mContext.RelativePath := 'Src\Kunden.pas';
  mContext.FileName := 'C:\Projekt\Src\Kunden.pas';
  Assert.AreEqual('C:\Projekt\Src\Kunden.pas', mContext.ResolverFileName);
  mContext := Default(TRuleContext);
end;

procedure TRuleContextTests.ResolverFileNameFallsBackToRelativePath;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.UnitName := 'Daten';
  mContext.RelativePath := 'Src/Daten.pas';
  Assert.AreEqual('Src/Daten.pas', mContext.ResolverFileName);
  mContext := Default(TRuleContext);
end;

procedure TRuleContextTests.ResolverFileNameFallsBackToUnitName;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.UnitName := 'Kunden';
  Assert.AreEqual('Kunden.pas', mContext.ResolverFileName);
  mContext := Default(TRuleContext);
end;

procedure TRuleContextTests.IncludeLowersConfidence;
begin
  Assert.AreEqual<TRuleConfidence>(TRuleConfidence.High, IncludeConfidence(TPascalLexer.Tokenize('unit U; {$R *.res}')));
  Assert.AreEqual<TRuleConfidence>(TRuleConfidence.Medium, IncludeConfidence(TPascalLexer.Tokenize('{$I Defs.inc}')));
  Assert.AreEqual<TRuleConfidence>(TRuleConfidence.Medium, IncludeConfidence(TPascalLexer.Tokenize('{$include a.inc}')));
end;

procedure TRuleContextTests.ProjectKindKeys;
begin
  Assert.AreEqual('application', ProjectKindKey(TGroupProjectKind.Application));
  Assert.AreEqual('package', ProjectKindKey(TGroupProjectKind.Package));
  Assert.AreEqual('library', ProjectKindKey(TGroupProjectKind.Library_));
  Assert.AreEqual('', ProjectKindKey(TGroupProjectKind.Unknown));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleContextTests);

end.
