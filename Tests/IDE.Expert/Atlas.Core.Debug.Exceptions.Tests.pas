unit Atlas.Core.Debug.Exceptions.Tests;

// Tests des Exception-Verlaufs (#517): gleiche Exception am gleichen Ort
// zählt hoch, neue Sitzung leert, Höchstzahl verdrängt den am längsten nicht
// gesehenen Eintrag, Filter nach Klasse und Wörtern (zuletzt gesehene zuerst),
// Klassenliste, Ort- und Threadtext, Kopiertext; Klasse und Meldung aus den
// Texten des Debuggers (englisch, deutsch, Hochkommas in der Meldung, Codes).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.Exceptions;

type
  [TestFixture]
  TAtlasDebugExceptionsTests = class
  private
    FHistory: TAtlasDebugExceptionHistory;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SameLocationCounts;
    [Test]
    procedure OtherLineIsNewEntry;
    [Test]
    procedure WithoutFileRoutineSeparates;
    [Test]
    procedure StartSessionClears;
    [Test]
    procedure FullHistoryDropsOldest;
    [Test]
    procedure FilterByClassAndWords;
    [Test]
    procedure FilterNewestFirst;
    [Test]
    procedure ClassesSortedWithoutDuplicates;
    [Test]
    procedure IgnoredStaysOnlyWhileAllIgnored;
    [Test]
    procedure TakeChangedResets;
    [Test]
    procedure LocationAndThreadText;
    [Test]
    procedure CopyTextHasClassMessageAndLocation;
    [Test]
    procedure ParseEnglishDialog;
    [Test]
    procedure ParseGermanDialog;
    [Test]
    procedure ParseMessageWithQuotes;
    [Test]
    procedure ParseCodeAndNothing;
    [Test]
    procedure UnquoteAndClassName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack;

function Sample(ATime: TDateTime; const AClass, AMessage, AFile: string; ALine: Integer): TAtlasDebugException;
begin
  Result := TAtlasDebugException.Create(ATime, AClass, AMessage, 1234, '', AFile, ALine, 'Unit1.TForm1.Button1Click');
end;

{ TAtlasDebugExceptionsTests }

procedure TAtlasDebugExceptionsTests.Setup;
begin
  FHistory := TAtlasDebugExceptionHistory.Create;
end;

procedure TAtlasDebugExceptionsTests.TearDown;
begin
  FreeAndNil(FHistory);
end;

procedure TAtlasDebugExceptionsTests.SameLocationCounts;
var
  Entry: TAtlasDebugException;
begin
  FHistory.Add(Sample(1, 'EConvertError', 'eins', 'C:\P\Unit1.pas', 42));
  Entry := Sample(2, 'econverterror', 'zwei', 'c:\p\UNIT1.pas', 42);
  Entry.ThreadId := 99;
  Entry.Frames := TArray<TAtlasDebugFrame>.Create(TAtlasDebugFrame.Create('Unit1.Laden', 'C:\P\Unit1.pas', 42));
  Assert.AreEqual(0, FHistory.Add(Entry));
  Assert.AreEqual(1, FHistory.Count, 'gleiche Klasse am gleichen Ort ohne Groß/klein');
  Assert.AreEqual(2, FHistory[0].Count);
  Assert.AreEqual('zwei', FHistory[0].Message, 'Meldung des letzten Auftretens');
  Assert.AreEqual(99, Integer(FHistory[0].ThreadId));
  Assert.IsTrue(FHistory[0].FirstTime = 1, 'zuerst gesehen bleibt');
  Assert.IsTrue(FHistory[0].LastTime = 2, 'zuletzt gesehen');
  Assert.AreEqual(2, FHistory.Total);
  Assert.AreEqual(1, Integer(Length(FHistory[0].Frames)), 'Stapel des letzten Auftretens (#578)');
end;

