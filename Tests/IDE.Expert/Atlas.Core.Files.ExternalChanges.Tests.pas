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

function F(const AName: string; AStamp: Int64; AModified: Boolean = False; AExists: Boolean = True): TAtlasObservedFile;
begin
  Result := TAtlasObservedFile.Create(AName, AExists, AStamp, AModified);
end;

function Text(const ADecisions: TArray<TAtlasReloadDecision>): string;
const
  Names: array[TAtlasReloadAction] of string = ('neu', 'behalten', 'gelöscht');
var
  Decision: TAtlasReloadDecision;
begin
  Result := '';
  for Decision in ADecisions do
    Result := Result + ExtractFileName(Decision.FileName) + '=' + Names[Decision.Action] + ' ';
end;

procedure TAtlasExternalChangesTests.FirstLookOnlyRemembers;
var
  Changes: TAtlasExternalChanges;
begin
  Changes := TAtlasExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1)], 0);
    Assert.IsFalse(Changes.Due(10000));
  finally
    Changes.Free;
  end;
end;

procedure TAtlasExternalChangesTests.BundlesChangesUntilQuiet;
var
  Changes: TAtlasExternalChanges;
begin
  Changes := TAtlasExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1)], 0);
    Changes.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 1)], 1000);
    Assert.IsFalse(Changes.Due(1300));
    // Zweite Datei 300 ms später: Der Vorgang verlängert sich.
    Changes.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 2)], 1300);
    Assert.IsFalse(Changes.Due(1700));
    Assert.IsTrue(Changes.Due(1800));
    Assert.AreEqual('A.pas=neu B.pas=neu ', Text(Changes.TakeBatch));
    Changes.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 2)], 2000);
    Assert.IsFalse(Changes.Due(9000));
  finally
    Changes.Free;
  end;
end;

procedure TAtlasExternalChangesTests.DecidesPerFile;
var
  Changes: TAtlasExternalChanges;
begin
  Changes := TAtlasExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1, True), F('C:\P\C.pas', 1)], 0);
    Changes.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 2, True), F('C:\P\C.pas', 0, False, False)], 100);
    Assert.IsTrue(Changes.Due(600));
    Assert.AreEqual('A.pas=neu B.pas=behalten C.pas=gelöscht ', Text(Changes.TakeBatch));
  finally
    Changes.Free;
  end;
end;

procedure TAtlasExternalChangesTests.FirstSaveOfNewFileIsNoChange;
var
  Changes: TAtlasExternalChanges;
begin
  Changes := TAtlasExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\Unit2.pas', 0, True, False)], 0);
    Changes.Observe([F('C:\P\Unit2.pas', 5)], 100);
    Assert.IsFalse(Changes.Due(5000));
  finally
    Changes.Free;
  end;
end;

procedure TAtlasExternalChangesTests.ChangeBackBeforeQuietCancels;
var
  Changes: TAtlasExternalChanges;
begin
  Changes := TAtlasExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\A.pas', 1)], 0);
    Changes.Observe([F('C:\P\A.pas', 2)], 100);
    Changes.Observe([F('C:\P\A.pas', 1)], 200);
    Assert.IsFalse(Changes.Due(5000));
    // Geschlossene Dateien werden vergessen; erneut geöffnet zählt wieder als erster Blick.
    Changes.Observe([], 300);
    Changes.Observe([F('C:\P\A.pas', 9)], 400);
    Assert.IsFalse(Changes.Due(5000));
  finally
    Changes.Free;
  end;
end;

procedure TAtlasExternalChangesTests.DiffShowsChangedLinesOnly;
var
  Lines: TArray<string>;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTextDiff.Lines('a'#13#10'b', 'a'#10'b'))), 'gleich trotz Zeilenenden');
  Lines := TAtlasTextDiff.Lines('a'#10'b'#10'c', 'a'#10'B'#10'c');
  Assert.AreEqual('Zeile 2:|- b|+ B', string.Join('|', Lines));
  Lines := TAtlasTextDiff.Lines('a'#10'c', 'a'#10'b'#10'c');
  Assert.AreEqual('ab Zeile 2:|+ b', string.Join('|', Lines));
end;

procedure TAtlasExternalChangesTests.TextDiffReportsTrailingNewline;
var
  Lines: TArray<string>;
begin
  // Eine zusätzliche letzte Zeilenschaltung ist ein Unterschied (früher von Split verschluckt).
  Lines := TAtlasTextDiff.Lines('a'#10'b', 'a'#10'b'#10);
  Assert.AreEqual('ab Zeile 3:|+ ', string.Join('|', Lines));
  // Alleinstehendes CR trennt Zeilen wie LF.
  Assert.AreEqual(0, Integer(Length(TAtlasTextDiff.Lines('a'#13'b', 'a'#10'b'))), 'CR wie LF');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExternalChangesTests);

end.