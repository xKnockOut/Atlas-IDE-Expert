unit Atlas.Common.Rules.Builtin.RtlTypePatterns;

// Regeln für fehleranfällige RTL-Muster, Stufe 2 aus #153 (mit deklarierten
// Typen aus der Datei, Atlas.Common.Pascal.DeclaredTypes):
//   int32-mul-overflow       Int64 := Int32 * Int32 läuft vor der Zuweisung über
//   sizeof-pointer           Move/FillChar mit SizeOf eines Zeigers, Strings oder dynamischen Arrays
//   char-to-pchar            Cast eines Char nach PChar
//   float-equality           Gleitkommavergleich mit = oder <> (nicht mit 0, nicht in Equals-Vergleichern)
//   constructor-on-instance  Konstruktor auf einer Variablen statt auf der Klasse
//   writeln-in-gui-app       Write, Writeln, Read oder Readln auf die Standardein- oder -ausgabe in einem
//                            Programm ohne Konsole (#926): E/A-Fehler 104 bzw. 105 zur Laufzeit
// Bezeichner, deren Typ in der Datei nicht deklariert ist, lösen keinen Treffer aus.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TInt32MulOverflowRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSizeOfPointerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCharToPCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFloatEqualityRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TConstructorOnInstanceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TWritelnInGuiAppRule = class(TInterfacedObject, IRule)
  public const
    cDefaultReplacement = 'OutputDebugString';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Anwendungsart aus DCC_ConsoleTarget der .dproj und dem Text der .dpr: Console bei
    /// "true" oder {$APPTYPE CONSOLE}, Service bei einem program mit Vcl.SvcMgr und ohne Vcl.Forms,
    /// sonst Gui bei einem program; Library_ bei einer library ohne Formulare und ohne Vcl.Forms,
    /// Package bei einem package, sonst Unknown (DLL mit Formularen, kein Text).</summary>
    class function ApplicationKind(const AConsoleTarget, AMainSource: string): TRuleApplicationKind; static;
    /// <summary>Option "replacement" aus den Regeloptionen; ohne Angabe OutputDebugString.</summary>
    class function Replacement(const AOptions: string): string; static;
  end;

/// <summary>Registriert die typbasierten Regeln für RTL-Muster.</summary>
procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Memory,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Collections,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Conversions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRtlTypePatternsText = (OverflowTitle, Overflow, CastOperand, SizeOfTitle, SizeOfPointer, CharTitle, CharToPChar,
    FloatTitle, FloatEqual, UseSameValue, CtorTitle, CtorOnInstance, WritelnTitle, ReplaceWith, NoConsoleWrite,
    NoConsoleRead, UseCreate);

const
  cTexts: array[TRtlTypePatternsText] of TAtlasText = (
    (De: 'Int32-Multiplikation läuft vor der Zuweisung an Int64 über';
     En: 'Int32 multiplication overflows before the assignment to Int64'),
    (De: '%s * %s wird in 32 Bit gerechnet und läuft über, bevor das Ergebnis in %s (Int64) landet';
     En: '%s * %s is computed in 32 bits and overflows before the result lands in %s (Int64)'),
    (De: 'Operand nach Int64 umwandeln'; En: 'Convert operand to Int64'),
    (De: 'Move/FillChar mit SizeOf eines Zeigers statt der Daten';
     En: 'Move/FillChar with SizeOf of a pointer instead of the data'),
    (De: 'SizeOf(%s) ist die Größe des Zeigers (%s), nicht die der Daten; Length(…) * SizeOf(Element) verwenden';
     En: 'SizeOf(%s) is the size of the pointer (%s), not of the data; use Length(…) * SizeOf(Element)'),
    (De: 'Char wird nach PChar umgewandelt'; En: 'Char is converted to PChar'),
    (De: '%s(%s) macht aus dem Zeichen eine Adresse; gemeint ist meist ein String: %s(string(%s))';
     En: '%s(%s) turns the character into an address; usually a string is meant: %s(string(%s))'),
    (De: 'Gleitkommavergleich mit = oder <>'; En: 'Floating-point comparison with = or <>'),
    (De: 'Gleitkommawerte sind selten exakt gleich; SameValue aus System.Math mit Toleranz verwenden';
     En: 'Floating-point values are rarely exactly equal; use SameValue from System.Math with a tolerance'),
    (De: 'SameValue verwenden'; En: 'Use SameValue'),
    (De: 'Konstruktor auf einer Instanz statt auf der Klasse'; En: 'Constructor on an instance instead of the class'),
    (De: 'Create auf der Variablen %s statt auf der Klasse %s; das legt kein neues Objekt an';
     En: 'Create on the variable %s instead of the class %s; this creates no new object'),
    (De: 'Writeln in einem Programm ohne Konsole'; En: 'Writeln in a program without console'),
    (De: 'Durch %s ersetzen'; En: 'Replace with %s'),
    (De: 'Das Projekt hat keine Konsole; %s löst zur Laufzeit E/A-Fehler 104 aus.';
     En: 'The project has no console; %s raises I/O error 104 at run time.'),
    (De: 'Das Projekt hat keine Konsole; %s löst zur Laufzeit E/A-Fehler 105 aus.';
     En: 'The project has no console; %s raises I/O error 105 at run time.'),
    (De: '%s.Create verwenden'; En: 'Use %s.Create'));

{$SCOPEDENUMS OFF}

{ TInt32MulOverflowRule }

function TInt32MulOverflowRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('int32-mul-overflow', TRuleSeverity.Warning,
    cTexts[TRtlTypePatternsText.OverflowTitle].Text);
end;

type
  /// <summary>Zuweisung V := A * B mit einfachen Operanden (B auch eine Zahl) als ganze Anweisung.</summary>
  TMulAssignment = record
    Target, Left, Right: Integer;
    /// <summary>Steht bei AAssign (":=") eine solche Zuweisung?</summary>
    function Matches(const ATokens: TTokens; AAssign: Integer): Boolean;
    /// <summary>Ist das Ziel Int64 und sind beide Operanden höchstens 32 Bit breit?</summary>
    function Overflows(ATypes: TDeclaredTypes; const ATokens: TTokens): Boolean;
  end;

