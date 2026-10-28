unit Atlas.Common.Lsp.CompactJson.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompactJsonTests = class
  public
    [Test]
    procedure RoundTripKeepsDiagnostics;
    [Test]
    procedure NonAsciiSurvives;
    [Test]
    procedure EmptyAndInvalidGiveEmptyArray;
    [Test]
    procedure PackedIsSmallerThanText;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.CompactJson;

function Diagnostic(ALine: Integer; const AMessage: string): TJSONObject;
var
  mRange, mStart, mEnd: TJSONObject;
begin
  mStart := TJSONObject.Create;
  mStart.AddPair('line', TJSONNumber.Create(ALine));
  mStart.AddPair('character', TJSONNumber.Create(2));
  mEnd := TJSONObject.Create;
  mEnd.AddPair('line', TJSONNumber.Create(ALine));
  mEnd.AddPair('character', TJSONNumber.Create(9));
  mRange := TJSONObject.Create;
  mRange.AddPair('start', mStart);
  mRange.AddPair('end', mEnd);
  Result := TJSONObject.Create;
  Result.AddPair('range', mRange);
  Result.AddPair('severity', TJSONNumber.Create(2));
  Result.AddPair('code', 'RL1001');
  Result.AddPair('source', 'Atlas');
  Result.AddPair('message', AMessage);
end;

procedure TCompactJsonTests.RoundTripKeepsDiagnostics;
var
  mItems, mBack: TJSONArray;
begin
  mItems := TJSONArray.Create;
  mBack := nil;
  try
    mItems.AddElement(Diagnostic(3, 'Variable wird nicht verwendet'));
    mItems.AddElement(Diagnostic(7, 'Leerer Block'));
    mBack := TCompactJson.UnpackArray(TCompactJson.Pack(mItems));
    Assert.AreEqual(mItems.ToJSON, mBack.ToJSON);
    Assert.AreEqual(2, mBack.Count);
    Assert.AreEqual(7, (mBack.Items[1] as TJSONObject).GetValue<Integer>('range.start.line'));
  finally
    mBack.Free;
    mItems.Free;
  end;
end;

procedure TCompactJsonTests.NonAsciiSurvives;
var
  mItems, mBack: TJSONArray;
begin
  mItems := TJSONArray.Create;
  mBack := nil;
  try
    mItems.AddElement(Diagnostic(1, 'Größe „äöü“ €'));
    mItems.AddElement(Diagnostic(2, 'Tab'#9'Zeile'#10'Steuer'#1));
    mBack := TCompactJson.UnpackArray(TCompactJson.Pack(mItems));
    Assert.AreEqual('Größe „äöü“ €', (mBack.Items[0] as TJSONObject).GetValue<string>('message'));
    Assert.AreEqual('Tab'#9'Zeile'#10'Steuer'#1, (mBack.Items[1] as TJSONObject).GetValue<string>('message'));
  finally
    mBack.Free;
    mItems.Free;
  end;
end;

procedure TCompactJsonTests.EmptyAndInvalidGiveEmptyArray;
var
  mBack: TJSONArray;
begin
  Assert.AreEqual(0, Integer(Length(TCompactJson.Pack(nil))));
  mBack := TCompactJson.UnpackArray(nil);
  try
    Assert.AreEqual(0, mBack.Count);
  finally
    mBack.Free;
  end;
  mBack := TCompactJson.UnpackArray(TEncoding.UTF8.GetBytes('{"kein":"Array"}'));
  try
    Assert.AreEqual(0, mBack.Count);
  finally
    mBack.Free;
  end;
  mBack := TCompactJson.UnpackArray(TEncoding.UTF8.GetBytes('[{'));
  try
    Assert.AreEqual(0, mBack.Count);
  finally
    mBack.Free;
  end;
end;

procedure TCompactJsonTests.PackedIsSmallerThanText;
var
  mItems: TJSONArray;
  mIndex: Integer;
begin
  // UTF-8 statt UTF-16: Die Ablage braucht höchstens die Hälfte des JSON-Texts als string.
  mItems := TJSONArray.Create;
  try
    for mIndex := 1 to 50 do
      mItems.AddElement(Diagnostic(mIndex, 'Bezeichner sollte mit m beginnen'));
    Assert.IsTrue(Length(TCompactJson.Pack(mItems)) * 2 <= Length(mItems.ToJSON) * SizeOf(Char));
  finally
    mItems.Free;
  end;
end;

end.
