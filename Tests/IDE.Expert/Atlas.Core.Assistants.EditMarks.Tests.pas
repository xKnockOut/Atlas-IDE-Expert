unit Atlas.Core.Assistants.EditMarks.Tests;

// Randmarken an Zeilen, die ein KI-Assistent geändert hat (#2616, Stufe 2): markierte Zeilen, Nachführen beim
// Tippen, Löschen beim Speichern, eigenes Speichern des Eingangs übergangen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Text.AssistantOrigin,
  Atlas.Core.Assistants.Sessions,
  Atlas.Core.Assistants.EditMarks;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasEditMarksTests = class
  private
    FNow: UInt64;
    FSessions: TAtlasAssistantSessions;
    FMarks: TAtlasEditMarks;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MarksTheChangedLinesWithTheirAssistant;
    [Test]
    procedure DeletionMarksTheLineAfter;
    [Test]
    procedure MarksFollowTypingAboveAndDropChangedLines;
    [Test]
    procedure SaveClearsTheMarks;
    [Test]
    procedure OwnSaveOfTheInboxIsIgnored;
    [Test]
    procedure TwoSessionsGetTwoNumbers;
    [Test]
    procedure StaleLineTextWaits;
  end;

implementation

uses
  System.SysUtils;

const
  cFile = 'C:\Src\Run.pas';
  cBefore = 'unit Run;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10;
  cAfter = 'unit Run;'#13#10'interface'#13#10'procedure A;'#13#10'procedure B;'#13#10'implementation'#13#10'end.'#13#10;

{ TAtlasEditMarksTests }

procedure TAtlasEditMarksTests.Setup;
begin
  FNow := 1000;
  FSessions := TAtlasAssistantSessions.Create;
  FMarks := TAtlasEditMarks.Create(FSessions,
    function: UInt64
    begin
      Result := FNow;
    end);
end;

procedure TAtlasEditMarksTests.TearDown;
begin
  FMarks.Free;
  FSessions.Free;
end;

procedure TAtlasEditMarksTests.MarksTheChangedLinesWithTheirAssistant;
var
  mMark: TAtlasEditMark;
begin
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), cBefore, cAfter, False, 0.5);
  Assert.AreEqual(2, FMarks.CountIn(cFile));
  Assert.IsFalse(FMarks.MarkAt(cFile, 1, '', False, mMark));
  Assert.IsTrue(FMarks.MarkAt('c:\src\run.pas', 2, 'procedure A;', True, mMark));
  Assert.AreEqual('Assistent A', mMark.Origin.Client);
  Assert.AreEqual('3f2a', mMark.Origin.Session);
  Assert.AreEqual(0, mMark.Assistant);
  Assert.AreEqual(0.5, Double(mMark.At), 1e-9);
  Assert.IsTrue(FMarks.MarkAt(cFile, 3, 'procedure B;', True, mMark));
  Assert.IsFalse(FMarks.MarkAt(cFile, 4, 'implementation', True, mMark));
end;

procedure TAtlasEditMarksTests.DeletionMarksTheLineAfter;
var
  mMark: TAtlasEditMark;
begin
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), cAfter, cBefore, False, 0);
  Assert.AreEqual(1, FMarks.CountIn(cFile));
  Assert.IsTrue(FMarks.MarkAt(cFile, 2, 'implementation', True, mMark));
  Assert.AreEqual(2, mMark.Removed);
end;

procedure TAtlasEditMarksTests.MarksFollowTypingAboveAndDropChangedLines;
var
  mMark: TAtlasEditMark;
  mTyped: string;
begin
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), cBefore, cAfter, False, 0);
  // Eine Zeile oben eingefügt: Die Marken rutschen mit.
  mTyped := '// Kopf'#13#10 + cAfter;
  FMarks.Track(cFile, mTyped);
  Assert.IsTrue(FMarks.MarkAt(cFile, 3, 'procedure A;', True, mMark));
  Assert.IsTrue(FMarks.MarkAt(cFile, 4, 'procedure B;', True, mMark));
  // Eine markierte Zeile selbst geändert: Ihre Marke fällt weg, die andere bleibt.
  FMarks.Track(cFile, mTyped.Replace('procedure B;', 'procedure B2;'));
  Assert.IsTrue(FMarks.MarkAt(cFile, 3, 'procedure A;', True, mMark));
  Assert.IsFalse(FMarks.MarkAt(cFile, 4, '', False, mMark));
  Assert.AreEqual(1, FMarks.CountIn(cFile));
end;

procedure TAtlasEditMarksTests.SaveClearsTheMarks;
begin
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), cBefore, cAfter, False, 0);
  FMarks.Saved('C:\Src\Anders.pas');
  Assert.IsTrue(FMarks.HasMarks(cFile));
  FMarks.Saved(cFile);
  Assert.IsFalse(FMarks.HasMarks(cFile));
  Assert.AreEqual(0, FMarks.CountIn(cFile));
end;

procedure TAtlasEditMarksTests.OwnSaveOfTheInboxIsIgnored;
begin
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), cBefore, cAfter, True, 0);
  FNow := FNow + 600;
  FMarks.Saved(cFile);
  Assert.IsTrue(FMarks.HasMarks(cFile), 'Eigenes Speichern des Eingangs');
  FNow := FNow + TAtlasEditMarks.cOwnSaveMs;
  FMarks.Saved(cFile);
  Assert.IsFalse(FMarks.HasMarks(cFile), 'Speichern des Menschen');
end;

procedure TAtlasEditMarksTests.TwoSessionsGetTwoNumbers;
var
  mMark: TAtlasEditMark;
  mThird: string;
begin
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), cBefore, cAfter, False, 0);
  mThird := cAfter.Replace('implementation', 'procedure C;'#13#10'implementation');
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '77c0'), cAfter, mThird, False, 0);
  Assert.IsTrue(FMarks.MarkAt(cFile, 2, 'procedure A;', True, mMark));
  Assert.AreEqual(0, mMark.Assistant);
  Assert.IsTrue(FMarks.MarkAt(cFile, 4, 'procedure C;', True, mMark));
  Assert.AreEqual(1, mMark.Assistant);
  Assert.AreEqual(3, FMarks.CountIn(cFile));
end;

procedure TAtlasEditMarksTests.StaleLineTextWaits;
var
  mMark: TAtlasEditMark;
begin
  FMarks.Edited(cFile, TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), cBefore, cAfter, False, 0);
  Assert.IsFalse(FMarks.MarkAt(cFile, 2, 'procedure A; // getippt', True, mMark));
  Assert.IsTrue(FMarks.MarkAt(cFile, 2, '', False, mMark));
  FMarks.Clear;
  Assert.IsFalse(FMarks.HasMarks(cFile));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditMarksTests);

end.
