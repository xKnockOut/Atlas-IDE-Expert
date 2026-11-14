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
  [Category('Atlas.IDE.Debugger')]
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
  Result := TAtlasDebugException.Create(ATime, AClass, AMessage, 1234, '').At(AFile, ALine,
    'Unit1.TForm1.Button1Click');
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
  mEntry: TAtlasDebugException;
begin
  FHistory.Add(Sample(1, 'EConvertError', 'eins', 'C:\P\Unit1.pas', 42));
  mEntry := Sample(2, 'econverterror', 'zwei', 'c:\p\UNIT1.pas', 42);
  mEntry.ThreadId := 99;
  mEntry.Frames := TArray<TAtlasDebugFrame>.Create(TAtlasDebugFrame.Create('Unit1.Laden', 'C:\P\Unit1.pas', 42));
  Assert.AreEqual(0, FHistory.Add(mEntry));
  Assert.AreEqual(1, FHistory.Count, 'gleiche Klasse am gleichen Ort ohne Groß/klein');
  Assert.AreEqual(2, FHistory[0].Count);
  Assert.AreEqual('zwei', FHistory[0].Message, 'Meldung des letzten Auftretens');
  Assert.AreEqual(99, Integer(FHistory[0].ThreadId));
  Assert.AreEqual<TDateTime>(1, FHistory[0].FirstTime, 'zuerst gesehen bleibt');
  Assert.AreEqual<TDateTime>(2, FHistory[0].LastTime, 'zuletzt gesehen');
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
  mFirst, mSecond, mFound: TAtlasDebugException;
begin
  mFirst := TAtlasDebugException.Create(1, 'EOSError', '', 1, '').At('', 0, 'System.SysUtils.RaiseLastOSError');
  mSecond := TAtlasDebugException.Create(2, 'EOSError', '', 1, '').At('', 0, 'Vcl.Forms.TApplication.Run');
  FHistory.Add(mFirst);
  FHistory.Add(mSecond);
  Assert.AreEqual(2, FHistory.Count, 'ohne Datei unterscheidet die Routine');
  Assert.IsTrue(FHistory.TryFind(mFirst.Key, mFound));
  Assert.AreEqual('System.SysUtils.RaiseLastOSError', mFound.Routine);
  Assert.IsFalse(FHistory.TryFind('gibt|es|nicht', mFound));
end;

procedure TAtlasDebugExceptionsTests.StartSessionClears;
var
  mSession: Integer;
begin
  FHistory.Add(Sample(1, 'EConvertError', '', 'Unit1.pas', 1));
  mSession := FHistory.Session;
  FHistory.StartSession;
  Assert.AreEqual(0, FHistory.Count);
  Assert.AreEqual(mSession + 1, FHistory.Session);
  Assert.AreEqual(0, FHistory.Total);
end;

procedure TAtlasDebugExceptionsTests.FullHistoryDropsOldest;
var
  mHistory: TAtlasDebugExceptionHistory;
begin
  mHistory := TAtlasDebugExceptionHistory.Create(2);
  try
    mHistory.Add(Sample(1, 'EA', '', 'Unit1.pas', 1));
    mHistory.Add(Sample(2, 'EB', '', 'Unit1.pas', 2));
    // EA erneut: zuletzt gesehen; verdrängt wird EB.
    mHistory.Add(Sample(3, 'EA', '', 'Unit1.pas', 1));
    mHistory.Add(Sample(4, 'EC', '', 'Unit1.pas', 3));
    Assert.AreEqual(2, mHistory.Count);
    Assert.AreEqual('EA', mHistory[0].ExceptionClass);
    Assert.AreEqual('EC', mHistory[1].ExceptionClass);
  finally
    mHistory.Free;
  end;
  Assert.AreEqual(1000, TAtlasDebugExceptionHistory.cMaxEntries);
end;

procedure TAtlasDebugExceptionsTests.FilterByClassAndWords;
var
  mHits: TArray<Integer>;
