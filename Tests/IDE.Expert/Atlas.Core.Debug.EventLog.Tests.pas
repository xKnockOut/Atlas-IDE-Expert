unit Atlas.Core.Debug.EventLog.Tests;

// Tests für das Ereignisprotokoll beim Debuggen (#580): Arten, Filter, Farben, Sprungziele, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEventLogTests = class
  public
    /// <summary>Präfixe der IDE auf Deutsch und Englisch; angehängter Prozess fällt weg.</summary>
    [Test]
    procedure ClassifiesIdeLines;
    /// <summary>Thread-Kennung aus „Thread ID: 1234“.</summary>
    [Test]
    procedure ReadsThreadId;
    /// <summary>Zeit relativ zum Start.</summary>
    [Test]
    procedure FormatsTime;
    /// <summary>Wörter: jedes muss vorkommen, Groß-/Kleinschreibung egal; Arten schränken ein.</summary>
    [Test]
    procedure FiltersByWordsAndKinds;
    /// <summary>„/…/“ ist ein regulärer Ausdruck; ungültig = alles zeigen.</summary>
    [Test]
    procedure FiltersByRegex;
    /// <summary>Farben aus debug.eventLogColors, erstes Muster gewinnt.</summary>
    [Test]
    procedure ColorsByPattern;
    /// <summary>Ungültige Farben fallen weg; Namen werden zu #RRGGBB.</summary>
    [Test]
    procedure NormalizesColors;
    /// <summary>Datei.pas(123), Datei.pas:123, mit Laufwerk und Spalte.</summary>
    [Test]
    procedure FindsFileJumps;
    /// <summary>Unit.Routine; Dateinamen wie Demo.exe zählen nicht.</summary>
    [Test]
    procedure FindsSymbolJumps;
    /// <summary>Älteste Einträge fallen über dem Limit weg; Text zum Speichern.</summary>
    [Test]
    procedure KeepsLimitAndWritesText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Color,
  Atlas.Core.Settings.Plugin.Debug,
  Atlas.Core.Debug.EventLog;

function Entry(AKind: TAtlasEventKind; const AText: string): TAtlasEventEntry;
begin
  Result := TAtlasEventEntry.Create(0, AKind, '', AText);
end;

procedure TAtlasEventLogTests.ClassifiesIdeLines;
var
  mText, mThread: string;
begin
  Assert.AreEqual(Ord(TAtlasEventKind.Output), Ord(TAtlasEventLog.Classify(
    'Debug Output: [FEHLER] Foo.pas(12) Process Demo.exe (4711)', mText, mThread)));
  Assert.AreEqual('[FEHLER] Foo.pas(12)', mText);
  Assert.AreEqual(Ord(TAtlasEventKind.Output), Ord(TAtlasEventLog.Classify('Debug-Ausgabe: Hallo Prozess Demo.exe (1)',
    mText, mThread)));
  Assert.AreEqual('Hallo', mText);
  Assert.AreEqual(Ord(TAtlasEventKind.Breakpoint), Ord(TAtlasEventLog.Classify('Breakpoint Message: x = 1', mText,
    mThread)));
  Assert.AreEqual(Ord(TAtlasEventKind.Module), Ord(TAtlasEventLog.Classify(
    'Module Load: KERNEL32.dll. No Debug Info. Base Address: $76A10000.', mText, mThread)));
  Assert.AreEqual(Ord(TAtlasEventKind.Module), Ord(TAtlasEventLog.Classify('Modul laden: ntdll.dll.', mText, mThread)));
  Assert.AreEqual(Ord(TAtlasEventKind.Process), Ord(TAtlasEventLog.Classify('Process Start: C:\Demo.exe', mText,
    mThread)));
  Assert.AreEqual(Ord(TAtlasEventKind.Other), Ord(TAtlasEventLog.Classify('Irgendwas ohne Doppelpunkt', mText,
    mThread)));
  Assert.AreEqual('Irgendwas ohne Doppelpunkt', mText);
  // Ein Doppelpunkt weit hinten ist kein Präfix.
  Assert.AreEqual(Ord(TAtlasEventKind.Other), Ord(TAtlasEventLog.Classify(
    'Eine lange Zeile ohne Präfix mit Ausgabe: am Ende', mText, mThread)));
end;

procedure TAtlasEventLogTests.ReadsThreadId;
var
  mText, mThread: string;