/// <summary>Beendet ATokens[AIndex] eine Anweisung (";", end, else)?</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or AToken.IsKeyword('end') or AToken.IsKeyword('else');
end;

/// <summary>Einfacher Bezeichner oder Zahl?</summary>
function IsSimpleOperand(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  Result := IsPlainIdentifier(ATokens, AIndex) or (ATokens[AIndex].Kind = TPascalTokenKind.Number);
end;

function TMulAssignment.Matches(const ATokens: TTokens; AAssign: Integer): Boolean;
var
  mTimes, mStop: Integer;
begin
  Target := PreviousCode(ATokens, AAssign);
  Left := NextCode(ATokens, AAssign + 1);
  mTimes := NextCode(ATokens, Left + 1);
  Right := NextCode(ATokens, mTimes + 1);
  mStop := NextCode(ATokens, Right + 1);
  Result := (mStop <= High(ATokens)) and ATokens[mTimes].IsSymbol('*') and EndsStatement(ATokens[mStop]);
  Result := Result and IsPlainIdentifier(ATokens, Target) and IsPlainIdentifier(ATokens, Left) and
    IsSimpleOperand(ATokens, Right);
end;

function TMulAssignment.Overflows(ATypes: TDeclaredTypes; const ATokens: TTokens): Boolean;
begin
  Result := TDeclaredTypes.IsInt64(DeclaredTypeAt(ATypes, ATokens, Target)) and
    TDeclaredTypes.IsInt32(DeclaredTypeAt(ATypes, ATokens, Left)) and
    ((ATokens[Right].Kind = TPascalTokenKind.Number) or TDeclaredTypes.IsInt32(DeclaredTypeAt(ATypes, ATokens, Right)));
end;

procedure TInt32MulOverflowRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex: Integer;
  mMul: TMulAssignment;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      // V := A * B; mit V: Int64 und A, B höchstens 32 Bit.
      if mTokens[mIndex].IsSymbol(':=') and mMul.Matches(mTokens, mIndex) and mMul.Overflows(mTypes, mTokens) then
      begin
        AReport.Add(RangeOf(mTokens, mMul.Left, mMul.Right),
          cTexts[TRtlTypePatternsText.Overflow].Fmt([mTokens[mMul.Left].Text, mTokens[mMul.Right].Text,
          mTokens[mMul.Target].Text]), TRuleConfidence.High,
            [TRuleFix.Create(cTexts[TRtlTypePatternsText.CastOperand].Text,
          [TRuleEdit.Create(RangeOf(mTokens, mMul.Left, mMul.Left), 'Int64(' + mTokens[mMul.Left].Text + ')')], True)]);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TSizeOfPointerRule }

function TSizeOfPointerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('sizeof-pointer', TRuleSeverity.Error,
    cTexts[TRtlTypePatternsText.SizeOfTitle].Text);
end;

/// <summary>Aufruf einer der Routinen ANames bei AIndex mit "(" bei AOpen?</summary>
function IsCallOf(const ATokens: TTokens; AIndex: Integer; const ANames: array of string; out AOpen: Integer): Boolean;
begin
  AOpen := NextCode(ATokens, AIndex + 1);
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and MatchText(ATokens[AIndex].Text, ANames) and
    (AOpen <= High(ATokens)) and ATokens[AOpen].IsSymbol('(');
end;

/// <summary>SizeOf(Name) bei AIndex vor AStop; AName ist der Bezeichner, AClose die schließende Klammer.</summary>
function IsSizeOfName(const ATokens: TTokens; AIndex, AStop: Integer; out AName, AClose: Integer): Boolean;
var
  mOpen: Integer;
begin
  mOpen := NextCode(ATokens, AIndex + 1);
  AName := NextCode(ATokens, mOpen + 1);
  AClose := NextCode(ATokens, AName + 1);
  Result := SameText(ATokens[AIndex].Text, 'SizeOf') and (AClose < AStop) and ATokens[mOpen].IsSymbol('(') and
    ATokens[AClose].IsSymbol(')') and (ATokens[AName].Kind = TPascalTokenKind.Identifier);
end;

/// <summary>Meldet jedes SizeOf eines Zeigers, Strings oder dynamischen Arrays zwischen AOpen und AClose.</summary>
procedure ReportPointerSizes(ATypes: TDeclaredTypes; const ATokens: TTokens; AOpen, AClose: Integer;
  const AReport: IRuleReport);
var
  mInner, mName, mSizeClose: Integer;
  mTypeName: string;
begin
  for mInner := AOpen + 1 to AClose - 1 do
  begin
    if not IsSizeOfName(ATokens, mInner, AClose, mName, mSizeClose) then
    begin
      Continue;
    end;
    mTypeName := DeclaredTypeAt(ATypes, ATokens, mName);
    if (mTypeName <> '') and TDeclaredTypes.IsReference(mTypeName) then
    begin
      AReport.Add(RangeOf(ATokens, mInner, mSizeClose),
        cTexts[TRtlTypePatternsText.SizeOfPointer].Fmt([ATokens[mName].Text, mTypeName]),
        TRuleConfidence.High);
    end;
  end;
end;

procedure TSizeOfPointerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex, mOpen: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      if IsCallOf(mTokens, mIndex, ['Move', 'FillChar', 'ZeroMemory', 'CopyMemory', 'FillMemory'], mOpen) then
      begin
        ReportPointerSizes(mTypes, mTokens, mOpen, MatchingParen(mTokens, mOpen), AReport);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TCharToPCharRule }

function TCharToPCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('char-to-pchar', TRuleSeverity.Error, cTexts[TRtlTypePatternsText.CharTitle].Text);
end;

procedure TCharToPCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex, mOpen, mName, mClose: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      if not ((mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
        MatchText(mTokens[mIndex].Text, ['PChar', 'PWideChar', 'PAnsiChar'])) then
      begin
        Continue;
      end;
      mOpen := NextCode(mTokens, mIndex + 1);
      mName := NextCode(mTokens, mOpen + 1);
      mClose := NextCode(mTokens, mName + 1);
      if (mClose > High(mTokens)) or not mTokens[mOpen].IsSymbol('(') or not mTokens[mClose].IsSymbol(')') or
        (mTokens[mName].Kind <> TPascalTokenKind.Identifier) then
      begin
        Continue;
      end;
      if TDeclaredTypes.IsChar(mTypes.DeclaredType(mTokens[mName].Text, mTokens[mName].StartPos)) then
      begin
        AReport.Add(RangeOf(mTokens, mIndex, mClose),
          cTexts[TRtlTypePatternsText.CharToPChar].Fmt([mTokens[mIndex].Text,
          mTokens[mName].Text,
          mTokens[mIndex].Text, mTokens[mName].Text]), TRuleConfidence.High);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TFloatEqualityRule }

function TFloatEqualityRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('float-equality', TRuleSeverity.Hint, cTexts[TRtlTypePatternsText.FloatTitle].Text);
end;

function IsZero(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Number) and MatchStr(AToken.Text, ['0', '0.0', '0.00']);
end;

/// <summary>Gleitkommatyp, für den ein exakter Vergleich verdächtig ist. Datum und Uhrzeit nicht: Zeitstempel
/// (z. B. Dateizeiten) werden absichtlich exakt verglichen (#647).</summary>
function IsInexact(const AType: string): Boolean;
begin
  Result := TDeclaredTypes.IsFloat(AType) and not MatchText(AType, ['TDateTime', 'TDate', 'TTime']);
end;

/// <summary>Beginnt bei AToken eine Routine (procedure, function, constructor, destructor)?</summary>
function IsRoutineStart(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('procedure') or AToken.IsKeyword('function') or AToken.IsKeyword('constructor') or
    AToken.IsKeyword('destructor');
end;

/// <summary>Steht bei AIndex "Name := Max(" bzw. "Min("?</summary>
function IsMinMaxAssignment(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  mAssign, mCall: Integer;
begin
  mAssign := NextCode(ATokens, AIndex + 1);
  mCall := NextCode(ATokens, mAssign + 1);
  Result := (mCall <= High(ATokens)) and ATokens[mAssign].IsSymbol(':=') and
    MatchText(ATokens[mCall].Text, ['Max', 'Min']);
end;

/// <summary>Nennt die Anweisung ab AFrom (bis zum ";") den Bezeichner AName?</summary>
function StatementNames(const ATokens: TTokens; AFrom: Integer; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := AFrom;
  while not Result and (mIndex <= High(ATokens)) and not ATokens[mIndex].IsSymbol(';') do
  begin
    Result := IsIdentifierNamed(ATokens[mIndex], AName);
    Inc(mIndex);
  end;
end;

/// <summary>Steht AName unter den Argumenten des Max- bzw. Min-Aufrufs der Zuweisung bei AIndex?</summary>
function MinMaxArgumentsName(const ATokens: TTokens; AIndex: Integer; const AName: string): Boolean;
var
  mOpen: Integer;
begin
  mOpen := NextCode(ATokens, NextCode(ATokens, NextCode(ATokens, AIndex + 1) + 1) + 1);
  Result := (mOpen <= High(ATokens)) and ATokens[mOpen].IsSymbol('(') and StatementNames(ATokens, mOpen + 1, AName);
end;

/// <summary>
/// Steht vor ATokens[AIndex] in derselben Routine "AName := Max(…)" bzw. Min(…) mit AOther unter den Argumenten?
/// Dann ist AName genau einer der Werte, und = AOther ist ein exakter Vergleich (MaxValue = R, #1109).
/// </summary>
function SelectedFrom(const ATokens: TTokens; AIndex: Integer; const AName, AOther: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := AIndex - 1;
  while (mIndex >= 0) and not IsRoutineStart(ATokens[mIndex]) do
  begin
    if IsIdentifierNamed(ATokens[mIndex], AName) and IsMinMaxAssignment(ATokens, mIndex) then
    begin
      // Die letzte Zuweisung zählt.
      Exit(MinMaxArgumentsName(ATokens, mIndex, AOther));
    end;
    Dec(mIndex);
  end;
  Result := False;
end;

/// <summary>Steht AOffset im Rumpf eines Gleichheitsvergleichers (Equals, Equals_Double, class operator Equal,
/// NotEqual, IsEqual)? Dort ist der exakte Vergleich Vertrag: Equals muss zu GetHashCode passen
/// (System.Generics.Defaults), eine Toleranz wäre nicht transitiv.</summary>
function InEqualityRoutine(ATree: TSyntaxTree; AOffset: Integer): Boolean;
var
  mRoutine: TSyntaxNode;
  mName: string;
begin
  mRoutine := TRoutineBody.RoutineAt(ATree, AOffset);
  if mRoutine = nil then
  begin
    Exit(False);
  end;
  mName := mRoutine.Name;
  if Pos('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  Result := StartsText('Equal', mName) or MatchText(mName, ['NotEqual', 'IsEqual']);
end;

/// <summary>Ist ATokens[AIndex] ein Rechenzeichen (+, -, *, /)? AIndex darf außerhalb liegen.</summary>
function IsArithmetic(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ATokens)) and (ATokens[AIndex].Kind = TPascalTokenKind.Symbol) and
    MatchStr(ATokens[AIndex].Text, ['+', '-', '*', '/']);
end;

/// <summary>Vergleich bei AIndex (= oder &lt;&gt;) mit beiden Operanden in der Datei: ALeft und ARight.</summary>
function IsComparison(const ATokens: TTokens; AIndex: Integer; out ALeft, ARight: Integer): Boolean;
begin
  ALeft := PreviousCode(ATokens, AIndex);
  ARight := NextCode(ATokens, AIndex + 1);
  Result := (ATokens[AIndex].IsSymbol('=') or ATokens[AIndex].IsSymbol('<>')) and (ALeft >= 0) and
    (ARight <= High(ATokens));
end;

/// <summary>Nur einfache Operanden: A = B, A &lt;&gt; 1.5; nicht Teil eines größeren Ausdrucks davor oder danach und
/// nicht mit 0.</summary>
function IsSimpleComparison(const ATokens: TTokens; ALeft, ARight: Integer): Boolean;
begin
  Result := IsSimpleOperand(ATokens, ALeft) and IsSimpleOperand(ATokens, ARight) and
    not IsArithmetic(ATokens, PreviousCode(ATokens, ALeft)) and
      not IsArithmetic(ATokens, NextCode(ATokens, ARight + 1));
  Result := Result and not IsZero(ATokens[ALeft]) and not IsZero(ATokens[ARight]);
end;

/// <summary>Bezeichner mit einem Gleitkommatyp, für den ein exakter Vergleich verdächtig ist?</summary>
function IsInexactOperand(ATypes: TDeclaredTypes; const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    IsInexact(DeclaredTypeAt(ATypes, ATokens, AIndex));
end;

/// <summary>Ist einer der Operanden ALeft, ARight ein solcher Gleitkommawert?</summary>
function IsInexactComparison(ATypes: TDeclaredTypes; const ATokens: TTokens; ALeft, ARight: Integer): Boolean;
begin
  Result := IsInexactOperand(ATypes, ATokens, ALeft) or IsInexactOperand(ATypes, ATokens, ARight);
end;

/// <summary>Ist der exakte Vergleich gewollt: ein Operand aus Max/Min des anderen oder im Gleichheitsvergleicher?
/// </summary>
function IsExactByDesign(ATree: TSyntaxTree; const ATokens: TTokens; AIndex, ALeft, ARight: Integer): Boolean;
begin
  Result := SelectedFrom(ATokens, AIndex, ATokens[ALeft].Text, ATokens[ARight].Text) or
    SelectedFrom(ATokens, AIndex, ATokens[ARight].Text, ATokens[ALeft].Text) or
    InEqualityRoutine(ATree, ATokens[AIndex].Offset);
end;

/// <summary>Meldet den Vergleich bei AIndex mit der Korrektur SameValue.</summary>
procedure ReportFloatEquality(const AReport: IRuleReport; const ATokens: TTokens; AIndex, ALeft, ARight: Integer);
var
  mCall: string;
begin
  mCall := 'SameValue(' + ATokens[ALeft].Text + ', ' + ATokens[ARight].Text + ')';
  if ATokens[AIndex].IsSymbol('<>') then
  begin
    mCall := 'not ' + mCall;
  end;
  AReport.Add(RangeOf(ATokens, ALeft, ARight), cTexts[TRtlTypePatternsText.FloatEqual].Text, TRuleConfidence.Medium,
    [TRuleFix.Create(cTexts[TRtlTypePatternsText.UseSameValue].Text, [TRuleEdit.Create(RangeOf(ATokens, ALeft, ARight),
      mCall)])]);
end;

procedure TFloatEqualityRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex, mLeft, mRight: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      if IsComparison(mTokens, mIndex, mLeft, mRight) and InStatements(AContext.Tree, mTokens[mIndex].StartPos) and
        IsSimpleComparison(mTokens, mLeft, mRight) and IsInexactComparison(mTypes, mTokens, mLeft, mRight) and
        not IsExactByDesign(AContext.Tree, mTokens, mIndex, mLeft, mRight) then
      begin
        ReportFloatEquality(AReport, mTokens, mIndex, mLeft, mRight);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TConstructorOnInstanceRule }

function TConstructorOnInstanceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('constructor-on-instance', TRuleSeverity.Warning,
    cTexts[TRtlTypePatternsText.CtorTitle].Text);
end;

/// <summary>Bezeichner bei AIndex gefolgt von ".Create", nicht selbst Teil einer Kette und nicht nach inherited;
/// ACtor ist dann Create.</summary>
function IsCreateOnName(const ATokens: TTokens; AIndex: Integer; out ACtor: Integer): Boolean;
var
  mPrev, mDot: Integer;
begin
  mPrev := PreviousCode(ATokens, AIndex);
  mDot := NextCode(ATokens, AIndex + 1);
  ACtor := NextCode(ATokens, mDot + 1);
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and (ACtor <= High(ATokens)) and
    ATokens[mDot].IsSymbol('.') and SameText(ATokens[ACtor].Text, 'Create');
  Result := Result and not ((mPrev >= 0) and (ATokens[mPrev].IsSymbol('.') or ATokens[mPrev].IsKeyword('inherited')));
end;

/// <summary>Typ einer Instanz: T…, keine Klassenreferenz (TComponentClass, class of …), kein generischer Typ.
/// </summary>
function IsInstanceType(const ATypeName: string): Boolean;
begin
  Result := (ATypeName <> '') and StartsStr('T', ATypeName) and not EndsText('Class', ATypeName);
  Result := Result and not StartsText('class', ATypeName) and (Pos('<', ATypeName) = 0);
end;

procedure TConstructorOnInstanceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex, mCtor: Integer;
  mTypeName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      if not IsCreateOnName(mTokens, mIndex, mCtor) then
      begin
        Continue;
      end;
      mTypeName := DeclaredTypeAt(mTypes, mTokens, mIndex);
      if IsInstanceType(mTypeName) and InStatements(AContext.Tree, mTokens[mIndex].StartPos) then
      begin
        AReport.Add(RangeOf(mTokens, mIndex, mCtor),
          cTexts[TRtlTypePatternsText.CtorOnInstance].Fmt([mTokens[mIndex].Text, mTypeName]), TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TRtlTypePatternsText.UseCreate].Fmt([mTypeName]), [TRuleEdit.Create(RangeOf(mTokens,
            mIndex, mIndex),
          mTypeName)])]);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TWritelnInGuiAppRule }

