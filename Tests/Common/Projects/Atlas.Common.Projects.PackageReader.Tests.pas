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
  Source: TPackageSource;
begin
  Source := TPackageReader.Read(
    'package Kasse.Core;'#10 +
    '{$R *.res}'#10 +
    'requires'#10 +
    '  rtl,'#10 +
    '  vcl;'#10 +
    'contains'#10 +
    '  uBeleg in ''Quellen\uBeleg.pas'','#10 +
    '  Kasse.Steuer;'#10 +
    'end.');
  Assert.IsTrue(Source.IsPackage);
  Assert.AreEqual('Kasse.Core', Source.Name);
  Assert.AreEqual(2, Integer(Length(Source.Requires)));
  Assert.AreEqual('vcl', Source.Requires[1].Name);
  Assert.IsTrue(Source.RequiresPackage('VCL'));
  Assert.AreEqual(2, Integer(Length(Source.Contains)));
  Assert.AreEqual('uBeleg', Source.Contains[0].Name);
  Assert.AreEqual('Quellen\uBeleg.pas', Source.Contains[0].Path);
  Assert.AreEqual(6, Source.Contains[0].Range.StartPos.Line);
  Assert.AreEqual(2, Source.Contains[0].Range.StartPos.Character);
  Assert.AreEqual(8, Source.Contains[0].Range.EndPos.Character);
  Assert.AreEqual('Kasse.Steuer', Source.Contains[1].Name);
  Assert.AreEqual('', Source.Contains[1].Path);
  Assert.AreEqual(1, Source.ContainsIndex('kasse.steuer'));
  Assert.AreEqual(-1, Source.ContainsIndex('uRunden'));
  Assert.IsTrue(Source.HasContains);
  Assert.AreEqual(7, Source.ContainsEnd.Line);
  Assert.AreEqual(14, Source.ContainsEnd.Character);
end;

procedure TPackageReaderTests.SkipsCommentsAndDirectives;
var
  Source: TPackageSource;
begin
  Source := TPackageReader.Read(
    '// Kopf'#10 +
    'package P;'#10 +
    'requires rtl { Laufzeit }, (* VCL *) vcl;'#10 +
    'contains A, {$IFDEF X} B, {$ENDIF} C;'#10 +
    'end.');
  Assert.AreEqual(2, Integer(Length(Source.Requires)));
  Assert.AreEqual('A,B,C', Source.Contains[0].Name + ',' + Source.Contains[1].Name + ',' + Source.Contains[2].Name);
end;

procedure TPackageReaderTests.UnitIsNoPackage;
var
  Source: TPackageSource;
begin
  Source := TPackageReader.Read('unit A;'#10'interface'#10'uses B;'#10'implementation'#10'end.');
  Assert.IsFalse(Source.IsPackage);
  Assert.AreEqual(0, Integer(Length(Source.Contains)));
end;

procedure TPackageReaderTests.PackageWithoutContains;
var
  Source: TPackageSource;
begin
  Source := TPackageReader.Read('package Leer;'#10'requires rtl;'#10'end.');
  Assert.IsTrue(Source.IsPackage);
  Assert.IsFalse(Source.HasContains);
  Assert.AreEqual(1, Integer(Length(Source.Requires)));
end;

procedure TPackageReaderTests.InsertionFollowsLineBreak;
begin
  Assert.AreEqual(','#13#10'  uRunden in ''uRunden.pas''',
    TPackageReader.ContainsInsertion('uRunden', 'uRunden.pas', #13#10));
  Assert.AreEqual(','#10'  uRunden', TPackageReader.ContainsInsertion('uRunden', '', #10));
  Assert.AreEqual(','#10'  A in ''O''''Brien.pas''', TPackageReader.ContainsInsertion('A', 'O''Brien.pas', #10));
end;

end.
