unit Atlas.Core.Files.EncodingDefault.Tests;

// Tests für die Vorgabe-Kodierung aus atlas.json im Plugin (#121).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEncodingDefaultTests = class
  public
    [Test]
    procedure ReadsEncodingSetting;
    [Test]
    procedure NearestAtlasJsonWins;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Files.EncodingDefault;

procedure TAtlasEncodingDefaultTests.ReadsEncodingSetting;
begin
  Assert.AreEqual(1250, TAtlasEncodingDefault.FromJson('{ // Altprojekt' + sLineBreak + '"encoding": "windows-1250" }'));
  Assert.AreEqual(65001, TAtlasEncodingDefault.FromJson('{"encoding": "utf-8"}'));
  // Unbekannt, fehlend oder kein JSON: UTF-8 wie beim Server; die Warnung kommt vom Server.
  Assert.AreEqual(0, TAtlasEncodingDefault.FromJson('{"encoding": "latin9"}'));
  Assert.AreEqual(0, TAtlasEncodingDefault.FromJson('{"index": {}}'));
  Assert.AreEqual(0, TAtlasEncodingDefault.FromJson('kein json'));
end;

procedure TAtlasEncodingDefaultTests.NearestAtlasJsonWins;
var
  Folder, Sub: string;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'Atlas-Encoding-' + IntToStr(Random(MaxInt)));
  Sub := TPath.Combine(Folder, 'Formulare');
  TDirectory.CreateDirectory(Sub);
  try
    TFile.WriteAllText(TPath.Combine(Folder, 'atlas.json'), '{"encoding": "1251"}');
    Assert.AreEqual(1251, TAtlasEncodingDefault.CodePageFor(TPath.Combine(Sub, 'Unit1.dfm')));
    TFile.WriteAllText(TPath.Combine(Sub, 'atlas.json'), '{"encoding": "cp1250"}');
    Assert.AreEqual(1250, TAtlasEncodingDefault.CodePageFor(TPath.Combine(Sub, 'Unit1.dfm')));
    Assert.AreEqual(1251, TAtlasEncodingDefault.CodePageFor(TPath.Combine(Folder, 'Unit2.pas')));
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEncodingDefaultTests);

end.