const
  cConsoleRoutines: array[0..3] of string = ('Write', 'Writeln', 'Read', 'Readln');
  cStandardFiles: array[0..2] of string = ('Output', 'ErrOutput', 'Input');
  cFileTypes: array[0..2] of string = ('Text', 'TextFile', 'File');
  cIntegerTypes: array[0..13] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Int32', 'UInt32');
  cFloatTypes: array[0..5] of string = ('Double', 'Single', 'Extended', 'Real', 'Currency', 'TDateTime');
  // Funktionen, die einen String liefern; dazu alle *ToStr und *ToHex.
  cStringFunctions: array[0..14] of string = ('Format', 'Trim', 'TrimLeft', 'TrimRight', 'UpperCase', 'LowerCase',
    'QuotedStr', 'Copy', 'StringOfChar', 'StringReplace', 'ExtractFileName', 'ExtractFilePath', 'Concat',
    'ParamStr', 'GetCurrentDir');

function TWritelnInGuiAppRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('writeln-in-gui-app', TRuleSeverity.Warning,
    cTexts[TRtlTypePatternsText.WritelnTitle].Text);
end;

type
  /// <summary>Was ApplicationKind beim Lesen der Hauptdatei sammelt.</summary>
  TMainSourceFacts = record
    Kind: TRuleApplicationKind;
    /// <summary>Steht die Art fest (Konsole, Package, keine Hauptdatei)?</summary>
    Done: Boolean;
    First, ServiceManager, Forms, FormMarker, AfterFileName: Boolean;
    procedure Add(const AToken: TPascalToken);
    procedure AddDirective(const AText: string);
    procedure AddComment(const AText: string);
    procedure AddCode(const AToken: TPascalToken);
    procedure Start(const AToken: TPascalToken);
    /// <summary>Art nach dem ganzen Text: Dienst, Bibliothek mit Formularen …</summary>
    function Final: TRuleApplicationKind;
  end;

