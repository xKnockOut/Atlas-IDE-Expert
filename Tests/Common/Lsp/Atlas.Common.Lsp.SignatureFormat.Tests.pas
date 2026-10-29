unit Atlas.Common.Lsp.SignatureFormat.Tests;

// Tests der Platzhalter im Parameter-Hint (#451): Zuordnung Platzhalter → Argument, Lage im Dokument,
// Eintrag am Cursor, Konstanten als Formatstring, überzählige Argumente, Typkonflikte mit Literalen,
// eigene Formatroutinen und JSON.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Lsp.SignatureHelp;

type
  [TestFixture]
  TSignatureFormatTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function HelpAt(const ABody: string; const ARoutines: TArray<TFormatRoutine>): TSignatureHelp; overload;
    function HelpAt(const ABody: string): TSignatureHelp; overload;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure IssueExample;
    [Test]
    procedure ArgumentsBehindTheCursor;
    [Test]
    procedure ThreeArgumentsForTwoPlaceholdersWarn;
    [Test]
    procedure EmptyTrailingArgumentDoesNotCount;
    [Test]
    procedure LiteralTypeConflict;
    [Test]
    procedure IndexAndStar;
    [Test]
    procedure ConstantFormatHasNoRanges;
    [Test]
    procedure UnknownFormatStaysSilent;
    [Test]
    procedure InvalidPlaceholder;
    [Test]
    procedure OwnFormatRoutine;
    [Test]
    procedure OtherRoutinesHaveNoFormat;
    [Test]
    procedure WritesJson;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.SignatureFormat;

const
  SysUtilsFile = 'C:\P\System.SysUtils.pas';
  HauptFile = 'C:\P\Haupt.pas';

  UnitSysUtils =
    'unit System.SysUtils;'#10 +
    'interface'#10 +
    'function Format(const Format: string; const Args: array of const): string;'#10 +
    'function FormatFloat(const Format: string; Value: Extended): string;'#10 +
    'implementation'#10 +
    'function Format(const Format: string; const Args: array of const): string;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function FormatFloat(const Format: string; Value: Extended): string;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  // | ist der Cursor; der Rumpf ersetzt ihn.
  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses System.SysUtils;'#10 +
    'const'#10 +
    '  cZeilen = ''%s hat %d Zeilen'';'#10 +
    'procedure Protokoll(const AText: string; const AWerte: array of const);'#10 +
    'implementation'#10 +
    'procedure Protokoll(const AText: string; const AWerte: array of const);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Melden(const FileName: string; Count: Integer; const AFormat: string);'#10 +
    'var'#10 +
    '  S: string;'#10 +
    'begin'#10 +
    '@'#10 +
    'end;'#10 +
    'end.';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := UnitSysUtils;
  Result := SameText(AFileName, SysUtilsFile);
end;

procedure TSignatureFormatTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSysUtils, SysUtilsFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TSignatureFormatTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TSignatureFormatTests.HelpAt(const ABody: string; const ARoutines: TArray<TFormatRoutine>): TSignatureHelp;
var
  mText: string;
  mTree: TSyntaxTree;
  mLine, mCharacter, mIndex: Integer;
