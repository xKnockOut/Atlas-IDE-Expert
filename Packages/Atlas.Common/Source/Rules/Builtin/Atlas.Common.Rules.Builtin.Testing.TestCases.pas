unit Atlas.Common.Rules.Builtin.Testing.TestCases;

// Regel aus Atlas.Common.Rules.Builtin.Testing (#1882); angemeldet wird sie dort:
//   dunitx-testcase-mismatch  [TestCase] passt nicht zur Methode: Die Zahl der Werte weicht von der Zahl der
//                             Parameter ab (DUnitX ruft über RTTI auf, Vorgabewerte zählen nicht), ein Wert passt
//                             nicht zum Typ seines Parameters, oder die Methode hat gar keine Parameter. DUnitX
//                             meldet das erst beim Lauf. Nur in Testunits (uses DUnitX.TestFramework …).
//
// Werte wie DUnitX: Der Werte-Text wird an jedem Zeichen des Trennzeichens geteilt (System.StrUtils.SplitString,
// Vorgabe Komma, keine Anführungszeichen), ein leerer Text ergibt keinen Wert. Typen: Ganzzahlen dezimal oder hex
// ($FF, 0xFF), Gleitkomma mit Punkt (DUnitX macht aus Komma einen Punkt), Boolean als True/False, Aufzählungen der
// Datei über ihre Namen; andere Typen (string, Datum, Typen anderer Units) prüft die Regel nicht.
// Formen: TestCase('Name', 'Werte'[, 'Trenner'[, Trim]]) wie bisher, TestCase('Werte'[, 'Trenner'[, Trim]]) und
// NamedTestCase('Name', 'Werte'[, …]) aus neueren DUnitX-Ständen. Mit zwei oder mehr Argumenten gilt die alte Form,
// außer das zweite ist ein Trennzeichen ohne Buchstaben und Ziffern oder das dritte True/False.
// TDUnitXTestCases ist öffentlich: Die TestCase-Tabelle (#1879) liest die Werte auf dieselbe Weise.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract;

const
  cDUnitXTestCaseMismatchRuleId = 'dunitx-testcase-mismatch';

type
  /// <summary>Ein [TestCase]-Eintrag mit seinen Werten.</summary>
  TDUnitXTestCase = record
    /// <summary>Der Attribut-Eintrag (Call-Knoten).</summary>
    Item: TSyntaxNode;
    /// <summary>Name des Falls; '' bei TestCase('Werte').</summary>
    CaseName: string;
    Values: TArray<string>;
    Separator: string;
  end;

  /// <summary>Ein Parameter einer Testmethode.</summary>
  TDUnitXParameter = record
    Name: string;
    /// <summary>Typ wie geschrieben; '' ohne Typ.</summary>
    TypeName: string;
  end;

  /// <summary>Art eines Parametertyps für die Prüfung der Werte.</summary>
{$SCOPEDENUMS ON}
  TDUnitXValueKind = (Unknown, Text, Integer_, Float, Boolean_, Enum);
{$SCOPEDENUMS OFF}

  TDUnitXTestCases = class
  public
    /// <summary>Liest einen Eintrag TestCase(…)/NamedTestCase(…); False, wenn er keiner ist oder Werte bzw.
    /// Trennzeichen keine Literale sind.</summary>
    class function Read(AItem: TSyntaxNode; out ACase: TDUnitXTestCase): Boolean; static;
    /// <summary>Wert eines String-Literals wie im Quelltext ('it''s', 'a'#9'b'); False bei anderem.</summary>
    class function Decode(const ALiteral: string; out AValue: string): Boolean; static;
    /// <summary>Teilt wie System.StrUtils.SplitString: jedes Zeichen von ASeparators trennt.</summary>
    class function Split(const AText, ASeparators: string): TArray<string>; static;
    /// <summary>Parameter einer Methode in Reihenfolge ('A, B: Integer' → zwei).</summary>
    class function Parameters(AHeader: TSyntaxNode): TArray<TDUnitXParameter>; static;
    /// <summary>Art des Typs ATypeName; Aufzählungen über AEnums (Typname=Name1,Name2 …).</summary>
    class function KindOf(const ATypeName: string; const AEnums: TArray<string>): TDUnitXValueKind; static;
    /// <summary>Passt AValue zur Art AKind? Für Enum nennt AEnumNames die Namen ("Rot,Gruen").</summary>
    class function Fits(const AValue: string; AKind: TDUnitXValueKind; const AEnumNames: string): Boolean; static;
    /// <summary>Aufzählungen der Datei als "Typ=Name1,Name2"; ohne Aufzählungen mit festen Werten.</summary>
    class function Enums(ARoot: TSyntaxNode): TArray<string>; static;
    /// <summary>Namen der Aufzählung ATypeName aus AEnums; '' wenn unbekannt.</summary>
    class function EnumNames(const ATypeName: string; const AEnums: TArray<string>): string; static;
  end;

  TDUnitXTestCaseMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Builtin.Testing.Classes,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTestCaseText = (Title, CountMismatch, NoParameters, ValueMismatch, ValueMismatchEnum);