procedure TAtlasDebugExceptionsTests.OtherLineIsNewEntry;
begin
  FHistory.Add(Sample(1, 'EConvertError', '', 'C:\P\Unit1.pas', 42));
  FHistory.Add(Sample(2, 'EConvertError', '', 'C:\P\Unit1.pas', 43));
  FHistory.Add(Sample(3, 'EAccessViolation', '', 'C:\P\Unit1.pas', 42));
  Assert.AreEqual(3, FHistory.Count);
end;

procedure TAtlasDebugExceptionsTests.WithoutFileRoutineSeparates;
var
  First, Second, Found: TAtlasDebugException;
begin
  First := TAtlasDebugException.Create(1, 'EOSError', '', 1, '', '', 0, 'System.SysUtils.RaiseLastOSError');
  Second := TAtlasDebugException.Create(2, 'EOSError', '', 1, '', '', 0, 'Vcl.Forms.TApplication.Run');
  FHistory.Add(First);
  FHistory.Add(Second);
  Assert.AreEqual(2, FHistory.Count, 'ohne Datei unterscheidet die Routine');
  Assert.IsTrue(FHistory.TryFind(First.Key, Found));
  Assert.AreEqual('System.SysUtils.RaiseLastOSError', Found.Routine);
  Assert.IsFalse(FHistory.TryFind('gibt|es|nicht', Found));
end;

procedure TAtlasDebugExceptionsTests.StartSessionClears;
var
  Session: Integer;
begin
  FHistory.Add(Sample(1, 'EConvertError', '', 'Unit1.pas', 1));
  Session := FHistory.Session;
  FHistory.StartSession;
  Assert.AreEqual(0, FHistory.Count);
  Assert.AreEqual(Session + 1, FHistory.Session);
  Assert.AreEqual(0, FHistory.Total);
end;

procedure TAtlasDebugExceptionsTests.FullHistoryDropsOldest;
var
  History: TAtlasDebugExceptionHistory;
begin
  History := TAtlasDebugExceptionHistory.Create(2);
  try
    History.Add(Sample(1, 'EA', '', 'Unit1.pas', 1));
    History.Add(Sample(2, 'EB', '', 'Unit1.pas', 2));
    // EA erneut: zuletzt gesehen; verdrängt wird EB.
    History.Add(Sample(3, 'EA', '', 'Unit1.pas', 1));
    History.Add(Sample(4, 'EC', '', 'Unit1.pas', 3));
    Assert.AreEqual(2, History.Count);
    Assert.AreEqual('EA', History[0].ExceptionClass);
    Assert.AreEqual('EC', History[1].ExceptionClass);
  finally
    History.Free;
  end;
  Assert.AreEqual(1000, TAtlasDebugExceptionHistory.MaxEntries);
end;

procedure TAtlasDebugExceptionsTests.FilterByClassAndWords;
var
  Hits: TArray<Integer>;
