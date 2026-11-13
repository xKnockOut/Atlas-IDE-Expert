unit Atlas.Core.Debug.BreakpointCheck.Tests;

// Tests für „Haltepunkte, die nicht greifen werden“ (#577) ohne IDE: Argumente
// je Datei, Antwort des Servers, nicht lesbare Dateien, außerhalb des
// gestarteten Projekts, Sortierung und Verschiebbarkeit.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.BreakpointCheck;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointCheckTests = class
  private
    FSpots: TAtlasBreakpointSpots;
    FProblems: TAtlasBreakpointProblems;
    function Read(const AJson: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ArgumentsGroupLinesByFile;
    [Test]
    procedure ReadsReasonsAndNextLine;
    [Test]
    procedure UnknownReasonAndForeignUriFallAway;
    [Test]
    procedure UnreadableFileReportsEachBreakpoint;
    [Test]
    procedure ForeignFormatIsRejected;
    [Test]
    procedure NotInProjectOnlyForOtherProjects;
    [Test]
    procedure NotInProjectBelowLaunchFolderIsKept;
    [Test]
    procedure SortedByFileAndLineWithoutDuplicates;
    [Test]
    procedure MovableNeedsNextLine;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

{ TAtlasBreakpointCheckTests }

procedure TAtlasBreakpointCheckTests.Setup;
begin
  FSpots := [TAtlasBreakpointSpot.Create('C:\P\Kunden.pas', 'file:///C:/P/Kunden.pas', 9),
    TAtlasBreakpointSpot.Create('C:\P\Kunden.pas', 'file:///C:/P/Kunden.pas', 24),
    TAtlasBreakpointSpot.Create('C:\P\Lager.pas', 'file:///C:/P/Lager.pas', 3)];
end;

procedure TAtlasBreakpointCheckTests.TearDown;
begin
  FSpots := nil;
  FProblems := nil;
end;

function TAtlasBreakpointCheckTests.Read(const AJson: string): Boolean;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasBreakpointCheck.ReadAnswer(mJson, FSpots, FProblems);
  finally
    mJson.Free;
  end;
end;

procedure TAtlasBreakpointCheckTests.ArgumentsGroupLinesByFile;
begin
  Assert.AreEqual('[[{"uri":"file:///C:/P/Kunden.pas","lines":[9,24]},{"uri":"file:///C:/P/Lager.pas","lines":[3]}]]',
    TAtlasBreakpointCheck.Arguments(FSpots));
end;

procedure TAtlasBreakpointCheckTests.ReadsReasonsAndNextLine;
begin
  Assert.IsTrue(Read('{"format":1,"files":[{"uri":"file:///C:/P/Kunden.pas","items":[' +
    '{"line":9,"reason":"noCode","nextLine":11},{"line":24,"reason":"inactive","detail":"RELEASE"}]},' +
    '{"uri":"file:///C:/P/Lager.pas","items":[{"line":3,"reason":"noDebugInfo","detail":"{$D-} (2)"}]}]}'));
  Assert.AreEqual(3, Integer(Length(FProblems)));
  Assert.AreEqual('C:\P\Kunden.pas', FProblems[0].FileName);
  Assert.AreEqual(Ord(TAtlasBreakpointReason.NoCode), Ord(FProblems[0].Reason));
  Assert.AreEqual(11, FProblems[0].NextLine);
  Assert.AreEqual(Ord(TAtlasBreakpointReason.Inactive), Ord(FProblems[1].Reason));
  Assert.AreEqual('RELEASE', FProblems[1].Detail);
  Assert.AreEqual(-1, FProblems[1].NextLine);
  Assert.AreEqual('C:\P\Lager.pas', FProblems[2].FileName);
  Assert.AreEqual(Ord(TAtlasBreakpointReason.NoDebugInfo), Ord(FProblems[2].Reason));
end;

procedure TAtlasBreakpointCheckTests.UnknownReasonAndForeignUriFallAway;
begin
  Assert.IsTrue(Read('{"format":1,"files":[{"uri":"file:///C:/P/Kunden.pas","items":[' +
    '{"line":9,"reason":"spaeter"},{"reason":"noCode"}]},' +
    '{"uri":"file:///C:/Fremd.pas","items":[{"line":1,"reason":"noCode"}]}]}'));
  Assert.AreEqual(0, Integer(Length(FProblems)));
end;

procedure TAtlasBreakpointCheckTests.UnreadableFileReportsEachBreakpoint;
begin
  Assert.IsTrue(Read('{"format":1,"files":[{"uri":"file:///C:/P/Kunden.pas","unreadable":true}]}'));
  Assert.AreEqual(2, Integer(Length(FProblems)));
  Assert.AreEqual(Ord(TAtlasBreakpointReason.Unreadable), Ord(FProblems[0].Reason));
  Assert.AreEqual(24, FProblems[1].Line);
end;

procedure TAtlasBreakpointCheckTests.ForeignFormatIsRejected;
begin
  Assert.IsFalse(Read('{"format":2,"files":[]}'));
  Assert.IsFalse(Read('[]'));
end;

procedure TAtlasBreakpointCheckTests.NotInProjectOnlyForOtherProjects;
begin
  Assert.IsTrue(TAtlasBreakpointCheck.NotInProject('C:\Q\Werkzeug.pas', 'C:\P', False, True));
  Assert.IsFalse(TAtlasBreakpointCheck.NotInProject('C:\Q\Werkzeug.pas', 'C:\P', True, True));
  // Weder Modul des gestarteten noch eines anderen Projekts: Bibliothek oder Package, kann zur Laufzeit dazukommen.
  Assert.IsFalse(TAtlasBreakpointCheck.NotInProject('C:\Delphi\Vcl.Forms.pas', 'C:\P', False, False));
end;

procedure TAtlasBreakpointCheckTests.NotInProjectBelowLaunchFolderIsKept;
begin
  Assert.IsFalse(TAtlasBreakpointCheck.NotInProject('C:\P\Gemeinsam\Werkzeug.pas', 'C:\P\', False, True));
  Assert.IsFalse(TAtlasBreakpointCheck.NotInProject('c:\p\Werkzeug.pas', 'C:\P', False, True));
end;

procedure TAtlasBreakpointCheckTests.SortedByFileAndLineWithoutDuplicates;
var
  mSorted: TAtlasBreakpointProblems;
begin
  FProblems := [TAtlasBreakpointCheck.NotInProjectProblem(FSpots[2]),
    TAtlasBreakpointCheck.NotInProjectProblem(FSpots[1]),
    TAtlasBreakpointCheck.NotInProjectProblem(FSpots[0])];
  FProblems[1].Reason := TAtlasBreakpointReason.Inactive;
  FProblems := FProblems + [TAtlasBreakpointCheck.NotInProjectProblem(FSpots[1])];
  mSorted := TAtlasBreakpointCheck.Sorted(FProblems);
  Assert.AreEqual(3, Integer(Length(mSorted)));
  Assert.AreEqual(9, mSorted[0].Line);
  Assert.AreEqual(24, mSorted[1].Line);
  Assert.AreEqual(Ord(TAtlasBreakpointReason.Inactive), Ord(mSorted[1].Reason));
  Assert.AreEqual('C:\P\Lager.pas', mSorted[2].FileName);
end;

procedure TAtlasBreakpointCheckTests.MovableNeedsNextLine;
begin
  Assert.IsTrue(Read('{"format":1,"files":[{"uri":"file:///C:/P/Kunden.pas","items":[' +
    '{"line":9,"reason":"noCode","nextLine":11},{"line":24,"reason":"noCode","nextLine":-1}]}]}'));
  Assert.IsTrue(FProblems[0].CanMove);
  Assert.IsFalse(FProblems[1].CanMove);
  Assert.AreEqual(1, TAtlasBreakpointCheck.Movable(FProblems));
end;

end.
