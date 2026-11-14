unit Atlas.Common.Projects.PackageReader.Tests;

// Tests des Lesers für requires und contains einer .dpk (#46).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPackageReaderTests = class
  public
    [Test]
    procedure ReadsRequiresAndContains;
    [Test]
    procedure SkipsCommentsAndDirectives;
    [Test]
    procedure UnitIsNoPackage;
    [Test]
    procedure PackageWithoutContains;
    [Test]
    procedure InsertionFollowsLineBreak;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Projects.PackageReader;

procedure TPackageReaderTests.ReadsRequiresAndContains;
var
  mSource: TPackageSource;
begin
  mSource := TPackageReader.Read(
    'package Kasse.Core;'#10 +
    '{$R *.res}'#10 +
    'requires'#10 +
    '  rtl,'#10 +
    '  vcl;'#10 +
    'contains'#10 +
    '  uBeleg in ''Quellen\uBeleg.pas'','#10 +
    '  Kasse.Steuer;'#10 +
    'end.');
  Assert.IsTrue(mSource.IsPackage);
  Assert.AreEqual('Kasse.Core', mSource.Name);
  Assert.AreEqual(2, Integer(Length(mSource.Requires)));
  Assert.AreEqual('vcl', mSource.Requires[1].Name);
  Assert.IsTrue(mSource.RequiresPackage('VCL'));
  Assert.AreEqual(2, Integer(Length(mSource.Contains)));
  Assert.AreEqual('uBeleg', mSource.Contains[0].Name);
  Assert.AreEqual('Quellen\uBeleg.pas', mSource.Contains[0].Path);
  Assert.AreEqual(6, mSource.Contains[0].Range.StartPos.Line);
  Assert.AreEqual(2, mSource.Contains[0].Range.StartPos.Character);
  Assert.AreEqual(8, mSource.Contains[0].Range.EndPos.Character);
  Assert.AreEqual('Kasse.Steuer', mSource.Contains[1].Name);
  Assert.AreEqual('', mSource.Contains[1].Path);
  Assert.AreEqual(1, mSource.ContainsIndex('kasse.steuer'));
  Assert.AreEqual(-1, mSource.ContainsIndex('uRunden'));
  Assert.IsTrue(mSource.HasContains);
  Assert.AreEqual(7, mSource.ContainsEnd.Line);
  Assert.AreEqual(14, mSource.ContainsEnd.Character);
end;

procedure TPackageReaderTests.SkipsCommentsAndDirectives;
var
  mSource: TPackageSource;
begin
  mSource := TPackageReader.Read(
    '// Kopf'#10 +
    'package P;'#10 +
    'requires rtl { Laufzeit }, (* VCL *) vcl;'#10 +
    'contains A, {$IFDEF X} B, {$ENDIF} C;'#10 +
    'end.');
  Assert.AreEqual(2, Integer(Length(mSource.Requires)));
  Assert.AreEqual('A,B,C', mSource.Contains[0].Name + ',' + mSource.Contains[1].Name + ',' + mSource.Contains[2].Name);
end;

procedure TPackageReaderTests.UnitIsNoPackage;
var
  mSource: TPackageSource;
begin
  mSource := TPackageReader.Read('unit A;'#10'interface'#10'uses B;'#10'implementation'#10'end.');
  Assert.IsFalse(mSource.IsPackage);
  Assert.AreEqual(0, Integer(Length(mSource.Contains)));
end;

procedure TPackageReaderTests.PackageWithoutContains;
var
  mSource: TPackageSource;
begin
  mSource := TPackageReader.Read('package Leer;'#10'requires rtl;'#10'end.');
  Assert.IsTrue(mSource.IsPackage);
  Assert.IsFalse(mSource.HasContains);
  Assert.AreEqual(1, Integer(Length(mSource.Requires)));
end;

procedure TPackageReaderTests.InsertionFollowsLineBreak;
begin
  Assert.AreEqual(','#13#10'  uRunden in ''uRunden.pas''',
    TPackageReader.ContainsInsertion('uRunden', 'uRunden.pas', #13#10));
  Assert.AreEqual(','#10'  uRunden', TPackageReader.ContainsInsertion('uRunden', '', #10));
  Assert.AreEqual(','#10'  A in ''O''''Brien.pas''', TPackageReader.ContainsInsertion('A', 'O''Brien.pas', #10));
end;

end.