procedure TMainSourceFacts.Add(const AToken: TPascalToken);
begin
  case AToken.Kind of
    TPascalTokenKind.Directive:
      AddDirective(AToken.Text);
    TPascalTokenKind.Comment:
      AddComment(AToken.Text);
  else
    AddCode(AToken);
  end;
end;

procedure TMainSourceFacts.AddDirective(const AText: string);
var
  mDirective: string;
begin
  // {$APPTYPE CONSOLE} oder (*$APPTYPE CONSOLE*), auch in {$IFDEF}: dann gilt Konsole.
  mDirective := UpperCase(AText);
  mDirective := StringReplace(StringReplace(mDirective, '(*$', '', []), '{$', '', []);
  if StartsText('APPTYPE', Trim(mDirective)) and ContainsText(mDirective, 'CONSOLE') then
  begin
    Kind := TRuleApplicationKind.Console;
    Done := True;
  end;
end;

procedure TMainSourceFacts.AddComment(const AText: string);
begin
  // Unit1 in 'Unit1.pas' {Form1}: die IDE markiert Formulare ohne Doppelpunkt, andere Designer
  // als {Name: TDataModule} (#1060).
  if AfterFileName and StartsStr('{', AText) and ((Pos(':', AText) = 0) or ContainsText(AText, ': TForm')) then
  begin
    FormMarker := True;
  end;
end;

procedure TMainSourceFacts.AddCode(const AToken: TPascalToken);
begin
  AfterFileName := AToken.Kind = TPascalTokenKind.StringLiteral;
  ServiceManager := ServiceManager or IsIdentifierNamed(AToken, 'SvcMgr');
  Forms := Forms or IsIdentifierNamed(AToken, 'Forms');
  if First then
  begin
    First := False;
    Start(AToken);
  end;
end;

procedure TMainSourceFacts.Start(const AToken: TPascalToken);
begin
  if AToken.IsKeyword('program') then
  begin
    Kind := TRuleApplicationKind.Gui;
  end
  else if AToken.IsKeyword('library') then
  begin
    Kind := TRuleApplicationKind.Library_;
  end
  // package ist kein reserviertes Wort (#943).
  else if IsIdentifierNamed(AToken, 'package') then
  begin
    Kind := TRuleApplicationKind.Package;
    Done := True;
  end
  else
  begin
    Kind := TRuleApplicationKind.Unknown;
    Done := True;
  end;
end;

function TMainSourceFacts.Final: TRuleApplicationKind;
begin
  Result := Kind;
  if Done then
  begin
    Exit;
  end;
  // Ein Dienst bindet Vcl.SvcMgr ein; mit Vcl.Forms daneben startet dasselbe Programm auch mit Oberfläche.
  if (Result = TRuleApplicationKind.Gui) and ServiceManager and not Forms then
  begin
    Result := TRuleApplicationKind.Service;
  end;
  if (Result = TRuleApplicationKind.Library_) and (Forms or FormMarker) then
  begin
    Result := TRuleApplicationKind.Unknown;
  end;
end;

class function TWritelnInGuiAppRule.ApplicationKind(const AConsoleTarget, AMainSource: string): TRuleApplicationKind;
var
  mTokens: TArray<TPascalToken>;
  mFacts: TMainSourceFacts;
  mIndex: Integer;
begin
  if SameText(Trim(AConsoleTarget), 'true') then
  begin
    Exit(TRuleApplicationKind.Console);
  end;
  mTokens := TPascalLexer.Tokenize(AMainSource);
  mFacts := Default(TMainSourceFacts);
  mFacts.Kind := TRuleApplicationKind.Unknown;
  mFacts.First := True;
  mIndex := 0;
  while not mFacts.Done and (mIndex <= High(mTokens)) do
  begin
    mFacts.Add(mTokens[mIndex]);
    Inc(mIndex);
  end;
  Result := mFacts.Final;
end;

class function TWritelnInGuiAppRule.Replacement(const AOptions: string): string;
var
  mValue: TJSONValue;
begin
  Result := cDefaultReplacement;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if (mValue is TJSONObject) and TJSONObject(mValue).TryGetValue<string>('replacement', Result) and
      (Trim(Result) = '') then
    begin
      Result := cDefaultReplacement;
    end;
  finally
    mValue.Free;
  end;
  Result := Trim(Result);
end;

