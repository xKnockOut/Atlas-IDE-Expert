unit Atlas.Core.Assistants.AiGhost.Tests;

// Tests für den KI-Schattentext (#1922) ohne IDE: Prompt mit Marke und Köpfen der Klasse, Antwort in Zeilen
// (Codezäune, Einrückung, Höchstzahl), Masken für assistants.exclude und der Tageszähler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAiGhostTests = class
  public
    [Test]
    procedure PromptMarksTheEmptyLine;
    [Test]
    procedure PromptSendsOnlyTheFileName;
    [Test]
    procedure PromptCarriesDeclarations;
    [Test]
    procedure PromptHonoursContextLines;
    [Test]
    procedure LinesDropFencesAndBlankEdges;
    [Test]
    procedure LinesTakeIndentOfTheEmptyLine;
    [Test]
    procedure LinesKeepRelativeIndent;
    [Test]
    procedure LinesUseTabsWithoutInsertSpaces;
    [Test]
    procedure LinesAreCapped;
    [Test]
    procedure EmptyAnswerGivesNoLines;
    [Test]
    procedure MasksMatchNameAndPath;
    [Test]
    procedure ExcludeSplitsMasks;
    [Test]
    procedure DailyCountStopsAtLimit;
    [Test]
    procedure DailyCountStartsNewDay;
    [Test]
    procedure DailyCountRoundTripsJson;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.Assistants.AiGhost;

