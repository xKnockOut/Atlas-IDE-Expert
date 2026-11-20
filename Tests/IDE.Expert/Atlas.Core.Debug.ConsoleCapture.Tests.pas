unit Atlas.Core.Debug.ConsoleCapture.Tests;

// Tests der angedockten Konsolenausgabe (#581) ohne IDE: Zeilen aus stdout
// und stderr, Frage und Eingabe auf einer Zeile, Obergrenze der Zeilen,
// Konsolen- oder Fensterprogramm aus dem PE-Kopf, Fundstellen in Zeilen,
// Entscheidung vor dem Start, Exit-Code als Text und der Schritt nach dem
// Anhängen des Debuggers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasConsoleCaptureTests = class
  public
    [Test]
    procedure OutputAndErrorKeepTheirStream;
    [Test]
    procedure InputClosesThePrompt;
    [Test]
    procedure FinishFlushesStartedLines;
    [Test]
    procedure OldLinesFallAway;
    [Test]
    procedure ClearForgetsEverything;
    [Test]
    procedure ImageKindFromPeHeader;
    [Test]
    procedure ImageKindOfMissingFile;
    [Test]
    procedure LocationsInLines;
    [Test]
    procedure NoLocationInPlainText;
    [Test]
    procedure LaunchChoice;
    [Test]
    procedure ExitCodeText;
    [Test]
    procedure AttachSteps;
    [Test]
    procedure ColorsAreReadable;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Color,
  Atlas.Core.Debug.ConsoleCapture;

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

procedure Feed(ABuffer: TAtlasConsoleBuffer; AStream: TAtlasConsoleStream; const AText: string);
var
  mData: TBytes;
begin
  mData := Bytes(AText);
  ABuffer.Add(AStream, mData, Length(mData));
end;

/// <summary>Kopf einer EXE: MZ, Verweis auf den PE-Kopf bei $80, Subsystem ASubsystem.</summary>
function Header(ASubsystem: Word): TBytes;
const
  cPe = $80;
  cSubsystemAt = cPe + 24 + 68;
begin
  SetLength(Result, 512);
  FillChar(Result[0], Length(Result), 0);
  Result[0] := Ord('M');
  Result[1] := Ord('Z');
  Result[$3C] := cPe;
  Result[cPe] := Ord('P');
  Result[cPe + 1] := Ord('E');
  Result[cSubsystemAt] := Lo(ASubsystem);
  Result[cSubsystemAt + 1] := Hi(ASubsystem);
end;

function Facts(AEnabled: Boolean; const APlatform: string; AKind: TAtlasImageKind; const AHost: string;
  ABusy: Boolean): TAtlasConsoleLaunchFacts;
begin
  Result := Default(TAtlasConsoleLaunchFacts);
  Result.Enabled := AEnabled;
  Result.Platform := APlatform;
  Result.Kind := AKind;
  Result.Host := AHost;
  Result.Busy := ABusy;
end;

function AttachFacts(AElapsed: UInt64; AReady, AAlive: Boolean): TAtlasConsoleAttachFacts;
begin
  Result := Default(TAtlasConsoleAttachFacts);
  Result.ElapsedMs := AElapsed;
  Result.TimeoutMs := 1000;
  Result.IdeReady := AReady;
  Result.Alive := AAlive;
end;

{ TAtlasConsoleCaptureTests }

procedure TAtlasConsoleCaptureTests.OutputAndErrorKeepTheirStream;
var
  mBuffer: TAtlasConsoleBuffer;