type
  /// <summary>Arbeitsklasse von writeln-in-gui-app: sucht Write, Writeln, Read und Readln auf die Konsole und baut
  /// die Korrektur.</summary>
  TConsoleCallScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTypes: TDeclaredTypes;
    FTokens: TTokens;
    FDeclared: TArray<string>;
    FReplacementText: string;
    FNeedsSysUtils: Boolean;
    function Text(ANode: TSyntaxNode): string;
    procedure CollectDeclared(ANode: TSyntaxNode);
    function DeclaredTypeOf(ANode: TSyntaxNode): string;
    function LiteralAsString(ANode: TSyntaxNode): string;
    function IdentifierAsString(ANode: TSyntaxNode): string;
    function CallAsString(ANode: TSyntaxNode): string;
    function LeafAsString(ANode: TSyntaxNode): string;
    function AsString(ANode: TSyntaxNode): string;
    function HasWidth(ACall: TSyntaxNode): Boolean;
    function ArgumentsExpression(ACall: TSyntaxNode; AFirst: Integer): string;
    function ReplacedCall(const AExpression: string): string;
    function FixName: string;
    procedure AddUnitEdit(ACall: TSyntaxNode; const AUsed: TArray<string>; const AUnitName: string;
      var AEdits: TArray<TRuleEdit>);
    function UsesEdits(ACall: TSyntaxNode): TArray<TRuleEdit>;
    function Fixes(ACall: TSyntaxNode; AFirst: Integer): TArray<TRuleFix>;
    function IsConsoleCall(ANode, ACallee: TSyntaxNode): Boolean;
    function IsFileArgument(ANode: TSyntaxNode): Boolean;
    function FirstArgument(ANode: TSyntaxNode; out AFirst: Integer): Boolean;
    procedure ReportCall(ANode, ACallee: TSyntaxNode; AFirst: Integer);
    procedure CheckCall(ANode, ACallee: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

  /// <summary>Wertet ein Argument iterativ als String-Ausdruck aus: Verkettungen sind so tief wie lang.
  /// Steps zählt die schon ausgewerteten Kinder, Values hält die Ergebnisse. Wie zuvor wertet + die rechte Seite
  /// nur aus, wenn die linke passt.</summary>
  TStringExpressionWalk = class
  private
    FScan: TConsoleCallScan;
    FPending: TStack<TSyntaxNode>;
    FSteps: TStack<Integer>;
    FValues: TStack<string>;
    procedure Push(ANode: TSyntaxNode; AStep: Integer);
    procedure Concatenation(ANode: TSyntaxNode; AStep: Integer);
    procedure Parenthesis(ANode: TSyntaxNode; AStep: Integer);
  public
    constructor Create(AScan: TConsoleCallScan);
    destructor Destroy; override;
    function Evaluate(ANode: TSyntaxNode): string;
  end;

/// <summary>Verkettung A + B?</summary>
function IsConcatenation(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '+') and (ANode.ChildCount = 2);
end;

/// <summary>Geklammerter Ausdruck (A)?</summary>
function IsParenthesis(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1);
end;

// Die Prüfung "if IsConsole then" zeigt, dass der Aufruf gewollt ist.
function MentionsIsConsole(ANode: TSyntaxNode): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while not Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      Result := (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, 'IsConsole');
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Steht ANode in einem if oder while, dessen Bedingung IsConsole nennt?</summary>
function Guarded(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  Result := False;
  mParent := ANode.Parent;
  while not Result and (mParent <> nil) do
  begin
    Result := (mParent.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement]) and (mParent.ChildCount > 0) and
      MentionsIsConsole(mParent[0]);
    mParent := mParent.Parent;
  end;
end;

// Innerhalb einer Methode: Read und Write können Methoden der Klasse sein (TStream.Read).
function InMethod(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  Result := False;
  mParent := ANode.Parent;
  while not Result and (mParent <> nil) do
  begin
    Result := (mParent.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', mParent.Name) > 0);
    mParent := mParent.Parent;
  end;
end;

{ TConsoleCallScan }

constructor TConsoleCallScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
end;

destructor TConsoleCallScan.Destroy;
begin
  FTypes.Free;
  inherited Destroy;
end;

function TConsoleCallScan.Text(ANode: TSyntaxNode): string;
begin
  Result := Trim(Copy(FContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

// Namen der Routinen, die die Unit selbst deklariert (letzter Teil von TKlasse.Write).
procedure TConsoleCallScan.CollectDeclared(ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht), Reihenfolge wie die frühere Rekursion.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.RoutineHeader] then
      begin
        mName := mNode.Name;
        if Pos('.', mName) > 0 then
        begin
          mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
        end;
        FDeclared := FDeclared + [mName];
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

function TConsoleCallScan.DeclaredTypeOf(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := FTypes.DeclaredType(ANode.Name, ANode.StartPos);
  end;
end;

function TConsoleCallScan.LiteralAsString(ANode: TSyntaxNode): string;
begin
  if (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']) then
  begin
    Result := Text(ANode);
  end
  else
  begin
    Result := QuotedStr(Text(ANode));
  end;
end;

function TConsoleCallScan.IdentifierAsString(ANode: TSyntaxNode): string;
var
  mTypeName: string;
begin
  Result := '';
  mTypeName := DeclaredTypeOf(ANode);
  if MatchText(mTypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'ShortString', 'Char',
    'WideChar', 'AnsiChar', 'TFileName']) then
  begin
    Result := ANode.Name;
  end
  else if MatchText(mTypeName, cIntegerTypes) then
  begin
    Result := 'IntToStr(' + ANode.Name + ')';
  end
  else if MatchText(mTypeName, cFloatTypes) then
  begin
    Result := 'FloatToStr(' + ANode.Name + ')';
  end
  else if SameText(mTypeName, 'Boolean') then
  begin
    Result := 'BoolToStr(' + ANode.Name + ', True)';
  end;
  // IntToStr, FloatToStr und BoolToStr stehen in System.SysUtils.
  FNeedsSysUtils := FNeedsSysUtils or ((Result <> '') and (Result <> ANode.Name));
end;

function TConsoleCallScan.CallAsString(ANode: TSyntaxNode): string;
begin
  Result := '';
  if EndsText('ToStr', ANode.Name) or EndsText('ToHex', ANode.Name) or MatchText(ANode.Name, cStringFunctions) then
  begin
    Result := Text(ANode);
  end;
end;

// AsString für Knoten ohne Unterausdrücke (Literal, Bezeichner, Aufruf); '' für alle anderen.
function TConsoleCallScan.LeafAsString(ANode: TSyntaxNode): string;
begin
  case ANode.Kind of
    TSyntaxKind.Literal:
      Result := LiteralAsString(ANode);
    TSyntaxKind.Identifier:
      Result := IdentifierAsString(ANode);
    TSyntaxKind.Call:
      Result := CallAsString(ANode);
  else
    // Übrige Werte bewusst ohne Wirkung.
    Result := '';
  end;
end;

// Argument als String-Ausdruck für die Korrektur; '' wenn der Typ nicht sicher ist.
function TConsoleCallScan.AsString(ANode: TSyntaxNode): string;
var
  mWalk: TStringExpressionWalk;
begin
  mWalk := TStringExpressionWalk.Create(Self);
  try
    Result := mWalk.Evaluate(ANode);
  finally
    mWalk.Free;
  end;
end;

// Breitenangaben wie X:5:2 lassen sich nicht in einen String übertragen.
function TConsoleCallScan.HasWidth(ACall: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  // Binär zum ersten Token des Aufrufs statt ab Dateianfang (#1323).
  Result := False;
  mIndex := TRoutineBody.TokenAt(FTokens, ACall.StartOffset);
  while not Result and (mIndex <= High(FTokens)) and (FTokens[mIndex].Offset < ACall.EndOffset) do
  begin
    Result := FTokens[mIndex].IsSymbol(':');
    Inc(mIndex);
  end;
end;

/// <summary>Argumente ab AFirst als ein String-Ausdruck mit +; '' wenn eines nicht sicher umzuwandeln ist.</summary>
function TConsoleCallScan.ArgumentsExpression(ACall: TSyntaxNode; AFirst: Integer): string;
var
  mIndex: Integer;
  mPart: string;
  mValid: Boolean;
begin
  Result := '';
  mValid := True;
  mIndex := AFirst;
  while mValid and (mIndex < ACall.ChildCount) do
  begin
    mPart := AsString(ACall[mIndex]);
    mValid := mPart <> '';
    if Result <> '' then
    begin
      Result := Result + ' + ';
    end;
    Result := Result + mPart;
    Inc(mIndex);
  end;
  if not mValid then
  begin
    Result := '';
  end;
end;

function TConsoleCallScan.ReplacedCall(const AExpression: string): string;
begin
  if Pos('%s', FReplacementText) > 0 then
  begin
    Result := StringReplace(FReplacementText, '%s', AExpression, []);
  end
  else if SameText(FReplacementText, TWritelnInGuiAppRule.cDefaultReplacement) then
  begin
    Result := FReplacementText + '(PChar(' + AExpression + '))';
  end
  else
  begin
    Result := FReplacementText + '(' + AExpression + ')';
  end;
end;

/// <summary>Name des Ersatzes für den Titel der Korrektur (ohne Argumente).</summary>
function TConsoleCallScan.FixName: string;
begin
  Result := FReplacementText;
  if Pos('(', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('(', Result) - 1));
  end;
end;

procedure TConsoleCallScan.AddUnitEdit(ACall: TSyntaxNode; const AUsed: TArray<string>; const AUnitName: string;
  var AEdits: TArray<TRuleEdit>);
var
  mEdit: TTextEdit;
begin
  if not TUsesClauses.IsUsed(AUsed, AUnitName, FContext.Namespaces) and TUsesClauses.AddUnit(FTokens,
    ACall.StartOffset, AUnitName, TTextLines.LineBreakOf(FContext.Text), mEdit) then
  begin
    AEdits := AEdits + [mEdit];
  end;
end;

/// <summary>Einträge in uses, die der Ersatz braucht: Winapi.Windows für OutputDebugString, System.SysUtils für
/// IntToStr und Verwandte.</summary>
function TConsoleCallScan.UsesEdits(ACall: TSyntaxNode): TArray<TRuleEdit>;
var
  mUsed: TArray<string>;
begin
  Result := nil;
  mUsed := TUsesClauses.UsedUnits(FTokens);
  if SameText(FReplacementText, TWritelnInGuiAppRule.cDefaultReplacement) then
  begin
    AddUnitEdit(ACall, mUsed, 'Winapi.Windows', Result);
  end;
  if FNeedsSysUtils then
  begin
    AddUnitEdit(ACall, mUsed, 'System.SysUtils', Result);
  end;
end;

function TConsoleCallScan.Fixes(ACall: TSyntaxNode; AFirst: Integer): TArray<TRuleFix>;
var
  mExpression: string;
  mEdits: TArray<TRuleEdit>;
begin
  Result := nil;
  if (ACall.Kind <> TSyntaxKind.Call) or (AFirst >= ACall.ChildCount) or HasWidth(ACall) then
  begin
    Exit;
  end;
  FNeedsSysUtils := False;
  mExpression := ArgumentsExpression(ACall, AFirst);
  if mExpression <> '' then
  begin
    mEdits := [TRuleEdit.Create(TTextRange.Create(ACall.StartPos, ACall.EndPos), ReplacedCall(mExpression))];
    mEdits := mEdits + UsesEdits(ACall);
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsText.ReplaceWith].Fmt([FixName]), mEdits)];
  end;
end;

/// <summary>Write, Writeln, Read oder Readln aus System: nicht von der Unit selbst deklariert und (Read, Write)
/// nicht in einer Methode.</summary>
function TConsoleCallScan.IsConsoleCall(ANode, ACallee: TSyntaxNode): Boolean;
var
  mName: string;
begin
  mName := ACallee.Name;
  Result := MatchText(mName, cConsoleRoutines) and not MatchText(mName, FDeclared) and
    not (MatchText(mName, ['Write', 'Read']) and InMethod(ANode));
end;

/// <summary>Ist das erste Argument eine Datei (Typ Text, TextFile, file …, oder unbekannt bei weiteren Argumenten)?
/// </summary>
function TConsoleCallScan.IsFileArgument(ANode: TSyntaxNode): Boolean;
var
  mTypeName: string;
begin
  mTypeName := DeclaredTypeOf(ANode[1]);
  Result := MatchText(mTypeName, cFileTypes) or StartsText('file ', mTypeName) or
    ((ANode[1].Kind = TSyntaxKind.Identifier) and (mTypeName = '') and (ANode.ChildCount > 2));
end;

/// <summary>Erstes auszugebendes Argument (hinter Output, ErrOutput, Input); False bei einer Datei: kein
/// Konsolenzugriff.</summary>
function TConsoleCallScan.FirstArgument(ANode: TSyntaxNode; out AFirst: Integer): Boolean;
begin
  AFirst := 1;
  Result := True;
  if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount <= 1) then
  begin
    Exit;
  end;
  if (ANode[1].Kind = TSyntaxKind.Identifier) and MatchText(ANode[1].Name, cStandardFiles) then
  begin
    AFirst := 2;
  end
  else
  begin
    Result := not IsFileArgument(ANode);
  end;
end;

procedure TConsoleCallScan.ReportCall(ANode, ACallee: TSyntaxNode; AFirst: Integer);
var
  mNone: TArray<TRuleFix>;
begin
  if MatchText(ACallee.Name, ['Read', 'Readln']) then
  begin
    mNone := nil;
    FReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos),
      cTexts[TRtlTypePatternsText.NoConsoleWrite].Fmt([Text(ACallee)]), TRuleConfidence.High, mNone);
  end
  else
  begin
    FReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos),
      cTexts[TRtlTypePatternsText.NoConsoleRead].Fmt([Text(ACallee)]), TRuleConfidence.High, Fixes(ANode, AFirst));
  end;