begin
  Assert.AreEqual(Ord(TAtlasEventKind.Thread), Ord(TAtlasEventLog.Classify(
    'Thread Start: Thread ID: 1234. Process Demo.exe (4711)', mText, mThread)));
  Assert.AreEqual('1234', mThread);
  TAtlasEventLog.Classify('Thread-Ende: Thread-ID: 99. Prozess Demo.exe (1)', mText, mThread);
  Assert.AreEqual('99', mThread);
  TAtlasEventLog.Classify('Debug Output: ohne Thread', mText, mThread);
  Assert.AreEqual('', mThread);
end;

procedure TAtlasEventLogTests.FormatsTime;
begin
  Assert.AreEqual('0:00.000', TAtlasEventEntry.Create(0, TAtlasEventKind.Other, '', '').TimeText);
  Assert.AreEqual('0:12.345', TAtlasEventEntry.Create(12345, TAtlasEventKind.Other, '', '').TimeText);
  Assert.AreEqual('2:03.004', TAtlasEventEntry.Create(123004, TAtlasEventKind.Other, '', '').TimeText);
  Assert.AreEqual('1:02:03.004', TAtlasEventEntry.Create(3723004, TAtlasEventKind.Other, '', '').TimeText);
  Assert.AreEqual('0:00.000', TAtlasEventEntry.Create(-5, TAtlasEventKind.Other, '', '').TimeText);
end;

procedure TAtlasEventLogTests.FiltersByWordsAndKinds;
var
  mLog: TAtlasEventLog;
  mHits: TArray<Integer>;
begin
  mLog := TAtlasEventLog.Create;
  try
    mLog.Add(Entry(TAtlasEventKind.Output, '[FEHLER] Foo.pas(12) Datei fehlt'));
    mLog.Add(Entry(TAtlasEventKind.Output, '[WARN] langsam'));
    mLog.Add(Entry(TAtlasEventKind.Module, 'fehler.dll geladen'));
    mHits := mLog.Filter(TAtlasEventFilter.Create('fehler', TAtlasEventLog.cAllKinds));
    Assert.AreEqual(Integer(2), Integer(Length(mHits)));
    Assert.AreEqual(Integer(0), mHits[0]);
    Assert.AreEqual(Integer(2), mHits[1]);
    mHits := mLog.Filter(TAtlasEventFilter.Create('FEHLER', [TAtlasEventKind.Output]));
    Assert.AreEqual(Integer(1), Integer(Length(mHits)));
    mHits := mLog.Filter(TAtlasEventFilter.Create('fehler datei', TAtlasEventLog.cAllKinds));
    Assert.AreEqual(Integer(1), Integer(Length(mHits)), 'alle Wörter');
    mHits := mLog.Filter(TAtlasEventFilter.Create('', [TAtlasEventKind.Module]));
    Assert.AreEqual(Integer(1), Integer(Length(mHits)));
    Assert.AreEqual(Integer(2), mHits[0]);
  finally
    mLog.Free;
  end;
end;

procedure TAtlasEventLogTests.FiltersByRegex;
var
  mLog: TAtlasEventLog;
  mFilter: TAtlasEventFilter;
begin
  mLog := TAtlasEventLog.Create;
  try
    mLog.Add(Entry(TAtlasEventKind.Output, '[FEHLER] eins'));
    mLog.Add(Entry(TAtlasEventKind.Output, '[WARN] zwei'));
    mLog.Add(Entry(TAtlasEventKind.Output, 'drei'));
    mFilter := TAtlasEventFilter.Create(' /^\[(fehler|warn)\]/ ', TAtlasEventLog.cAllKinds);
    Assert.IsTrue(mFilter.IsRegex);
    Assert.AreEqual('^\[(fehler|warn)\]', mFilter.Pattern);
    Assert.IsTrue(mFilter.Valid);
    Assert.AreEqual(Integer(2), Integer(Length(mLog.Filter(mFilter))));
    mFilter := TAtlasEventFilter.Create('/[unvollständig/', TAtlasEventLog.cAllKinds);
    Assert.IsFalse(mFilter.Valid);
    Assert.AreEqual(Integer(3), Integer(Length(mLog.Filter(mFilter))), 'ungültiger Ausdruck: alles');
    Assert.IsFalse(TAtlasEventFilter.Create('/', TAtlasEventLog.cAllKinds).IsRegex);
    Assert.IsFalse(TAtlasEventFilter.Create('//', TAtlasEventLog.cAllKinds).IsRegex);
  finally
    mLog.Free;
  end;
end;

procedure TAtlasEventLogTests.ColorsByPattern;
var
  mColors: TAtlasEventColors;
  mColor: TAtlasColor;
