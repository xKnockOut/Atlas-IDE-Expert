unit Atlas.Common.Mcp.EditFindings.Tests;

// Tests für die Befunde nach schreibenden MCP-Werkzeugen (#2603): Zeilenversatz, Vergleich (neu, behoben,
// verschoben, geänderte Zeile), Antwort mit Grenze und mehreren Dateien, Auswertung samt delphi://edits/last und die
// Einbindung in TMcpEditTools (nur ohne dryRun, auch fix_findings).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpEditFindingsTests = class
  public
    [Test]
    procedure LineMapFollowsInsertedAndChangedLines;
    /// <summary>Ein Befund, der nur durch Zeilenversatz verschoben ist, gilt nicht als neu.</summary>
    [Test]
    procedure ShiftedFindingIsUnchanged;
    [Test]
    procedure FindsNewAndFixedFindings;
    /// <summary>Gleicher Befund in einer geänderten Zeile bleibt derselbe.</summary>
    [Test]
    procedure SameFindingInChangedLineIsUnchanged;
    [Test]
    procedure ReportWithoutNewFindingsIsOneLine;
    [Test]
    procedure ReportListsNewFindingsAcrossFilesWithLimit;
    /// <summary>Abgeschaltet kein Abschnitt; die Ressource meldet vor der ersten Änderung einen Hinweis, danach die
    /// letzte Auswertung; nach dem Schreiben zählt der gelesene Text.</summary>
    [Test]
    procedure EvaluationUsesWrittenTextAndKeepsLast;
    /// <summary>Apply hängt den Abschnitt nur ohne dryRun an.</summary>
    [Test]
    procedure ApplyAppendsFindingsOnlyWhenWriting;
    [Test]
    procedure FixFindingsAppendsFindingsOfChangedFiles;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Mcp.EditFindings;

type
  /// <summary>Dateien im Speicher.</summary>
  TFindingTestFiles = class
  public
    Files: TDictionary<string, string>;
    constructor Create;
    destructor Destroy; override;
  end;

const
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;

{ TFindingTestFiles }

constructor TFindingTestFiles.Create;
begin
  inherited Create;
  Files := TDictionary<string, string>.Create;
end;

destructor TFindingTestFiles.Destroy;
begin
  Files.Free;
  inherited Destroy;
end;

function Finding(ALine: Integer; const ARule, AMessage: string): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := ARule;
  Result.Message := AMessage;
  Result.Range := TTextRange.Create(ALine, 0, ALine, 1);
end;

/// <summary>Je Zeile mit "Alt" ein Befund test-alt.</summary>
function AltFindings(const AText: string): TArray<TRuleFinding>;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  mLines := AText.Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    if ContainsText(mLines[mIndex], 'Alt') then
    begin
      Result := Result + [Finding(mIndex, 'test-alt', 'Alt gefunden')];
    end;
  end;
end;

function AltFindingsFunc: TMcpFindingsFunc;
begin
  Result :=
    function(const AFileName, AText: string): TArray<TRuleFinding>
    begin
      Result := AltFindings(AText);
    end;
end;

function FlagOf(AFlag: PBoolean): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := AFlag^;
    end;
end;

function ReadOf(AFiles: TFindingTestFiles): TMcpEditReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AFiles.Files.TryGetValue(AFileName, AText);
    end;
end;

function NewTools(AFiles: TFindingTestFiles): TMcpEditTools;
begin
  Result := TMcpEditTools.Create(nil,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AFiles.Files.TryGetValue(AFileName, AText);
    end,
    procedure(const AFileName, AText: string)
    begin
      AFiles.Files[AFileName] := AText;
    end,
    function: TArray<string>
    begin
      Result := nil;
    end,
    nil);
end;

/// <summary>Reicht an die Auswertung weiter und merkt sich das Werkzeug.</summary>
function AfterWriteOf(const AEvaluation: IMcpEditEvaluation; ATools: TList<string>): TMcpAfterWrite;
begin
  Result :=
    function(const ATool: string; const ANames, AOldTexts, ANewTexts: TArray<string>): string
    begin
      ATools.Add(ATool);
      Result := AEvaluation.Run(ATool, ANames, AOldTexts, ANewTexts);
    end;
end;

function Compared(const AOld, ANew: string): TMcpFindingDelta;
begin
  Result := TMcpEditFindings.Compare('U.pas', AOld, ANew, AltFindings(AOld), AltFindings(ANew));
end;

{ TMcpEditFindingsTests }