end;

procedure TConsoleCallScan.CheckCall(ANode, ACallee: TSyntaxNode);
var
  mFirst: Integer;
begin
  if IsConsoleCall(ANode, ACallee) and FirstArgument(ANode, mFirst) and not Guarded(ANode) then
  begin
    ReportCall(ANode, ACallee, mFirst);
  end;
end;

procedure TConsoleCallScan.Visit(ANode: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) and (mNode[0].Kind = TSyntaxKind.Identifier) then
      begin
        CheckCall(mNode, mNode[0]);
      end
      else if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount = 1) and
        (mNode[0].Kind = TSyntaxKind.Identifier) then
      begin
        CheckCall(mNode[0], mNode[0]);
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

procedure TConsoleCallScan.Run;
begin
  FTokens := FContext.Tree.Tokens;
  FReplacementText := TWritelnInGuiAppRule.Replacement(FContext.Options);
  FDeclared := nil;
  CollectDeclared(FContext.Tree.Root);
  Visit(FContext.Tree.Root);
end;

{ TStringExpressionWalk }

constructor TStringExpressionWalk.Create(AScan: TConsoleCallScan);
begin
  inherited Create;
  FScan := AScan;
  FPending := TStack<TSyntaxNode>.Create;
  FSteps := TStack<Integer>.Create;
  FValues := TStack<string>.Create;
