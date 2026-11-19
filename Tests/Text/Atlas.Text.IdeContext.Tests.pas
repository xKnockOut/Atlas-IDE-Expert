unit Atlas.Text.IdeContext.Tests;

// Zustand der IDE für KI-Assistenten (#2050): Datei schreiben und lesen, Auswahl kürzen, Meldungen des Builds
// auswählen, Schlüssel der Wechsel (Tippen in einer Methode schreibt nicht).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIdeContextsTests = class
  public
    [Test]
    procedure RoundTrip;
    [Test]
    procedure MissingPartsStayEmpty;
    [Test]
    procedure RejectsBrokenOrNewerFiles;
    [Test]
    procedure ShortensSelection;
    [Test]
    procedure RelevantMessagesErrorsFirst;
    [Test]
    procedure ChangeKeyIgnoresCursorInMethod;
    [Test]
    procedure FileNameHasPid;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Text.IdeContext;

function Message(const ASeverity, AText: string): TIdeContextMessage;
begin
  Result := Default(TIdeContextMessage);
  Result.FileName := 'C:\Quellen\Kunde.pas';
  Result.Line := 12;
  Result.Column := 3;
  Result.Severity := ASeverity;
  Result.Code := 'W1036';
  Result.Text := AText;
end;

function Sample: TIdeContext;
begin
  Result := Default(TIdeContext);
  Result.Pid := 4711;
  Result.AtUtc := EncodeDateTime(2026, 11, 18, 21, 30, 0, 0);
  Result.Editor.Known := True;
  Result.Editor.FileName := 'C:\Quellen\Kunde.pas';
  Result.Editor.Line := 118;
  Result.Editor.Column := 3;
  Result.Editor.Modified := True;
  Result.Editor.Method := 'TKunde.Laden';
  Result.Selection.Known := True;
  Result.Selection.StartLine := 121;
  Result.Selection.StartColumn := 1;
  Result.Selection.EndLine := 124;
  Result.Selection.EndColumn := 5;
  Result.Selection.Length := 80;
  Result.Selection.Text := 'mZeile := Größe;';
  Result.Project.FileName := 'C:\Quellen\Kunde.dproj';
  Result.Project.Configuration := 'Debug';
  Result.Project.Platform := 'Win64';
  Result.Project.Group := 'C:\Quellen\Alle.groupproj';
  Result.Build.Known := True;
  Result.Build.Project := 'C:\Quellen\Kunde.dproj';
  Result.Build.Kind := 'make';
  Result.Build.Warnings := 1;
  Result.Build.Success := True;
  Result.Build.FinishedAtUtc := EncodeDateTime(2026, 11, 18, 21, 28, 0, 0);
  Result.Build.Messages := [Message('warning', 'Variable ist möglicherweise nicht initialisiert')];
  Result.Tabs := ['C:\Quellen\Kunde.pas', 'C:\Quellen\Auftrag.pas'];
end;

procedure TIdeContextsTests.RoundTrip;
var
  mRead: TIdeContext;
begin
  Assert.IsTrue(TIdeContexts.Parse(TIdeContexts.ToJson(Sample), mRead));
  Assert.AreEqual(Int64(4711), Int64(mRead.Pid));
  Assert.IsTrue(SameDateTime(Sample.AtUtc, mRead.AtUtc));
  Assert.AreEqual('TKunde.Laden', mRead.Editor.Method);
  Assert.AreEqual(118, mRead.Editor.Line);
  Assert.IsTrue(mRead.Editor.Modified);
  Assert.AreEqual(124, mRead.Selection.EndLine);
  Assert.AreEqual('mZeile := Größe;', mRead.Selection.Text);
  Assert.AreEqual('Win64', mRead.Project.Platform);
  Assert.AreEqual('C:\Quellen\Alle.groupproj', mRead.Project.Group);
  Assert.IsTrue(mRead.Build.Known);
  Assert.AreEqual(1, Integer(Length(mRead.Build.Messages)));
  Assert.AreEqual('W1036', mRead.Build.Messages[0].Code);
  Assert.AreEqual(12, mRead.Build.Messages[0].Line);
  Assert.AreEqual(2, Integer(Length(mRead.Tabs)));
  Assert.AreEqual('C:\Quellen\Auftrag.pas', mRead.Tabs[1]);
end;

procedure TIdeContextsTests.MissingPartsStayEmpty;
var
  mContext, mRead: TIdeContext;
begin
  mContext := Default(TIdeContext);
  mContext.Pid := 1;
  Assert.IsTrue(TIdeContexts.Parse(TIdeContexts.ToJson(mContext), mRead));
  Assert.IsFalse(mRead.Editor.Known);
  Assert.IsFalse(mRead.Selection.Known);
  Assert.IsFalse(mRead.Build.Known);
  Assert.AreEqual('', mRead.Project.FileName);
  Assert.AreEqual(0, Integer(Length(mRead.Tabs)));
