unit Atlas.Core.Files.ExternalChanges.Tests;

// Tests für extern geänderte Dateien (#536).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasExternalChangesTests = class
  public
    [Test]
    procedure FirstLookOnlyRemembers;
    [Test]
    procedure BundlesChangesUntilQuiet;
    [Test]
    procedure DecidesPerFile;
    [Test]
    procedure FirstSaveOfNewFileIsNoChange;
    [Test]
    procedure ChangeBackBeforeQuietCancels;
    [Test]
    procedure DiffShowsChangedLinesOnly;
    [Test]
    procedure TextDiffReportsTrailingNewline;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Files.ExternalChanges,
  Atlas.Core.Files.TextDiff;

function F(const AName: string; AStamp: Int64; AModified: Boolean; AExists: Boolean): TAtlasObservedFile; overload;
begin
  Result := TAtlasObservedFile.Create(AName, AExists, AStamp, AModified);
end;

function F(const AName: string; AStamp: Int64): TAtlasObservedFile; overload;
begin
  Result := F(AName, AStamp, False, True);
end;

function F(const AName: string; AStamp: Int64; AModified: Boolean): TAtlasObservedFile; overload;
begin
  Result := F(AName, AStamp, AModified, True);
end;

function Text(const ADecisions: TArray<TAtlasReloadDecision>): string;
const
  cNames: array[TAtlasReloadAction] of string = ('neu', 'behalten', 'gelöscht');
var
  mDecision: TAtlasReloadDecision;
begin
  Result := '';
  for mDecision in ADecisions do
  begin
    Result := Result + ExtractFileName(mDecision.FileName) + '=' + cNames[mDecision.Action] + ' ';
  end;
end;

procedure TAtlasExternalChangesTests.FirstLookOnlyRemembers;
var
  mChanges: TAtlasExternalChanges;
begin
  mChanges := TAtlasExternalChanges.Create;
  try
    mChanges.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1)], 0);
    Assert.IsFalse(mChanges.Due(10000));
  finally
    mChanges.Free;
  end;
end;

procedure TAtlasExternalChangesTests.BundlesChangesUntilQuiet;
var
  mChanges: TAtlasExternalChanges;
begin
  mChanges := TAtlasExternalChanges.Create;
  try
    mChanges.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1)], 0);
    mChanges.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 1)], 1000);
    Assert.IsFalse(mChanges.Due(1300));
    // Zweite Datei 300 ms später: Der Vorgang verlängert sich.
    mChanges.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 2)], 1300);
    Assert.IsFalse(mChanges.Due(1700));
    Assert.IsTrue(mChanges.Due(1800));
    Assert.AreEqual('A.pas=neu B.pas=neu ', Text(mChanges.TakeBatch));
    mChanges.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 2)], 2000);
    Assert.IsFalse(mChanges.Due(9000));
  finally
    mChanges.Free;
  end;
end;

procedure TAtlasExternalChangesTests.DecidesPerFile;
var
  mChanges: TAtlasExternalChanges;
begin
  mChanges := TAtlasExternalChanges.Create;
  try
    mChanges.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1, True), F('C:\P\C.pas', 1)], 0);
    mChanges.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 2, True), F('C:\P\C.pas', 0, False, False)], 100);
    Assert.IsTrue(mChanges.Due(600));
    Assert.AreEqual('A.pas=neu B.pas=behalten C.pas=gelöscht ', Text(mChanges.TakeBatch));
  finally
    mChanges.Free;
  end;
end;

procedure TAtlasExternalChangesTests.FirstSaveOfNewFileIsNoChange;
var
  mChanges: TAtlasExternalChanges;
begin
  mChanges := TAtlasExternalChanges.Create;
  try
    mChanges.Observe([F('C:\P\Unit2.pas', 0, True, False)], 0);
    mChanges.Observe([F('C:\P\Unit2.pas', 5)], 100);
    Assert.IsFalse(mChanges.Due(5000));
  finally
    mChanges.Free;
  end;
end;

procedure TAtlasExternalChangesTests.ChangeBackBeforeQuietCancels;
var
  mChanges: TAtlasExternalChanges;
begin
  mChanges := TAtlasExternalChanges.Create;
  try
    mChanges.Observe([F('C:\P\A.pas', 1)], 0);
    mChanges.Observe([F('C:\P\A.pas', 2)], 100);
    mChanges.Observe([F('C:\P\A.pas', 1)], 200);
    Assert.IsFalse(mChanges.Due(5000));
    // Geschlossene Dateien werden vergessen; erneut geöffnet zählt wieder als erster Blick.
    mChanges.Observe([], 300);
    mChanges.Observe([F('C:\P\A.pas', 9)], 400);
    Assert.IsFalse(mChanges.Due(5000));
  finally
    mChanges.Free;
  end;
end;

procedure TAtlasExternalChangesTests.DiffShowsChangedLinesOnly;
var
  mLines: TArray<string>;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTextDiff.Lines('a'#13#10'b', 'a'#10'b'))), 'gleich trotz Zeilenenden');
  mLines := TAtlasTextDiff.Lines('a'#10'b'#10'c', 'a'#10'B'#10'c');
  Assert.AreEqual('Zeile 2:|- b|+ B', string.Join('|', mLines));
  mLines := TAtlasTextDiff.Lines('a'#10'c', 'a'#10'b'#10'c');
  Assert.AreEqual('ab Zeile 2:|+ b', string.Join('|', mLines));
end;

procedure TAtlasExternalChangesTests.TextDiffReportsTrailingNewline;
var
  mLines: TArray<string>;
begin
  // Eine zusätzliche letzte Zeilenschaltung ist ein Unterschied (früher von Split verschluckt).
  mLines := TAtlasTextDiff.Lines('a'#10'b', 'a'#10'b'#10);
  Assert.AreEqual('ab Zeile 3:|+ ', string.Join('|', mLines));
  // Alleinstehendes CR trennt Zeilen wie LF.
  Assert.AreEqual(0, Integer(Length(TAtlasTextDiff.Lines('a'#13'b', 'a'#10'b'))), 'CR wie LF');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExternalChangesTests);

end.