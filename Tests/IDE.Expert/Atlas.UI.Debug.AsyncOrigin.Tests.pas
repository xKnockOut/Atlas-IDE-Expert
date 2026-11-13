unit Atlas.UI.Debug.AsyncOrigin.Tests;

// Tests zu den Texten der Herkunft eingereihter Methoden (#859): Überschrift, Zeilen mit zusammengefasster Bibliothek.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasAsyncOriginTextsTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TitleNamesKindAndThread;
    [Test]
    procedure RowsCollapseLibrary;
    [Test]
    procedure EnglishTitle;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.AsyncOrigin,
  Atlas.UI.Debug.AsyncOrigin;

function Entry(AThreadId: Cardinal): TAtlasAsyncEntry;
begin
  Result := Default(TAtlasAsyncEntry);
  Result.ThreadId := AThreadId;
end;

function OwnFrame(const AHeader: string; ALine: Integer): TAtlasDebugFrame;
begin
  Result := TAtlasDebugFrame.Create(AHeader, 'C:\P\Unit1.pas', ALine);
  Result.Own := True;
end;

{ TAtlasAsyncOriginTextsTests }

procedure TAtlasAsyncOriginTextsTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasAsyncOriginTextsTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasAsyncOriginTextsTests.TitleNamesKindAndThread;
begin
  Assert.AreEqual('Eingereiht mit TThread.Queue von Thread 4120',
    TAtlasAsyncOriginTexts.Title(Entry(4120), TAtlasAsyncKind.Queue));
  Assert.AreEqual('Herkunft: 3 Aufrufstellen', TAtlasAsyncOriginTexts.StatusText(3));
end;

procedure TAtlasAsyncOriginTextsTests.RowsCollapseLibrary;
var
  mRows: TArray<string>;
  mIndex: TArray<Integer>;
begin
  mRows := TAtlasAsyncOriginTexts.Rows([OwnFrame('Unit1.TWorker.Execute', 30),
    TAtlasDebugFrame.Create('System.Classes.ThreadProc', '', 0),
    TAtlasDebugFrame.Create('System.ThreadWrapper', '', 0)], mIndex);
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('TWorker.Execute (Unit1.pas:30)', mRows[0]);
  Assert.AreEqual('2 Rahmen der Bibliothek', mRows[1]);
  Assert.AreEqual(0, mIndex[0]);
  Assert.AreEqual(-1, mIndex[1]);
  mRows := nil;
  mIndex := nil;
end;

procedure TAtlasAsyncOriginTextsTests.EnglishTitle;
begin
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('Queued with TTask.Run from thread 7', TAtlasAsyncOriginTexts.Title(Entry(7), TAtlasAsyncKind.TaskRun));
end;

end.