begin
  mColors := TAtlasEventColors.Parse(cDefaultEventLogColors);
  Assert.AreEqual(Integer(3), Integer(Length(mColors.Rules)));
  Assert.IsTrue(mColors.TryColorOf('[FEHLER] Foo.pas(12)', mColor));
  Assert.AreEqual('#D13438', TAtlasColorMath.ToHex(mColor));
  Assert.IsTrue(mColors.TryColorOf('x [warn] y', mColor), 'Groß-/Kleinschreibung egal');
  Assert.AreEqual('#C19C00', TAtlasColorMath.ToHex(mColor));
  Assert.IsFalse(mColors.TryColorOf('alles gut', mColor));
  mColors := TAtlasEventColors.Parse('a=b=rot; a=#00FF00');
  Assert.AreEqual('a=b', mColors.Rules[0].Pattern, 'das letzte = trennt');
  Assert.IsTrue(mColors.TryColorOf('xa=by', mColor));
  Assert.AreEqual('#D13438', TAtlasColorMath.ToHex(mColor), 'erstes Muster gewinnt');
end;

procedure TAtlasEventLogTests.NormalizesColors;
begin
  Assert.AreEqual('[X]=#107C10; Y=#0000FF', TAtlasEventColors.Normalize(' [X] = grün ;kaputt; Z=#12; Y=#0000ff;=rot'));
  Assert.AreEqual('', TAtlasEventColors.Normalize(''));
end;

procedure TAtlasEventLogTests.FindsFileJumps;
var
  mJump: TAtlasEventJump;
begin
  mJump := TAtlasEventJump.Find('[FEHLER] Foo.pas(12) Datei fehlt');
  Assert.AreEqual(Ord(TAtlasEventJumpKind.FileLine), Ord(mJump.Kind));
  Assert.AreEqual('Foo.pas', mJump.FileName);
  Assert.AreEqual(Integer(12), mJump.Line);
  mJump := TAtlasEventJump.Find('Fehler in C:\Src\Haupt.Form.pas(7,3): E2003');
  Assert.AreEqual('C:\Src\Haupt.Form.pas', mJump.FileName);
  Assert.AreEqual(Integer(7), mJump.Line);
  mJump := TAtlasEventJump.Find('at src/Unit1.pas:345 in Foo');
  Assert.AreEqual(Ord(TAtlasEventJumpKind.FileLine), Ord(mJump.Kind));
  Assert.AreEqual('src/Unit1.pas', mJump.FileName);
  Assert.AreEqual(Integer(345), mJump.Line);
  mJump := TAtlasEventJump.Find('Projekt.dpr(0)');
  Assert.AreEqual(Integer(1), mJump.Line, 'Zeile mindestens 1');
end;

procedure TAtlasEventLogTests.FindsSymbolJumps;
var
  mJump: TAtlasEventJump;
begin
  mJump := TAtlasEventJump.Find('Fehler in Demo.exe bei Main.TForm1.Button1Click');
  Assert.AreEqual(Ord(TAtlasEventJumpKind.Symbol), Ord(mJump.Kind));
  Assert.AreEqual('Main.TForm1.Button1Click', mJump.Symbol);
  mJump := TAtlasEventJump.Find('KERNEL32.dll geladen');
  Assert.AreEqual(Ord(TAtlasEventJumpKind.None), Ord(mJump.Kind));
  mJump := TAtlasEventJump.Find('nur Text');
  Assert.AreEqual(Ord(TAtlasEventJumpKind.None), Ord(mJump.Kind));
end;

procedure TAtlasEventLogTests.KeepsLimitAndWritesText;
var
  mLog: TAtlasEventLog;
  mIndex: Integer;
begin
  mLog := TAtlasEventLog.Create(10);
  try
    for mIndex := 1 to 11 do
    begin
      mLog.Add(TAtlasEventEntry.Create(mIndex, TAtlasEventKind.Output, '', IntToStr(mIndex)));
    end;
    Assert.AreEqual(Integer(10), mLog.Count);
    Assert.AreEqual(Integer(1), mLog.Dropped);
    Assert.AreEqual('2', mLog[0].Text);
    mLog.Clear;
    Assert.AreEqual(Integer(0), mLog.Dropped);
    mLog.Add(TAtlasEventEntry.Create(1500, TAtlasEventKind.Thread, '7', 'a'#13#10'b'));
    Assert.AreEqual('0:01.500'#9'thread'#9'7'#9'a b'#13#10, mLog.ToText);
  finally
    mLog.Free;
  end;
end;

end.