const
  cCode =
    'procedure TKunde.Speichern;' + #13#10 +
    'begin' + #13#10 +
    '  if FName = '''' then' + #13#10 +
    '' + #13#10 +
    'end;';

function RequestOf(const AText: string; ALine: Integer): TAtlasAiGhostRequest;
begin
  Result := Default(TAtlasAiGhostRequest);
  Result.FileName := 'C:\Projekt\Geheim\Kunden.pas';
  Result.Line := ALine;
  Result.Text := AText;
  Result.ContextLines := 40;
end;

{ TAtlasAiGhostTests }

procedure TAtlasAiGhostTests.PromptMarksTheEmptyLine;
var
  mPrompt: TAtlasAiPrompt;
begin
  mPrompt := TAtlasAiGhost.Prompt(RequestOf(cCode, 3), 7000);
  Assert.IsTrue(Pos('  ' + TAtlasAiGhost.cMarker, mPrompt.Task) > 0, 'Marke mit Einrückung');
  Assert.IsTrue(Pos('if FName', mPrompt.Task) > 0, 'Zeile davor');
  Assert.IsTrue(Pos('end;', mPrompt.Task) > 0, 'Zeile danach');
  Assert.IsTrue(Pos(TAtlasAiGhost.cMarker, mPrompt.Instructions) > 0, 'Anweisungen nennen die Marke');
  Assert.AreEqual(7000, mPrompt.TimeoutMs);
  Assert.AreEqual(TAtlasAiGhost.cMaxTokens, mPrompt.MaxTokens);
end;

procedure TAtlasAiGhostTests.PromptSendsOnlyTheFileName;
var
  mPrompt: TAtlasAiPrompt;
begin
  mPrompt := TAtlasAiGhost.Prompt(RequestOf(cCode, 3), 1000);
  Assert.IsTrue(Pos('Kunden.pas', mPrompt.Task) > 0, 'Name');
  Assert.IsFalse(Pos('Geheim', mPrompt.Task) > 0, 'kein Pfad');
end;

procedure TAtlasAiGhostTests.PromptCarriesDeclarations;
var
  mRequest: TAtlasAiGhostRequest;
  mPrompt: TAtlasAiPrompt;
begin
  mRequest := RequestOf(cCode, 3);
  mRequest.Declarations := TArray<string>.Create('TKunde = class', 'procedure Speichern;');
  mPrompt := TAtlasAiGhost.Prompt(mRequest, 1000);
  Assert.IsTrue(Pos('TKunde = class', mPrompt.Task) > 0, 'Klasse');
  Assert.IsTrue(Pos('procedure Speichern;', mPrompt.Task) > 0, 'Mitglied');
end;

procedure TAtlasAiGhostTests.PromptHonoursContextLines;
var
  mRequest: TAtlasAiGhostRequest;
  mPrompt: TAtlasAiPrompt;
begin
  mRequest := RequestOf(cCode, 3);
  mRequest.ContextLines := 1;
  mPrompt := TAtlasAiGhost.Prompt(mRequest, 1000);
  Assert.IsFalse(Pos('procedure TKunde.Speichern', mPrompt.Task) > 0, 'nur eine Zeile davor');
  Assert.IsTrue(Pos('if FName', mPrompt.Task) > 0, 'die Zeile davor');
end;

procedure TAtlasAiGhostTests.LinesDropFencesAndBlankEdges;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasAiGhost.LinesOf('```pascal' + #10 + #10 + 'Exit;' + #10 + '```' + #10, cCode, 3, 2, True);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual('  Exit;', mLines[0]);
end;

procedure TAtlasAiGhostTests.LinesTakeIndentOfTheEmptyLine;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasAiGhost.LinesOf('      Exit;', cCode, 3, 2, True);
  Assert.AreEqual('  Exit;', mLines[0], 'Einrückung der Zeile davor');
  mLines := TAtlasAiGhost.LinesOf('Exit;', 'begin' + #13#10 + '    ' + #13#10 + 'end;', 1, 2, True);
  Assert.AreEqual('    Exit;', mLines[0], 'eigene Einrückung der leeren Zeile');
end;

procedure TAtlasAiGhostTests.LinesKeepRelativeIndent;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasAiGhost.LinesOf('begin' + #13#10 + '  Exit;' + #13#10 + 'end;', cCode, 3, 2, True);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual('  begin', mLines[0]);
  Assert.AreEqual('    Exit;', mLines[1]);
  Assert.AreEqual('  end;', mLines[2]);
end;

procedure TAtlasAiGhostTests.LinesUseTabsWithoutInsertSpaces;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasAiGhost.LinesOf('Exit;', 'begin' + #10 + #9 + 'A;' + #10 + '', 2, 4, False);
  Assert.AreEqual(#9 + 'Exit;', mLines[0]);
end;

procedure TAtlasAiGhostTests.LinesAreCapped;
var
  mAnswer: string;
  mIndex: Integer;
begin
  mAnswer := '';
  for mIndex := 1 to 20 do
  begin
    mAnswer := mAnswer + 'A' + IntToStr(mIndex) + ';' + #10;
  end;
  Assert.AreEqual(TAtlasAiGhost.cMaxLines, Integer(Length(TAtlasAiGhost.LinesOf(mAnswer, cCode, 3, 2, True))));
end;

procedure TAtlasAiGhostTests.EmptyAnswerGivesNoLines;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasAiGhost.LinesOf('  ' + #10 + '```' + #10, cCode, 3, 2, True))));
end;

procedure TAtlasAiGhostTests.MasksMatchNameAndPath;
begin
  Assert.IsTrue(TAtlasAiGhost.Matches('Kunden.pas', '*.pas'), 'Stern');
  Assert.IsTrue(TAtlasAiGhost.Matches('Kunden.pas', 'K?nden.PAS'), 'Fragezeichen, Groß/klein');
  Assert.IsFalse(TAtlasAiGhost.Matches('Kunden.pas', '*.dfm'), 'andere Endung');
  Assert.IsTrue(TAtlasAiGhost.Matches('abcabd', '*abd'), 'Rücksprung im Stern');
  Assert.IsTrue(TAtlasAiGhost.Matches('', '*'), 'leer');
end;

procedure TAtlasAiGhostTests.ExcludeSplitsMasks;
begin
  Assert.IsTrue(TAtlasAiGhost.Excluded('C:\P\Geheim\Kunden.pas', '*.dfm; *\Geheim\*'), 'Pfadmaske');
  Assert.IsTrue(TAtlasAiGhost.Excluded('C:/P/Lizenz.pas', 'Lizenz*'), 'Namensmaske, Schrägstriche');
  Assert.IsFalse(TAtlasAiGhost.Excluded('C:\P\Kunden.pas', '*.dfm;;'), 'keine passt');
  Assert.IsFalse(TAtlasAiGhost.Excluded('C:\P\Kunden.pas', ''), 'keine Masken');
end;

procedure TAtlasAiGhostTests.DailyCountStopsAtLimit;
var
  mCount: TAtlasAiDailyCount;
begin
  mCount := TAtlasAiDailyCount.Create;
  try
    Assert.IsTrue(mCount.TryTake('2026-11-18', 2), 'erste');
    Assert.IsTrue(mCount.TryTake('2026-11-18', 2), 'zweite');
    Assert.IsFalse(mCount.TryTake('2026-11-18', 2), 'Grenze');
    Assert.AreEqual(2, mCount.CountOn('2026-11-18'));
    Assert.IsTrue(mCount.Changed, 'geändert');
  finally
    mCount.Free;
  end;
end;

procedure TAtlasAiGhostTests.DailyCountStartsNewDay;
var
  mCount: TAtlasAiDailyCount;
begin
  mCount := TAtlasAiDailyCount.Create;
  try
    mCount.TryTake('2026-11-18', 1);
    Assert.IsTrue(mCount.TryTake('2026-11-19', 1), 'neuer Tag');
    Assert.AreEqual(0, mCount.CountOn('2026-11-18'));
    Assert.AreEqual(1, mCount.CountOn('2026-11-19'));
  finally
    mCount.Free;
  end;
end;

procedure TAtlasAiGhostTests.DailyCountRoundTripsJson;
var
  mCount, mRead: TAtlasAiDailyCount;
begin
  mCount := TAtlasAiDailyCount.Create;
  mRead := TAtlasAiDailyCount.Create;
  try
    mCount.TryTake('2026-11-18', 5);
    mCount.TryTake('2026-11-18', 5);
    Assert.IsTrue(mRead.FromJson(mCount.ToJson), 'gelesen');
    Assert.AreEqual(2, mRead.CountOn('2026-11-18'));
    Assert.IsFalse(mRead.Changed, 'frisch gelesen');
    Assert.IsFalse(mRead.FromJson('[1]'), 'kein Objekt');
    Assert.IsFalse(mRead.FromJson('{"day":"x"}'), 'ohne Zahl');
    Assert.AreEqual(2, mRead.CountOn('2026-11-18'), 'alter Stand bleibt');
  finally
    mRead.Free;
    mCount.Free;
  end;
end;

end.