const
  cTexts: array[TTestCaseText] of TAtlasText = (
    (De: 'TestCase passt nicht zur Methode'; En: 'TestCase does not match the method'),
    (De: '%s hat %d Werte, %s erwartet %d Parameter.'; En: '%s has %d values, %s expects %d parameters.'),
    (De: '%s an %s, die keine Parameter hat: DUnitX kann die Werte nicht übergeben.';
     En: '%s on %s, which has no parameters: DUnitX cannot pass the values.'),
    (De: 'Wert ''%s'' passt nicht zu Parameter %s: %s.'; En: 'Value ''%s'' does not fit parameter %s: %s.'),
    (De: 'Wert ''%s'' passt nicht zu Parameter %s: %s (erlaubt: %s).';
     En: 'Value ''%s'' does not fit parameter %s: %s (allowed: %s).'));

{$SCOPEDENUMS OFF}

const
  cIntegerTypes: array[0..21] of string = ('Integer', 'Cardinal', 'LongInt', 'LongWord', 'SmallInt', 'ShortInt',
    'Word', 'Byte', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Int8', 'Int16', 'Int32', 'UInt8', 'UInt16',
    'UInt32', 'FixedInt', 'FixedUInt', 'DWORD', 'QWord');
  cFloatTypes: array[0..4] of string = ('Single', 'Double', 'Extended', 'Real', 'Currency');
  cTextTypes: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'UTF8String');

{ TDUnitXTestCases }

/// <summary>Liest ab AIndex (auf dem öffnenden Hochkomma) einen Abschnitt 'text' samt '' an AValue an.</summary>
function ReadQuoted(const ALiteral: string; var AIndex: Integer; var AValue: string): Boolean;
begin
  Inc(AIndex);
  while AIndex <= Length(ALiteral) do
  begin
    if ALiteral[AIndex] <> '''' then
    begin
      AValue := AValue + ALiteral[AIndex];
      Inc(AIndex);
    end
    else if (AIndex < Length(ALiteral)) and (ALiteral[AIndex + 1] = '''') then
    begin
      AValue := AValue + '''';
      Inc(AIndex, 2);
    end
    else
    begin
      Inc(AIndex);
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Liest ab AIndex (auf #) ein Zeichen #9 bzw. #$41 an AValue an.</summary>
function ReadCharCode(const ALiteral: string; var AIndex: Integer; var AValue: string): Boolean;
var
  mDigits: string;
  mCode: Integer;
begin
  Inc(AIndex);
  mDigits := '';
  while (AIndex <= Length(ALiteral)) and CharInSet(ALiteral[AIndex], ['0'..'9', '$', 'a'..'f', 'A'..'F']) do
  begin
    mDigits := mDigits + ALiteral[AIndex];
    Inc(AIndex);
  end;
  mCode := StrToIntDef(mDigits, -1);
  Result := (mCode >= 0) and (mCode <= $FFFF);
  if Result then
  begin
    AValue := AValue + Char(mCode);
  end;
end;

class function TDUnitXTestCases.Decode(const ALiteral: string; out AValue: string): Boolean;
var
  mIndex: Integer;
begin
  AValue := '';
  Result := ALiteral <> '';
  mIndex := 1;
  while Result and (mIndex <= Length(ALiteral)) do
  begin
    case ALiteral[mIndex] of
      '''':
        Result := ReadQuoted(ALiteral, mIndex, AValue);
      '#':
        Result := ReadCharCode(ALiteral, mIndex, AValue);
    else
      Result := False;
    end;
  end;
