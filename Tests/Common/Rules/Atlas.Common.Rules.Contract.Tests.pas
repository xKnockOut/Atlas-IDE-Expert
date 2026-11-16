unit Atlas.Common.Rules.Contract.Tests;

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
  end;

implementation

uses
  Atlas.Common.Rules.Contract;

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

initialization
  TDUnitX.RegisterTestFixture(TRuleContextTests);

end.
