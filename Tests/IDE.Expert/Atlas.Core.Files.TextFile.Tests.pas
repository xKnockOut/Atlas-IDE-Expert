unit Atlas.Core.Files.TextFile.Tests;

// Tests für das Ändern von Quelltexten auf der Platte in ihrer Kodierung (#397),
// Vorgabe-Codepage und binäre Formulare (#121), atomares Ersetzen und Lesen
// ohne Sperre.

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
    procedure LoadTextAndLines;
    [Test]
    procedure ReplacesFileHeldOpenByOthers;
    /// <summary>Hält ein fremdes Programm die Datei ohne FILE_SHARE_DELETE offen, scheitert Save nach dem Netz
    /// und lässt die Datei, wie sie war (früher: an Ort und Stelle überschrieben).</summary>
    [Test]
    procedure KeepsFileLockedByOthers;
    /// <summary>ReadAllBytes teilt Löschen: Es liest, während ein anderer die Datei zum Ersetzen offen hat.</summary>
    [Test]
    procedure ReadAllBytesDoesNotBlockReplace;
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
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Files.TextFile;

procedure TAtlasTextFileTests.DetectsEncodings;
var
  mContent: TAtlasTextFileContent;
begin
  mContent := TAtlasTextFile.Decode(TBytes.Create($EF, $BB, $BF, $61, $C3, $A4));
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf8Bom, mContent.Encoding);
  Assert.AreEqual('aä', mContent.Text);
  mContent := TAtlasTextFile.Decode(TBytes.Create($61, $C3, $A4));
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf8, mContent.Encoding);
  Assert.AreEqual('aä', mContent.Text);
  mContent := TAtlasTextFile.Decode(TBytes.Create($FF, $FE, $61, $00));
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf16LE, mContent.Encoding);
  Assert.AreEqual('a', mContent.Text);
  mContent := TAtlasTextFile.Decode(TBytes.Create($FE, $FF, $00, $61));
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf16BE, mContent.Encoding);
  Assert.AreEqual('a', mContent.Text);
  // $E4 allein ist kein UTF-8: ANSI wie in der IDE.
  mContent := TAtlasTextFile.Decode(TBytes.Create($61, $E4));
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Ansi, mContent.Encoding);
  mContent := TAtlasTextFile.Decode(nil);
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf8, mContent.Encoding);
  Assert.AreEqual('', mContent.Text);
end;

function Hex(const ABytes: TBytes): string;
var
  mValue: Byte;
begin
  Result := '';
  for mValue in ABytes do
  begin
    Result := Result + IntToHex(mValue, 2) + ' ';
  end;
end;

procedure TAtlasTextFileTests.KeepsBytesOnRoundTrip;
var
  mSamples: TArray<TBytes>;
  mSample: TBytes;
begin
  mSamples := [TBytes.Create($EF, $BB, $BF, $61, $0D, $0A, $C3, $A4), TBytes.Create($61, $0A, $C3, $A4),
    TBytes.Create($FF, $FE, $61, $00, $0D, $00), TBytes.Create($FE, $FF, $00, $61), TBytes.Create($61, $E4, $0D, $0A)];
  for mSample in mSamples do
  begin
    Assert.AreEqual(Hex(mSample), Hex(TAtlasTextFile.Encode(TAtlasTextFile.Decode(mSample))));
  end;
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
  mFolder, mFileName: string;
  mContent: TAtlasTextFileContent;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(mFolder);
  try
    mFileName := TPath.Combine(mFolder, 'A.pas');
    TFile.WriteAllBytes(mFileName, TBytes.Create($EF, $BB, $BF, $61));
    mContent := TAtlasTextFile.Load(mFileName);
    mContent.Text := mContent.Text + 'ä';
    TAtlasTextFile.Save(mFileName, mContent);
    Assert.AreEqual<NativeInt>(6, Length(TFile.ReadAllBytes(mFileName)));
    Assert.IsFalse(TFile.Exists(mFileName + '.atlas-tmp'), 'keine Nachbardatei übrig');
    Assert.AreEqual('aä', TAtlasTextFile.Load(mFileName).Text);
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