begin
  FHistory.Add(Sample(1, 'EConvertError', '''abc'' ist kein gültiger Integerwert', 'Kunde.pas', 10));
  FHistory.Add(Sample(2, 'EAccessViolation', 'Zugriffsverletzung bei Adresse 0040', 'Lager.pas', 20));
  FHistory.Add(Sample(3, 'EConvertError', 'Datum ungültig', 'Lager.pas', 30));
  Hits := FHistory.Filter('EConvertError', '');
  Assert.AreEqual(2, Integer(Length(Hits)));
  Hits := FHistory.Filter('', 'lager ungültig');
  Assert.AreEqual(1, Integer(Length(Hits)), 'jedes Wort muss vorkommen');
  Assert.AreEqual(2, Hits[0]);
  Hits := FHistory.Filter('', '1234');
  Assert.AreEqual(3, Integer(Length(Hits)), 'Thread-Kennung zählt mit');
  Hits := FHistory.Filter('econverterror', 'Kunde.pas:10');
  Assert.AreEqual(1, Integer(Length(Hits)), 'Ort und Klasse ohne Groß/klein');
  Assert.AreEqual(0, Integer(Length(FHistory.Filter('EAccessViolation', 'Kunde'))));
end;

procedure TAtlasDebugExceptionsTests.FilterNewestFirst;
var
  Hits: TArray<Integer>;
begin
  FHistory.Add(Sample(5, 'EA', '', 'Unit1.pas', 1));
  FHistory.Add(Sample(3, 'EB', '', 'Unit1.pas', 2));
  FHistory.Add(Sample(5, 'EC', '', 'Unit1.pas', 3));
  FHistory.Add(Sample(9, 'EB', '', 'Unit1.pas', 2));
  Hits := FHistory.Filter('', '');
  Assert.AreEqual(3, Integer(Length(Hits)));
  Assert.AreEqual(1, Hits[0], 'EB zuletzt gesehen');
  Assert.AreEqual(2, Hits[1], 'bei gleicher Zeit der spätere Eintrag zuerst');
  Assert.AreEqual(0, Hits[2]);
end;

procedure TAtlasDebugExceptionsTests.ClassesSortedWithoutDuplicates;
var
  Classes: TArray<string>;
begin
  FHistory.Add(Sample(1, 'EConvertError', '', 'Unit1.pas', 1));
  FHistory.Add(Sample(2, 'EAccessViolation', '', 'Unit1.pas', 2));
  FHistory.Add(Sample(3, 'EConvertError', '', 'Unit1.pas', 3));
  Classes := FHistory.Classes;
  Assert.AreEqual(2, Integer(Length(Classes)));
  Assert.AreEqual('EAccessViolation', Classes[0]);
  Assert.AreEqual('EConvertError', Classes[1]);
end;

procedure TAtlasDebugExceptionsTests.IgnoredStaysOnlyWhileAllIgnored;
var
  Entry: TAtlasDebugException;
begin
  Entry := Sample(1, 'EAbort', '', 'Unit1.pas', 1);
  Entry.Ignored := True;
  FHistory.Add(Entry);
  Entry.LastTime := 2;
  FHistory.Add(Entry);
  Assert.IsTrue(FHistory[0].Ignored);
  Entry.Ignored := False;
  FHistory.Add(Entry);
  Assert.IsFalse(FHistory[0].Ignored, 'ein Halt mit Dialog zählt als nicht ignoriert');
  Assert.AreEqual(3, FHistory[0].Count);
end;

procedure TAtlasDebugExceptionsTests.TakeChangedResets;
begin
  Assert.IsFalse(FHistory.TakeChanged);
  FHistory.Add(Sample(1, 'EA', '', 'Unit1.pas', 1));
  Assert.IsTrue(FHistory.TakeChanged);
  Assert.IsFalse(FHistory.TakeChanged);
  FHistory.Clear;
  Assert.IsTrue(FHistory.TakeChanged);
  FHistory.Clear;
  Assert.IsFalse(FHistory.TakeChanged, 'leere Liste leeren ändert nichts');
end;

procedure TAtlasDebugExceptionsTests.LocationAndThreadText;
var
  Entry: TAtlasDebugException;
begin
  Entry := Sample(1, 'EA', '', 'C:\Projekte\Unit1.pas', 42);
  Assert.AreEqual('Unit1.pas:42', Entry.LocationText);
  Assert.IsTrue(Entry.HasSource);
  Assert.AreEqual('Hauptthread 1234', Entry.ThreadText('Hauptthread'));
  Entry.ThreadName := 'Lader';
  Assert.AreEqual('Lader (1234)', Entry.ThreadText('Hauptthread'));
  Entry.FileName := '';
  Entry.Line := 0;
  Assert.AreEqual('Unit1.TForm1.Button1Click', Entry.LocationText);
  Assert.IsFalse(Entry.HasSource);
  Entry.Routine := '';
  Assert.AreEqual('', Entry.LocationText);
end;

procedure TAtlasDebugExceptionsTests.CopyTextHasClassMessageAndLocation;
var
  Entry: TAtlasDebugException;
  Text: string;
begin
  Entry := Sample(1, 'EConvertError', 'kein Integer', 'C:\P\Unit1.pas', 42);
  Entry.Count := 3;
  Entry.Frames := TArray<TAtlasDebugFrame>.Create(TAtlasDebugFrame.Create(':0040A1B2 System._RaiseExcept', '', 0),
    TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', 'C:\P\Unit1.pas', 42));
  Text := Entry.CopyText;
  Assert.StartsWith('EConvertError: kein Integer', Text);
  Assert.IsTrue(Pos('Unit1.TForm1.Button1Click', Text) > 0);
  Assert.IsTrue(Pos('C:\P\Unit1.pas(42)', Text) > 0);
  Assert.IsTrue(Pos('Thread 1234', Text) > 0);
  Assert.IsTrue(Pos('3 x', Text) > 0);
  Assert.IsTrue(Pos('  :0040A1B2 System._RaiseExcept', Text) > 0, 'Aufrufstapel (#578)');
  Assert.IsTrue(Pos('  Unit1.TForm1.Button1Click(Self=$02A3F2C0) (Unit1.pas:42)', Text) > 0);
end;

procedure TAtlasDebugExceptionsTests.ParseEnglishDialog;
var
  ExceptionClass, Message: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse(
    'Project Project1.exe raised exception class EConvertError with message ''''abc'' is not a valid integer value''.',
    ExceptionClass, Message));
  Assert.AreEqual('EConvertError', ExceptionClass);
  Assert.AreEqual('''abc'' is not a valid integer value', Message);
end;

procedure TAtlasDebugExceptionsTests.ParseGermanDialog;
var
  ExceptionClass, Message: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Im Projekt Project1.exe ist eine Exception der Klasse ' +
    'System.SysUtils.EAccessViolation mit der Meldung ''Zugriffsverletzung bei Adresse 00405A1C'' aufgetreten.',
    ExceptionClass, Message));
  Assert.AreEqual('System.SysUtils.EAccessViolation', ExceptionClass);
  Assert.AreEqual('Zugriffsverletzung bei Adresse 00405A1C', Message);
end;

procedure TAtlasDebugExceptionsTests.ParseMessageWithQuotes;
var
  ExceptionClass, Message: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Project X.exe raised exception class EMyError with message' +
    #13#10 + '''Datei ''a.txt'' fehlt''.', ExceptionClass, Message));
  Assert.AreEqual('EMyError', ExceptionClass);
  Assert.AreEqual('Datei ''a.txt'' fehlt', Message, 'Meldung bis zum letzten Hochkomma, auch über Zeilen');
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Project X.exe raised exception class EAbort.', ExceptionClass,
    Message));
  Assert.AreEqual('EAbort', ExceptionClass, 'Punkt am Satzende gehört nicht zur Klasse');
  Assert.AreEqual('', Message);
