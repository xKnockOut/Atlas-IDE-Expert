unit Atlas.Common.Diagnostics.CrashSkip.Tests;

// Tests für TCrashSkips (#1355): Ab dem zweiten Absturz derselben Kombination
// wird übersprungen, bis sich der Inhalt ändert oder „Erneut versuchen“.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Diagnostics.CrashSkip;

type
  [TestFixture]
  TCrashSkipTests = class
  private
    FSkips: TCrashSkips;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChecksumIsStableAndDiffers;
    [Test]
    procedure SecondCrashStartsSkipping;
    [Test]
    procedure OtherContentCountsFromStart;
    [Test]
    procedure ChangedContentEndsSkipping;
    [Test]
    procedure RetryEndsSkippingForUri;
    [Test]
    procedure RetryWithoutUriEndsAll;
    [Test]
    procedure OtherMethodIsNotSkipped;
    [Test]
    procedure JsonKeepsEntries;
    [Test]
    procedure UnreadableJsonGivesNoEntries;
  end;

implementation

uses
  System.SysUtils;

const
  cUri = 'file:///C:/P/UI.Auftrag.pas';
  cHover = 'textDocument/hover';

procedure TCrashSkipTests.Setup;
begin
  FSkips := TCrashSkips.Create;
end;

procedure TCrashSkipTests.TearDown;
begin
  FreeAndNil(FSkips);
end;

procedure TCrashSkipTests.ChecksumIsStableAndDiffers;
begin
  Assert.AreEqual(TCrashSkips.Checksum('unit A;'), TCrashSkips.Checksum('unit A;'));
  Assert.AreNotEqual(TCrashSkips.Checksum('unit A;'), TCrashSkips.Checksum('unit B;'));
  Assert.AreEqual(16, Length(TCrashSkips.Checksum('')));
  // FNV-1a-Startwert für leeren Text.
  Assert.AreEqual('CBF29CE484222325', UpperCase(TCrashSkips.Checksum('')));
end;

procedure TCrashSkipTests.SecondCrashStartsSkipping;
var
  mEntry: TCrashSkipEntry;
  mChanged: Boolean;
begin
  Assert.IsFalse(FSkips.Crashed(cHover, cUri, 'A', 'fall1', 'EStackOverflow'));
  Assert.IsTrue(FSkips.Watched(cHover, cUri));
  Assert.IsFalse(FSkips.Skip(cHover, cUri, 'A', mEntry, mChanged));
  Assert.IsTrue(FSkips.Crashed(cHover, cUri, 'A', 'fall2', 'EStackOverflow'));
  Assert.IsTrue(FSkips.Skip(cHover, cUri, 'A', mEntry, mChanged));
  Assert.IsFalse(mChanged);
  Assert.AreEqual('fall2', mEntry.CaseFolder);
  Assert.AreEqual(2, mEntry.Crashes);
  Assert.AreEqual(1, Integer(Length(FSkips.Skipped)));
  // Der dritte Absturz meldet nicht erneut den Beginn.
  Assert.IsFalse(FSkips.Crashed(cHover, cUri, 'A', 'fall3', 'EStackOverflow'));
end;

procedure TCrashSkipTests.OtherContentCountsFromStart;
var
  mEntry: TCrashSkipEntry;
  mChanged: Boolean;
begin
  FSkips.Crashed(cHover, cUri, 'A', 'fall1', 'E');
  Assert.IsFalse(FSkips.Crashed(cHover, cUri, 'B', 'fall2', 'E'));
  Assert.IsFalse(FSkips.Skip(cHover, cUri, 'B', mEntry, mChanged));
end;

procedure TCrashSkipTests.ChangedContentEndsSkipping;
var
  mEntry: TCrashSkipEntry;
  mChanged: Boolean;
  mEnded: TArray<TCrashSkipEntry>;
begin
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  Assert.IsFalse(FSkips.Skip(cHover, cUri, 'B', mEntry, mChanged));
  Assert.IsTrue(mChanged);
  Assert.AreEqual(0, FSkips.Count);
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  mEnded := FSkips.Changed(cUri, 'C');
  Assert.AreEqual(1, Integer(Length(mEnded)));
  Assert.IsFalse(FSkips.WatchedUri(cUri));
  // Gleicher Inhalt: bleibt.
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  Assert.AreEqual(0, Integer(Length(FSkips.Changed(cUri, 'A'))));
  Assert.AreEqual(1, FSkips.Count);
end;

procedure TCrashSkipTests.RetryEndsSkippingForUri;
var
  mEntry: TCrashSkipEntry;
  mChanged: Boolean;
begin
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Crashed(cHover, 'file:///b.pas', 'A', 'f', 'E');
  FSkips.Crashed(cHover, 'file:///b.pas', 'A', 'f', 'E');
  Assert.AreEqual(1, Integer(Length(FSkips.Retry(cUri))));
  Assert.IsFalse(FSkips.Skip(cHover, cUri, 'A', mEntry, mChanged));
  Assert.IsTrue(FSkips.Skip(cHover, 'file:///b.pas', 'A', mEntry, mChanged));
end;

procedure TCrashSkipTests.RetryWithoutUriEndsAll;
begin
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Crashed(cHover, 'file:///b.pas', 'A', 'f', 'E');
  Assert.AreEqual(1, Integer(Length(FSkips.Retry(''))));
  Assert.AreEqual(0, FSkips.Count);
end;

procedure TCrashSkipTests.OtherMethodIsNotSkipped;
var
  mEntry: TCrashSkipEntry;
  mChanged: Boolean;
begin
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  Assert.IsFalse(FSkips.Watched('textDocument/completion', cUri));
  Assert.IsFalse(FSkips.Skip('textDocument/completion', cUri, 'A', mEntry, mChanged));
end;

procedure TCrashSkipTests.JsonKeepsEntries;
var
  mOther: TCrashSkips;
  mEntry: TCrashSkipEntry;
  mChanged: Boolean;
begin
  FSkips.Crashed(cHover, cUri, 'A', 'fall', 'EStackOverflow');
  FSkips.Crashed(cHover, cUri, 'A', 'fall', 'EStackOverflow');
  mOther := TCrashSkips.Create;
  try
    mOther.Load(FSkips.ToJson);
    Assert.IsTrue(mOther.Skip(cHover, cUri, 'A', mEntry, mChanged));
    Assert.AreEqual('fall', mEntry.CaseFolder);
    Assert.AreEqual('EStackOverflow', mEntry.ExceptionClass);
  finally
    mOther.Free;
  end;
end;

procedure TCrashSkipTests.UnreadableJsonGivesNoEntries;
begin
  FSkips.Crashed(cHover, cUri, 'A', 'f', 'E');
  FSkips.Load('kein JSON');
  Assert.AreEqual(0, FSkips.Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TCrashSkipTests);

end.