begin
  FHistory.Add(Sample(1, 'EConvertError', '''abc'' ist kein gültiger Integerwert', 'Kunde.pas', 10));
  FHistory.Add(Sample(2, 'EAccessViolation', 'Zugriffsverletzung bei Adresse 0040', 'Lager.pas', 20));
  FHistory.Add(Sample(3, 'EConvertError', 'Datum ungültig', 'Lager.pas', 30));
  mHits := FHistory.Filter('EConvertError', '');
  Assert.AreEqual(2, Integer(Length(mHits)));
  mHits := FHistory.Filter('', 'lager ungültig');
  Assert.AreEqual(1, Integer(Length(mHits)), 'jedes Wort muss vorkommen');
  Assert.AreEqual(2, mHits[0]);
  mHits := FHistory.Filter('', '1234');
  Assert.AreEqual(3, Integer(Length(mHits)), 'Thread-Kennung zählt mit');
  mHits := FHistory.Filter('econverterror', 'Kunde.pas:10');
  Assert.AreEqual(1, Integer(Length(mHits)), 'Ort und Klasse ohne Groß/klein');
  Assert.AreEqual(0, Integer(Length(FHistory.Filter('EAccessViolation', 'Kunde'))));
end;

procedure TAtlasDebugExceptionsTests.FilterNewestFirst;
var
  mHits: TArray<Integer>;
begin
  FHistory.Add(Sample(5, 'EA', '', 'Unit1.pas', 1));
  FHistory.Add(Sample(3, 'EB', '', 'Unit1.pas', 2));
  FHistory.Add(Sample(5, 'EC', '', 'Unit1.pas', 3));
  FHistory.Add(Sample(9, 'EB', '', 'Unit1.pas', 2));
  mHits := FHistory.Filter('', '');
  Assert.AreEqual(3, Integer(Length(mHits)));
  Assert.AreEqual(1, mHits[0], 'EB zuletzt gesehen');
  Assert.AreEqual(2, mHits[1], 'bei gleicher Zeit der spätere Eintrag zuerst');
  Assert.AreEqual(0, mHits[2]);
end;

procedure TAtlasDebugExceptionsTests.ClassesSortedWithoutDuplicates;
var
  mClasses: TArray<string>;
begin
  FHistory.Add(Sample(1, 'EConvertError', '', 'Unit1.pas', 1));
  FHistory.Add(Sample(2, 'EAccessViolation', '', 'Unit1.pas', 2));
  FHistory.Add(Sample(3, 'EConvertError', '', 'Unit1.pas', 3));
  mClasses := FHistory.Classes;
  Assert.AreEqual(2, Integer(Length(mClasses)));
  Assert.AreEqual('EAccessViolation', mClasses[0]);
  Assert.AreEqual('EConvertError', mClasses[1]);
end;

procedure TAtlasDebugExceptionsTests.IgnoredStaysOnlyWhileAllIgnored;
var
  mEntry: TAtlasDebugException;
begin
  mEntry := Sample(1, 'EAbort', '', 'Unit1.pas', 1);
  mEntry.Ignored := True;
  FHistory.Add(mEntry);
  mEntry.LastTime := 2;
  FHistory.Add(mEntry);
  Assert.IsTrue(FHistory[0].Ignored);
  mEntry.Ignored := False;
  FHistory.Add(mEntry);
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
  mEntry: TAtlasDebugException;
begin
  mEntry := Sample(1, 'EA', '', 'C:\Projekte\Unit1.pas', 42);
  Assert.AreEqual('Unit1.pas:42', mEntry.LocationText);
  Assert.IsTrue(mEntry.HasSource);
  Assert.AreEqual('Hauptthread 1234', mEntry.ThreadText('Hauptthread'));
  mEntry.ThreadName := 'Lader';
  Assert.AreEqual('Lader (1234)', mEntry.ThreadText('Hauptthread'));
  mEntry.FileName := '';
  mEntry.Line := 0;
  Assert.AreEqual('Unit1.TForm1.Button1Click', mEntry.LocationText);
  Assert.IsFalse(mEntry.HasSource);
  mEntry.Routine := '';
  Assert.AreEqual('', mEntry.LocationText);
end;

procedure TAtlasDebugExceptionsTests.CopyTextHasClassMessageAndLocation;
var
  mEntry: TAtlasDebugException;
  mText: string;
begin
  mEntry := Sample(1, 'EConvertError', 'kein Integer', 'C:\P\Unit1.pas', 42);
  mEntry.Count := 3;
  mEntry.Frames := TArray<TAtlasDebugFrame>.Create(TAtlasDebugFrame.Create(':0040A1B2 System._RaiseExcept', '', 0),
    TAtlasDebugFrame.Create('Unit1.TForm1.Button1Click(Self=$02A3F2C0)', 'C:\P\Unit1.pas', 42));
  mText := mEntry.CopyText;
  Assert.StartsWith('EConvertError: kein Integer', mText);
  Assert.IsTrue(Pos('Unit1.TForm1.Button1Click', mText) > 0);
  Assert.IsTrue(Pos('C:\P\Unit1.pas(42)', mText) > 0);
  Assert.IsTrue(Pos('Thread 1234', mText) > 0);
  Assert.IsTrue(Pos('3 x', mText) > 0);
  Assert.IsTrue(Pos('  :0040A1B2 System._RaiseExcept', mText) > 0, 'Aufrufstapel (#578)');
  Assert.IsTrue(Pos('  Unit1.TForm1.Button1Click(Self=$02A3F2C0) (Unit1.pas:42)', mText) > 0);
end;

procedure TAtlasDebugExceptionsTests.ParseEnglishDialog;
var
  mExceptionClass, mMessage: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse(
    'Project Project1.exe raised exception class EConvertError with message ''''abc'' is not a valid integer value''.',
    mExceptionClass, mMessage));
  Assert.AreEqual('EConvertError', mExceptionClass);
  Assert.AreEqual('''abc'' is not a valid integer value', mMessage);
end;

procedure TAtlasDebugExceptionsTests.ParseGermanDialog;
var
  mExceptionClass, mMessage: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Im Projekt Project1.exe ist eine Exception der Klasse ' +
    'System.SysUtils.EAccessViolation mit der Meldung ''Zugriffsverletzung bei Adresse 00405A1C'' aufgetreten.',
    mExceptionClass, mMessage));
  Assert.AreEqual('System.SysUtils.EAccessViolation', mExceptionClass);
  Assert.AreEqual('Zugriffsverletzung bei Adresse 00405A1C', mMessage);
end;

procedure TAtlasDebugExceptionsTests.ParseMessageWithQuotes;
var
  mExceptionClass, mMessage: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Project X.exe raised exception class EMyError with message' +
    #13#10 + '''Datei ''a.txt'' fehlt''.', mExceptionClass, mMessage));
  Assert.AreEqual('EMyError', mExceptionClass);
  Assert.AreEqual('Datei ''a.txt'' fehlt', mMessage, 'Meldung bis zum letzten Hochkomma, auch über Zeilen');
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Project X.exe raised exception class EAbort.', mExceptionClass,
    mMessage));
  Assert.AreEqual('EAbort', mExceptionClass, 'Punkt am Satzende gehört nicht zur Klasse');
  Assert.AreEqual('', mMessage);
end;

procedure TAtlasDebugExceptionsTests.ParseCodeAndNothing;
var
  mExceptionClass, mMessage: string;
begin
  Assert.IsTrue(TAtlasDebugExceptionText.Parse('Project X.exe raised exception class $C0000005 with message ' +
    '''access violation at 0x00405a1c''.', mExceptionClass, mMessage));
  Assert.AreEqual('$C0000005', mExceptionClass);
  Assert.IsFalse(TAtlasDebugExceptionText.Parse('Process stopped. Use Step or Run to continue.', mExceptionClass,
    mMessage));
  Assert.AreEqual('', mExceptionClass);
  Assert.IsFalse(TAtlasDebugExceptionText.Parse('', mExceptionClass, mMessage));
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
