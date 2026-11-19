unit Atlas.Common.Mcp.HistoryTools.Tests;

// Tests von get_symbol_history (#2641) über Index und Versionsverwaltung im Speicher: Bereich der Routine aus dem
// übernommenen Stand, Typen, mehrdeutige und unbekannte Namen, Datei außerhalb der Arbeitskopie, JSON und der
// Hinweis ohne Versionsverwaltung.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.History.Contract,
  Atlas.Common.History.Service.Tests,
  Atlas.Common.Mcp.HistoryTools;

type
  [TestFixture]
  TMcpHistoryToolsTests = class
  private
    FService: ISymbolHistoryService;
    FTools: TMcpHistoryTools;
    FVcs: TSymbolFakeVcs;
    FVcsRef: ISymbolHistoryVcs;
    function Args(const AName: string): TMcpHistoryArgs;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RoutineRangeComesFromCommittedText;
    [Test]
    procedure TypeUsesItsDeclaration;
    [Test]
    procedure JsonAnswer;
    [Test]
    procedure AmbiguousNameListsCandidates;
    [Test]
    procedure UnknownNameGivesHint;
    [Test]
    procedure FileOutsideWorkingCopy;
    [Test]
    procedure WithoutVcsGivesHint;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.History.Service;

const
  cFile = 'C:\P\Src\Rechner.pas';
  cOutsideFile = 'D:\Fremd\Rechner2.pas';
  // Arbeitskopie: eine Zeile mehr als der übernommene Stand.
  cWorking =
    'unit Rechner;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '    procedure Summe(AWert: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    '// neu, noch nicht übernommen'#10 +
    'procedure TRechner.Summe(AWert: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  cCommitted =
    'unit Rechner;'#10 +                         // 1
    'interface'#10 +                             // 2
    'type'#10 +                                  // 3
    '  TRechner = class'#10 +                    // 4
    '    procedure Summe(AWert: Integer);'#10 +  // 5
    '  end;'#10 +                                // 6
    'implementation'#10 +                        // 7
    'procedure TRechner.Summe(AWert: Integer);'#10 + // 8
    'begin'#10 +                                 // 9
    'end;'#10 +                                  // 10
    'end.';
  cOutside =
    'unit Rechner2;'#10'interface'#10'procedure Zaehle;'#10'implementation'#10'procedure Zaehle;'#10'begin'#10 +
    'end;'#10'end.';
  cTwin =
    'unit Zwilling;'#10'interface'#10'type'#10'  TRechner = class'#10'  end;'#10'implementation'#10'end.';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, cFile);
  AText := '';
  if Result then
  begin
    AText := cWorking;
  end;
end;

procedure TMcpHistoryToolsTests.Setup;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cWorking, cFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cOutside, cOutsideFile, nil));
  FService := TSymbolHistoryService.Create;
  FTools := TMcpHistoryTools.Create(mIndex, FService, ReadText);
  FVcs := TSymbolFakeVcs.Create(THotspotVcsKind.Git);
  FVcsRef := FVcs;
  FVcs.AddText('Src/Rechner.pas', '', False, cCommitted);
  FVcs.AddLog('Src/Rechner.pas', '', [LineCommit('c1', 'Rechner (#3)', IntroPatch('Src/Rechner.pas', 8, 3))]);
end;

procedure TMcpHistoryToolsTests.TearDown;
begin
  FreeAndNil(FTools);
  FService := nil;
  FVcs := nil;
  FVcsRef := nil;
end;

function TMcpHistoryToolsTests.Args(const AName: string): TMcpHistoryArgs;
begin
  Result := TMcpHistoryArgs.Default;
  Result.Name := AName;
end;

procedure TMcpHistoryToolsTests.RoutineRangeComesFromCommittedText;
var
  mText: string;
begin
  mText := FTools.Run(FVcsRef, Args('TRechner.Summe'));
  Assert.AreEqual('Src/Rechner.pas||8|10', FVcs.Ranges[0]);
  Assert.Contains(mText, 'TRechner.Summe – 1 Änderung (git, Stand kopf1)');
  Assert.Contains(mText, 'eingeführt');
  Assert.Contains(mText, 'Issues: #3');
end;

procedure TMcpHistoryToolsTests.TypeUsesItsDeclaration;
begin
  FTools.Run(FVcsRef, Args('TRechner'));
  Assert.AreEqual('Src/Rechner.pas||4|6', FVcs.Ranges[0]);
end;

procedure TMcpHistoryToolsTests.JsonAnswer;
var
  mArgs: TMcpHistoryArgs;
  mRoot, mEvent: TJSONObject;
begin
  mArgs := Args('TRechner.Summe');
  mArgs.Json := True;
  mRoot := TJSONObject.ParseJSONValue(FTools.Run(FVcsRef, mArgs)) as TJSONObject;
  try
    Assert.AreEqual('Src/Rechner.pas', mRoot.GetValue<string>('path'));
    Assert.AreEqual(1, mRoot.GetValue<Integer>('count'));
    mEvent := TJSONArray(mRoot.GetValue('events')).Items[0] as TJSONObject;
    Assert.AreEqual('introduced', mEvent.GetValue<string>('kind'));
  finally
    mRoot.Free;
  end;
end;

procedure TMcpHistoryToolsTests.AmbiguousNameListsCandidates;
var
  mIndex: ISymbolIndex;
  mTools: TMcpHistoryTools;
  mText: string;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cWorking, cFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cTwin, 'C:\P\Src\Zwilling.pas', nil));
  mTools := TMcpHistoryTools.Create(mIndex, FService, ReadText);
  try
    mText := mTools.Run(FVcsRef, Args('TRechner'));
  finally
    mTools.Free;
  end;
  Assert.Contains(mText, '"TRechner" ist mehrdeutig, 2 Treffer:');
  Assert.Contains(mText, 'Zwilling.TRechner');
  Assert.AreEqual(0, FVcs.LineLogs);
end;

procedure TMcpHistoryToolsTests.UnknownNameGivesHint;
begin
  Assert.AreEqual('Kein Symbol "TGibtEsNicht" im Index.', FTools.Run(FVcsRef, Args('TGibtEsNicht')));
end;

procedure TMcpHistoryToolsTests.FileOutsideWorkingCopy;
begin
  Assert.Contains(FTools.Run(FVcsRef, Args('Zaehle')), 'liegt nicht in der Arbeitskopie');
  Assert.AreEqual(0, FVcs.LineLogs);
end;

procedure TMcpHistoryToolsTests.WithoutVcsGivesHint;
begin
  Assert.Contains(TMcpHistoryTools.NoVcs('kein Repository'), 'Keine Geschichte: kein Repository.');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpHistoryToolsTests);

end.