// UTF-8 ohne BOM liest LoadText als UTF-8 (TFile.ReadAllText nähme ANSI); LoadLines ohne leere letzte Zeile (#1109).
procedure TAtlasTextFileTests.LoadTextAndLines;
var
  mFolder, mFileName: string;
  mLines: TArray<string>;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(mFolder);
  try
    mFileName := TPath.Combine(mFolder, 'A.dproj');
    TFile.WriteAllBytes(mFileName, TBytes.Create($61, $C3, $A4, $0D, $0A, $62, $0D, $0A));
    Assert.AreEqual('a'#$E4#13#10'b'#13#10, TAtlasTextFile.LoadText(mFileName));
    mLines := TAtlasTextFile.LoadLines(mFileName);
    Assert.AreEqual(2, Integer(Length(mLines)));
    Assert.AreEqual('a'#$E4, mLines[0]);
    Assert.AreEqual('b', mLines[1]);
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TAtlasTextFileTests.ReplacesFileHeldOpenByOthers;
var
  mFolder, mFileName: string;
  mContent: TAtlasTextFileContent;
  mHandle: THandle;
  mOld: array[0..1] of Byte;
  mCount: DWORD;
begin
  // Wie ein Leser, der Löschen teilt (der Server mit TWindowsSharedRead, ReadAllBytes): Löschen und
  // Verschieben getrennt meldete „Datei bereits vorhanden“, klassisches MoveFileEx scheitert ebenso.
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(mFolder);
  try
    mFileName := TPath.Combine(mFolder, 'settings.json');
    TFile.WriteAllText(mFileName, '{}');
    mHandle := CreateFile(PChar(mFileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, mHandle);
    try
      mContent := TAtlasTextFile.Load(mFileName);
      mContent.Text := '{"metrics": false}';
      TAtlasTextFile.Save(mFileName, mContent);
      // Atomar ersetzt, nicht überschrieben: Der Leser sieht weiter den alten Stand.
      Assert.IsTrue(ReadFile(mHandle, mOld, SizeOf(mOld), mCount, nil));
      Assert.AreEqual(2, Integer(mCount));
      Assert.AreEqual(Integer(Ord('{')), Integer(mOld[0]));
      Assert.AreEqual(Integer(Ord('}')), Integer(mOld[1]));
    finally
      CloseHandle(mHandle);
    end;
    Assert.AreEqual('{"metrics": false}', TAtlasTextFile.Load(mFileName).Text);
    Assert.IsFalse(TFile.Exists(mFileName + '.atlas-tmp'), 'keine Nachbardatei übrig');
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TAtlasTextFileTests.KeepsFileLockedByOthers;
var
  mFolder, mFileName: string;
  mContent: TAtlasTextFileContent;
  mHandle: THandle;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(mFolder);
  try
    mFileName := TPath.Combine(mFolder, 'settings.json');
    TFile.WriteAllText(mFileName, '{}');
    // So las TFile.ReadAllBytes: Lesen geteilt, Löschen nicht.
    mHandle := CreateFile(PChar(mFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, 0);
    Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, mHandle);
    try
      mContent := TAtlasTextFile.Load(mFileName);
      mContent.Text := '{"metrics": false}';
      Assert.WillRaise(
        procedure
        begin
          TAtlasTextFile.Save(mFileName, mContent);
        end, EAtlasTextFileError);
    finally
      CloseHandle(mHandle);
    end;
    Assert.AreEqual('{}', TAtlasTextFile.Load(mFileName).Text);
    Assert.IsFalse(TFile.Exists(mFileName + '.atlas-tmp'), 'keine Nachbardatei übrig');
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TAtlasTextFileTests.ReadAllBytesDoesNotBlockReplace;
var
  mFolder, mFileName: string;
  mContent: TAtlasTextFileContent;
  mHandle: THandle;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(mFolder);
  try
    mFileName := TPath.Combine(mFolder, 'atlas.json');
    TFile.WriteAllText(mFileName, '{}');
    // Wie Save beim Ersetzen: offen zum Löschen. TFile.ReadAllBytes scheitert daran, ReadAllBytes nicht.
    mHandle := CreateFile(PChar(mFileName), _DELETE or SYNCHRONIZE,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    Assert.AreNotEqual<THandle>(INVALID_HANDLE_VALUE, mHandle);
    try
      Assert.AreEqual(2, Integer(Length(TAtlasTextFile.ReadAllBytes(mFileName))));
    finally
      CloseHandle(mHandle);
    end;
    Assert.WillRaise(
      procedure
      begin
        TAtlasTextFile.ReadAllBytes(TPath.Combine(mFolder, 'fehlt.json'));
      end, EFOpenError);
    mContent := TAtlasTextFile.Load(mFileName);
    mContent.Text := '{"a": 1}';
    TAtlasTextFile.Save(mFileName, mContent);
    Assert.AreEqual('{"a": 1}', TAtlasTextFile.Load(mFileName).Text);
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TAtlasTextFileTests.AnsiDefaultCodePage;
var
  mSource: TBytes;
  mContent: TAtlasTextFileContent;
begin
  // "Š" ist in Codepage 1250 $8A; außerhalb der Änderung bleibt jedes Byte gleich.
  mSource := TBytes.Create($8A, $0D, $0A, Ord('x'));
  mContent := TAtlasTextFile.Decode(mSource, 1250);
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Ansi, mContent.Encoding);
  Assert.AreEqual(1250, mContent.CodePage);
  Assert.AreEqual(#$0160#13#10'x', mContent.Text);
  mContent.Text := StringReplace(mContent.Text, 'x', 'y', []);
  Assert.AreEqual(Hex(TBytes.Create($8A, $0D, $0A, Ord('y'))), Hex(TAtlasTextFile.Encode(mContent)));
  // Gültiges UTF-8 bleibt UTF-8, auch mit ANSI-Vorgabe.
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf8,
    TAtlasTextFile.Decode(TBytes.Create($61, $C3, $A4), 1250).Encoding);
  // Vorgabe UTF-8: ANSI in der Codepage des Systems.
  Assert.AreEqual(0, TAtlasTextFile.Decode(TBytes.Create($61, $E4), TAtlasTextFile.cUtf8CodePage).CodePage);
end;

procedure TAtlasTextFileTests.PureAsciiFollowsDefault;
var
  mContent: TAtlasTextFileContent;
begin
  mContent := TAtlasTextFile.Decode(TBytes.Create($61), 1250);
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Ansi, mContent.Encoding);
  mContent.Text := mContent.Text + #$010D;
  Assert.AreEqual(Hex(TBytes.Create($61, $E8)), Hex(TAtlasTextFile.Encode(mContent)));
  Assert.AreEqual<TAtlasTextEncoding>(TAtlasTextEncoding.Utf8, TAtlasTextFile.Decode(TBytes.Create($61)).Encoding);
end;

procedure TAtlasTextFileTests.ParsesCodePages;
var
  mCodePage: Integer;
begin
  Assert.IsTrue(TAtlasTextFile.ParseCodePage('utf-8', mCodePage));
  Assert.AreEqual(65001, mCodePage);
  Assert.IsTrue(TAtlasTextFile.ParseCodePage(' Windows-1251 ', mCodePage));
  Assert.AreEqual(1251, mCodePage);
  Assert.IsTrue(TAtlasTextFile.ParseCodePage('cp1250', mCodePage));
  Assert.AreEqual(1250, mCodePage);
  Assert.IsFalse(TAtlasTextFile.ParseCodePage('932', mCodePage));
  Assert.IsFalse(TAtlasTextFile.ParseCodePage('latin9', mCodePage));
  Assert.AreEqual(0, mCodePage);
end;

procedure TAtlasTextFileTests.NeverTouchesBinaryForms;
var
  mFolder, mFileName: string;
  mSource: TBytes;
  mContent: TAtlasTextFileContent;
begin
  Assert.IsTrue(TAtlasTextFile.IsBinaryForm(TBytes.Create($FF, $0A, $00, $54)));
  Assert.IsFalse(TAtlasTextFile.IsBinaryForm(TBytes.Create(Ord('o'), Ord('b'))));
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-TextFile-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(mFolder);
  try
    mFileName := TPath.Combine(mFolder, 'Form1.dfm');
    mSource := TBytes.Create(Ord('T'), Ord('P'), Ord('F'), Ord('0'), 6, $E4);
    TFile.WriteAllBytes(mFileName, mSource);
    Assert.WillRaise(
      procedure
      begin
        TAtlasTextFile.Load(mFileName);
      end, EAtlasTextFileError);
    mContent.Text := 'object Form1: TForm1'#13#10'end';
    mContent.Encoding := TAtlasTextEncoding.Utf8;
    mContent.CodePage := 0;
    Assert.WillRaise(
      procedure
      begin
        TAtlasTextFile.Save(mFileName, mContent);
      end, EAtlasTextFileError);
    Assert.AreEqual(Hex(mSource), Hex(TFile.ReadAllBytes(mFileName)));
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTextFileTests);

end.
