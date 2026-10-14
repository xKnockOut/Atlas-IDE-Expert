unit Atlas.Core.Files.TextFile.Tests;

// Tests für das Ändern von Quelltexten auf der Platte in ihrer Kodierung (#397).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTextFileTests = class
  public
    [Test]
    procedure DetectsEncodings;
    [Test]
    procedure KeepsBytesOnRoundTrip;
    [Test]
    procedure ChecksUtf8Sequences;
    [Test]
    procedure SavesBesideAndReplaces;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Files.TextFile;

procedure TAtlasTextFileTests.DetectsEncodings;
var
  Content: TAtlasTextFileContent;
begin
  Content := TAtlasTextFile.Decode(TBytes.Create($EF, $BB, $BF, $61, $C3, $A4));
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Utf8Bom);
  Assert.AreEqual('aä', Content.Text);
  Content := TAtlasTextFile.Decode(TBytes.Create($61, $C3, $A4));
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Utf8);
  Assert.AreEqual('aä', Content.Text);
  Content := TAtlasTextFile.Decode(TBytes.Create($FF, $FE, $61, $00));
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Utf16LE);
  Assert.AreEqual('a', Content.Text);
  Content := TAtlasTextFile.Decode(TBytes.Create($FE, $FF, $00, $61));
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Utf16BE);
  Assert.AreEqual('a', Content.Text);
  // $E4 allein ist kein UTF-8: ANSI wie in der IDE.
  Content := TAtlasTextFile.Decode(TBytes.Create($61, $E4));
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Ansi);
  Content := TAtlasTextFile.Decode(nil);
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Utf8);
  Assert.AreEqual('', Content.Text);
end;

function Hex(const ABytes: TBytes): string;
var
  Value: Byte;
begin
  Result := '';
  for Value in ABytes do
    Result := Result + IntToHex(Value, 2) + ' ';
end;

procedure TAtlasTextFileTests.KeepsBytesOnRoundTrip;
var
  Samples: TArray<TBytes>;
  Sample: TBytes;
begin
  Samples := [TBytes.Create($EF, $BB, $BF, $61, $0D, $0A, $C3, $A4), TBytes.Create($61, $0A, $C3, $A4),
    TBytes.Create($FF, $FE, $61, $00, $0D, $00), TBytes.Create($FE, $FF, $00, $61), TBytes.Create($61, $E4, $0D, $0A)];
  for Sample in Samples do
    Assert.AreEqual(Hex(Sample), Hex(TAtlasTextFile.Encode(TAtlasTextFile.Decode(Sample))));
end;

procedure TAtlasTextFileTests.ChecksUtf8Sequences;
begin
  Assert.IsTrue(TAtlasTextFile.IsUtf8(TBytes.Create($61, $62)));
  Assert.IsTrue(TAtlasTextFile.IsUtf8(TBytes.Create($F0, $9F, $98, $80)));
  Assert.IsFalse(TAtlasTextFile.IsUtf8(TBytes.Create($C3)), 'abgeschnitten');
  Assert.IsFalse(TAtlasTextFile.IsUtf8(TBytes.Create($C3, $41)), 'Folgebyte fehlt');
  Assert.IsFalse(TAtlasTextFile.IsUtf8(TBytes.Create($C0, $80)), 'überlang');
  Assert.IsFalse(TAtlasTextFile.IsUtf8(TBytes.Create($80)));
end;

procedure TAtlasTextFileTests.SavesBesideAndReplaces;
var
  Folder, FileName: string;
  Content: TAtlasTextFileContent;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Folder);
  try
    FileName := TPath.Combine(Folder, 'A.pas');
    TFile.WriteAllBytes(FileName, TBytes.Create($EF, $BB, $BF, $61));
    Content := TAtlasTextFile.Load(FileName);
    Content.Text := Content.Text + 'ä';
    TAtlasTextFile.Save(FileName, Content);
    Assert.AreEqual<NativeInt>(6, Length(TFile.ReadAllBytes(FileName)));
    Assert.IsFalse(TFile.Exists(FileName + '.atlas-tmp'), 'keine Nachbardatei übrig');
    Assert.AreEqual('aä', TAtlasTextFile.Load(FileName).Text);
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTextFileTests);

end.