begin
  mBuffer := TAtlasConsoleBuffer.Create(0, 1000);
  try
    Feed(mBuffer, TAtlasConsoleStream.Output, 'Hallo'#13#10'Wel');
    Feed(mBuffer, TAtlasConsoleStream.Error, 'Fehler'#10);
    Feed(mBuffer, TAtlasConsoleStream.Output, 't'#10);
    Assert.AreEqual(3, mBuffer.Count);
    Assert.AreEqual('Hallo', mBuffer.Line(0).Text);
    Assert.IsTrue(mBuffer.Line(0).Stream = TAtlasConsoleStream.Output);
    Assert.AreEqual('Fehler', mBuffer.Line(1).Text, 'stderr ist vor dem Ende der angefangenen Zeile fertig');
    Assert.IsTrue(mBuffer.Line(1).Stream = TAtlasConsoleStream.Error);
    Assert.AreEqual('Welt', mBuffer.Line(2).Text);
    Assert.AreEqual(0, Integer(Length(mBuffer.PendingLines)));
    // Eingabe und Hinweis kommen nicht über Add.
    Assert.AreEqual(0, mBuffer.Add(TAtlasConsoleStream.Input, Bytes('x'#10), 2));
  finally
    mBuffer.Free;
  end;
end;

procedure TAtlasConsoleCaptureTests.InputClosesThePrompt;
var
  mBuffer: TAtlasConsoleBuffer;
  mPending: TArray<TAtlasConsoleLine>;
begin
  mBuffer := TAtlasConsoleBuffer.Create(0, 1000);
  try
    Feed(mBuffer, TAtlasConsoleStream.Output, 'Name: ');
    mPending := mBuffer.PendingLines;
    Assert.AreEqual(1, Integer(Length(mPending)));
    Assert.AreEqual('Name: ', mPending[0].Text);
    mBuffer.AddInput('Marco');
    Assert.AreEqual(1, mBuffer.Count);
    Assert.AreEqual('Name: Marco', mBuffer.Line(0).Text);
    Assert.IsTrue(mBuffer.Line(0).Stream = TAtlasConsoleStream.Input);
    Assert.AreEqual(6, mBuffer.Line(0).PromptLength);
    Assert.AreEqual(0, Integer(Length(mBuffer.PendingLines)), 'die Frage ist abgeschlossen');
    // Die Antwort des Programms beginnt eine eigene Zeile.
    Feed(mBuffer, TAtlasConsoleStream.Output, 'Hallo Marco'#10);
    Assert.AreEqual('Hallo Marco', mBuffer.Line(1).Text);
    // Ohne Frage steht die Eingabe allein.
    mBuffer.AddInput('quit');
    Assert.AreEqual('quit', mBuffer.Line(2).Text);
    Assert.AreEqual(0, mBuffer.Line(2).PromptLength);
  finally
    mBuffer.Free;
  end;
end;

procedure TAtlasConsoleCaptureTests.FinishFlushesStartedLines;
var
  mBuffer: TAtlasConsoleBuffer;
begin
  mBuffer := TAtlasConsoleBuffer.Create(0, 1000);
  try
    Feed(mBuffer, TAtlasConsoleStream.Output, 'ohne Ende');
    Feed(mBuffer, TAtlasConsoleStream.Error, 'auch');
    mBuffer.Finish;
    mBuffer.AddNote('Beendet');
    Assert.AreEqual(3, mBuffer.Count);
    Assert.AreEqual('ohne Ende', mBuffer.Line(0).Text);
    Assert.IsTrue(mBuffer.Line(1).Stream = TAtlasConsoleStream.Error);
    Assert.IsTrue(mBuffer.Line(2).Stream = TAtlasConsoleStream.Note);
    Assert.AreEqual('ohne Ende' + sLineBreak + 'auch' + sLineBreak + 'Beendet' + sLineBreak, mBuffer.Text);
  finally
    mBuffer.Free;
  end;
end;

procedure TAtlasConsoleCaptureTests.OldLinesFallAway;
var
  mBuffer: TAtlasConsoleBuffer;
  mIndex: Integer;
begin
  // Unter 100 gilt 100.
  mBuffer := TAtlasConsoleBuffer.Create(0, 5);
  try
    for mIndex := 1 to 101 do
    begin
      Feed(mBuffer, TAtlasConsoleStream.Output, IntToStr(mIndex) + #10);
    end;
    Assert.AreEqual(90, mBuffer.Count, 'ein Zehntel Luft');
    Assert.AreEqual(11, mBuffer.Dropped);
    Assert.AreEqual('12', mBuffer.Line(0).Text);
    Assert.AreEqual('101', mBuffer.Line(mBuffer.Count - 1).Text);
  finally
    mBuffer.Free;
  end;
end;

procedure TAtlasConsoleCaptureTests.ClearForgetsEverything;
var
  mBuffer: TAtlasConsoleBuffer;
begin
  mBuffer := TAtlasConsoleBuffer.Create(0, 1000);
  try
    Feed(mBuffer, TAtlasConsoleStream.Output, 'eins'#10'angefangen');
    mBuffer.Clear;
    Assert.AreEqual(0, mBuffer.Count);
    Assert.AreEqual(0, Integer(Length(mBuffer.PendingLines)));
    Feed(mBuffer, TAtlasConsoleStream.Output, ' weiter'#10);
    Assert.AreEqual(' weiter', mBuffer.Line(0).Text, 'der alte Anfang ist weg');
  finally
    mBuffer.Free;
  end;
end;

procedure TAtlasConsoleCaptureTests.ImageKindFromPeHeader;
var
  mHeader: TBytes;
begin
  Assert.IsTrue(TAtlasConsoleImage.KindOf(Header(3)) = TAtlasImageKind.Console);
  Assert.IsTrue(TAtlasConsoleImage.KindOf(Header(2)) = TAtlasImageKind.Gui);
  Assert.IsTrue(TAtlasConsoleImage.KindOf(Header(10)) = TAtlasImageKind.Unknown, 'EFI');
  Assert.IsTrue(TAtlasConsoleImage.KindOf(nil) = TAtlasImageKind.Unknown);
  mHeader := Header(3);
  mHeader[0] := Ord('X');
  Assert.IsTrue(TAtlasConsoleImage.KindOf(mHeader) = TAtlasImageKind.Unknown, 'kein MZ');
  mHeader := Header(3);
  mHeader[$81] := Ord('X');
  Assert.IsTrue(TAtlasConsoleImage.KindOf(mHeader) = TAtlasImageKind.Unknown, 'kein PE');
  mHeader := Header(3);
  SetLength(mHeader, $80 + 24 + 68);
  Assert.IsTrue(TAtlasConsoleImage.KindOf(mHeader) = TAtlasImageKind.Unknown, 'abgeschnitten');
  mHeader := Header(3);
  mHeader[$3C] := $FF;
  mHeader[$3F] := $7F;
  Assert.IsTrue(TAtlasConsoleImage.KindOf(mHeader) = TAtlasImageKind.Unknown, 'Verweis hinter das Ende');
end;

procedure TAtlasConsoleCaptureTests.ImageKindOfMissingFile;
begin
  Assert.IsTrue(TAtlasConsoleImage.KindOfFile('') = TAtlasImageKind.Unknown);
  Assert.IsTrue(TAtlasConsoleImage.KindOfFile(IncludeTrailingPathDelimiter(GetCurrentDir) + 'fehlt-581.exe') =
    TAtlasImageKind.Unknown);
end;

procedure TAtlasConsoleCaptureTests.LocationsInLines;
var
  mLocation: TAtlasConsoleLocation;
begin
  Assert.IsTrue(TAtlasConsoleLocations.Find('Fehler in Main.pas(12): x', mLocation));
  Assert.AreEqual('Main.pas', mLocation.FileName);
  Assert.AreEqual(12, mLocation.Line);
  Assert.AreEqual(0, mLocation.Column);
  Assert.AreEqual(11, mLocation.Start);
  Assert.AreEqual(12, mLocation.Length);
  Assert.IsTrue(TAtlasConsoleLocations.Find('C:\Projekt\Src\Unit1.pas(7,3) Hinweis', mLocation));
  Assert.AreEqual('C:\Projekt\Src\Unit1.pas', mLocation.FileName);
  Assert.AreEqual(7, mLocation.Line);
  Assert.AreEqual(3, mLocation.Column);
  Assert.AreEqual(1, mLocation.Start);
  Assert.IsTrue(TAtlasConsoleLocations.Find('at D:\a\b.dpr:40:2', mLocation));
  Assert.AreEqual('D:\a\b.dpr', mLocation.FileName);
  Assert.AreEqual(40, mLocation.Line);
  Assert.AreEqual(2, mLocation.Column);
  Assert.AreEqual(4, mLocation.Start);
  Assert.IsTrue(TAtlasConsoleLocations.Find('src/util.inc:9: Warnung', mLocation));
  Assert.AreEqual('src/util.inc', mLocation.FileName);
  Assert.AreEqual(9, mLocation.Line);
  Assert.AreEqual(0, mLocation.Column);
  Assert.AreEqual(14, mLocation.Length);
  Assert.IsTrue(TAtlasConsoleLocations.Find('"Test.pas"(5)', mLocation) = False, 'Anführungszeichen trennen');
  Assert.IsTrue(TAtlasConsoleLocations.Find('Test.pas(5:8)', mLocation));
  Assert.AreEqual(8, mLocation.Column);
end;

procedure TAtlasConsoleCaptureTests.NoLocationInPlainText;
var
  mLocation: TAtlasConsoleLocation;
begin
  Assert.IsFalse(TAtlasConsoleLocations.Find('', mLocation));
  Assert.IsFalse(TAtlasConsoleLocations.Find('Uhrzeit 12:30', mLocation));
  Assert.IsFalse(TAtlasConsoleLocations.Find('Version 1.2:3', mLocation), 'Endung braucht Buchstaben');
  Assert.IsFalse(TAtlasConsoleLocations.Find('Main.pas(x)', mLocation));
  Assert.IsFalse(TAtlasConsoleLocations.Find('Main.pas(12', mLocation), 'Klammer fehlt');
  Assert.IsFalse(TAtlasConsoleLocations.Find('http://example.com:8080/', mLocation));
  Assert.IsFalse(TAtlasConsoleLocations.Find('Main.pas(0)', mLocation), 'Zeile 0 gibt es nicht');
  Assert.AreEqual('', mLocation.FileName);
end;

procedure TAtlasConsoleCaptureTests.LaunchChoice;
begin
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(True, 'Win32', TAtlasImageKind.Console, '', False)) =
    TAtlasConsoleLaunchChoice.Capture);
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(True, 'win64', TAtlasImageKind.Console, '', False)) =
    TAtlasConsoleLaunchChoice.Capture);
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(True, 'Win64x', TAtlasImageKind.Console, '', True)) =
    TAtlasConsoleLaunchChoice.Busy);
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(False, 'Win32', TAtlasImageKind.Console, '', False)) =
    TAtlasConsoleLaunchChoice.Ide, 'aus');
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(True, 'Win32', TAtlasImageKind.Gui, '', False)) =
    TAtlasConsoleLaunchChoice.Ide, 'Fensterprogramm');
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(True, 'Win32', TAtlasImageKind.Unknown, '', True)) =
    TAtlasConsoleLaunchChoice.Ide, 'EXE fehlt');
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(True, 'Linux64', TAtlasImageKind.Console, '', False)) =
    TAtlasConsoleLaunchChoice.Ide, 'fremde Plattform');
  Assert.IsTrue(TAtlasConsoleLaunch.Choose(Facts(True, 'Win32', TAtlasImageKind.Console, 'C:\Host.exe', False)) =
    TAtlasConsoleLaunchChoice.Ide, 'Host-Anwendung');