begin
  mText := StringReplace(UnitHaupt, '@', ABody, []);
  mIndex := Pos('|', mText);
  Assert.IsTrue(mIndex > 0, 'Cursor fehlt');
  Delete(mText, mIndex, 1);
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to mIndex - 1 do
    if mText[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
      Inc(mCharacter);
  mTree := TPascalParser.Parse(mText);
  try
    FIndex.AddUnit(TIndexExtractor.Extract(mTree, HauptFile));
    Result := TLspSignatureHelp.HelpAt(FResolver, FIndex, mTree, mText, HauptFile,
      TTextPosition.Create(mLine, mCharacter), ReadText, ARoutines);
  finally
    mTree.Free;
  end;
end;

function TSignatureFormatTests.HelpAt(const ABody: string): TSignatureHelp;
begin
  Result := HelpAt(ABody, TFormatRoutines.Defaults);
end;

procedure TSignatureFormatTests.IssueExample;
var
  mHelp: TSignatureHelp;
  mFormat: TSignatureFormat;
begin
  // Zeile 14 im Dokument; "  S := Format('" ist 15 Zeichen lang.
  mHelp := HelpAt('  S := Format(''%s hat %d Zeilen'', [FileName, |');
  Assert.IsTrue(mHelp.Found);
  mFormat := mHelp.Format;
  Assert.IsTrue(mFormat.Found);
  Assert.AreEqual(0, mFormat.FormatParameter);
  Assert.AreEqual(1, mFormat.ListParameter);
  Assert.AreEqual(2, Integer(Length(mFormat.Specs)));
  Assert.AreEqual(2, mFormat.ArgumentCount);
  // Der Cursor steht im zweiten Eintrag: Platzhalter 2 (%d, ganzzahlig).
  Assert.AreEqual(1, mFormat.ActiveArgument);
  Assert.AreEqual(1, mFormat.Specs[1].Argument);
  Assert.AreEqual('d', mFormat.Specs[1].TypeChar);
  // %s und FileName haben ihre Lage im Dokument.
  Assert.AreEqual(14, mFormat.Specs[0].Range.StartPos.Line);
  Assert.AreEqual(15, mFormat.Specs[0].Range.StartPos.Character);
  Assert.AreEqual(17, mFormat.Specs[0].Range.EndPos.Character);
  Assert.AreEqual(22, mFormat.Specs[1].Range.StartPos.Character);
  Assert.AreEqual(2, Integer(Length(mFormat.Arguments)));
  Assert.AreEqual(1, mFormat.FilledArguments);
  Assert.AreEqual(35, mFormat.Arguments[0].StartPos.Character);
  Assert.AreEqual(43, mFormat.Arguments[0].EndPos.Character);
  Assert.AreEqual(Ord(TSignatureFormatProblem.None), Ord(mFormat.Problem));
end;

procedure TSignatureFormatTests.ArgumentsBehindTheCursor;
var
  mFormat: TSignatureFormat;
begin
  // Cursor im ersten Eintrag einer fertigen Liste: alle Einträge zählen.
  mFormat := HelpAt('  S := Format(''%s hat %d Zeilen'', [File|Name, Count]);').Format;
  Assert.IsTrue(mFormat.Found);
  Assert.AreEqual(0, mFormat.ActiveArgument);
  Assert.AreEqual(2, mFormat.FilledArguments);
  // Hinter der Liste ist kein Eintrag aktiv.
  mFormat := HelpAt('  S := Format(''%s hat %d Zeilen'', [FileName, Count]|);').Format;
  Assert.AreEqual(-1, mFormat.ActiveArgument);
  // Im Formatstring selbst wird noch getippt.
  Assert.IsFalse(HelpAt('  S := Format(''%s hat %d|').Format.Found);
end;

procedure TSignatureFormatTests.ThreeArgumentsForTwoPlaceholdersWarn;
var
  mFormat: TSignatureFormat;
begin
  mFormat := HelpAt('  S := Format(''%s hat %d Zeilen'', [FileName, Count, |S]);').Format;
  Assert.AreEqual(Ord(TSignatureFormatProblem.TooManyArguments), Ord(mFormat.Problem));
  Assert.AreEqual(2, mFormat.ProblemArgument);
  Assert.AreEqual(2, mFormat.ActiveArgument);
end;

procedure TSignatureFormatTests.EmptyTrailingArgumentDoesNotCount;
var
  mFormat: TSignatureFormat;
begin
  mFormat := HelpAt('  S := Format(''%s hat %d Zeilen'', [FileName, Count, |').Format;
  Assert.AreEqual(3, Integer(Length(mFormat.Arguments)));
  Assert.AreEqual(2, mFormat.FilledArguments);
  Assert.AreEqual(Ord(TSignatureFormatProblem.None), Ord(mFormat.Problem));
end;

procedure TSignatureFormatTests.LiteralTypeConflict;
var
  mFormat: TSignatureFormat;
begin
  mFormat := HelpAt('  S := Format(''%s hat %d Zeilen'', [FileName, ''viele''|').Format;
  Assert.AreEqual(Ord(TSignatureFormatProblem.TypeConflict), Ord(mFormat.Problem));
  Assert.AreEqual(1, mFormat.ProblemSpec);
  Assert.AreEqual(1, mFormat.ProblemArgument);
  Assert.AreEqual('string', mFormat.ProblemKind);
  mFormat := HelpAt('  S := Format(''%s'', [5|').Format;
  Assert.AreEqual(Ord(TSignatureFormatProblem.TypeConflict), Ord(mFormat.Problem));
  Assert.AreEqual('integer', mFormat.ProblemKind);
  mFormat := HelpAt('  S := Format(''%d'', [True|').Format;
  Assert.AreEqual('boolean', mFormat.ProblemKind);
  // Ausdrücke und Bezeichner bleiben ohne Aussage, ein Zeichen passt zu %s.
  Assert.AreEqual(Ord(TSignatureFormatProblem.None),
    Ord(HelpAt('  S := Format(''%d %s %d'', [5 + Count, #13, -1|').Format.Problem));
end;

procedure TSignatureFormatTests.IndexAndStar;
var
  mFormat: TSignatureFormat;
begin
  mFormat := HelpAt('  S := Format(''%1:s %0:*d'', [Count, |').Format;
  Assert.AreEqual(2, Integer(Length(mFormat.Specs)));
  Assert.AreEqual(1, mFormat.Specs[0].Argument);
  Assert.AreEqual(0, mFormat.Specs[1].WidthArgument);
  Assert.AreEqual(1, mFormat.Specs[1].Argument);
  Assert.AreEqual(2, mFormat.ArgumentCount);
  // "*" mit einem String: Konflikt beim Platzhalter 2.
  mFormat := HelpAt('  S := Format(''%*d'', [''breit'', 3|').Format;
  Assert.AreEqual(Ord(TSignatureFormatProblem.TypeConflict), Ord(mFormat.Problem));
  Assert.AreEqual(0, mFormat.ProblemSpec);
  Assert.AreEqual(0, mFormat.ProblemArgument);
end;

procedure TSignatureFormatTests.ConstantFormatHasNoRanges;
var
  mFormat: TSignatureFormat;
begin
  mFormat := HelpAt('  S := Format(cZeilen, [FileName, |').Format;
  Assert.IsTrue(mFormat.Found);
  Assert.AreEqual(2, Integer(Length(mFormat.Specs)));
  Assert.AreEqual(-1, mFormat.Specs[0].Range.StartPos.Line);
  Assert.AreEqual(1, mFormat.ActiveArgument);
  // Verkettung aus Literalen hat ihre Lage.
  mFormat := HelpAt('  S := Format(''%s '' + ''%d'', [FileName, |').Format;
  Assert.AreEqual(2, Integer(Length(mFormat.Specs)));
  Assert.AreEqual(23, mFormat.Specs[1].Range.StartPos.Character);
end;

procedure TSignatureFormatTests.UnknownFormatStaysSilent;
begin
  Assert.IsFalse(HelpAt('  S := Format(AFormat, [FileName, |').Format.Found);
  Assert.IsFalse(HelpAt('  S := Format(''%s'' + AFormat, [|').Format.Found);
end;

procedure TSignatureFormatTests.InvalidPlaceholder;
var
  mFormat: TSignatureFormat;
begin
  mFormat := HelpAt('  S := Format(''%q und %d'', [|').Format;
  Assert.AreEqual(Ord(TSignatureFormatProblem.Invalid), Ord(mFormat.Problem));
  Assert.AreEqual(0, mFormat.ProblemSpec);
  Assert.IsFalse(mFormat.Specs[0].Valid);
end;

procedure TSignatureFormatTests.OwnFormatRoutine;
var
  mFormat: TSignatureFormat;
begin
  // Ohne Eintrag keine Platzhalter, mit Eintrag (formatMethods bzw. .atlas) schon.
  Assert.IsFalse(HelpAt('  Protokoll(''%d Fehler'', [|').Format.Found);
  mFormat := HelpAt('  Protokoll(''%d Fehler'', [|', TFormatRoutines.Defaults +
    [TFormatRoutines.Custom('Protokoll', 0)]).Format;
  Assert.IsTrue(mFormat.Found);
  Assert.AreEqual(0, mFormat.ActiveArgument);
  Assert.AreEqual('d', mFormat.Specs[0].TypeChar);
end;

procedure TSignatureFormatTests.OtherRoutinesHaveNoFormat;
begin
  Assert.IsTrue(HelpAt('  S := FormatFloat(''0.00'', |').Found);
  Assert.IsFalse(HelpAt('  S := FormatFloat(''0.00'', |').Format.Found);
end;

procedure TSignatureFormatTests.WritesJson;
var
  mJson: TJSONValue;
  mFormat: TJSONObject;
  mText: string;
begin
  mJson := TLspSignatureHelp.ToJson(HelpAt('  S := Format(''%s hat %d Zeilen'', [FileName, Count, |S]);'));
  try
    Assert.IsTrue(TJSONObject(mJson).TryGetValue<TJSONObject>('format', mFormat));
    Assert.AreEqual(2, mFormat.GetValue<Integer>('activeArgument'));
    Assert.AreEqual(2, mFormat.GetValue<Integer>('argumentCount'));
    mText := mFormat.GetValue<string>('problem.kind');
    Assert.AreEqual('tooManyArguments', mText);
    Assert.AreEqual(2, Integer((mFormat.GetValue('placeholders') as TJSONArray).Count));
    Assert.AreEqual(3, Integer((mFormat.GetValue('arguments') as TJSONArray).Count));
  finally
    mJson.Free;
  end;
  // Ohne Formatroutine kein "format".
  mJson := TLspSignatureHelp.ToJson(HelpAt('  S := FormatFloat(''0.00'', |'));
  try
    Assert.IsNull(TJSONObject(mJson).GetValue('format'));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSignatureFormatTests);

end.
