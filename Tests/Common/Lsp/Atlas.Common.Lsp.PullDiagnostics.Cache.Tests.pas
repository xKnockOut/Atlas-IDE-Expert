unit Atlas.Common.Lsp.PullDiagnostics.Cache.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.PullDiagnostics.Cache;

type
  [TestFixture]
  TPullReportCacheTests = class
  private
    FCache: TPullReportCache;
    FComputed: Integer;
    function Compute: TPullCompute;
    function CountOf(const AUri, AResultId: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WithoutResultIdAlwaysComputes;
    [Test]
    procedure SameStateComesFromStore;
    [Test]
    procedure NewStateComputesAgain;
    [Test]
    procedure FilesAreStoredSeparately;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON;

procedure TPullReportCacheTests.Setup;
begin
  FComputed := 0;
  FCache := TPullReportCache.Create;
end;

procedure TPullReportCacheTests.TearDown;
begin
  FCache.Free;
  FCache := nil;
end;

function TPullReportCacheTests.Compute: TPullCompute;
var
  mTests: TPullReportCacheTests;
begin
  mTests := Self;
  Result :=
    function: TJSONArray
    begin
      Inc(mTests.FComputed);
      Result := TJSONArray.Create;
      Result.Add(mTests.FComputed);
    end;
end;

/// <summary>Zahl im ersten Eintrag der Befunde, also der Lauf, der sie berechnet hat.</summary>
function TPullReportCacheTests.CountOf(const AUri, AResultId: string): Integer;
var
  mItems: TJSONArray;
begin
  mItems := FCache.Get(AUri, AResultId, Compute(), nil);
  try
    Result := mItems.Items[0].GetValue<Integer>;
  finally
    mItems.Free;
  end;
end;

procedure TPullReportCacheTests.WithoutResultIdAlwaysComputes;
begin
  Assert.AreEqual(1, CountOf('file:///a.pas', ''));
  Assert.AreEqual(2, CountOf('file:///a.pas', ''));
  Assert.AreEqual(2, FComputed);
end;

procedure TPullReportCacheTests.SameStateComesFromStore;
begin
  Assert.AreEqual(1, CountOf('file:///a.pas', '1:v1'));
  Assert.AreEqual(1, CountOf('file:///a.pas', '1:v1'));
  Assert.AreEqual(1, FComputed);
end;

procedure TPullReportCacheTests.NewStateComputesAgain;
begin
  CountOf('file:///a.pas', '1:v1');
  Assert.AreEqual(2, CountOf('file:///a.pas', '1:v2'));
  Assert.AreEqual(2, FComputed);
end;

procedure TPullReportCacheTests.FilesAreStoredSeparately;
begin
  CountOf('file:///a.pas', '1:v1');
  Assert.AreEqual(2, CountOf('file:///b.pas', '1:v1'));
  Assert.AreEqual(1, CountOf('file:///a.pas', '1:v1'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPullReportCacheTests);

end.