end;

procedure TAtlasConsoleCaptureTests.ExitCodeText;
begin
  Assert.AreEqual('0', TAtlasConsoleLaunch.ExitCodeText(0));
  Assert.AreEqual('3', TAtlasConsoleLaunch.ExitCodeText(3));
  Assert.AreEqual('-1073741819 ($C0000005)', TAtlasConsoleLaunch.ExitCodeText($C0000005));
  Assert.AreEqual('-1 ($FFFFFFFF)', TAtlasConsoleLaunch.ExitCodeText($FFFFFFFF));
end;

procedure TAtlasConsoleCaptureTests.AttachSteps;
begin
  Assert.IsTrue(TAtlasConsoleAttach.Next(AttachFacts(10, False, True)) = TAtlasConsoleAttachStep.Wait);
  Assert.IsTrue(TAtlasConsoleAttach.Next(AttachFacts(10, True, True)) = TAtlasConsoleAttachStep.Resume);
  Assert.IsTrue(TAtlasConsoleAttach.Next(AttachFacts(1000, False, True)) = TAtlasConsoleAttachStep.ResumeLate);
  Assert.IsTrue(TAtlasConsoleAttach.Next(AttachFacts(5000, True, True)) = TAtlasConsoleAttachStep.Resume,
    'bereit geht vor der Wartezeit');
  Assert.IsTrue(TAtlasConsoleAttach.Next(AttachFacts(10, True, False)) = TAtlasConsoleAttachStep.Gone);