end;

class function TDUnitXTestCases.Split(const AText, ASeparators: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  if AText = '' then
  begin
    Exit;
  end;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if Pos(AText[mIndex], ASeparators) > 0 then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  Result := Result + [Copy(AText, mStart, MaxInt)];
end;

/// <summary>Trennzeichen der neuen Form: nicht leer, ohne Buchstaben und Ziffern.</summary>
function LooksLikeSeparator(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    if CharInSet(mChar, ['0'..'9', 'A'..'Z', 'a'..'z']) or (mChar > #127) then
    begin
      Exit(False);
    end;
  end;
end;

function IsBooleanLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and MatchText(ANode.Name, ['True', 'False']);
end;

/// <summary>Text eines String-Literals; False bei Konstanten und Ausdrücken.</summary>
function LiteralText(ANode: TSyntaxNode; out AText: string): Boolean;
begin
  AText := '';
  Result := (ANode.Kind = TSyntaxKind.Literal) and TDUnitXTestCases.Decode(ANode.Name, AText);
end;

/// <summary>Stelle des Werte-Arguments: 0 bei der neuen Form TestCase('Werte'[, 'Trenner'[, Trim]]) (ein
/// Argument, ein Trennzeichen an zweiter Stelle oder True/False an dritter), sonst 1.</summary>
function ValuesIndex(const AName: string; const AArgs: TArray<TSyntaxNode>): Integer;
var
  mSecond: string;
begin
  Result := 1;
  if Length(AArgs) = 1 then
  begin
    Result := 0;
  end
  else if not SameText(AName, 'TestCase') then
  begin
    Result := 1;
  end
  else if (Length(AArgs) = 3) and IsBooleanLiteral(AArgs[2]) then
  begin
    Result := 0;
  end
  else if LiteralText(AArgs[1], mSecond) and LooksLikeSeparator(mSecond) then
  begin
    Result := 0;
  end;
end;

class function TDUnitXTestCases.Read(AItem: TSyntaxNode; out ACase: TDUnitXTestCase): Boolean;
var
  mName, mText: string;
  mArgs: TArray<TSyntaxNode>;
  mValuesAt: Integer;
begin
  ACase := Default(TDUnitXTestCase);
  ACase.Item := AItem;
  ACase.Separator := ',';
  mName := TDUnitXClasses.ItemName(AItem);
  mArgs := TDUnitXClasses.Arguments(AItem);
  if not MatchText(mName, ['TestCase', 'NamedTestCase']) or (Length(mArgs) = 0) or
    (SameText(mName, 'NamedTestCase') and (Length(mArgs) < 2)) then
  begin
    Exit(False);
  end;
  mValuesAt := ValuesIndex(mName, mArgs);
  if (mValuesAt = 1) and not LiteralText(mArgs[0], ACase.CaseName) then
  begin
    ACase.CaseName := '';
  end;
  Result := LiteralText(mArgs[mValuesAt], mText) and
    ((Length(mArgs) <= mValuesAt + 1) or LiteralText(mArgs[mValuesAt + 1], ACase.Separator));
  if Result then
  begin
    ACase.Values := Split(mText, ACase.Separator);
  end;
end;

class function TDUnitXTestCases.Parameters(AHeader: TSyntaxNode): TArray<TDUnitXParameter>;
var
  mParams, mParam, mType: TSyntaxNode;
  mIndex: Integer;
  mName: string;
  mEntry: TDUnitXParameter;
begin
  Result := nil;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    mParam := mParams[mIndex];
    if mParam.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    mType := mParam.FindChild(TSyntaxKind.TypeReference);
    mEntry.TypeName := '';
    if mType <> nil then
    begin
      mEntry.TypeName := mType.Name;
    end;
    for mName in mParam.Name.Split([',']) do
    begin
      mEntry.Name := Trim(mName);
      Result := Result + [mEntry];
    end;
  end;
end;

/// <summary>Name ohne Unit davor (System.Integer → Integer).</summary>
function BareName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

class function TDUnitXTestCases.EnumNames(const ATypeName: string; const AEnums: TArray<string>): string;
var
  mEntry: string;
begin
  for mEntry in AEnums do
  begin
    if SameText(Copy(mEntry, 1, Pos('=', mEntry) - 1), BareName(ATypeName)) then
    begin
      Exit(Copy(mEntry, Pos('=', mEntry) + 1, MaxInt));
    end;
  end;
  Result := '';
end;

class function TDUnitXTestCases.KindOf(const ATypeName: string; const AEnums: TArray<string>): TDUnitXValueKind;
var
  mName: string;
begin
  mName := BareName(ATypeName);
  if mName = '' then
  begin
    Result := TDUnitXValueKind.Unknown;
  end
  else if MatchText(mName, cIntegerTypes) then
  begin
    Result := TDUnitXValueKind.Integer_;
  end
  else if MatchText(mName, cFloatTypes) then
  begin
    Result := TDUnitXValueKind.Float;
  end
  else if SameText(mName, 'Boolean') then
  begin
    Result := TDUnitXValueKind.Boolean_;
  end
  else if MatchText(mName, cTextTypes) then
  begin
    Result := TDUnitXValueKind.Text;
  end
  else if EnumNames(mName, AEnums) <> '' then
  begin
    Result := TDUnitXValueKind.Enum;
  end
  else
  begin
    Result := TDUnitXValueKind.Unknown;
  end;
end;

/// <summary>Ganzzahl wie StrToInt64: Vorzeichen, dezimal oder hex ($FF, 0xFF, xFF).</summary>
function IsIntegerText(const AText: string): Boolean;
var
  mText: string;
  mHex: Boolean;
  mChar: Char;
begin
  mText := Trim(AText);
  if (mText <> '') and CharInSet(mText[1], ['+', '-']) then
  begin
    mText := Copy(mText, 2, MaxInt);
  end;
  mHex := False;
  if StartsText('0x', mText) then
  begin
    mText := Copy(mText, 3, MaxInt);
    mHex := True;
  end
  else if (mText <> '') and CharInSet(mText[1], ['$', 'x', 'X']) then
  begin
    mText := Copy(mText, 2, MaxInt);
    mHex := True;
  end;
  Result := mText <> '';
  for mChar in mText do
  begin
    if not (CharInSet(mChar, ['0'..'9']) or (mHex and CharInSet(mChar, ['a'..'f', 'A'..'F']))) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Überspringt Ziffern ab AIndex; Ergebnis ist ihre Zahl.</summary>
function SkipDigits(const AText: string; var AIndex: Integer): Integer;
begin
  Result := 0;
  while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['0'..'9']) do
  begin
    Inc(AIndex);
    Inc(Result);
  end;
end;

/// <summary>Überspringt ein Vorzeichen an AIndex.</summary>
procedure SkipSign(const AText: string; var AIndex: Integer);
begin
  if (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['+', '-']) then
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Gleitkommazahl mit Punkt oder Komma als Dezimaltrenner, optional mit Exponent.</summary>
function IsFloatText(const AText: string): Boolean;
var
  mText: string;
  mIndex, mDigits: Integer;
begin
  mText := StringReplace(Trim(AText), ',', '.', [rfReplaceAll]);
  mIndex := 1;
  SkipSign(mText, mIndex);
  mDigits := SkipDigits(mText, mIndex);
  if (mIndex <= Length(mText)) and (mText[mIndex] = '.') then
  begin
    Inc(mIndex);
    Inc(mDigits, SkipDigits(mText, mIndex));
  end;
  Result := mDigits > 0;
  if Result and (mIndex <= Length(mText)) and CharInSet(mText[mIndex], ['e', 'E']) then
  begin
    Inc(mIndex);
    SkipSign(mText, mIndex);
    Result := SkipDigits(mText, mIndex) > 0;
  end;
  Result := Result and (mIndex > Length(mText));
end;

class function TDUnitXTestCases.Fits(const AValue: string; AKind: TDUnitXValueKind; const AEnumNames: string): Boolean;
begin
  case AKind of
    TDUnitXValueKind.Integer_:
      Result := IsIntegerText(AValue);
    TDUnitXValueKind.Float:
      Result := IsFloatText(AValue);
    TDUnitXValueKind.Boolean_:
      Result := MatchText(Trim(AValue), ['True', 'False']);
    TDUnitXValueKind.Enum:
      Result := MatchText(Trim(AValue), AEnumNames.Split([',']));
  else
    Result := True;
  end;
end;

class function TDUnitXTestCases.Enums(ARoot: TSyntaxNode): TArray<string>;
var
  mPending: TStack<TSyntaxNode>;
  mNode, mEnum: TSyntaxNode;
  mIndex: Integer;
  mNames: string;
  mPlain: Boolean;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      mEnum := nil;
      if mNode.Kind = TSyntaxKind.TypeDecl then
      begin
        mEnum := mNode.FindChild(TSyntaxKind.EnumType);
      end;
      if mEnum <> nil then
      begin
        // Aufzählungen mit festen Werten (A = 1) haben keine RTTI; DUnitX kann sie nicht umwandeln.
        mNames := '';
        mPlain := mEnum.ChildCount > 0;
        for mIndex := 0 to mEnum.ChildCount - 1 do
        begin
          mPlain := mPlain and (mEnum[mIndex].Kind = TSyntaxKind.Identifier);
          mNames := mNames + IfThen(mIndex > 0, ',') + mEnum[mIndex].Name;
        end;
        if mPlain then
        begin
          Result := Result + [mNode.Name + '=' + mNames];
        end;
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

{ TDUnitXTestCaseMismatchRule }

function TDUnitXTestCaseMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDUnitXTestCaseMismatchRuleId, TRuleSeverity.Warning,
    cTexts[TTestCaseText.Title].Text);
end;

procedure TDUnitXTestCaseMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEnums: TArray<string>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := '[' + Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset) + ']';
  end;

  function Range(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  procedure CheckValues(const ACase: TDUnitXTestCase; const AParams: TArray<TDUnitXParameter>);
  var
    mIndex: Integer;
    mKind: TDUnitXValueKind;
    mNames: string;
  begin
    for mIndex := 0 to High(AParams) do
    begin
      mNames := TDUnitXTestCases.EnumNames(AParams[mIndex].TypeName, mEnums);
      mKind := TDUnitXTestCases.KindOf(AParams[mIndex].TypeName, mEnums);
      if TDUnitXTestCases.Fits(ACase.Values[mIndex], mKind, mNames) then
      begin
        Continue;
      end;
      if mKind = TDUnitXValueKind.Enum then
      begin
        AReport.Add(Range(ACase.Item), cTexts[TTestCaseText.ValueMismatchEnum].Fmt([ACase.Values[mIndex],
          AParams[mIndex].Name, AParams[mIndex].TypeName, StringReplace(mNames, ',', ', ', [rfReplaceAll])]),
          TRuleConfidence.High, []);
      end
      else
      begin
        AReport.Add(Range(ACase.Item), cTexts[TTestCaseText.ValueMismatch].Fmt([ACase.Values[mIndex],
          AParams[mIndex].Name, AParams[mIndex].TypeName]), TRuleConfidence.High, []);
      end;
    end;
  end;

  procedure CheckMember(const AMember: TDUnitXMember);
  var
    mItem: TSyntaxNode;
    mCase: TDUnitXTestCase;
    mParams: TArray<TDUnitXParameter>;
  begin
    mParams := TDUnitXTestCases.Parameters(AMember.Node);
    for mItem in AMember.Attributes do
    begin
      if not TDUnitXTestCases.Read(mItem, mCase) then
      begin
        Continue;
      end;
      if mParams = nil then
      begin
        AReport.Add(Range(mItem), cTexts[TTestCaseText.NoParameters].Fmt([NodeText(mItem), AMember.Node.Name]),
          TRuleConfidence.High, []);
      end
      else if Length(mCase.Values) <> Length(mParams) then
      begin
        AReport.Add(Range(mItem), cTexts[TTestCaseText.CountMismatch].Fmt([NodeText(mItem), Length(mCase.Values),
          AMember.Node.Name, Length(mParams)]), TRuleConfidence.High, []);
      end
      else
      begin
        CheckValues(mCase, mParams);
      end;
    end;
  end;

var
  mClass: TDUnitXClass;
  mMember: TDUnitXMember;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'TestCase') or
    not TUsesClauses.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mEnums := TDUnitXTestCases.Enums(AContext.Tree.Root);
  for mClass in TDUnitXClasses.Collect(AContext.Tree.Root) do
  begin
    for mMember in mClass.Members do
    begin
      if mMember.Node.Kind = TSyntaxKind.RoutineHeader then
      begin
        CheckMember(mMember);
      end;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.TestCases', cTexts);

end.