end;

destructor TStringExpressionWalk.Destroy;
begin
  FValues.Free;
  FSteps.Free;
  FPending.Free;
  inherited Destroy;
end;

procedure TStringExpressionWalk.Push(ANode: TSyntaxNode; AStep: Integer);
begin
  FPending.Push(ANode);
  FSteps.Push(AStep);
end;

procedure TStringExpressionWalk.Concatenation(ANode: TSyntaxNode; AStep: Integer);
begin
  case AStep of
    0:
      begin
        Push(ANode, 1);
        Push(ANode[0], 0);
      end;
    1:
      if FValues.Pop = FScan.Text(ANode[0]) then
      begin
        Push(ANode, 2);
        Push(ANode[1], 0);
      end
      else
      begin
        FValues.Push('');
      end;
  else
    if FValues.Pop = FScan.Text(ANode[1]) then
    begin
      FValues.Push(FScan.Text(ANode));
    end
    else
    begin
      FValues.Push('');
    end;
  end;
end;

procedure TStringExpressionWalk.Parenthesis(ANode: TSyntaxNode; AStep: Integer);
var
  mValue: string;
begin
  if AStep = 0 then
  begin
    Push(ANode, 1);
    Push(ANode[0], 0);
  end
  else
  begin
    mValue := FValues.Pop;
    if mValue <> '' then
    begin
      FValues.Push('(' + mValue + ')');
    end
    else
    begin
      FValues.Push('');
    end;
  end;
end;

function TStringExpressionWalk.Evaluate(ANode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
  mStep: Integer;
begin
  Push(ANode, 0);
  while FPending.Count > 0 do
  begin
    mNode := FPending.Pop;
    mStep := FSteps.Pop;
    if IsConcatenation(mNode) then
    begin
      Concatenation(mNode, mStep);
    end
    else if IsParenthesis(mNode) then
    begin
      Parenthesis(mNode, mStep);
    end
    else
    begin
      FValues.Push(FScan.LeafAsString(mNode));
    end;
  end;
  Result := FValues.Pop;
end;

{ TWritelnInGuiAppRule }

procedure TWritelnInGuiAppRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mKind: TRuleApplicationKind;
  mScan: TConsoleCallScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mKind := AContext.Application;
  // Ohne Projekt nur die .dpr selbst: program ohne {$APPTYPE CONSOLE}.
  if mKind = TRuleApplicationKind.Unknown then
  begin
    mKind := ApplicationKind('', AContext.Text);
  end;
  // Auch ein Windows-Dienst hat keine Konsole (#1060).
  if (mKind = TRuleApplicationKind.Gui) or (mKind = TRuleApplicationKind.Service) then
  begin
    mScan := TConsoleCallScan.Create(AContext, AReport);
    try
      mScan.Run;
    finally
      mScan.Free;
    end;
  end;
end;

procedure RegisterRtlTypePatternRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TInt32MulOverflowRule.Create);
  ARegistry.Register(TDelimitedTextWithoutStrictRule.Create);
  ARegistry.Register(TSizeOfPointerRule.Create);
  ARegistry.Register(TCharToPCharRule.Create);
  ARegistry.Register(TFloatEqualityRule.Create);
  ARegistry.Register(TConstructorOnInstanceRule.Create);
  ARegistry.Register(TFormatWithoutSettingsRule.Create);
  ARegistry.Register(TManagedTypeRawMemoryRule.Create);
  ARegistry.Register(TThreadvarManagedRule.Create);
  ARegistry.Register(TPCharOfTemporaryRule.Create);
  ARegistry.Register(TStringListUnsortedRule.Create);
  ARegistry.Register(TWritelnInGuiAppRule.Create);
  ARegistry.Register(TUncheckedConversionRule.Create);
  ARegistry.Register(TDictionaryGetWithoutCheckRule.Create);
  ARegistry.Register(TUncheckedEnumCastRule.Create);
  ARegistry.Register(TCreateProcessReadonlyCommandLineRule.Create);
  ARegistry.Register(TGlobalFormatSettingsModifiedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.RtlTypePatterns', cTexts);

end.
