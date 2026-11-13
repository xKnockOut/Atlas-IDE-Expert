unit Atlas.Common.Editing.TestCommands;

// Schnellbefehle für Tests und Fehlersuche (#305) im Rahmen aus #293:
//   /mock IKundenRepo     auf Unit-Ebene: Klasse TKundenRepoMock = class(TInterfacedObject,
//                         IKundenRepo) mit allen Methoden; jede zählt ihre Aufrufe
//                         (LadenCalls), Funktionen liefern ein einstellbares Feld
//                         (LadenResult). In einer Routine einer Unit mit Delphi.Mocks:
//                         lokale Variable TMock<IKundenRepo> samt Create.
//   /testcase 'a', 2, True  über einer Testmethode: [TestCase('Fall1', 'a,2,True')],
//                         fortlaufend nummeriert; die Zahl der Werte muss zu den
//                         Parametern der Methode darunter passen
//   /dump                 Ausgabe aller Parameter und lokalen Variablen einfacher Typen
//                         über OutputDebugString bzw. slashCommands.logCall
//   /assert               Assert für die Variable der vorigen Zeile passend zum Typ;
//                         in Testunits Assert.IsNotNull/AreNotEqual/IsTrue aus DUnitX

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /mock, /testcase, /dump und /assert über ARegister ein.</summary>
procedure RegisterTestCommands(const ARegister: TSlashRegister);

type
  /// <summary>Reine Textbausteine der Befehle, für Tests offen.</summary>
  TTestCommandTexts = class
  public
    /// <summary>Werte aus "'a', 2, True": Strings ohne Anführungszeichen ('' wird '), sonst wie geschrieben;
    /// Kommas in Strings trennen nicht. False bei offenem String.</summary>
    class function SplitValues(const AText: string; out AValues: TArray<string>): Boolean; static;
    /// <summary>Attribut TestCase mit Name und Werten, bzw. mit ';' als Trenner, wenn ein Wert ein Komma enthält.
    /// </summary>
    class function TestCaseAttribute(const AName: string; const AValues: TArray<string>): string; static;
    /// <summary>Name der Mock-Klasse: IKundenRepo wird TKundenRepoMock.</summary>
    class function MockClassName(const AInterfaceName: string): string; static;
    /// <summary>Platzhalter für Format je Typ (%d, %s, %g) und der Ausdruck dazu; False bei anderen Typen.
    /// </summary>
    class function DumpPart(const AName, ATypeName: string; out AFormat, AArgument: string): Boolean; static;
    /// <summary>Assert-Zeile für die Variable AName vom Typ ATypeName; AIsClass bei bekannten Klassen, ATestUnit
    /// für DUnitX. False, wenn der Typ keine Prüfung hergibt.</summary>
    class function AssertLine(const AName, ATypeName: string; AIsClass, ATestUnit: Boolean;
      out ALine: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTestCommandsText = (MockSummary, TestCaseSummary, DumpSummary, AssertSummary, MockNeedsName, MockPlace,
    NotAnInterface, MockWithoutMethods, TestCasePlace, TestCaseNeedsValues, TestCaseOpenString, NoTestMethodBelow,
    TestCaseCount, CaseName, DumpPlace, DumpNothing, AssertPlace, AssertNoVariable, AssertNoType, NotNil, NotEmpty,
    NotNegative, IsFalse);

const
  cTexts: array[TTestCommandsText] of TAtlasText = (
    (De: 'Mock-Klasse zu einem Interface erzeugen (Aufrufe zählen, Ergebnisse einstellbar)';
     En: 'Create a mock class for an interface (counts calls, configurable results)'),
    (De: 'Testfall-Attribut über der Testmethode einfügen'; En: 'Insert a test case attribute above the test method'),
    (De: 'Parameter und lokale Variablen ausgeben'; En: 'Output parameters and local variables'),
    (De: 'Assert für die Variable der vorigen Zeile'; En: 'Assert for the variable of the previous line'),
    (De: 'Erwartet wird ein Interface, z. B. /mock IKundenRepo'; En: 'Expected is an interface, e.g. /mock ICustomerRepo'),
    (De: '/mock gilt auf Unit-Ebene oder in einer Routine einer Unit mit Delphi.Mocks';
     En: '/mock applies at unit level or in a routine of a unit using Delphi.Mocks'),
    (De: '%s ist kein bekanntes Interface'; En: '%s is not a known interface'),
    (De: '%s hat keine Methoden'; En: '%s has no methods'),
    (De: '/testcase gilt in einer Testklasse über einer Testmethode';
     En: '/testcase applies in a test class above a test method'),
    (De: 'Erwartet werden Werte, z. B. /testcase ''a'', 2, True'; En: 'Expected are values, e.g. /testcase ''a'', 2, True'),
    (De: 'Ein String in den Werten ist nicht geschlossen'; En: 'A string in the values is not closed'),
    (De: 'Unter /testcase steht keine Testmethode'; En: 'There is no test method below /testcase'),
    (De: '%s erwartet %d Werte, angegeben sind %d'; En: '%s expects %d values, %d are given'),
    (De: 'Fall'; En: 'Case'),
    (De: '/dump gilt nur im Rumpf einer Routine'; En: '/dump only applies in the body of a routine'),
    (De: 'Keine Parameter oder lokalen Variablen einfacher Typen'; En: 'No parameters or local variables of simple types'),
    (De: '/assert gilt nur im Rumpf einer Routine'; En: '/assert only applies in the body of a routine'),
    (De: 'In der Zeile davor wird keine Variable zugewiesen'; En: 'The previous line assigns no variable'),
    (De: 'Für den Typ von %s gibt es keine passende Prüfung'; En: 'There is no fitting check for the type of %s'),
    (De: '%s ist nil'; En: '%s is nil'),
    (De: '%s ist leer'; En: '%s is empty'),
    (De: '%s ist negativ'; En: '%s is negative'),
    (De: '%s ist False'; En: '%s is False'));

{$SCOPEDENUMS OFF}

const
  cIntegerTypes: array[0..15] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'LongInt', 'LongWord', 'ShortInt', 'SmallInt', 'FixedInt', 'FixedUInt', 'Int32', 'UInt32');
  cFloatTypes: array[0..5] of string = ('Double', 'Single', 'Extended', 'Real', 'Currency', 'TDateTime');
  cStringTypes: array[0..7] of string = ('string', 'AnsiString', 'UnicodeString', 'WideString', 'RawByteString',
    'UTF8String', 'ShortString', 'TFileName');
  cCharTypes: array[0..2] of string = ('Char', 'WideChar', 'AnsiChar');
  cBooleanTypes: array[0..1] of string = ('Boolean', 'LongBool');
  cReferenceTypes: array[0..4] of string = ('TObject', 'Pointer', 'IInterface', 'IUnknown', 'TComponent');