end;

procedure TIdeContextsTests.RejectsBrokenOrNewerFiles;
var
  mRead: TIdeContext;
begin
  Assert.IsFalse(TIdeContexts.Parse('', mRead));
  Assert.IsFalse(TIdeContexts.Parse('{"format":1}', mRead), 'ohne pid');
  Assert.IsFalse(TIdeContexts.Parse('{"format":99,"pid":3}', mRead), 'höheres Format');
  Assert.IsTrue(TIdeContexts.Parse('{"format":1,"pid":3}', mRead));
end;

procedure TIdeContextsTests.ShortensSelection;
var
  mTruncated: Boolean;
begin
  Assert.AreEqual('abc', TIdeContexts.Shorten('abc', 4000, mTruncated));
  Assert.IsFalse(mTruncated);
  Assert.AreEqual('ab', TIdeContexts.Shorten('abc', 2, mTruncated));
  Assert.IsTrue(mTruncated);
  Assert.AreEqual('', TIdeContexts.Shorten('abc', 0, mTruncated), '0 = kein Text');
  Assert.IsTrue(mTruncated);
  Assert.AreEqual('a', TIdeContexts.Shorten('a' + #$D83D#$DE00, 2, mTruncated), 'kein halbes Ersatzzeichenpaar');
end;

procedure TIdeContextsTests.RelevantMessagesErrorsFirst;
var
  mMessages, mRelevant: TArray<TIdeContextMessage>;
  mIndex: Integer;
begin
  mMessages := [Message('hint', 'h'), Message('warning', 'w'), Message('error', 'e'), Message('fatal', 'f')];
  mRelevant := TIdeContexts.Relevant(mMessages);
  Assert.AreEqual(3, Integer(Length(mRelevant)), 'Hinweise fallen weg');
  Assert.AreEqual('e', mRelevant[0].Text);
  Assert.AreEqual('f', mRelevant[1].Text);
  Assert.AreEqual('w', mRelevant[2].Text);
  mMessages := nil;
  for mIndex := 1 to TIdeContexts.cMaxMessages + 5 do
  begin
    mMessages := mMessages + [Message('warning', IntToStr(mIndex))];
  end;
  Assert.AreEqual(TIdeContexts.cMaxMessages, Integer(Length(TIdeContexts.Relevant(mMessages))));
end;

procedure TIdeContextsTests.ChangeKeyIgnoresCursorInMethod;
var
  mBefore, mAfter: TIdeContext;
begin
  mBefore := Sample;
  mAfter := Sample;
  mAfter.Editor.Line := 140;
  mAfter.Editor.Column := 9;
  mAfter.Editor.Modified := False;
  mAfter.AtUtc := mAfter.AtUtc + 1;
  Assert.AreEqual(TIdeContexts.ChangeKey(mBefore), TIdeContexts.ChangeKey(mAfter), 'Tippen in der Methode');
  mAfter.Editor.Method := 'TKunde.Speichern';
  Assert.AreNotEqual(TIdeContexts.ChangeKey(mBefore), TIdeContexts.ChangeKey(mAfter), 'andere Methode');
  mAfter := Sample;
  mAfter.Selection.EndLine := 125;
  Assert.AreNotEqual(TIdeContexts.ChangeKey(mBefore), TIdeContexts.ChangeKey(mAfter), 'andere Auswahl');
  mAfter := Sample;
  mAfter.Build.FinishedAtUtc := mAfter.Build.FinishedAtUtc + 1;
  Assert.AreNotEqual(TIdeContexts.ChangeKey(mBefore), TIdeContexts.ChangeKey(mAfter), 'neuer Build');
  mAfter := Sample;
  mAfter.Tabs := ['C:\Quellen\Auftrag.pas', 'C:\Quellen\Kunde.pas'];
  Assert.AreNotEqual(TIdeContexts.ChangeKey(mBefore), TIdeContexts.ChangeKey(mAfter), 'Reiter verschoben');
  mAfter := Sample;
  mAfter.Project.Platform := 'Win32';
  Assert.AreNotEqual(TIdeContexts.ChangeKey(mBefore), TIdeContexts.ChangeKey(mAfter), 'andere Plattform');
end;

procedure TIdeContextsTests.FileNameHasPid;
begin
  Assert.EndsWith('ide-context-4711.json', TIdeContexts.FileName('Atlas', 4711));
end;

initialization
  TDUnitX.RegisterTestFixture(TIdeContextsTests);

end.
