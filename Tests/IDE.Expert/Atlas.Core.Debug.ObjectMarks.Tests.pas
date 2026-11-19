unit Atlas.Core.Debug.ObjectMarks.Tests;

// Tests für markierte Objekte beim Debuggen (#839): Tabelle Adresse → Etikett, Farbvergabe, „vermutlich
// freigegeben“, Klassenname aus der VMT und Vorschlag fürs Etikett; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasObjectMarksTests = class
  public
    [Test]
    procedure MarkAndFindByAddress;
    [Test]
    procedure MarkAgainKeepsColor;
    [Test]
    procedure ColorsFirstFreeThenRoundRobin;
    [Test]
    procedure SetColorWraps;
    [Test]
    procedure OtherClassMeansFreed;
    [Test]
    procedure UnknownClassKeepsMark;
    [Test]
    procedure SeenUpdatesLastPlace;
    [Test]
    procedure LabelsWithoutFreed;
    [Test]
    procedure RemoveAndClear;
    [Test]
    procedure SuggestFromClassAndName;
    [Test]
    procedure DecorateOnlyWithCaption;
    [Test]
    procedure LooksLikeObjectOnlyForFieldsOrAddress;
    [Test]
    procedure ReadClassNameWin32;
    [Test]
    procedure ReadClassNameWin64;
    [Test]
    procedure ReadClassNameRejectsGarbage;
    [Test]
    procedure PlaceTextOfWindowsPath;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Debug.InstanceBreakpoint,
  Atlas.Core.Debug.ObjectMarks;

type
  /// <summary>Speicher eines gedachten Programms: Bytes je Adresse.</summary>
  TFakeMemory = class
  private
    FBytes: TDictionary<UInt64, Byte>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure PutPointer(AAddress, AValue: UInt64; ASize: Integer);
    procedure PutName(AAddress: UInt64; const AName: string);
    function Reader: TAtlasMemoryReader;
  end;

constructor TFakeMemory.Create;
begin
  inherited Create;
  FBytes := TDictionary<UInt64, Byte>.Create;
end;

destructor TFakeMemory.Destroy;
begin
  FreeAndNil(FBytes);
  inherited Destroy;
end;

