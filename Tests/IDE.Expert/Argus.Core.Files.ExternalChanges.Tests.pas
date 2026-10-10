unit Argus.Core.Files.ExternalChanges.Tests;

// Tests für extern geänderte Dateien (#536).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusExternalChangesTests = class
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
  end;

implementation

uses
  System.SysUtils,
  Argus.Core.Files.ExternalChanges;

function F(const AName: string; AStamp: Int64; AModified: Boolean = False; AExists: Boolean = True): TArgusObservedFile;
begin
  Result := TArgusObservedFile.Create(AName, AExists, AStamp, AModified);
end;

function Text(const ADecisions: TArray<TArgusReloadDecision>): string;
const
  Names: array[TArgusReloadAction] of string = ('neu', 'behalten', 'gelöscht');
var
  Decision: TArgusReloadDecision;
begin
  Result := '';
  for Decision in ADecisions do
    Result := Result + ExtractFileName(Decision.FileName) + '=' + Names[Decision.Action] + ' ';
end;

procedure TArgusExternalChangesTests.FirstLookOnlyRemembers;
var
  Changes: TArgusExternalChanges;
begin
  Changes := TArgusExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1)], 0);
    Assert.IsFalse(Changes.Due(10000));
  finally
    Changes.Free;
  end;
end;

procedure TArgusExternalChangesTests.BundlesChangesUntilQuiet;
var
  Changes: TArgusExternalChanges;
begin
  Changes := TArgusExternalChanges.Create;
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

procedure TArgusExternalChangesTests.DecidesPerFile;
var
  Changes: TArgusExternalChanges;
begin
  Changes := TArgusExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\A.pas', 1), F('C:\P\B.pas', 1, True), F('C:\P\C.pas', 1)], 0);
    Changes.Observe([F('C:\P\A.pas', 2), F('C:\P\B.pas', 2, True), F('C:\P\C.pas', 0, False, False)], 100);
    Assert.IsTrue(Changes.Due(600));
    Assert.AreEqual('A.pas=neu B.pas=behalten C.pas=gelöscht ', Text(Changes.TakeBatch));
  finally
    Changes.Free;
  end;
end;

procedure TArgusExternalChangesTests.FirstSaveOfNewFileIsNoChange;
var
  Changes: TArgusExternalChanges;
begin
  Changes := TArgusExternalChanges.Create;
  try
    Changes.Observe([F('C:\P\Unit2.pas', 0, True, False)], 0);
    Changes.Observe([F('C:\P\Unit2.pas', 5)], 100);
    Assert.IsFalse(Changes.Due(5000));
  finally
    Changes.Free;
  end;
end;

procedure TArgusExternalChangesTests.ChangeBackBeforeQuietCancels;
var
  Changes: TArgusExternalChanges;
begin
  Changes := TArgusExternalChanges.Create;
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

initialization
  TDUnitX.RegisterTestFixture(TArgusExternalChangesTests);

end.