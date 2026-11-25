unit Atlas.Core.Processes.OutputLines.Tests;

// Tests der Zeilen aus der Ausgabe eines Prozesses (#900, #581): Stücke ohne
// Zeilenende, UTF-8 über Stückgrenzen, Ersatz-Codepage, CR, Farbfolgen, Rest
// am Ende und die angefangene Zeile (Pending).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasOutputLinesTests = class
  public
    [Test]
    procedure LinesAreSplitAcrossChunks;
    [Test]
    procedure NonUtf8LinesUseTheCodePage;
    [Test]
    procedure PendingShowsTheStartedLine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Processes.OutputLines;

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

{ TAtlasOutputLinesTests }

procedure TAtlasOutputLinesTests.LinesAreSplitAcrossChunks;
var
  mLines: TAtlasOutputLines;
  mGot: TArray<string>;
  mData: TBytes;
begin
  mLines := TAtlasOutputLines.Create(0);
  try
    mData := Bytes('eins'#13#10'zw');
    mGot := mLines.Feed(mData, Length(mData));
    Assert.AreEqual('eins', string.Join('|', mGot), 'CR fällt weg, „zw“ wartet');
    mData := Bytes('ei'#10#10#27'[31mrot'#27'[0m'#10'Ende');
    mGot := mLines.Feed(mData, Length(mData));
    Assert.AreEqual('zwei||rot', string.Join('|', mGot), 'leere Zeile bleibt, Farbfolgen fallen weg');
    // Nur ein Teil des Puffers gilt.
    mData := Bytes('!xyz');
    mGot := mLines.Feed(mData, 1);
    Assert.AreEqual(0, Integer(Length(mGot)));
    Assert.AreEqual('Ende!', string.Join('|', mLines.Flush));
    Assert.AreEqual(0, Integer(Length(mLines.Flush)), 'Rest nur einmal');
    // UTF-8 über die Grenze zweier Stücke: ü = C3 BC.
    mData := TBytes.Create($50, $72, $C3);
    mLines.Feed(mData, Length(mData));
    mData := TBytes.Create($BC, $66, 10);
    mGot := mLines.Feed(mData, Length(mData));
    Assert.AreEqual('Prüf', string.Join('|', mGot));
    // Fenstertitel (OSC) und einzelne Steuerzeichen am Ende.
    Assert.AreEqual('ab', TAtlasOutputLines.Clean('a'#27']0;Titel'#7'b'));
    Assert.AreEqual('ab', TAtlasOutputLines.Clean('a'#27']0;T'#27'\b'#27));
    Assert.AreEqual('Fehler', TAtlasOutputLines.Clean(#27'[1;31;40mFehler'#27'[K'#13));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasOutputLinesTests.NonUtf8LinesUseTheCodePage;
var
  mLines: TAtlasOutputLines;
  mData: TBytes;
begin
  // Gültiges UTF-8 gewinnt auch mit Codepage; überlange Formen und abgeschnittene Folgen nicht.
  mLines := TAtlasOutputLines.Create(1252);
  try
    mData := Bytes('Prüfung ✓' + #10);
    Assert.AreEqual('Prüfung ✓', string.Join('|', mLines.Feed(mData, Length(mData))));
    mData := TBytes.Create($C0, $80, 10);
    Assert.AreEqual(#$00C0#$20AC, string.Join('|', mLines.Feed(mData, Length(mData))), 'überlange Form');
    mData := TBytes.Create($E2, $9C, 10);
    Assert.AreEqual(#$00E2#$0153, string.Join('|', mLines.Feed(mData, Length(mData))), 'abgeschnitten');
  finally
    mLines.Free;
  end;
  // 1252: FC = ü.
  mLines := TAtlasOutputLines.Create(1252);
  try
    mData := TBytes.Create($50, $72, $FC, $66, 10);
    Assert.AreEqual('Prüf', string.Join('|', mLines.Feed(mData, Length(mData))));
  finally
    mLines.Free;
  end;
  Assert.AreEqual('ab', TAtlasOutputLines.Clean(#27'[1;32ma'#27'[0mb'#13));
end;

procedure TAtlasOutputLinesTests.PendingShowsTheStartedLine;
var
  mLines: TAtlasOutputLines;
  mData: TBytes;
begin
  mLines := TAtlasOutputLines.Create(0);
  try
    Assert.AreEqual('', mLines.Pending, 'leer am Anfang');
    // Frage vor einem Readln: kein Zeilenende, trotzdem sichtbar und nicht verbraucht.
    mData := Bytes('Name: ');
    Assert.AreEqual(0, Integer(Length(mLines.Feed(mData, Length(mData)))));
    Assert.AreEqual('Name: ', mLines.Pending);
    Assert.AreEqual('Name: ', mLines.Pending, 'Pending verbraucht nichts');
    // Angefangene UTF-8-Folge zählt erst mit ihren Folgebytes (ü = C3 BC).
    mData := TBytes.Create($47, $72, $C3);
    mLines.Feed(mData, Length(mData));
    Assert.AreEqual('Name: Gr', mLines.Pending);
    mData := TBytes.Create($BC, 10);
    Assert.AreEqual(0, Integer(Length(mLines.Feed(mData, 1))), 'ohne Zeilenende bleibt die Zeile angefangen');
    Assert.AreEqual('Name: Grü', mLines.Pending);
    mData := TBytes.Create(10);
    Assert.AreEqual('Name: Grü', string.Join('|', mLines.Feed(mData, 1)));
    Assert.AreEqual('', mLines.Pending, 'fertige Zeile ist nicht mehr angefangen');
    // Eingabe hinter der Frage: TakePending nimmt sie heraus, die abgeschnittene Folge bleibt.
    mData := TBytes.Create($3F, $20, $E2, $9C);
    mLines.Feed(mData, Length(mData));
    Assert.AreEqual('? ', mLines.TakePending);
    Assert.AreEqual('', mLines.Pending);
    mData := TBytes.Create($93, 10);
    Assert.AreEqual('✓', string.Join('|', mLines.Feed(mData, Length(mData))), 'Folge über TakePending hinweg');
  finally
    mLines.Free;
  end;
end;

end.