procedure TMcpEditFindingsTests.LineMapFollowsInsertedAndChangedLines;
var
  mMap: TArray<Integer>;
begin
  mMap := TMcpEditFindings.LineMap('a'#10'b'#10'c', 'x'#10'a'#10'B'#10'c');
  Assert.AreEqual(3, Integer(Length(mMap)));
  Assert.AreEqual(1, mMap[0], 'a eine Zeile tiefer');
  Assert.AreEqual(-1, mMap[1], 'b geändert');
  Assert.AreEqual(3, mMap[2], 'c eine Zeile tiefer');
end;

procedure TMcpEditFindingsTests.ShiftedFindingIsUnchanged;
var
  mDelta: TMcpFindingDelta;
begin
  mDelta := Compared('a'#10'Alt'#10'c', 'neu'#10'neu'#10'a'#10'Alt'#10'c');
  Assert.AreEqual(0, Integer(Length(mDelta.Added)));
  Assert.AreEqual(0, Integer(Length(mDelta.Fixed)));
  Assert.AreEqual(1, mDelta.Unchanged);
end;

procedure TMcpEditFindingsTests.FindsNewAndFixedFindings;
var
  mDelta: TMcpFindingDelta;
begin
  mDelta := Compared('a'#10'b', 'a'#10'Alt');
  Assert.AreEqual(1, Integer(Length(mDelta.Added)));
  Assert.AreEqual(1, mDelta.Added[0].Range.StartPos.Line, 'Zeile im neuen Text');
  mDelta := Compared('Alt'#10'b'#10'Alt', 'a'#10'b'#10'Alt');
  Assert.AreEqual(0, Integer(Length(mDelta.Added)));
  Assert.AreEqual(1, Integer(Length(mDelta.Fixed)));
  Assert.AreEqual(0, mDelta.Fixed[0].Range.StartPos.Line, 'Zeile im alten Text');
  Assert.AreEqual(1, mDelta.Unchanged);
end;

procedure TMcpEditFindingsTests.SameFindingInChangedLineIsUnchanged;
var
  mDelta: TMcpFindingDelta;
begin
  mDelta := Compared('x := Alt;'#10'b', 'x := Alt + 1;'#10'b');
  Assert.AreEqual(0, Integer(Length(mDelta.Added)));
  Assert.AreEqual(1, mDelta.Unchanged);
  // Eine zweite gleiche Meldung in geänderten Zeilen ist neu.
  mDelta := Compared('x := Alt;'#10'b', 'x := Alt;'#10'y := Alt;'#10'b');
  Assert.AreEqual(1, Integer(Length(mDelta.Added)));
  Assert.AreEqual(1, mDelta.Unchanged);
end;

procedure TMcpEditFindingsTests.ReportWithoutNewFindingsIsOneLine;
var
  mText: string;
begin
  mText := TMcpEditFindings.Report('', [Compared('Alt'#10'b'#10'Alt', 'a'#10'b'#10'Alt')]);
  Assert.IsFalse(ContainsStr(mText, sLineBreak), mText);
  Assert.Contains(mText, ': 1 (test-alt');
  Assert.Contains(mText, ': 1.');
end;

procedure TMcpEditFindingsTests.ReportListsNewFindingsAcrossFilesWithLimit;
var
  mDeltas: TArray<TMcpFindingDelta>;
  mText, mMany: string;
  mIndex: Integer;
begin
  mDeltas := [TMcpEditFindings.Compare('C:\P\Src\A.pas', 'a', 'Alt', AltFindings('a'), AltFindings('Alt')),
    TMcpEditFindings.Compare('C:\P\B.pas', 'Alt', 'b', AltFindings('Alt'), AltFindings('b'))];
  mText := TMcpEditFindings.Report('C:\P', mDeltas);
  Assert.Contains(mText, 'Src/A.pas:1  test-alt – Alt gefunden');
  Assert.Contains(mText, '(1)');
  Assert.Contains(mText, ': 1 (test-alt');
  mMany := 'Alt';
  for mIndex := 2 to TMcpEditFindings.cMaxShown + 10 do
  begin
    mMany := mMany + #10'Alt';
  end;
  mDeltas := [TMcpEditFindings.Compare('U.pas', '', mMany, nil, AltFindings(mMany))];
  mText := TMcpEditFindings.Report('', mDeltas);
  Assert.Contains(mText, 'U.pas:50 ');
  Assert.DoesNotContain(mText, 'U.pas:51 ');
  Assert.Contains(mText, ' 10 ', 'Rest gezählt');
  mDeltas := nil;
end;

procedure TMcpEditFindingsTests.EvaluationUsesWrittenTextAndKeepsLast;
var
  mFiles: TFindingTestFiles;
  mEvaluation: IMcpEditEvaluation;
  mEnabled: Boolean;
  mText, mHint: string;
begin
  mFiles := TFindingTestFiles.Create;
  try
    mEnabled := False;
    mEvaluation := TMcpEditEvaluation.Create('', AltFindingsFunc(), ReadOf(mFiles), FlagOf(@mEnabled));
    mHint := mEvaluation.Last;
    Assert.AreNotEqual('', mHint, 'Hinweis vor der ersten Änderung');
    Assert.AreEqual('', mEvaluation.Run('format_code', ['U.pas'], ['a'], ['Alt']), 'abgeschaltet');
    Assert.AreEqual(mHint, mEvaluation.Last);
    mEnabled := True;
    // Im Puffer steht etwas anderes als geplant: das zählt.
    mFiles.Files.Add('U.pas', 'b');
    mText := mEvaluation.Run('format_code', ['U.pas'], ['a'], ['Alt']);
    Assert.DoesNotContain(mText, 'U.pas:1', mText);
    mFiles.Files['U.pas'] := 'Alt';
    mText := mEvaluation.Run('format_code', ['U.pas'], ['a'], ['a']);
    Assert.Contains(mText, 'U.pas:1  test-alt');
    Assert.Contains(mEvaluation.Last, 'format_code');
    Assert.Contains(mEvaluation.Last, 'U.pas:1  test-alt');
  finally
    mEvaluation := nil;
    mFiles.Free;
  end;
end;

procedure TMcpEditFindingsTests.ApplyAppendsFindingsOnlyWhenWriting;
var
  mFiles: TFindingTestFiles;
  mEdit: TMcpEditTools;
  mEvaluation: IMcpEditEvaluation;
  mEdits: TArray<TMcpFileEdit>;
  mReport: string;
  mTools: TList<string>;
begin
  mFiles := TFindingTestFiles.Create;
  mEdit := NewTools(mFiles);
  mTools := TList<string>.Create;
  try
    mEvaluation := TMcpEditEvaluation.Create('', AltFindingsFunc(), ReadOf(mFiles), nil);
    mEdit.AfterWrite := AfterWriteOf(mEvaluation, mTools);
    mFiles.Files.Add('A.pas', 'Neu;'#10'b');
    mEdits := [TMcpFileEdit.Create('A.pas', TTextRange.Create(1, 0, 1, 1), 'Alt')];
    mReport := mEdit.Apply('rename_symbol', mEdits, True);
    Assert.DoesNotContain(mReport, 'test-alt', 'dryRun ohne Abschnitt');
    mReport := mEdit.Apply('rename_symbol', mEdits, False);
    Assert.Contains(mReport, 'A.pas:2  test-alt – Alt gefunden');
    Assert.IsTrue(Pos('test-alt', mReport) > Pos('--- A.pas', mReport), 'am Ende der Antwort');
    Assert.AreEqual('rename_symbol', string.Join(',', mTools.ToArray));
  finally
    mEdit.Free;
    mTools.Free;
    mEvaluation := nil;
    mFiles.Free;
    mEdits := nil;
  end;
end;

procedure TMcpEditFindingsTests.FixFindingsAppendsFindingsOfChangedFiles;
var
  mFiles: TFindingTestFiles;
  mEdit: TMcpEditTools;
  mNames: TList<string>;
  mReport: string;
begin
  mFiles := TFindingTestFiles.Create;
  mEdit := NewTools(mFiles);
  mNames := TList<string>.Create;
  try
    mEdit.AfterWrite :=
      function(const ATool: string; const ANames, AOldTexts, ANewTexts: TArray<string>): string
      begin
        mNames.AddRange(ANames);
        Result := 'Auswertung ' + ATool;
      end;
    mFiles.Files.Add('U.pas', cAssignedFree);
    mReport := mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''), ['U.pas'],
      ['redundant-assigned-free'], '', True);
    Assert.AreEqual(0, mNames.Count, 'Vorschau ohne Auswertung');
    mReport := mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''), ['U.pas'],
      ['redundant-assigned-free'], '', False);
    Assert.AreEqual(1, mNames.Count);
    Assert.AreEqual('U.pas', mNames[0]);
    Assert.Contains(mReport, 'Auswertung fix_findings');
  finally
    mEdit.Free;
    mNames.Free;
    mFiles.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpEditFindingsTests);

end.
