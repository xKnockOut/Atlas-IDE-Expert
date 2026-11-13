unit Atlas.Text.PeImage.Tests;

// Tests für den Kopf von EXE/DLL (PE32 und PE32+) und den Vergleich mit der
// Map-Datei (#74). Die Bytes baut der Test selbst: DOS-Kopf, Signatur,
// COFF-Kopf, optionaler Kopf und Abschnittstabelle mit .text und .data.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPeImageTests = class
  public
    [Test]
    procedure ReadsPe32;
    [Test]
    procedure ReadsPe32Plus;
    [Test]
    procedure RejectsOtherBytes;
    [Test]
    procedure MapMatchesByEntryPoint;
    [Test]
    procedure MapDiffersByEntryPoint;
    [Test]
    procedure MapComparedByCodeSizeWithoutEntryPoint;
    [Test]
    procedure UnknownWithoutImage;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.MapFile,
  Atlas.Text.PeImage;

const
  cHeaderAt = $40;
  cOptionalSize32 = $E0;
  cOptionalSize64 = $F0;
  cTimeStamp = $6550A1B2;

  cMap =
    ' Start         Length     Name                   Class'#13#10 +
    ' 0001:00401000 0000A000H .text                   CODE'#13#10 +
    #13#10 +
    '  Address             Publics by Value'#13#10 +
    #13#10 +
    ' 0001:00000000       System.TObject.Create'#13#10 +
    #13#10 +
    'Program entry point at 0001:00000180'#13#10;

procedure Put(var ABytes: TBytes; AOffset: Integer; AValue: UInt64; ASize: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ASize - 1 do
  begin
    ABytes[AOffset + mIndex] := Byte(AValue shr (8 * mIndex));
  end;
end;

procedure PutSection(var ABytes: TBytes; AOffset: Integer; const AName: AnsiString; AVirtualSize, AAddress: Cardinal);
var
  mIndex: Integer;
begin
  for mIndex := 1 to Length(AName) do
  begin
    ABytes[AOffset + mIndex - 1] := Byte(AName[mIndex]);
  end;
  Put(ABytes, AOffset + 8, AVirtualSize, 4);
  Put(ABytes, AOffset + 12, AAddress, 4);
end;

/// <summary>Kleinste PE-Datei mit .data vor .text, damit die Suche nach dem Namen zählt.</summary>
function Image(AIs64: Boolean; AEntryPoint, ACodeSize: Cardinal): TBytes;
var
  mOptional, mSections, mOptionalSize: Integer;
begin
  mOptionalSize := cOptionalSize32;
  if AIs64 then
  begin
    mOptionalSize := cOptionalSize64;
  end;
  SetLength(Result, $400);
  FillChar(Result[0], Length(Result), 0);
  Put(Result, 0, $5A4D, 2);
  Put(Result, $3C, cHeaderAt, 4);
  Put(Result, cHeaderAt, $00004550, 4);
  Put(Result, cHeaderAt + 6, 2, 2);
  Put(Result, cHeaderAt + 8, cTimeStamp, 4);
  Put(Result, cHeaderAt + 20, mOptionalSize, 2);
  mOptional := cHeaderAt + 24;
  Put(Result, mOptional + 16, AEntryPoint, 4);
  if AIs64 then
  begin
    Put(Result, mOptional, $20B, 2);
    Put(Result, mOptional + 24, $140000000, 8);
  end
  else
  begin
    Put(Result, mOptional, $10B, 2);
    Put(Result, mOptional + 28, $400000, 4);
  end;
  mSections := mOptional + mOptionalSize;
  PutSection(Result, mSections, '.data', $2000, $B000);
  PutSection(Result, mSections + 40, '.text', ACodeSize, $1000);
end;

procedure TPeImageTests.ReadsPe32;
var
  mImage: TPeImage;
begin
  mImage := TPeImage.Read(Image(False, $1180, $A000));
  Assert.IsTrue(mImage.Valid);
  Assert.IsFalse(mImage.Is64);
  Assert.AreEqual<UInt64>($400000, mImage.ImageBase);
  Assert.AreEqual<UInt64>($1180, mImage.EntryPoint);
  Assert.AreEqual<UInt64>($1000, mImage.CodeStart);
  Assert.AreEqual<UInt64>($A000, mImage.CodeSize);
  Assert.AreEqual<Cardinal>(cTimeStamp, mImage.TimeStamp);
end;

procedure TPeImageTests.ReadsPe32Plus;
var
  mImage: TPeImage;
begin
  mImage := TPeImage.Read(Image(True, $2000, $5000));
  Assert.IsTrue(mImage.Valid);
  Assert.IsTrue(mImage.Is64);
  Assert.AreEqual<UInt64>($140000000, mImage.ImageBase);
  Assert.AreEqual<UInt64>($2000, mImage.EntryPoint);
  Assert.AreEqual<UInt64>($5000, mImage.CodeSize);
end;

procedure TPeImageTests.RejectsOtherBytes;
var
  mBytes: TBytes;
begin
  Assert.IsFalse(TPeImage.Read(nil).Valid);
  Assert.IsFalse(TPeImage.Read(TEncoding.UTF8.GetBytes('unit Main; interface end.')).Valid);
  // MZ, aber der Verweis auf den PE-Kopf zeigt hinter das Ende.
  mBytes := Image(False, $1180, $A000);
  Put(mBytes, $3C, $10000, 4);
  Assert.IsFalse(TPeImage.Read(mBytes).Valid);
  mBytes := nil;
end;

procedure TPeImageTests.MapMatchesByEntryPoint;
var
  mMap: TMapFile;
begin
  mMap := TMapFile.Create(cMap);
  try
    Assert.AreEqual<TMapImageMatch>(TMapImageMatch.Matches,
      TMapImageCheck.Compare(mMap, TPeImage.Read(Image(False, $1180, $A000))));
  finally
    mMap.Free;
  end;
end;

procedure TPeImageTests.MapDiffersByEntryPoint;
var
  mMap: TMapFile;
begin
  mMap := TMapFile.Create(cMap);
  try
    Assert.AreEqual<TMapImageMatch>(TMapImageMatch.EntryPointDiffers,
      TMapImageCheck.Compare(mMap, TPeImage.Read(Image(False, $1190, $A000))));
  finally
    mMap.Free;
  end;
end;

procedure TPeImageTests.MapComparedByCodeSizeWithoutEntryPoint;
var
  mMap: TMapFile;
begin
  mMap := TMapFile.Create(StringReplace(cMap, 'Program entry point at 0001:00000180', '', []));
  try
    Assert.AreEqual<TMapImageMatch>(TMapImageMatch.Matches,
      TMapImageCheck.Compare(mMap, TPeImage.Read(Image(False, $1180, $A000))));
    Assert.AreEqual<TMapImageMatch>(TMapImageMatch.CodeSizeDiffers,
      TMapImageCheck.Compare(mMap, TPeImage.Read(Image(False, $1180, $A100))));
  finally
    mMap.Free;
  end;
end;

procedure TPeImageTests.UnknownWithoutImage;
var
  mMap: TMapFile;
begin
  mMap := TMapFile.Create(cMap);
  try
    Assert.AreEqual<TMapImageMatch>(TMapImageMatch.Unknown, TMapImageCheck.Compare(mMap, TPeImage.Read(nil)));
    Assert.AreEqual<TMapImageMatch>(TMapImageMatch.Unknown,
      TMapImageCheck.Compare(nil, TPeImage.Read(Image(False, $1180, $A000))));
  finally
    mMap.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPeImageTests);

end.