end;

procedure TAtlasConsoleCaptureTests.ColorsAreReadable;
const
  cMinContrast = 3.0;
var
  mBackgrounds: array[0..1] of TAtlasColor;
  mBackground, mText: TAtlasColor;
  mStream: TAtlasConsoleStream;
begin
  mBackgrounds[0] := TAtlasColorMath.Rgb(255, 255, 255);
  mBackgrounds[1] := TAtlasColorMath.Rgb(30, 30, 30);
  for mBackground in mBackgrounds do
  begin
    mText := TAtlasColorMath.Rgb(0, 0, 0);
    if TAtlasColorMath.IsDark(mBackground) then
    begin
      mText := TAtlasColorMath.Rgb(220, 220, 220);
    end;
    Assert.AreEqual(Int64(mText), Int64(TAtlasConsoleColors.ForStream(TAtlasConsoleStream.Output, mBackground,
      mText)));
    for mStream in [TAtlasConsoleStream.Error, TAtlasConsoleStream.Input] do
    begin
      Assert.IsTrue(TAtlasColorMath.Contrast(TAtlasConsoleColors.ForStream(mStream, mBackground, mText),
        mBackground) >= cMinContrast, 'lesbar');
    end;
    Assert.IsTrue(TAtlasConsoleColors.ForStream(TAtlasConsoleStream.Note, mBackground, mText) <> mText,
      'gedämpft');
  end;
end;

end.