procedure TFakeMemory.PutPointer(AAddress, AValue: UInt64; ASize: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ASize - 1 do
  begin
    FBytes.AddOrSetValue(AAddress + UInt64(mIndex), Byte(AValue shr (8 * mIndex)));
  end;
end;

procedure TFakeMemory.PutName(AAddress: UInt64; const AName: string);
var
  mIndex: Integer;
begin
  FBytes.AddOrSetValue(AAddress, Byte(Length(AName)));
  for mIndex := 1 to Length(AName) do
  begin
    FBytes.AddOrSetValue(AAddress + UInt64(mIndex), Byte(Ord(AName[mIndex])));
  end;
end;

function TFakeMemory.Reader: TAtlasMemoryReader;
var
  mBytes: TDictionary<UInt64, Byte>;
begin
  mBytes := FBytes;
  Result :=
    function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean
    var
      mAt: Integer;
      mByte: Byte;
    begin
      ABytes := nil;
      SetLength(ABytes, ACount);
      for mAt := 0 to ACount - 1 do
      begin
        if not mBytes.TryGetValue(AAddress + UInt64(mAt), mByte) then
        begin
          ABytes := nil;
          Exit(False);
        end;
        ABytes[mAt] := mByte;
      end;
      Result := True;
    end;
end;

{ TAtlasObjectMarksTests }

procedure TAtlasObjectMarksTests.MarkAndFindByAddress;
var
  mMarks: TAtlasObjectMarks;
  mMark: TAtlasObjectMark;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    Assert.IsTrue(mMarks.Mark($0A3F1C20, ' Kunde A ', 'TKunde', 'Alt', 'Haupt.pas:12'));
    Assert.IsFalse(mMarks.Mark(0, 'Null', 'TKunde', 'X', ''), 'nil');
    Assert.IsFalse(mMarks.Mark($10, ' ', 'TKunde', 'X', ''), 'ohne Etikett');
    Assert.AreEqual('Kunde A', mMarks.CaptionOf($0A3F1C20));
    Assert.AreEqual('', mMarks.CaptionOf($0A3F1C24));
    Assert.IsTrue(mMarks.Find($0A3F1C20, mMark));
    Assert.AreEqual('TKunde', mMark.TypeName);
    Assert.AreEqual('Alt', mMark.LastExpression);
    Assert.AreEqual(1, mMarks.Count);
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.MarkAgainKeepsColor;
var
  mMarks: TAtlasObjectMarks;
  mMark: TAtlasObjectMark;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    mMarks.Mark($100, 'A', 'TA', 'X', '');
    mMarks.Mark($200, 'B', 'TB', 'Y', '');
    mMarks.Mark($100, 'A neu', 'TA', 'Z', 'U.pas:3');
    Assert.IsTrue(mMarks.Find($100, mMark));
    Assert.AreEqual('A neu', mMark.Caption);
    Assert.AreEqual(0, mMark.Color);
    Assert.AreEqual('Z', mMark.LastExpression);
    Assert.AreEqual(2, mMarks.Count);
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.ColorsFirstFreeThenRoundRobin;
var
  mMarks: TAtlasObjectMarks;
  mMark: TAtlasObjectMark;
  mIndex: Integer;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    for mIndex := 1 to 3 do
    begin
      mMarks.Mark(UInt64(mIndex) * $10, 'M' + IntToStr(mIndex), 'TA', 'X', '');
    end;
    mMarks.Remove($20);
    mMarks.Mark($40, 'M4', 'TA', 'X', '');
    Assert.IsTrue(mMarks.Find($40, mMark));
    Assert.AreEqual(1, mMark.Color, 'Farbe der entfernten Markierung ist wieder frei');
    for mIndex := 5 to TAtlasObjectMarks.cColorCount + 1 do
    begin
      mMarks.Mark(UInt64(mIndex) * $10, 'M' + IntToStr(mIndex), 'TA', 'X', '');
    end;
    Assert.AreEqual(TAtlasObjectMarks.cColorCount, mMarks.Count);
    mMarks.Mark($1000, 'Neunte', 'TA', 'X', '');
    Assert.IsTrue(mMarks.Find($1000, mMark));
    Assert.AreEqual(0, mMark.Color, 'alle vergeben: reihum');
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.SetColorWraps;
var
  mMarks: TAtlasObjectMarks;
  mMark: TAtlasObjectMark;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    mMarks.Mark($100, 'A', 'TA', 'X', '');
    Assert.IsTrue(mMarks.SetColor($100, TAtlasObjectMarks.cColorCount + 2));
    mMarks.Find($100, mMark);
    Assert.AreEqual(2, mMark.Color);
    Assert.IsTrue(mMarks.SetColor($100, -1));
    mMarks.Find($100, mMark);
    Assert.AreEqual(TAtlasObjectMarks.cColorCount - 1, mMark.Color);
    Assert.IsFalse(mMarks.SetColor($200, 1));
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.OtherClassMeansFreed;
var
  mMarks: TAtlasObjectMarks;
  mItems: TArray<TAtlasObjectMark>;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    mMarks.Mark($100, 'Kunde A', 'TKunde', 'Alt', '');
    Assert.IsFalse(mMarks.Check($100, 'tkunde'), 'dieselbe Klasse');
    Assert.IsTrue(mMarks.Check($100, 'TStringList'));
    Assert.IsFalse(mMarks.Check($100, 'TStringList'), 'nur einmal');
    Assert.AreEqual('', mMarks.CaptionOf($100), 'kein Etikett mehr');
    mItems := mMarks.Items;
    Assert.AreEqual(1, Integer(Length(mItems)), 'bleibt im Fenster');
    Assert.IsTrue(mItems[0].Freed);
    Assert.IsFalse(mMarks.Seen($100, 'Neu', ''), 'freigegeben wird nicht mehr gesehen');
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.UnknownClassKeepsMark;
var
  mMarks: TAtlasObjectMarks;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    mMarks.Mark($100, 'A', 'TKunde', 'X', '');
    mMarks.Mark($200, 'B', '', 'Y', '');
    Assert.IsFalse(mMarks.Check($100, ''), 'nicht lesbar');
    Assert.IsFalse(mMarks.Check($200, 'TKunde'), 'beim Markieren unbekannt');
    Assert.AreEqual('A', mMarks.CaptionOf($100));
    Assert.AreEqual('B', mMarks.CaptionOf($200));
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.SeenUpdatesLastPlace;
var
  mMarks: TAtlasObjectMarks;
  mMark: TAtlasObjectMark;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    mMarks.Mark($100, 'Kunde A', 'TKunde', 'Alt', 'Haupt.pas:12');
    Assert.IsTrue(mMarks.Seen($100, 'Ziel', 'Haupt.pas:14'));
    Assert.IsFalse(mMarks.Seen($100, 'Ziel', 'Haupt.pas:14'), 'unverändert');
    Assert.IsFalse(mMarks.Seen($300, 'Ziel', 'Haupt.pas:14'), 'nicht markiert');
    mMarks.Find($100, mMark);
    Assert.AreEqual('Ziel', mMark.LastExpression);
    Assert.AreEqual('Haupt.pas:14', mMark.LastPlace);
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.LabelsWithoutFreed;
var
  mMarks: TAtlasObjectMarks;
  mLabels: TArray<TAtlasObjectLabel>;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    mMarks.Mark($100, 'A', 'TA', 'X', '');
    mMarks.Mark($200, 'B', 'TB', 'Y', '');
    mMarks.Check($100, 'TC');
    mLabels := mMarks.Labels;
    Assert.AreEqual(1, Integer(Length(mLabels)));
    Assert.AreEqual('B', mLabels[0].Caption);
    Assert.AreEqual('B', TAtlasInstanceBreakpoint.ObjectCaption($200, mLabels));
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.RemoveAndClear;
var
  mMarks: TAtlasObjectMarks;
begin
  mMarks := TAtlasObjectMarks.Create;
  try
    mMarks.Mark($100, 'A', 'TA', 'X', '');
    mMarks.Mark($200, 'B', 'TB', 'Y', '');
    Assert.IsTrue(mMarks.Remove($100));
    Assert.IsFalse(mMarks.Remove($100));
    Assert.AreEqual(1, mMarks.Count);
    mMarks.Clear;
    Assert.AreEqual(0, mMarks.Count, 'Ende der Sitzung');
  finally
    mMarks.Free;
  end;
end;

procedure TAtlasObjectMarksTests.SuggestFromClassAndName;
begin
  Assert.AreEqual('Kunde Meier', TAtlasObjectMarks.Suggest('TKunde', '''Meier'''));
  Assert.AreEqual('Kunde O''Neil', TAtlasObjectMarks.Suggest('Auftrag.Daten.TKunde', '''O''''Neil'''));
  Assert.AreEqual('Kunde', TAtlasObjectMarks.Suggest('TKunde', ''));
  Assert.AreEqual('Tabelle', TAtlasObjectMarks.Suggest('Tabelle', ''), 'kein T-Präfix');
  Assert.AreEqual('', TAtlasObjectMarks.Suggest('', ''));
end;

procedure TAtlasObjectMarksTests.DecorateOnlyWithCaption;
begin
  Assert.AreEqual('(FNr: 4) ‹Kunde A›', TAtlasObjectMarks.Decorate('(FNr: 4)', 'Kunde A', '%0:s ‹%1:s›'));
  Assert.AreEqual('(FNr: 4)', TAtlasObjectMarks.Decorate('(FNr: 4)', '', '%0:s ‹%1:s›'));
end;

procedure TAtlasObjectMarksTests.LooksLikeObjectOnlyForFieldsOrAddress;
begin
  Assert.IsTrue(TAtlasObjectMarks.LooksLikeObject(' (FNr: 4; FName: ''Meier'')'));
  Assert.IsTrue(TAtlasObjectMarks.LooksLikeObject('$0A3F1C20'));
  Assert.IsTrue(TAtlasObjectMarks.LooksLikeObject('0x000000000a3f1c20'));
  Assert.IsFalse(TAtlasObjectMarks.LooksLikeObject('nil'));
  Assert.IsFalse(TAtlasObjectMarks.LooksLikeObject('42'));
  Assert.IsFalse(TAtlasObjectMarks.LooksLikeObject('''Meier'''));
  Assert.IsFalse(TAtlasObjectMarks.LooksLikeObject('[fsBold]'));
  Assert.IsFalse(TAtlasObjectMarks.LooksLikeObject(''));
end;

procedure TAtlasObjectMarksTests.ReadClassNameWin32;
var
  mMemory: TFakeMemory;
begin
  mMemory := TFakeMemory.Create;
  try
    // Objekt an $1000 zeigt auf die VMT $5000; bei $5000 - 56 steht der Zeiger auf den Namen bei $6000.
    mMemory.PutPointer($1000, $5000, 4);
    mMemory.PutPointer($5000 - 56, $6000, 4);
    mMemory.PutName($6000, 'TKunde');
    Assert.AreEqual('TKunde', TAtlasObjectMarks.ReadClassName($1000, 4, mMemory.Reader()));
    Assert.AreEqual('', TAtlasObjectMarks.ReadClassName($2000, 4, mMemory.Reader()), 'nicht lesbar');
    Assert.AreEqual('', TAtlasObjectMarks.ReadClassName($1000, 2, mMemory.Reader()), 'Zeigergröße');
  finally
    mMemory.Free;
  end;
end;

procedure TAtlasObjectMarksTests.ReadClassNameWin64;
var
  mMemory: TFakeMemory;
begin
  mMemory := TFakeMemory.Create;
  try
    mMemory.PutPointer($1000, $1234500000, 8);
    mMemory.PutPointer($1234500000 - 112, $1234600000, 8);
    mMemory.PutName($1234600000, 'TList<System.Integer>');
    Assert.AreEqual('TList<System.Integer>', TAtlasObjectMarks.ReadClassName($1000, 8, mMemory.Reader()));
  finally
    mMemory.Free;
  end;
end;

procedure TAtlasObjectMarksTests.ReadClassNameRejectsGarbage;
var
  mMemory: TFakeMemory;
begin
  mMemory := TFakeMemory.Create;
  try
    // Freigegeben und überschrieben: Der „Name“ besteht aus Füllbytes.
    mMemory.PutPointer($1000, $5000, 4);
    mMemory.PutPointer($5000 - 56, $6000, 4);
    mMemory.PutName($6000, 'ab' + Char($80) + Char($8B));
    Assert.AreEqual('', TAtlasObjectMarks.ReadClassName($1000, 4, mMemory.Reader()));
    mMemory.PutPointer($1000, $10, 4);
    Assert.AreEqual('', TAtlasObjectMarks.ReadClassName($1000, 4, mMemory.Reader()), 'VMT unterhalb des Abstands');
  finally
    mMemory.Free;
  end;
end;

procedure TAtlasObjectMarksTests.PlaceTextOfWindowsPath;
begin
  Assert.AreEqual('Haupt.pas:12', TAtlasObjectMarks.PlaceText('C:\P\Haupt.pas', 12));
  Assert.AreEqual('Haupt.pas:3', TAtlasObjectMarks.PlaceText('/p/Haupt.pas', 3));
  Assert.AreEqual('', TAtlasObjectMarks.PlaceText('', 3));
end;

end.
