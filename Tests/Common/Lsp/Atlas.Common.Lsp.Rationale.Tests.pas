unit Atlas.Common.Lsp.Rationale.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspRationaleTests = class
  public
    [Test]
    procedure SelectsConfiguredMarkers;
    [Test]
    procedure SelectsNothingWhenSwitchedOff;
    [Test]
    procedure NeverSelectsTodoMarkers;
    [Test]
    procedure ResolvesAdrFolder;
    [Test]
    procedure ListsAdrFiles;
    [Test]
    procedure KeepsAdrWithoutFileAsText;
    [Test]
    procedure WritesUrlsAsLinks;
    [Test]
    procedure CollectsDeclarationAndImplementationOfOverload;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Rationale.References,
  Atlas.Common.Lsp.Rationale;

function Entries: TArray<TRationaleEntry>;
begin
  Result := [TRationaleEntry.Create('WHY', 'Grund', 1), TRationaleEntry.Create('TODO', 'Offen', 2),
    TRationaleEntry.Create('PERF', 'Schnell', 3), TRationaleEntry.Create('NOTE', 'Hinweis', 4)];
end;

function OptionsOf(const AJson: string): TRationaleOptions;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse(AJson, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Result := TRationaleOptions.FromSettings(mSettings, '');
end;

procedure TLspRationaleTests.SelectsConfiguredMarkers;
var
  mSelected: TArray<TRationaleEntry>;
begin
  mSelected := TLspRationale.Select(Entries, TRationaleOptions.Default);
  Assert.AreEqual(2, Integer(Length(mSelected)));
  Assert.AreEqual('WHY', mSelected[0].Marker);
  Assert.AreEqual('NOTE', mSelected[1].Marker);
  mSelected := TLspRationale.Select(Entries, OptionsOf('{}'));
  Assert.AreEqual(2, Integer(Length(mSelected)));
  // Eigene Marke, Groß-/Kleinschreibung egal.
  mSelected := TLspRationale.Select(Entries, OptionsOf('{"hints": {"rationaleMarkers": ["perf"]}}'));
  Assert.AreEqual(1, Integer(Length(mSelected)));
  Assert.AreEqual('PERF', mSelected[0].Marker);
end;

procedure TLspRationaleTests.SelectsNothingWhenSwitchedOff;
var
  mOptions: TRationaleOptions;
begin
  mOptions := OptionsOf('{"hints": {"rationale": false}}');
  Assert.AreEqual(0, Integer(Length(TLspRationale.Select(Entries, mOptions))));
  // get_rationale filtert nur nach Marken.
  Assert.AreEqual(2, Integer(Length(TLspRationale.ByMarkers(Entries, mOptions))));
end;

procedure TLspRationaleTests.NeverSelectsTodoMarkers;
var
  mSelected: TArray<TRationaleEntry>;
begin
  mSelected := TLspRationale.Select(Entries, OptionsOf('{"hints": {"rationaleMarkers": ["TODO", "WHY"]}}'));
  Assert.AreEqual(1, Integer(Length(mSelected)));
  Assert.AreEqual('WHY', mSelected[0].Marker);
  // Eine Marke der TODO-Übersicht (Option keywords von todo-comment) gilt nur dort.
  mSelected := TLspRationale.Select(Entries, OptionsOf('{"rules": {"todo-comment": {"keywords": ["NOTE"]}}}'));
  Assert.AreEqual(1, Integer(Length(mSelected)));
  Assert.AreEqual('WHY', mSelected[0].Marker);
end;

procedure TLspRationaleTests.ResolvesAdrFolder;
var
  mRoot: string;
begin
  mRoot := TPath.Combine(TPath.GetTempPath, 'Projekt');
  Assert.AreEqual(TPath.Combine(mRoot, 'docs' + PathDelim + 'adr'), TLspRationale.AdrFolder('', mRoot));
  Assert.AreEqual(TPath.Combine(mRoot, 'doc' + PathDelim + 'decisions'),
    TLspRationale.AdrFolder('doc/decisions', mRoot));
  // Relativ ohne Arbeitsbereich: kein Ordner; absolut bleibt.
  Assert.AreEqual('', TLspRationale.AdrFolder('docs/adr', ''));
  Assert.AreEqual(mRoot, TLspRationale.AdrFolder(mRoot, ''));
end;

procedure TLspRationaleTests.ListsAdrFiles;
var
  mFolder: string;
  mFiles: TArray<string>;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasAdr' + IntToStr(Random(1000000)));
  TDirectory.CreateDirectory(mFolder);
  try
    TFile.WriteAllText(TPath.Combine(mFolder, '0007-ganzzahlen.md'), '# 7');
    mFiles := TLspRationale.AdrFiles(mFolder);
    Assert.AreEqual(1, Integer(Length(mFiles)));
    Assert.AreEqual(TPath.Combine(mFolder, '0007-ganzzahlen.md'), TRationaleReferences.AdrFile('7', mFiles));
    Assert.AreEqual(0, Integer(Length(TLspRationale.AdrFiles(TPath.Combine(mFolder, 'fehlt')))));
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TLspRationaleTests.KeepsAdrWithoutFileAsText;
var
  mSections: TJSONArray;
  mRuns: TJSONArray;
begin
  mSections := TJSONArray.Create;
  try
    TLspRationale.AddSections(mSections, [TRationaleEntry.Create('WHY', 'Siehe ADR 9', 0)], ['C:\adr\0007-a.md']);
    mRuns := mSections.Items[0].GetValue<TJSONArray>('runs');
    Assert.AreEqual(2, mRuns.Count);
    Assert.AreEqual('text', mRuns.Items[1].GetValue<string>('kind'));
    Assert.AreEqual('ADR 9', mRuns.Items[1].GetValue<string>('text'));
  finally
    mSections.Free;
  end;
end;

procedure TLspRationaleTests.WritesUrlsAsLinks;
var
  mSections: TJSONArray;
  mRuns: TJSONArray;
begin
  mSections := TJSONArray.Create;
  try
    TLspRationale.AddSections(mSections, [TRationaleEntry.Create('HACK', 'https://example.org/qc/1', 0)], nil);
    mRuns := mSections.Items[0].GetValue<TJSONArray>('runs');
    Assert.AreEqual(1, mRuns.Count);
    Assert.AreEqual('link', mRuns.Items[0].GetValue<string>('kind'));
    Assert.AreEqual('https://example.org/qc/1', mRuns.Items[0].GetValue<string>('target'));
  finally
    mSections.Free;
  end;
end;

procedure TLspRationaleTests.CollectsDeclarationAndImplementationOfOverload;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  T = class'#10 +
    '    // WHY: Text.'#10 +
    '    procedure P(const A: string); overload;'#10 +
    '    // WHY: Zahl.'#10 +
    '    procedure P(A: Integer); overload;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure T.P(const A: string);'#10 +
    'begin'#10 +
    '  // HACK: Text im Rumpf.'#10 +
    'end;'#10 +
    'procedure T.P(A: Integer);'#10 +
    'begin'#10 +
    '  // HACK: Zahl im Rumpf.'#10 +
    'end;'#10 +
    'end.';
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mFound: TArray<TRationaleEntry>;
begin
  mUnit := TIndexExtractor.ExtractText(cSource, 'C:\P\U.pas', nil);
  mFound := nil;
  for mSymbol in mUnit.Symbols do
    if (mSymbol.Name = 'P') and mSymbol.InInterface and (Length(mSymbol.ParamTypes) = 1) and
      SameText(mSymbol.ParamTypes[0], 'Integer') then
      mFound := TLspRationale.OfSymbol(mUnit, mSymbol);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Zahl.', mFound[0].Text);
  Assert.AreEqual('Zahl im Rumpf.', mFound[1].Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRationaleTests);

end.