end;

procedure TAtlasDebugExceptionsTests.ParseCodeAndNothing;
var
  ExceptionClass, Message: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Project X.exe raised exception class $C0000005 with message ' +
    '''access violation at 0x00405a1c''.', ExceptionClass, Message));
  Assert.AreEqual('$C0000005', ExceptionClass);
  Assert.IsFalse(TAtlasDebugExceptionText.Parse('Process stopped. Use Step or Run to continue.', ExceptionClass,
    Message));
  Assert.AreEqual('', ExceptionClass);
  Assert.IsFalse(TAtlasDebugExceptionText.Parse('', ExceptionClass, Message));
end;

procedure TAtlasDebugExceptionsTests.UnquoteAndClassName;
begin
  Assert.AreEqual('Abc', TAtlasDebugExceptionText.Unquote('''Abc'''));
  Assert.AreEqual('it''s', TAtlasDebugExceptionText.Unquote(' ''it''''s'' '));
  Assert.AreEqual('Abc', TAtlasDebugExceptionText.Unquote('Abc'));
  Assert.IsTrue(TAtlasDebugExceptionText.IsClassName('System.SysUtils.EConvertError'));
  Assert.IsTrue(TAtlasDebugExceptionText.IsClassName('_E1'));
  Assert.IsFalse(TAtlasDebugExceptionText.IsClassName('1E'));
  Assert.IsFalse(TAtlasDebugExceptionText.IsClassName(''));
  Assert.IsFalse(TAtlasDebugExceptionText.IsClassName('E Error'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugExceptionsTests);

end.
