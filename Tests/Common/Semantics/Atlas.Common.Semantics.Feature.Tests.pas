unit Atlas.Common.Semantics.Feature.Tests;

// Gemeinsame Grundlage der LSP-Dienste: Felder aus dem Konstruktor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFeatureTests = class
  public
    [Test]
    procedure ProjectFeatureKeepsServices;
    [Test]
    procedure IndexFeatureWithoutEnsureUnit;
    [Test]
    procedure UnitOfFilePrefersCurrent;
  end;

implementation

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Feature;

type
  TProjectFeatureProbe = class(TProjectFeature)
  public
    function ReadsWith(const AFileName: string; out AText: string): Boolean;
    function FileCount: Integer;
    function EnsuresWith(const AUnitName: string): Boolean;
  end;

  TIndexFeatureProbe = class(TIndexFeature)
  public
    function HasEnsureUnit: Boolean;
    function HasStore: Boolean;
  end;

function TProjectFeatureProbe.ReadsWith(const AFileName: string; out AText: string): Boolean;
begin
  Result := FReadText(AFileName, AText);
end;

function TProjectFeatureProbe.FileCount: Integer;
begin
  Result := Length(FFiles());
end;

function TProjectFeatureProbe.EnsuresWith(const AUnitName: string): Boolean;
begin
  Result := FEnsureUnit(AUnitName);
end;

function TIndexFeatureProbe.HasEnsureUnit: Boolean;
begin
  Result := Assigned(FEnsureUnit);
end;

function TIndexFeatureProbe.HasStore: Boolean;
begin
  Result := FStore <> nil;
end;

function ReadFixed(const AFileName: string; out AText: string): Boolean;
begin
  AText := 'Text von ' + AFileName;
  Result := True;
end;

function TwoFiles: TArray<string>;
begin
  Result := TArray<string>.Create('A.pas', 'B.pas');
end;

function EnsureOnlyA(const AUnitName: string): Boolean;
begin
  Result := AUnitName = 'A';
end;

{ TLspFeatureTests }

procedure TLspFeatureTests.ProjectFeatureKeepsServices;
var
  mFeature: TProjectFeatureProbe;
  mText: string;
begin
  mFeature := TProjectFeatureProbe.Create(nil, nil, ReadFixed, TwoFiles, EnsureOnlyA);
  try
    Assert.IsTrue(mFeature.ReadsWith('X.pas', mText));
    Assert.AreEqual('Text von X.pas', mText);
    Assert.AreEqual(2, mFeature.FileCount);
    Assert.IsTrue(mFeature.EnsuresWith('A'));
    Assert.IsFalse(mFeature.EnsuresWith('B'));
  finally
    mFeature.Free;
  end;
end;

procedure TLspFeatureTests.IndexFeatureWithoutEnsureUnit;
var
  mFeature: TIndexFeatureProbe;
begin
  mFeature := TIndexFeatureProbe.Create(nil, nil, nil);
  try
    Assert.IsFalse(mFeature.HasEnsureUnit);
    Assert.IsFalse(mFeature.HasStore);
  finally
    mFeature.Free;
  end;
end;

procedure TLspFeatureTests.UnitOfFilePrefersCurrent;
var
  mCurrent, mUnit: TUnitIndex;
begin
  mCurrent := Default(TUnitIndex);
  mCurrent.FileName := 'C:\P\Haupt.pas';
  mCurrent.UnitName := 'Haupt';
  // Die eigene Datei kommt aus dem Editor-Stand, ohne den Index zu fragen.
  Assert.IsTrue(UnitOfFile(nil, mCurrent, 'c:\p\haupt.pas', mUnit));
  Assert.AreEqual('Haupt', mUnit.UnitName);
  mCurrent := Default(TUnitIndex);
  mUnit := Default(TUnitIndex);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFeatureTests);

end.
