unit Atlas.Core.Files.TextFile.Tests;

// Tests für das Ändern von Quelltexten auf der Platte in ihrer Kodierung (#397),
// Vorgabe-Codepage und binäre Formulare (#121).

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
    [Test]
    procedure AnsiDefaultCodePage;
    [Test]
    procedure PureAsciiFollowsDefault;
    [Test]
    procedure ParsesCodePages;
    [Test]
    procedure NeverTouchesBinaryForms;
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

procedure TAtlasTextFileTests.AnsiDefaultCodePage;
var
  Source: TBytes;
  Content: TAtlasTextFileContent;
begin
  // "Š" ist in Codepage 1250 $8A; außerhalb der Änderung bleibt jedes Byte gleich.
  Source := TBytes.Create($8A, $0D, $0A, Ord('x'));
  Content := TAtlasTextFile.Decode(Source, 1250);
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Ansi);
  Assert.AreEqual(1250, Content.CodePage);
  Assert.AreEqual(#$0160#13#10'x', Content.Text);
  Content.Text := StringReplace(Content.Text, 'x', 'y', []);
  Assert.AreEqual(Hex(TBytes.Create($8A, $0D, $0A, Ord('y'))), Hex(TAtlasTextFile.Encode(Content)));
  // Gültiges UTF-8 bleibt UTF-8, auch mit ANSI-Vorgabe.
  Assert.IsTrue(TAtlasTextFile.Decode(TBytes.Create($61, $C3, $A4), 1250).Encoding = TAtlasTextEncoding.Utf8);
  // Vorgabe UTF-8: ANSI in der Codepage des Systems.
  Assert.AreEqual(0, TAtlasTextFile.Decode(TBytes.Create($61, $E4), TAtlasTextFile.Utf8CodePage).CodePage);
end;

procedure TAtlasTextFileTests.PureAsciiFollowsDefault;
var
  Content: TAtlasTextFileContent;
begin
  Content := TAtlasTextFile.Decode(TBytes.Create($61), 1250);
  Assert.IsTrue(Content.Encoding = TAtlasTextEncoding.Ansi);
  Content.Text := Content.Text + #$010D;
  Assert.AreEqual(Hex(TBytes.Create($61, $E8)), Hex(TAtlasTextFile.Encode(Content)));
  Assert.IsTrue(TAtlasTextFile.Decode(TBytes.Create($61)).Encoding = TAtlasTextEncoding.Utf8);
end;

procedure TAtlasTextFileTests.ParsesCodePages;
var
  CodePage: Integer;
begin
  Assert.IsTrue(TAtlasTextFile.ParseCodePage('utf-8', CodePage));
  Assert.AreEqual(65001, CodePage);
  Assert.IsTrue(TAtlasTextFile.ParseCodePage(' Windows-1251 ', CodePage));
  Assert.AreEqual(1251, CodePage);
  Assert.IsTrue(TAtlasTextFile.ParseCodePage('cp1250', CodePage));
  Assert.AreEqual(1250, CodePage);
  Assert.IsFalse(TAtlasTextFile.ParseCodePage('932', CodePage));
  Assert.IsFalse(TAtlasTextFile.ParseCodePage('latin9', CodePage));
  Assert.AreEqual(0, CodePage);
end;

procedure TAtlasTextFileTests.NeverTouchesBinaryForms;
var
  Folder, FileName: string;
  Source: TBytes;
  Content: TAtlasTextFileContent;
begin
  Assert.IsTrue(TAtlasTextFile.IsBinaryForm(TBytes.Create($FF, $0A, $00, $54)));
  Assert.IsFalse(TAtlasTextFile.IsBinaryForm(TBytes.Create(Ord('o'), Ord('b'))));
  Folder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Folder);
  try
    FileName := TPath.Combine(Folder, 'Form1.dfm');
    Source := TBytes.Create(Ord('T'), Ord('P'), Ord('F'), Ord('0'), 6, $E4);
    TFile.WriteAllBytes(FileName, Source);
    Assert.WillRaise(
      procedure
      begin
        TAtlasTextFile.Load(FileName);
      end, EAtlasTextFileError);
    Content.Text := 'object Form1: TForm1'#13#10'end';
    Content.Encoding := TAtlasTextEncoding.Utf8;
    Content.CodePage := 0;
    Assert.WillRaise(
      procedure
      begin
        TAtlasTextFile.Save(FileName, Content);
      end, EAtlasTextFileError);
    Assert.AreEqual(Hex(Source), Hex(TFile.ReadAllBytes(FileName)));
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTextFileTests);

end.