{ TTestCommandTexts }

/// <summary>Ein Wert aus AText ab AIndex (1-basiert) bis vor das trennende Komma; AIndex steht danach dahinter.
/// </summary>
function ReadValue(const AText: string; var AIndex: Integer; out AValue: string): Boolean;
var
  mBuilder: TStringBuilder;
  mInString: Boolean;
begin
  mBuilder := TStringBuilder.Create;
  try
    mInString := False;
    while AIndex <= Length(AText) do
    begin
      if AText[AIndex] = '''' then
      begin
        if mInString and (AIndex < Length(AText)) and (AText[AIndex + 1] = '''') then
        begin
          mBuilder.Append('''');
          Inc(AIndex);
        end
        else
        begin
          mInString := not mInString;
        end;
      end
      else if (AText[AIndex] = ',') and not mInString then
      begin
        Break;
      end
      else
      begin
        mBuilder.Append(AText[AIndex]);
      end;
      Inc(AIndex);
    end;
    Inc(AIndex);
    AValue := mBuilder.ToString;
    Result := not mInString;
  finally
    mBuilder.Free;
  end;
end;

class function TTestCommandTexts.SplitValues(const AText: string; out AValues: TArray<string>): Boolean;
var
  mIndex: Integer;
  mValue: string;
begin
  AValues := nil;
  Result := True;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mIndex := 1;
  while Result and (mIndex <= Length(AText) + 1) do
  begin
    Result := ReadValue(AText, mIndex, mValue);
    AValues := AValues + [mValue.Trim];
  end;
end;

class function TTestCommandTexts.TestCaseAttribute(const AName: string; const AValues: TArray<string>): string;
var
  mSeparator, mValue: string;
begin
  mSeparator := ',';
  for mValue in AValues do
  begin
    if Pos(',', mValue) > 0 then
    begin
      mSeparator := ';';
    end;
  end;
  Result := '[TestCase(' + QuotedStr(AName) + ', ' + QuotedStr(string.Join(mSeparator, AValues));
  if mSeparator <> ',' then
  begin
    Result := Result + ', ' + QuotedStr(mSeparator);
  end;
  Result := Result + ')]';
end;

class function TTestCommandTexts.MockClassName(const AInterfaceName: string): string;
var
  mName: string;
begin
  mName := AInterfaceName;
  if (Length(mName) > 1) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']) then
  begin
    mName := Copy(mName, 2, MaxInt);
  end;
  Result := 'T' + mName + 'Mock';
end;

class function TTestCommandTexts.DumpPart(const AName, ATypeName: string; out AFormat, AArgument: string): Boolean;
begin
  Result := True;
  AArgument := AName;
  if MatchText(ATypeName, cIntegerTypes) then
  begin
    AFormat := AName + '=%d';
  end
  else if MatchText(ATypeName, cFloatTypes) then
  begin
    AFormat := AName + '=%g';
  end
  else if MatchText(ATypeName, cStringTypes) or MatchText(ATypeName, cCharTypes) then
  begin
    AFormat := AName + '=%s';
  end
  else if MatchText(ATypeName, cBooleanTypes) then
  begin
    AFormat := AName + '=%s';
    AArgument := 'BoolToStr(' + AName + ', True)';
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Prüfung mit Assert aus System bzw. DUnitX; AMessage ist schon übersetzt.</summary>
function AssertText(ATestUnit: Boolean; const ACondition, ADUnitX, AMessage: string): string;
begin
  if ATestUnit then
  begin
    Result := ADUnitX;
  end
  else
  begin
    Result := 'Assert(' + ACondition + ', ' + QuotedStr(AMessage) + ');';
  end;
end;

class function TTestCommandTexts.AssertLine(const AName, ATypeName: string; AIsClass, ATestUnit: Boolean;
  out ALine: string): Boolean;
var
  mType: string;
begin
  Result := True;
  mType := Trim(ATypeName);
  if AIsClass or MatchText(mType, cReferenceTypes) or
    ((Length(mType) > 1) and (mType[1] = 'I') and CharInSet(mType[2], ['A'..'Z'])) then
  begin
    ALine := AssertText(ATestUnit, 'Assigned(' + AName + ')', 'Assert.IsNotNull(' + AName + ');',
      cTexts[TTestCommandsText.NotNil].Fmt([AName]));
  end
  else if MatchText(mType, cStringTypes) then
  begin
    ALine := AssertText(ATestUnit, AName + ' <> ''''', 'Assert.AreNotEqual('''', ' + AName + ');',
      cTexts[TTestCommandsText.NotEmpty].Fmt([AName]));
  end
  else if MatchText(mType, cIntegerTypes) or MatchText(mType, cFloatTypes) then
  begin
    ALine := AssertText(ATestUnit, AName + ' >= 0', 'Assert.IsTrue(' + AName + ' >= 0);',
      cTexts[TTestCommandsText.NotNegative].Fmt([AName]));
  end
  else if MatchText(mType, cBooleanTypes) then
  begin
    ALine := AssertText(ATestUnit, AName, 'Assert.IsTrue(' + AName + ');',
      cTexts[TTestCommandsText.IsFalse].Fmt([AName]));
  end
  else
  begin
    ALine := '';
    Result := False;
  end;
end;

{ /mock }

/// <summary>Methoden des Interfaces AName samt Vorfahren, die TInterfacedObject nicht schon hat. False, wenn AName
/// kein bekanntes Interface ist.</summary>
function InterfaceMembers(const AContext: TSlashContext; const AOwn: TUnitIndex; const AName, AMockName: string;
  out AMembers: TArray<TResolvedSymbol>): Boolean;
var
  mResolver: TNameResolver;
  mResolved, mMember: TResolvedSymbol;
  mUnit: TUnitIndex;
  mMock: TIndexSymbol;
begin
  AMembers := nil;
  // Die Mock-Klasse gibt es noch nicht: gedacht in die Unit eintragen, damit die Abfrage ihre Vorfahren kennt.
  mUnit := AOwn;
  mMock := Default(TIndexSymbol);
  mMock.Name := AMockName;
  mMock.Kind := TIndexSymbolKind.ClassType;
  mMock.Ancestors := ['TInterfacedObject', AName];
  mUnit.Symbols := mUnit.Symbols + [mMock];
  mResolver := TNameResolver.Create(AContext.Index);
  try
    mResolver.Namespaces := AContext.Namespaces;
    Result := mResolver.ResolveNameFrom(AOwn, AName, mResolved) and
      (mResolved.SymbolKind = TIndexSymbolKind.InterfaceType);
    if not Result then
    begin
      Exit;
    end;
    for mMember in mResolver.Queries.MissingInterfaceMembers(mUnit, AMockName, ['TInterfacedObject', AName]) do
    begin
      // IInterface erfüllt TInterfacedObject.
      if not MatchText(mMember.Container, ['IInterface', 'IUnknown']) then
      begin
        AMembers := AMembers + [mMember];
      end;
    end;
  finally
    mResolver.Free;
  end;
end;

/// <summary>Deklaration von AMember aus seiner Datei (oder der eigenen); '' wenn sie sich nicht lesen lässt.
/// </summary>
function MemberDeclaration(ASource: TCommandSource; const AFileName: string;
  const AMember: TResolvedSymbol): string;
var
  mText: string;
  mLines: TArray<string>;
begin
  mLines := ASource.Lines;
  if (AMember.FileName <> '') and not SameText(AMember.FileName, AFileName) then
  begin
    if not LoadText(AMember.FileName, mText) then
    begin
      Exit('');
    end;
    mLines := mText.Replace(#13, '').Split([#10]);
  end;
  Result := TInterfaceStubs.DeclarationOf(mLines, AMember.Range);
end;

type
  /// <summary>Teile der Mock-Klasse: Felder, Deklarationen, Rümpfe.</summary>
  TMockParts = record
    Fields: TArray<string>;
    Declarations: TArray<string>;
    Bodies: TArray<string>;
    Names: TArray<string>;
    procedure Add(const AMockName, ADeclaration, ALineBreak: string);
  end;

procedure TMockParts.Add(const AMockName, ADeclaration, ALineBreak: string);
var
  mIsClass: Boolean;
  mKind, mHead, mDirectives, mName, mPrefix, mResultType: string;
  mNumber: Integer;
begin
  if not TInterfaceStubs.Split(ADeclaration, mIsClass, mKind, mHead, mDirectives) then
  begin
    Exit;
  end;
  mName := Trim(Copy(mHead, 1, Pos('(', mHead + '(') - 1));
  mName := Trim(Copy(mName, 1, Pos(':', mName + ':') - 1));
  // Überladungen: LadenCalls, Laden2Calls …
  mPrefix := mName;
  mNumber := 1;
  while MatchText(mPrefix, Names) do
  begin
    Inc(mNumber);
    mPrefix := mName + IntToStr(mNumber);
  end;
  Names := Names + [mPrefix];
  mResultType := TInterfaceStubs.ReturnType(mHead);
  Fields := Fields + [mPrefix + 'Calls: Integer;'];
  if mResultType <> '' then
  begin
    Fields := Fields + [mPrefix + 'Result: ' + mResultType + ';'];
  end;
  Declarations := Declarations + [mKind + ' ' + mHead + ';'];
  mHead := StringReplace(mHead, mName, AMockName + '.' + mName, []);
  if mResultType <> '' then
  begin
    Bodies := Bodies + [mKind + ' ' + mHead + ';' + ALineBreak + 'begin' + ALineBreak + '  Inc(' + mPrefix +
      'Calls);' + ALineBreak + '  Result := ' + mPrefix + 'Result;' + ALineBreak + 'end;'];
  end
  else
  begin
    Bodies := Bodies + [mKind + ' ' + mHead + ';' + ALineBreak + 'begin' + ALineBreak + '  Inc(' + mPrefix +
      'Calls);' + ALineBreak + 'end;'];
  end;
end;

/// <summary>Zeilen der Mock-Klasse samt "type".</summary>
function MockClassLines(const AMockName, AInterface: string; const AParts: TMockParts): TArray<string>;
var
  mLine: string;
begin
  Result := ['type', '  ' + AMockName + ' = class(TInterfacedObject, ' + AInterface + ')', '  public'];
  for mLine in AParts.Fields do
  begin
    Result := Result + ['    ' + mLine];
  end;
  for mLine in AParts.Declarations do
  begin
    Result := Result + ['    ' + mLine];
  end;
  Result := Result + ['  end;'];
end;

/// <summary>/mock in einer Routine einer Unit mit Delphi.Mocks: lokale Variable und Create.</summary>
function DelphiMocksEdits(ASource: TCommandSource; ARoutine: TSyntaxNode; const AName: string;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mVariable: string;
begin
  // Variable ohne I und ohne Mock: IKundenRepo wird KundenRepo.
  mVariable := TTestCommandTexts.MockClassName(AName);
  mVariable := Copy(mVariable, 2, Length(mVariable) - Length('TMock'));
  AEdits := [AddLocal(ASource, ARoutine, TSyntaxKind.VarSection, 'var', mVariable + ': TMock<' + AName + '>;'),
    ASource.ReplaceWithIndentedLines([mVariable + ' := TMock<' + AName + '>.Create;'])];
  Result := True;
end;

/// <summary>Steht die Befehlszeile auf Unit-Ebene (nicht in einer Routine oder Typdeklaration)?</summary>
function AtUnitLevel(ASource: TCommandSource): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := ASource.RoutineAt = nil;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if Result and (mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.ObjectType]) and
      (mSymbol.Range.StartPos.Line < ASource.Line) and (mSymbol.Range.EndPos.Line > ASource.Line) then
    begin
      Result := False;
    end;
  end;
end;

function MockEdits(ASource: TCommandSource; const AContext: TSlashContext; const AName: string;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mMockName, mFileName, mDeclaration: string;
  mOwn: TUnitIndex;
  mMembers: TArray<TResolvedSymbol>;
  mMember: TResolvedSymbol;
  mParts: TMockParts;
begin
  mMockName := TTestCommandTexts.MockClassName(AName);
  mFileName := '';
  if AContext.Uri <> '' then
  begin
    mFileName := TDocumentUris.ToPath(AContext.Uri);
  end;
  mOwn := ASource.UnitIndex;
  mOwn.FileName := mFileName;
  if not InterfaceMembers(AContext, mOwn, AName, mMockName, mMembers) then
  begin
    Exit(Fail(cTexts[TTestCommandsText.NotAnInterface].Fmt([AName]), AReason));
  end;
  mParts := Default(TMockParts);
  for mMember in mMembers do
  begin
    mDeclaration := MemberDeclaration(ASource, mFileName, mMember);
    if mDeclaration <> '' then
    begin
      mParts.Add(mMockName, mDeclaration, ASource.LineBreak);
    end;
  end;
  if Length(mParts.Declarations) = 0 then
  begin
    Exit(Fail(cTexts[TTestCommandsText.MockWithoutMethods].Fmt([AName]), AReason));
  end;
  AEdits := [ASource.ReplaceWithLines(MockClassLines(mMockName, AName, mParts)),
    ASource.AddBody(mMockName, string.Join(ASource.LineBreak + ASource.LineBreak, mParts.Bodies) +
    ASource.LineBreak)];
  Result := True;
end;

function ExecuteMock(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mName: string;
  mRoutine: TSyntaxNode;
begin
  AEdits := nil;
  mName := Trim(AContext.Arguments);
  if not IsValidIdent(mName, True) then
  begin
    Exit(Fail(cTexts[TTestCommandsText.MockNeedsName].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if (mRoutine <> nil) and TUsesClauses.IsUsed(TUsesClauses.UsedUnits(mSource.Tree.Tokens), 'Delphi.Mocks', nil)
    then
    begin
      Exit(DelphiMocksEdits(mSource, mRoutine, mName, AEdits));
    end;
    if not AtUnitLevel(mSource) then
    begin
      Exit(Fail(cTexts[TTestCommandsText.MockPlace].Text, AReason));
    end;
    Result := MockEdits(mSource, AContext, mName, AEdits, AReason);
  finally
    mSource.Free;
  end;
end;

{ /testcase }

/// <summary>Erste Zeile nach ALine, die kein Attribut, keine Leerzeile und kein Kommentar ist.</summary>
function MethodLineBelow(const ALines: TArray<string>; ALine: Integer; out ACases: Integer): Integer;
var
  mText: string;
begin
  ACases := 0;
  Result := ALine + 1;
  while Result <= High(ALines) do
  begin
    mText := Trim(ALines[Result]);
    if StartsText('[TestCase(', mText) then
    begin
      Inc(ACases);
    end
    else if not ((mText = '') or mText.StartsWith('[') or mText.StartsWith('//')) then
    begin
      Exit;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Testfälle über der Befehlszeile, die schon zur selben Methode gehören.</summary>
function CasesAbove(const ALines: TArray<string>; ALine: Integer): Integer;
var
  mIndex: Integer;
  mText: string;
begin
  Result := 0;
  mIndex := ALine - 1;
  while mIndex >= 0 do
  begin
    mText := Trim(ALines[mIndex]);
    if StartsText('[TestCase(', mText) then
    begin
      Inc(Result);
    end
    else if not (mText.StartsWith('[') or (mText = '')) then
    begin
      Exit;
    end;
    Dec(mIndex);
  end;
end;

/// <summary>Kopf der Methode in Zeile ALine; False, wenn dort keine beginnt.</summary>
function MethodHeaderAt(ASource: TCommandSource; ALine: Integer; out AHeader: TSignatureHeader): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mText: string;
begin
  AHeader := Default(TSignatureHeader);
  mText := ASource.Lines[ALine];
  mTokens := TPascalLexer.Tokenize(mText);
  Result := (Length(mTokens) > 1) and (mTokens[0].IsKeyword('procedure') or mTokens[0].IsKeyword('function')) and
    TChangeSignature.ReadHeader(mText, mTokens, 1, AHeader);
end;

/// <summary>Grund, warum die Argumente von /testcase nicht taugen; leer, wenn AValues gefüllt ist.</summary>
function TestCaseValuesProblem(const AArguments: string; out AValues: TArray<string>): string;
begin
  AValues := nil;
  Result := '';
  if Trim(AArguments) = '' then
  begin
    Result := cTexts[TTestCommandsText.TestCaseNeedsValues].Text;
  end
  else if not TTestCommandTexts.SplitValues(AArguments, AValues) then
  begin
    Result := cTexts[TTestCommandsText.TestCaseOpenString].Text;
  end;
end;

function ExecuteTestCase(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mValues: TArray<string>;
  mMethodLine, mCases: Integer;
  mHeader: TSignatureHeader;
begin
  AEdits := nil;
  AReason := TestCaseValuesProblem(AContext.Arguments, mValues);
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClass) or (mClass.Range.StartPos.Line >= mSource.Line) then
    begin
      Exit(Fail(cTexts[TTestCommandsText.TestCasePlace].Text, AReason));
    end;
    mMethodLine := MethodLineBelow(mSource.Lines, mSource.Line, mCases);
    if (mMethodLine < 0) or not MethodHeaderAt(mSource, mMethodLine, mHeader) then
    begin
      Exit(Fail(cTexts[TTestCommandsText.NoTestMethodBelow].Text, AReason));
    end;
    if Length(mHeader.Parameters) <> Length(mValues) then
    begin
      Exit(Fail(cTexts[TTestCommandsText.TestCaseCount].Fmt([mHeader.QualifiedName, Length(mHeader.Parameters),
        Length(mValues)]), AReason));
    end;
    mCases := mCases + CasesAbove(mSource.Lines, mSource.Line) + 1;
    AEdits := [mSource.ReplaceWithIndentedLines([TTestCommandTexts.TestCaseAttribute(
      cTexts[TTestCommandsText.CaseName].Text + IntToStr(mCases), mValues)])];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /dump }

function ExecuteDump(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mLocal: TRoutineLocal;
  mFormats, mArguments: TArray<string>;
  mFormat, mArgument: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TTestCommandsText.DumpPlace].Text, AReason));
    end;
    mFormats := nil;
    mArguments := nil;
    for mLocal in TRoutineLocals.Collect(mSource.Text, mSource.Tree, mRoutine) do
    begin
      if (mLocal.Kind in [TRoutineLocalKind.Parameter, TRoutineLocalKind.Variable]) and
        TTestCommandTexts.DumpPart(mLocal.Name, Trim(mLocal.TypeText), mFormat, mArgument) then
      begin
        mFormats := mFormats + [mFormat];
        mArguments := mArguments + [mArgument];
      end;
    end;
    if Length(mFormats) = 0 then
    begin
      Exit(Fail(cTexts[TTestCommandsText.DumpNothing].Text, AReason));
    end;
    AEdits := [mSource.ReplaceWithIndentedLines([LogStatement(AContext, 'Format(' +
      QuotedStr(mRoutine.Name + ': ' + string.Join(', ', mFormats)) + ', [' + string.Join(', ', mArguments) + '])')])];
    AddUses(mSource, AContext, mSource.Line, ['System.SysUtils'], AEdits);
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /assert }

/// <summary>Ziel der Zuweisung in der Zeile vor ALine ("X := …;", "var X := …;", "var X: T := …;"); '' ohne.
/// </summary>
function AssignedName(const ALines: TArray<string>; ALine: Integer): string;
var
  mIndex: Integer;
  mText: string;
  mTokens: TArray<TPascalToken>;
begin
  Result := '';
  mIndex := ALine - 1;
  while (mIndex >= 0) and (Trim(ALines[mIndex]) = '') do
  begin
    Dec(mIndex);
  end;
  if mIndex < 0 then
  begin
    Exit;
  end;
  mText := Trim(ALines[mIndex]);
  mTokens := TPascalLexer.Tokenize(mText);
  if (Length(mTokens) > 1) and mTokens[0].IsKeyword('var') then
  begin
    mTokens := Copy(mTokens, 1, MaxInt);
  end;
  if (Length(mTokens) > 1) and (mTokens[0].Kind = TPascalTokenKind.Identifier) and
    (mTokens[1].IsSymbol(':=') or mTokens[1].IsSymbol(':')) then
  begin
    Result := mTokens[0].Text;
  end;
end;

/// <summary>Ist ATypeName eine Klasse aus der Unit oder dem Index?</summary>
function IsClassType(ASource: TCommandSource; const AContext: TSlashContext; const ATypeName: string): Boolean;
var
  mResolver: TNameResolver;
  mResolved: TResolvedSymbol;
begin
  mResolver := TNameResolver.Create(AContext.Index);
  try
    mResolver.Namespaces := AContext.Namespaces;
    Result := mResolver.ResolveNameFrom(ASource.UnitIndex, ATypeName, mResolved) and
      (mResolved.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]);
  finally
    mResolver.Free;
  end;
end;

/// <summary>Typ der lokalen Variablen bzw. des Parameters AName; '' ohne.</summary>
function LocalType(ASource: TCommandSource; ARoutine: TSyntaxNode; const AName: string): string;
var
  mLocal: TRoutineLocal;
begin
  Result := '';
  for mLocal in TRoutineLocals.Collect(ASource.Text, ASource.Tree, ARoutine) do
  begin
    if SameText(mLocal.Name, AName) then
    begin
      Result := Trim(mLocal.TypeText);
    end;
  end;
end;

function ExecuteAssert(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mName, mType, mLine: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TTestCommandsText.AssertPlace].Text, AReason));
    end;
    mName := AssignedName(mSource.Lines, mSource.Line);
    if mName = '' then
    begin
      Exit(Fail(cTexts[TTestCommandsText.AssertNoVariable].Text, AReason));
    end;
    mType := LocalType(mSource, mRoutine, mName);
    if (mType = '') or not TTestCommandTexts.AssertLine(mName, mType, IsClassType(mSource, AContext, mType),
      TUsesClauses.IsTestUnit(mSource.Tree.Tokens), mLine) then
    begin
      Exit(Fail(cTexts[TTestCommandsText.AssertNoType].Fmt([mName]), AReason));
    end;
    AEdits := [mSource.ReplaceWithIndentedLines([mLine])];
    Result := True;
  finally
    mSource.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterTestCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('mock', cTexts[TTestCommandsText.MockSummary].Text, '/mock IKundenRepo', ExecuteMock));
  ARegister(Command('testcase', cTexts[TTestCommandsText.TestCaseSummary].Text, '/testcase ''a'', 2, True',
    ExecuteTestCase));
  ARegister(Command('dump', cTexts[TTestCommandsText.DumpSummary].Text, '/dump', ExecuteDump));
  ARegister(Command('assert', cTexts[TTestCommandsText.AssertSummary].Text, '/assert', ExecuteAssert));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TestCommands', cTexts);

end.
