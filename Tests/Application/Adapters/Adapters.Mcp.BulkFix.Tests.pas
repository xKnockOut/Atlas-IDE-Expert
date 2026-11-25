unit Adapters.Mcp.BulkFix.Tests;

// Tests für den Host-Adapter zwischen Mcp und Rules (fix_findings): Dateien, Regeln, Untergrenze und Ergebnis gehen
// unverändert durch, ein Fehler mit seinem Grund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpBulkFixAdapterTests = class
  public
    [Test]
    procedure PassesFilesAndResults;
    [Test]
    procedure PassesError;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Contract.BulkFix,
  Rules.Contract.Api,
  Adapters.Mcp.BulkFix;

type
  /// <summary>Merkt die Eingaben und antwortet fest; mit Error scheitert es.</summary>
  TFakeBulkFix = class(TInterfacedObject, IRuleBulkFix)
  public
    Files: TArray<TRuleBulkFixInput>;
    FixRules: TArray<string>;
    MinConfidence: string;
    Error: string;
    function Run(const AFiles: TArray<TRuleBulkFixInput>; const AFixRules: TArray<string>;
      const AMinConfidence: string; const ASettings: TServerSettings; out ARun: TRuleBulkFixRun;
      out AError: string): Boolean;
  end;

function TFakeBulkFix.Run(const AFiles: TArray<TRuleBulkFixInput>; const AFixRules: TArray<string>;
  const AMinConfidence: string; const ASettings: TServerSettings; out ARun: TRuleBulkFixRun;
  out AError: string): Boolean;
begin
  Files := AFiles;
  FixRules := AFixRules;
  MinConfidence := AMinConfidence;
  ARun := Default(TRuleBulkFixRun);
  AError := Error;
  Result := Error = '';
  if not Result then
  begin
    Exit;
  end;
  SetLength(ARun.Files, 1);
  ARun.Files[0] := Default(TRuleBulkFixOutput);
  ARun.Files[0].FileName := AFiles[0].FileName;
  ARun.Files[0].OldText := 'alt';
  ARun.Files[0].NewText := 'neu';
  ARun.Files[0].Changed := True;
  ARun.Files[0].Diff := 'diff';
  ARun.PreviewSummary := 'Vorschau';
  ARun.WrittenSummary := 'Geschrieben';
end;

function Input: TMcpFixInput;
begin
  Result := Default(TMcpFixInput);
  Result.FileName := 'C:\P\U.pas';
  Result.RelativePath := 'U.pas';
  Result.Text := 'alt';
end;

{ TMcpBulkFixAdapterTests }

procedure TMcpBulkFixAdapterTests.PassesFilesAndResults;
var
  mFake: TFakeBulkFix;
  mRules: IRuleBulkFix;
  mAdapter: IMcpBulkFix;
  mRun: TMcpFixRun;
  mError: string;
begin
  mFake := TFakeBulkFix.Create;
  mRules := mFake;
  mAdapter := TMcpBulkFixAdapter.Create(mRules);
  Assert.IsTrue(mAdapter.Run([Input], ['redundant-assigned-free'], 'high', TServerSettings.Default, mRun, mError));
  Assert.AreEqual(1, Integer(Length(mFake.Files)));
  Assert.AreEqual('C:\P\U.pas', mFake.Files[0].FileName);
  Assert.AreEqual('U.pas', mFake.Files[0].RelativePath);
  Assert.AreEqual('alt', mFake.Files[0].Text);
  Assert.AreEqual('redundant-assigned-free', mFake.FixRules[0]);
  Assert.AreEqual('high', mFake.MinConfidence);
  Assert.AreEqual(1, Integer(Length(mRun.Files)));
  Assert.AreEqual('C:\P\U.pas', mRun.Files[0].FileName);
  Assert.AreEqual('alt', mRun.Files[0].OldText);
  Assert.AreEqual('neu', mRun.Files[0].NewText);
  Assert.IsTrue(mRun.Files[0].Changed);
  Assert.AreEqual('diff', mRun.Files[0].Diff);
  Assert.AreEqual('Vorschau', mRun.PreviewSummary);
  Assert.AreEqual('Geschrieben', mRun.WrittenSummary);
end;

procedure TMcpBulkFixAdapterTests.PassesError;
var
  mFake: TFakeBulkFix;
  mRules: IRuleBulkFix;
  mAdapter: IMcpBulkFix;
  mRun: TMcpFixRun;
  mError: string;
begin
  mFake := TFakeBulkFix.Create;
  mFake.Error := 'zu niedrig';
  mRules := mFake;
  mAdapter := TMcpBulkFixAdapter.Create(mRules);
  Assert.IsFalse(mAdapter.Run([Input], ['all'], 'medium', TServerSettings.Default, mRun, mError));
  Assert.AreEqual('zu niedrig', mError);
  Assert.AreEqual(0, Integer(Length(mRun.Files)));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpBulkFixAdapterTests);

end.
