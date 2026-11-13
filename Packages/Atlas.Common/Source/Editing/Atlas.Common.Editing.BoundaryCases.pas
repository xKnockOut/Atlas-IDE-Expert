unit Atlas.Common.Editing.BoundaryCases;

// Grenzfälle als Testfälle aus den Bedingungen einer Routine (#2173), statisch
// und ohne Namensauflösung:
//   - Vergleiche, deren eine Seite ein Parameter (oder eine lokale Kopie
//     m := AParam ohne weitere Zuweisung) und deren andere Seite eine
//     Konstante ist: =, <>, <, <=, >, >= bei Zahl (Wert davor, darauf,
//     dahinter), Gleitkomma (Schrittweite aus den Nachkommastellen), String
//     (Treffer, andere Schreibung, knapp daneben, leer) und Aufzählung;
//   - SameText/SameStr/AnsiSameText, StartsText/StartsStr, EndsText/EndsStr,
//     ContainsText/ContainsStr, Pos(K, P) > 0, Length(P) gegen eine Zahl,
//     Assigned(P) bzw. P = nil;
//   - case P of und P in [...]: jede Marke, Bereichsgrenzen und ein nicht
//     genannter Wert für else (Zahl: hinter der größten Marke; Aufzählung nur,
//     wenn ihr Typ in der Unit steht);
//   - Boolean-Parameter in einer Bedingung: True und False.
// Konstante ist ein Literal, True/False, nil, eine Konstante oder ein
// Aufzählungswert der Unit oder TTyp.Wert zum Typ des Parameters; Felder und
// Funktionsaufrufe liefern nichts (kein geratener Wert). Kombiniert wird nicht
// über Kreuz: Je Fall weicht ein Parameter ab, die übrigen stehen auf einem
// neutralen Wert. Werte stehen in der Schreibweise von DUnitX-[TestCase]
// (Strings ohne Hochkommas, Aufzählungswerte ohne Typ).

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Parametertyps: Text (String, Char), Zahl, Gleitkomma, Boolean, Aufzählung, Zeiger
  /// (Objekt, Interface, nur nil), Unknown (nicht unterstützt).</summary>
  TBoundaryKind = (Unknown, Text, Ordinal, Float, Logical, Enum, Reference);
{$SCOPEDENUMS OFF}

  TBoundaryParameter = record
    Name: string;
    TypeName: string;
    Kind: TBoundaryKind;
    /// <summary>Wert, auf dem der Parameter steht, wenn ein anderer abweicht.</summary>
    Neutral: string;
    /// <summary>Werte der Aufzählung, wenn ihr Typ in der Unit steht; sonst leer.</summary>
    Members: TArray<string>;
  end;

  TBoundaryCase = record
    /// <summary>Index des abweichenden Parameters.</summary>
    Parameter: Integer;
    /// <summary>Wert in der Schreibweise von [TestCase].</summary>
    Value: string;
    /// <summary>Warum dieser Wert (Bedingung und Art: Treffer, knapp daneben …).</summary>
    Reason: string;
    /// <summary>Zeile der Bedingung (0-basiert); -1 bei Fällen ohne eigene Bedingung.</summary>
    Line: Integer;
  end;

  TBoundaryResult = record
    Routine: string;
    Parameters: TArray<TBoundaryParameter>;
    Cases: TArray<TBoundaryCase>;
    /// <summary>Gab es mehr Fälle als erlaubt?</summary>
    Truncated: Boolean;
    /// <summary>Werte aller Parameter für den Fall ACase.</summary>
    function Values(ACase: Integer): TArray<string>;
  end;

  TBoundaryCases = class
  public const
    cDefaultMax = 20;
  public
    /// <summary>Grenzfälle der Routine ARoutine (RoutineDecl mit Rumpf) aus ATree, höchstens AMax.</summary>
    class function Find(ATree: TSyntaxTree; ARoutine: TSyntaxNode; AMax: Integer): TBoundaryResult; static;
    /// <summary>Art eines Parametertyps nach seinem Namen; Aufzählungen der Unit erkennt Find.</summary>
    class function KindOf(const ATypeName: string): TBoundaryKind; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TBoundaryText = (Hit, OtherCase, NearMiss, Empty, NoMatch, Below, OnBound, Above, CaseLabel, CaseElse, InSet,
    Starts, Ends, Contains, LengthBelow, LengthOn, LengthAbove, NilValue, LogicalTrue, LogicalFalse);

const
  cTexts: array[TBoundaryText] of TAtlasText = (
    (De: '%s: Treffer'; En: '%s: match'),
    (De: '%s: andere Schreibung'; En: '%s: different case'),
    (De: '%s: knapp daneben'; En: '%s: just off'),
    (De: '%s: leer'; En: '%s: empty'),
    (De: 'keine Bedingung trifft'; En: 'no condition matches'),
    (De: '%s: knapp darunter'; En: '%s: just below'),
    (De: '%s: Grenze'; En: '%s: on the boundary'),
    (De: '%s: knapp darüber'; En: '%s: just above'),
    (De: 'case-Marke %s'; En: 'case label %s'),
    (De: 'case: keine Marke (else)'; En: 'case: no label (else)'),
    (De: 'in [...]: %s'; En: 'in [...]: %s'),
    (De: '%s: beginnt damit'; En: '%s: starts with it'),
    (De: '%s: endet damit'; En: '%s: ends with it'),
    (De: '%s: enthalten'; En: '%s: contained'),
    (De: '%s: eine Länge darunter'; En: '%s: one length below'),
    (De: '%s: Länge auf der Grenze'; En: '%s: length on the boundary'),
    (De: '%s: eine Länge darüber'; En: '%s: one length above'),
    (De: '%s: nil'; En: '%s: nil'),
    (De: '%s: True'; En: '%s: True'),
    (De: '%s: False'; En: '%s: False'));

{$SCOPEDENUMS OFF}

const
  cMaxLength = 64;
  cNoMatch = 'x';


type
{$SCOPEDENUMS ON}
  TConstKind = (None, Int, Float, Str, Name, NilValue, Logical);
{$SCOPEDENUMS OFF}

  /// <summary>Konstante Seite einer Bedingung.</summary>
  TConstant = record
    Kind: TConstKind;
    /// <summary>Wert in der Schreibweise von [TestCase] (String ohne Hochkommas, Name wie geschrieben).</summary>
    Value: string;
  end;

  /// <summary>Sammelt die Fälle einer Routine ohne Doppelte.</summary>
  TCollector = record
    Found: TBoundaryResult;
    /// <summary>Lokale Kopien: Name der Variablen und Index des Parameters.</summary>
    AliasNames: TArray<string>;
    AliasParams: TArray<Integer>;
    /// <summary>Namen der Konstanten und Aufzählungswerte der Unit; je Name der Wert der Konstanten (nil bei
    /// Aufzählungswerten).</summary>
    Constants: TArray<string>;
    ConstValues: TArray<TSyntaxNode>;
    /// <summary>Je Parameter die String-Konstanten mit Treffer und ob ohne Groß-/Kleinschreibung verglichen.
    /// </summary>
    TextHits: TArray<TArray<string>>;
    TextInsensitive: TArray<TArray<Boolean>>;
    procedure Add(AParam: Integer; const AValue, AReason: string; ALine: Integer);
    procedure AddTextHit(AParam: Integer; const AValue: string; AInsensitive: Boolean; const ACondition: string;
      ALine: Integer);
    function ParamOf(ANode: TSyntaxNode): Integer;
    function ConstantOf(ANode: TSyntaxNode; AParam: Integer): TConstant;
    function ConstantValue(const AName: string; AParam: Integer): TConstant;
    procedure Compare(AParam: Integer; const AOp: string; const AConst: TConstant; ALine: Integer;
      const ACondition: string);
    procedure NumberBoundary(AParam: Integer; const AConst: TConstant; ALine: Integer; const ACondition: string);
    procedure Comparison(ANode: TSyntaxNode);
    function Sides(ANode: TSyntaxNode; out ALeft, ARight: TSyntaxNode; out AOp: string): Boolean;
    procedure LengthCondition(AParam: Integer; const AConst: TConstant; ALine: Integer; const ACondition: string);
    procedure CallCondition(ANode: TSyntaxNode);
    procedure TextCall(AParam: Integer; const AName, AConst: string; ALine: Integer; const ACondition: string);
    function LabelConstant(AParam: Integer; ALabel: TSyntaxNode; out ALow, AHigh: TConstant): Boolean;
    procedure ElseMember(AParam: Integer; const ANames: TArray<string>; ALine: Integer);
    procedure Labels(AParam: Integer; const ALabels: TArray<TSyntaxNode>; ALine: Integer; AIsCase: Boolean);
    procedure CaseStatement(ANode: TSyntaxNode);
    procedure SetMembership(ANode: TSyntaxNode);
    procedure TextVariants;
    procedure ReplaceValue(AParam: Integer; const AOld, ANew, AReason: string);
    procedure LogicalUse(ANode: TSyntaxNode);
    procedure Neutrals;
    function EnumNeutral(AParam: Integer): string;
    procedure Visit(ANode: TSyntaxNode);
  end;

function Reason(AText: TBoundaryText; const AArg: string): string;
begin
  Result := cTexts[AText].Fmt([AArg]);
end;

function BareName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function Unparen(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

/// <summary>Text eines String-Literals ('a''b' → a'b, #65 → A); False bei anderem oder Steuerzeichen.</summary>
function StringValue(const ALiteral: string; out AText: string): Boolean;
var
  mIndex: Integer;
  mCode: Integer;
begin
  AText := '';
  Result := False;
  if (Length(ALiteral) >= 2) and (ALiteral[1] = '''') and (ALiteral[Length(ALiteral)] = '''') then
  begin
    AText := StringReplace(Copy(ALiteral, 2, Length(ALiteral) - 2), '''''', '''', [rfReplaceAll]);
    Result := True;
  end
  else if (Length(ALiteral) > 1) and (ALiteral[1] = '#') and TryStrToInt(Copy(ALiteral, 2, MaxInt), mCode) and
    (mCode >= Ord(' ')) and (mCode < Ord('~')) then
  begin
    AText := Char(mCode);
    Result := True;
  end;
  for mIndex := 1 to Length(AText) do
  begin
    if Ord(AText[mIndex]) < Ord(' ') then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Andere Schreibung von AText (klein, sonst groß); '' ohne Buchstaben.</summary>
function OtherCase(const AText: string): string;
begin
  Result := LowerCase(AText);
  if Result = AText then
  begin
    Result := UpperCase(AText);
  end;
  if Result = AText then
  begin
    Result := '';
  end;
end;

/// <summary>AText um AStep Einheiten der letzten Stelle verschoben (Dezimalzahl als Text, ohne Rundung); False,
/// wenn AText keine einfache Dezimalzahl ist.</summary>
function ShiftDecimal(const AText: string; AStep: Integer; out AShifted: string): Boolean;
const
  cMaxDecimals = 9;
var
  mDot, mDecimals: Integer;
  mDigits: string;
  mValue: Int64;
  mNegative: Boolean;
begin
  AShifted := '';
  mDot := Pos('.', AText);
  mDecimals := 0;
  mDigits := AText;
  if mDot > 0 then
  begin
    mDecimals := Length(AText) - mDot;
    mDigits := Copy(AText, 1, mDot - 1) + Copy(AText, mDot + 1, MaxInt);
  end;
  Result := (mDecimals <= cMaxDecimals) and TryStrToInt64(mDigits, mValue);
  if not Result then
  begin
    Exit;
  end;
  mValue := mValue + AStep;
  mNegative := mValue < 0;
  AShifted := IntToStr(Abs(mValue));
  if mDecimals > 0 then
  begin
    while Length(AShifted) <= mDecimals do
    begin
      AShifted := '0' + AShifted;
    end;
    Insert('.', AShifted, Length(AShifted) - mDecimals + 1);
  end;
  if mNegative then
  begin
    AShifted := '-' + AShifted;
  end;
end;

/// <summary>Operator mit vertauschten Seiten (K &lt; P wird P &gt; K).</summary>
function Mirrored(const AOp: string): string;
const
  cFrom: array[0..3] of string = ('<', '>', '<=', '>=');
  cTo: array[0..3] of string = ('>', '<', '>=', '<=');
var
  mIndex: Integer;
begin
  Result := AOp;
  for mIndex := Low(cFrom) to High(cFrom) do
  begin
    if AOp = cFrom[mIndex] then
    begin
      Result := cTo[mIndex];
    end;
  end;
end;

/// <summary>Treffer für andere Schreibung und knapp daneben: bevorzugt einer, der Anfang eines anderen ist
/// (Win64 neben Win64x), sonst der erste.</summary>
function BaseHit(const AHits: TArray<string>): Integer;
var
  mIndex, mOther: Integer;
begin
  for mIndex := 0 to High(AHits) do
  begin
    for mOther := 0 to High(AHits) do
    begin
      if (mOther <> mIndex) and StartsStr(AHits[mIndex], AHits[mOther]) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := 0;
end;

/// <summary>Steht ANode als Bedingung (if, while, repeat, if-Ausdruck) oder als Teil von not, and, or, xor?
/// </summary>
function InCondition(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  while (mParent <> nil) and (mParent.Kind = TSyntaxKind.ParenExpr) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent = nil then
  begin
    Exit(False);
  end;
  case mParent.Kind of
    TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.IfExpr:
      Result := True;
    TSyntaxKind.UnaryExpr:
      Result := mParent.Name = 'not';
    TSyntaxKind.BinaryExpr:
      Result := MatchText(mParent.Name, ['and', 'or', 'xor']);
  else
    Result := False;
  end;
end;

/// <summary>Konstante eines Literals: nil, String, ganze Zahl oder Dezimalzahl; None sonst.</summary>
function LiteralConstant(const ALiteral: string): TConstant;
var
  mText: string;
  mInt: Int64;
begin
  Result := Default(TConstant);
  if SameText(ALiteral, 'nil') then
  begin
    Result.Kind := TConstKind.NilValue;
    Result.Value := 'nil';
  end
  else if StringValue(ALiteral, mText) then
  begin
    Result.Kind := TConstKind.Str;
    Result.Value := mText;
  end
  else if TryStrToInt64(ALiteral, mInt) then
  begin
    Result.Kind := TConstKind.Int;
    Result.Value := IntToStr(mInt);
  end
  else if (Pos('.', ALiteral) > 0) and (Pos('e', LowerCase(ALiteral)) = 0) then
  begin
    Result.Kind := TConstKind.Float;
    Result.Value := ALiteral;
  end;
end;

/// <summary>Zahl mit Minus davor; andere Konstanten werden None.</summary>
function Negated(const AConst: TConstant): TConstant;
begin
  Result := Default(TConstant);
  if AConst.Kind in [TConstKind.Int, TConstKind.Float] then
  begin
    Result := AConst;
    Result.Value := '-' + AConst.Value;
  end;
end;

/// <summary>Ist ANode TTyp.Wert zum Typ ATypeName?</summary>
function IsTypeMember(ANode: TSyntaxNode; const ATypeName: string): Boolean;
begin
  Result := (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and (ATypeName <> '') and
    SameText(ANode[0].Name, BareName(ATypeName));
end;

/// <summary>Konstante, wie sie im Quelltext stünde ('Win32' mit Hochkommas).</summary>
function ConstText(const AConst: TConstant): string;
begin
  if AConst.Kind = TConstKind.Str then
  begin
    Result := QuotedStr(AConst.Value);
  end
  else
  begin
    Result := AConst.Value;
  end;
end;

{ TBoundaryResult }

function TBoundaryResult.Values(ACase: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(Parameters));
  for mIndex := 0 to High(Parameters) do
  begin
    Result[mIndex] := Parameters[mIndex].Neutral;
  end;
  if (ACase >= 0) and (ACase <= High(Cases)) then
  begin
    Result[Cases[ACase].Parameter] := Cases[ACase].Value;
  end;
end;

{ TCollector }

procedure TCollector.Add(AParam: Integer; const AValue, AReason: string; ALine: Integer);
var
  mCase: TBoundaryCase;
begin
  for mCase in Found.Cases do
  begin
    if (mCase.Parameter = AParam) and (mCase.Value = AValue) then
    begin
      Exit;
    end;
  end;
  mCase.Parameter := AParam;
  mCase.Value := AValue;
  mCase.Reason := AReason;
  mCase.Line := ALine;
  Found.Cases := Found.Cases + [mCase];
end;

procedure TCollector.AddTextHit(AParam: Integer; const AValue: string; AInsensitive: Boolean;
  const ACondition: string; ALine: Integer);
begin
  if AValue = '' then
  begin
    Add(AParam, '', Reason(TBoundaryText.Empty, ACondition), ALine);
    Exit;
  end;
  Add(AParam, AValue, Reason(TBoundaryText.Hit, ACondition), ALine);
  TextHits[AParam] := TextHits[AParam] + [AValue];
  TextInsensitive[AParam] := TextInsensitive[AParam] + [AInsensitive];
end;

function TCollector.ParamOf(ANode: TSyntaxNode): Integer;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := -1;
  mNode := Unparen(ANode);
  if (mNode = nil) or (mNode.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Found.Parameters) do
  begin
    if (Found.Parameters[mIndex].Kind <> TBoundaryKind.Unknown) or (Found.Parameters[mIndex].TypeName <> '') then
    begin
      if SameText(Found.Parameters[mIndex].Name, mNode.Name) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  for mIndex := 0 to High(AliasNames) do
  begin
    if SameText(AliasNames[mIndex], mNode.Name) then
    begin
      Exit(AliasParams[mIndex]);
    end;
  end;
end;

function TCollector.ConstantOf(ANode: TSyntaxNode; AParam: Integer): TConstant;
var
  mNode: TSyntaxNode;
begin
  Result := Default(TConstant);
  mNode := Unparen(ANode);
  if mNode = nil then
  begin
    Exit;
  end;
  case mNode.Kind of
    TSyntaxKind.UnaryExpr:
      if (mNode.Name = '-') and (mNode.ChildCount = 1) then
      begin
        Result := Negated(ConstantOf(mNode[0], AParam));
      end;
    TSyntaxKind.Literal:
      Result := LiteralConstant(mNode.Name);
    TSyntaxKind.Identifier:
      if MatchText(mNode.Name, ['True', 'False']) then
      begin
        Result.Kind := TConstKind.Logical;
        Result.Value := mNode.Name;
      end
      else if MatchText(mNode.Name, Constants) then
      begin
        Result := ConstantValue(mNode.Name, AParam);
      end;
    TSyntaxKind.MemberAccess:
      if IsTypeMember(mNode, Found.Parameters[AParam].TypeName) then
      begin
        // TArt.Rot zum Typ TArt des Parameters.
        Result.Kind := TConstKind.Name;
        Result.Value := mNode.Name;
      end;
  else
    // Andere Ausdrücke sind keine Konstanten.
  end;
end;

function TCollector.ConstantValue(const AName: string; AParam: Integer): TConstant;
var
  mValue: TSyntaxNode;
begin
  // Konstante der Unit mit Literal (cGrenze = 7) zählt mit ihrem Wert; sonst als Name (Aufzählungswert).
  mValue := ConstValues[IndexText(AName, Constants)];
  if (mValue <> nil) and (mValue.Kind in [TSyntaxKind.Literal, TSyntaxKind.UnaryExpr]) then
  begin
    Result := ConstantOf(mValue, AParam);
    if Result.Kind <> TConstKind.None then
    begin
      Exit;
    end;
  end;
  Result.Kind := TConstKind.Name;
  Result.Value := AName;
end;

procedure TCollector.Compare(AParam: Integer; const AOp: string; const AConst: TConstant; ALine: Integer;
  const ACondition: string);
var
  mKind: TBoundaryKind;
  mEquality: Boolean;
begin
  mKind := Found.Parameters[AParam].Kind;
  mEquality := (AOp = '=') or (AOp = '<>');
  case AConst.Kind of
    TConstKind.Int, TConstKind.Float:
      NumberBoundary(AParam, AConst, ALine, ACondition);
    TConstKind.Str:
      if (mKind = TBoundaryKind.Text) and mEquality then
      begin
        AddTextHit(AParam, AConst.Value, False, ACondition, ALine);
      end;
    TConstKind.Name, TConstKind.Logical:
      if (mKind in [TBoundaryKind.Enum, TBoundaryKind.Logical, TBoundaryKind.Unknown]) and mEquality then
      begin
        if mKind = TBoundaryKind.Unknown then
        begin
          Found.Parameters[AParam].Kind := TBoundaryKind.Enum;
        end;
        Add(AParam, BareName(AConst.Value), Reason(TBoundaryText.Hit, ACondition), ALine);
      end;
    TConstKind.NilValue:
      if (mKind in [TBoundaryKind.Reference, TBoundaryKind.Unknown]) and mEquality then
      begin
        Found.Parameters[AParam].Kind := TBoundaryKind.Reference;
        Add(AParam, 'nil', Reason(TBoundaryText.NilValue, ACondition), ALine);
      end;
  else
    // Keine Konstante: nichts raten.
  end;
end;

procedure TCollector.NumberBoundary(AParam: Integer; const AConst: TConstant; ALine: Integer;
  const ACondition: string);
var
  mKind: TBoundaryKind;
  mValue: Int64;
  mShifted: string;
begin
  mKind := Found.Parameters[AParam].Kind;
  if (AConst.Kind = TConstKind.Int) and (mKind in [TBoundaryKind.Ordinal, TBoundaryKind.Float]) then
  begin
    mValue := StrToInt64(AConst.Value);
    Add(AParam, IntToStr(mValue - 1), Reason(TBoundaryText.Below, ACondition), ALine);
    Add(AParam, IntToStr(mValue), Reason(TBoundaryText.OnBound, ACondition), ALine);
    Add(AParam, IntToStr(mValue + 1), Reason(TBoundaryText.Above, ACondition), ALine);
  end
  else if (AConst.Kind = TConstKind.Float) and (mKind = TBoundaryKind.Float) then
  begin
    if ShiftDecimal(AConst.Value, -1, mShifted) then
    begin
      Add(AParam, mShifted, Reason(TBoundaryText.Below, ACondition), ALine);
    end;
    Add(AParam, AConst.Value, Reason(TBoundaryText.OnBound, ACondition), ALine);
    if ShiftDecimal(AConst.Value, 1, mShifted) then
    begin
      Add(AParam, mShifted, Reason(TBoundaryText.Above, ACondition), ALine);
    end;
  end;
end;

procedure TCollector.LengthCondition(AParam: Integer; const AConst: TConstant; ALine: Integer;
  const ACondition: string);
var
  mLength: Int64;
begin
  if (Found.Parameters[AParam].Kind <> TBoundaryKind.Text) or (AConst.Kind <> TConstKind.Int) then
  begin
    Exit;
  end;
  mLength := StrToInt64(AConst.Value);
  if (mLength < 0) or (mLength > cMaxLength) then
  begin
    Exit;
  end;
  if mLength > 0 then
  begin
    Add(AParam, StringOfChar('a', mLength - 1), Reason(TBoundaryText.LengthBelow, ACondition), ALine);
  end;
  Add(AParam, StringOfChar('a', mLength), Reason(TBoundaryText.LengthOn, ACondition), ALine);
  Add(AParam, StringOfChar('a', mLength + 1), Reason(TBoundaryText.LengthAbove, ACondition), ALine);
end;

procedure TCollector.Comparison(ANode: TSyntaxNode);
var
  mLeft, mRight: TSyntaxNode;
  mParam: Integer;
  mOp: string;
  mConst: TConstant;
begin
  if not Sides(ANode, mLeft, mRight, mOp) then
  begin
    Exit;
  end;
  mParam := ParamOf(mLeft);
  if mParam >= 0 then
  begin
    mConst := ConstantOf(mRight, mParam);
    Compare(mParam, mOp, mConst, ANode.StartPos.Line, Found.Parameters[mParam].Name + ' ' + mOp + ' ' +
      ConstText(mConst));
  end
  else if (mLeft.Kind = TSyntaxKind.Call) and SameText(mLeft.Name, 'Length') and (mLeft.ChildCount = 2) then
  begin
    // Length(P) <op> n.
    mParam := ParamOf(mLeft[1]);
    if mParam >= 0 then
    begin
      mConst := ConstantOf(mRight, mParam);
      LengthCondition(mParam, mConst, ANode.StartPos.Line, 'Length(' + Found.Parameters[mParam].Name + ') ' + mOp +
        ' ' + ConstText(mConst));
    end;
  end
  else if (mLeft.Kind = TSyntaxKind.Call) and MatchText(mLeft.Name, ['Pos', 'AnsiPos']) and (mOp = '>') and
    (mRight.Kind = TSyntaxKind.Literal) and (mRight.Name = '0') then
  begin
    // Pos(K, P) > 0.
    CallCondition(mLeft);
  end;
end;

function TCollector.Sides(ANode: TSyntaxNode; out ALeft, ARight: TSyntaxNode; out AOp: string): Boolean;
begin
  // Parameter bzw. Aufruf nach links, die Konstante nach rechts.
  AOp := ANode.Name;
  ALeft := Unparen(ANode[0]);
  ARight := Unparen(ANode[1]);
  Result := (ALeft <> nil) and (ARight <> nil);
  if Result and (ParamOf(ALeft) < 0) and ((ParamOf(ARight) >= 0) or (ARight.Kind = TSyntaxKind.Call)) then
  begin
    ALeft := Unparen(ANode[1]);
    ARight := Unparen(ANode[0]);
    AOp := Mirrored(AOp);
  end;
end;

procedure TCollector.TextCall(AParam: Integer; const AName, AConst: string; ALine: Integer;
  const ACondition: string);
begin
  if MatchText(AName, ['SameText', 'AnsiSameText', 'SameStr', 'AnsiSameStr']) then
  begin
    AddTextHit(AParam, AConst, MatchText(AName, ['SameText', 'AnsiSameText']), ACondition, ALine);
  end
  else if AConst = '' then
  begin
    Exit;
  end
  else if MatchText(AName, ['StartsText', 'StartsStr', 'AnsiStartsText', 'AnsiStartsStr']) then
  begin
    Add(AParam, AConst + cNoMatch, Reason(TBoundaryText.Starts, ACondition), ALine);
    Add(AParam, Copy(AConst, 1, Length(AConst) - 1), Reason(TBoundaryText.NearMiss, ACondition), ALine);
  end
  else if MatchText(AName, ['EndsText', 'EndsStr', 'AnsiEndsText', 'AnsiEndsStr']) then
  begin
    Add(AParam, cNoMatch + AConst, Reason(TBoundaryText.Ends, ACondition), ALine);
    Add(AParam, Copy(AConst, 2, MaxInt), Reason(TBoundaryText.NearMiss, ACondition), ALine);
  end
  else
  begin
    // ContainsText, ContainsStr, Pos(K, P) > 0.
    Add(AParam, cNoMatch + AConst + cNoMatch, Reason(TBoundaryText.Contains, ACondition), ALine);
    if Length(AConst) > 1 then
    begin
      Add(AParam, Copy(AConst, 1, Length(AConst) - 1), Reason(TBoundaryText.NearMiss, ACondition), ALine);
    end;
  end;
end;

procedure TCollector.CallCondition(ANode: TSyntaxNode);
var
  mParam, mParamArg, mConstArg: Integer;
  mConst: TConstant;
  mName, mCondition: string;
begin
  mName := BareName(ANode.Name);
  if MatchText(mName, ['Assigned']) and (ANode.ChildCount = 2) then
  begin
    mParam := ParamOf(ANode[1]);
    if (mParam >= 0) and (Found.Parameters[mParam].Kind in [TBoundaryKind.Reference, TBoundaryKind.Unknown]) then
    begin
      Found.Parameters[mParam].Kind := TBoundaryKind.Reference;
      Add(mParam, 'nil', Reason(TBoundaryText.NilValue, 'Assigned(' + Found.Parameters[mParam].Name + ')'),
        ANode.StartPos.Line);
    end;
    Exit;
  end;
  if not MatchText(mName, ['SameText', 'AnsiSameText', 'SameStr', 'AnsiSameStr', 'StartsText', 'StartsStr',
    'AnsiStartsText', 'AnsiStartsStr', 'EndsText', 'EndsStr', 'AnsiEndsText', 'AnsiEndsStr', 'ContainsText',
    'ContainsStr', 'Pos', 'AnsiPos']) or (ANode.ChildCount <> 3) then
  begin
    Exit;
  end;
  // Starts…/Ends…(Teil, Text), Pos(Teil, Text), Contains…(Text, Teil); Same… beliebig herum.
  mParamArg := 2;
  mConstArg := 1;
  if MatchText(mName, ['ContainsText', 'ContainsStr']) or
    (MatchText(mName, ['SameText', 'AnsiSameText', 'SameStr', 'AnsiSameStr']) and (ParamOf(ANode[1]) >= 0)) then
  begin
    mParamArg := 1;
    mConstArg := 2;
  end;
  mParam := ParamOf(ANode[mParamArg]);
  if (mParam < 0) or (Found.Parameters[mParam].Kind <> TBoundaryKind.Text) then
  begin
    Exit;
  end;
  mConst := ConstantOf(ANode[mConstArg], mParam);
  if mConst.Kind <> TConstKind.Str then
  begin
    Exit;
  end;
  if mParamArg = 1 then
  begin
    mCondition := mName + '(' + Found.Parameters[mParam].Name + ', ' + ConstText(mConst) + ')';
  end
  else
  begin
    mCondition := mName + '(' + ConstText(mConst) + ', ' + Found.Parameters[mParam].Name + ')';
  end;
  TextCall(mParam, mName, mConst.Value, ANode.StartPos.Line, mCondition);
end;

function TCollector.LabelConstant(AParam: Integer; ALabel: TSyntaxNode; out ALow, AHigh: TConstant): Boolean;
begin
  if (ALabel.Kind = TSyntaxKind.RangeExpr) and (ALabel.ChildCount = 2) then
  begin
    ALow := ConstantOf(ALabel[0], AParam);
    AHigh := ConstantOf(ALabel[1], AParam);
  end
  else
  begin
    ALow := ConstantOf(ALabel, AParam);
    AHigh := ALow;
  end;
  if (ALow.Kind = TConstKind.None) and (ALabel.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    (Found.Parameters[AParam].Kind in [TBoundaryKind.Enum, TBoundaryKind.Unknown]) then
  begin
    // Marken sind immer Konstanten: auch Aufzählungswerte anderer Units.
    ALow.Kind := TConstKind.Name;
    ALow.Value := ALabel.Name;
    AHigh := ALow;
  end;
  if ALow.Kind = TConstKind.Name then
  begin
    if Found.Parameters[AParam].Kind = TBoundaryKind.Unknown then
    begin
      Found.Parameters[AParam].Kind := TBoundaryKind.Enum;
    end;
    Result := Found.Parameters[AParam].Kind = TBoundaryKind.Enum;
  end
  else
  begin
    Result := (ALow.Kind = AHigh.Kind) and (((ALow.Kind = TConstKind.Int) and
      (Found.Parameters[AParam].Kind = TBoundaryKind.Ordinal)) or ((ALow.Kind = TConstKind.Str) and
      (Found.Parameters[AParam].Kind = TBoundaryKind.Text)));
  end;
end;

procedure TCollector.Labels(AParam: Integer; const ALabels: TArray<TSyntaxNode>; ALine: Integer; AIsCase: Boolean);
var
  mLabel: TSyntaxNode;
  mLow, mHigh: TConstant;
  mMax: Int64;
  mHasInt: Boolean;
  mNames: TArray<string>;
  mText: TBoundaryText;
begin
  mText := TBoundaryText.InSet;
  if AIsCase then
  begin
    mText := TBoundaryText.CaseLabel;
  end;
  mMax := Low(Int64);
  mHasInt := False;
  mNames := nil;
  for mLabel in ALabels do
  begin
    if not LabelConstant(AParam, mLabel, mLow, mHigh) then
    begin
      Continue;
    end;
    Add(AParam, BareName(mLow.Value), Reason(mText, ConstText(mLow)), ALine);
    if mHigh.Value <> mLow.Value then
    begin
      Add(AParam, BareName(mHigh.Value), Reason(mText, ConstText(mLow) + '..' + ConstText(mHigh)), ALine);
    end;
    if mLow.Kind = TConstKind.Name then
    begin
      mNames := mNames + [BareName(mLow.Value)];
    end
    else if mHigh.Kind = TConstKind.Int then
    begin
      mHasInt := True;
      mMax := Max(mMax, StrToInt64(mHigh.Value));
    end;
  end;
  if mHasInt then
  begin
    Add(AParam, IntToStr(mMax + 1), cTexts[TBoundaryText.CaseElse].Text, ALine);
  end
  else if mNames <> nil then
  begin
    ElseMember(AParam, mNames, ALine);
  end;
end;

procedure TCollector.ElseMember(AParam: Integer; const ANames: TArray<string>; ALine: Integer);
var
  mMember: string;
begin
  for mMember in Found.Parameters[AParam].Members do
  begin
    if not MatchText(mMember, ANames) then
    begin
      Add(AParam, mMember, cTexts[TBoundaryText.CaseElse].Text, ALine);
      Exit;
    end;
  end;
end;

procedure TCollector.CaseStatement(ANode: TSyntaxNode);
var
  mParam, mIndex, mChild: Integer;
  mLabels: TArray<TSyntaxNode>;
  mItem: TSyntaxNode;
begin
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mParam := ParamOf(ANode[0]);
  if mParam < 0 then
  begin
    Exit;
  end;
  mLabels := nil;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    mItem := ANode[mIndex];
    if mItem.Kind <> TSyntaxKind.CaseItem then
    begin
      Continue;
    end;
    for mChild := 0 to mItem.ChildCount - 1 do
    begin
      if not TRoutineBody.IsStatement(mItem[mChild]) then
      begin
        mLabels := mLabels + [mItem[mChild]];
      end;
    end;
  end;
  Labels(mParam, mLabels, ANode.StartPos.Line, True);
end;

procedure TCollector.SetMembership(ANode: TSyntaxNode);
var
  mParam, mIndex: Integer;
  mSet: TSyntaxNode;
  mLabels: TArray<TSyntaxNode>;
begin
  mParam := ParamOf(ANode[0]);
  mSet := Unparen(ANode[1]);
  if (mParam < 0) or (mSet = nil) or (mSet.Kind <> TSyntaxKind.SetConstructor) then
  begin
    Exit;
  end;
  mLabels := nil;
  for mIndex := 0 to mSet.ChildCount - 1 do
  begin
    mLabels := mLabels + [mSet[mIndex]];
  end;
  Labels(mParam, mLabels, ANode.StartPos.Line, False);
end;

procedure TCollector.TextVariants;
var
  mParam, mBase: Integer;
  mHits: TArray<string>;
  mValue: string;
begin
  for mParam := 0 to High(Found.Parameters) do
  begin
    mHits := TextHits[mParam];
    if mHits = nil then
    begin
      Continue;
    end;
    mBase := BaseHit(mHits);
    mValue := OtherCase(mHits[mBase]);
    if (mValue <> '') and TextInsensitive[mParam][mBase] then
    begin
      // Ohne Groß-/Kleinschreibung verglichen: die andere Schreibung ist auch ein Treffer und ersetzt ihn.
      ReplaceValue(mParam, mHits[mBase], mValue, Reason(TBoundaryText.OtherCase, QuotedStr(mHits[mBase])));
    end
    else if mValue <> '' then
    begin
      Add(mParam, mValue, Reason(TBoundaryText.OtherCase, QuotedStr(mHits[mBase])), -1);
    end;
    Add(mParam, mHits[mBase] + ' ', Reason(TBoundaryText.NearMiss, QuotedStr(mHits[mBase])), -1);
    mValue := cNoMatch;
    while MatchText(mValue, mHits) do
    begin
      mValue := mValue + cNoMatch;
    end;
    Add(mParam, mValue, cTexts[TBoundaryText.NoMatch].Text, -1);
  end;
end;

procedure TCollector.ReplaceValue(AParam: Integer; const AOld, ANew, AReason: string);
var
  mCase: Integer;
begin
  for mCase := 0 to High(Found.Cases) do
  begin
    if (Found.Cases[mCase].Parameter = AParam) and (Found.Cases[mCase].Value = AOld) then
    begin
      Found.Cases[mCase].Value := ANew;
      Found.Cases[mCase].Reason := AReason;
    end;
  end;
end;

procedure TCollector.LogicalUse(ANode: TSyntaxNode);
var
  mParam: Integer;
begin
  mParam := ParamOf(ANode);
  if (mParam < 0) or (Found.Parameters[mParam].Kind <> TBoundaryKind.Logical) or not InCondition(ANode) then
  begin
    Exit;
  end;
  Add(mParam, 'True', Reason(TBoundaryText.LogicalTrue, Found.Parameters[mParam].Name), ANode.StartPos.Line);
  Add(mParam, 'False', Reason(TBoundaryText.LogicalFalse, Found.Parameters[mParam].Name), ANode.StartPos.Line);
end;

procedure TCollector.Neutrals;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Found.Parameters) do
  begin
    case Found.Parameters[mIndex].Kind of
      TBoundaryKind.Ordinal, TBoundaryKind.Float:
        Found.Parameters[mIndex].Neutral := '0';
      TBoundaryKind.Logical:
        Found.Parameters[mIndex].Neutral := 'False';
      TBoundaryKind.Reference:
        Found.Parameters[mIndex].Neutral := 'nil';
      TBoundaryKind.Enum:
        Found.Parameters[mIndex].Neutral := EnumNeutral(mIndex);
    else
      Found.Parameters[mIndex].Neutral := '';
    end;
  end;
end;

function TCollector.EnumNeutral(AParam: Integer): string;
var
  mCase: TBoundaryCase;
begin
  if Found.Parameters[AParam].Members <> nil then
  begin
    Exit(Found.Parameters[AParam].Members[0]);
  end;
  // Ohne Typ in der Unit: der erste genannte Wert.
  for mCase in Found.Cases do
  begin
    if mCase.Parameter = AParam then
    begin
      Exit(mCase.Value);
    end;
  end;
  Result := '';
end;

/// <summary>Name nach der Konvention eines Interfaces (IKunde)?</summary>
function IsInterfaceName(const AName: string): Boolean;
begin
  Result := (Length(AName) > 1) and (AName[1] = 'I') and CharInSet(AName[2], ['A'..'Z']);
end;

{ TBoundaryCases }

class function TBoundaryCases.KindOf(const ATypeName: string): TBoundaryKind;
var
  mName: string;
begin
  mName := LowerCase(BareName(ATypeName));
  if MatchStr(mName, ['string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'rawbytestring',
    'utf8string', 'char', 'widechar', 'ansichar', 'tfilename']) then
  begin
    Result := TBoundaryKind.Text;
  end
  else if MatchStr(mName, ['integer', 'cardinal', 'int64', 'uint64', 'byte', 'word', 'shortint', 'smallint',
    'longint', 'longword', 'nativeint', 'nativeuint', 'int8', 'int16', 'int32', 'uint8', 'uint16', 'uint32',
    'dword', 'fixedint', 'fixeduint']) then
  begin
    Result := TBoundaryKind.Ordinal;
  end
  else if MatchStr(mName, ['double', 'single', 'extended', 'currency', 'real', 'tdatetime', 'tdate', 'ttime']) then
  begin
    Result := TBoundaryKind.Float;
  end
  else if MatchStr(mName, ['boolean', 'bytebool', 'wordbool', 'longbool']) then
  begin
    Result := TBoundaryKind.Logical;
  end
  else if MatchStr(mName, ['tobject', 'pointer', 'iinterface', 'iunknown', 'tcomponent', 'tstrings',
    'tstringlist', 'tstream']) or IsInterfaceName(BareName(ATypeName)) then
  begin
    Result := TBoundaryKind.Reference;
  end
  else
  begin
    Result := TBoundaryKind.Unknown;
  end;
end;

/// <summary>Werte des Aufzählungstyps AEnum.</summary>
function EnumNames(AEnum: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AEnum.ChildCount - 1 do
  begin
    if AEnum[mIndex].Kind = TSyntaxKind.Identifier then
    begin
      Result := Result + [AEnum[mIndex].Name];
    end;
  end;
end;

type
  /// <summary>Konstanten und Aufzählungen einer Unit.</summary>
  TUnitConstants = record
    Names, EnumTypes: TArray<string>;
    Values: TArray<TSyntaxNode>;
    EnumMembers: TArray<TArray<string>>;
    procedure Take(ANode: TSyntaxNode);
  end;

procedure TUnitConstants.Take(ANode: TSyntaxNode);
var
  mEnum: TSyntaxNode;
  mNames: TArray<string>;
begin
  if ANode.Kind = TSyntaxKind.ConstDecl then
  begin
    Names := Names + [ANode.Name];
    SetLength(Values, Length(Names));
    if ANode.ChildCount > 0 then
    begin
      Values[High(Values)] := ANode[ANode.ChildCount - 1];
    end;
    Exit;
  end;
  mEnum := nil;
  if ANode.Kind = TSyntaxKind.TypeDecl then
  begin
    mEnum := ANode.FindChild(TSyntaxKind.EnumType);
  end;
  if mEnum <> nil then
  begin
    mNames := EnumNames(mEnum);
    EnumTypes := EnumTypes + [ANode.Name];
    EnumMembers := EnumMembers + [mNames];
    Names := Names + mNames;
    SetLength(Values, Length(Names));
  end;
end;

/// <summary>Konstanten und Aufzählungen der Unit: Namen aller Konstanten und Werte, je Aufzählungstyp seine
/// Werte.</summary>
function UnitConstants(ARoot: TSyntaxNode): TUnitConstants;
var
  mFound: TUnitConstants;
begin
  mFound := Default(TUnitConstants);
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.RoutineHeader]);
      mFound.Take(ANode);
    end);
  Result := mFound;
end;

/// <summary>Trägt Typ und Art des Parameters AParam in AEntry ein; var- und out-Parameter und solche ohne Typ
/// bleiben Unknown.</summary>
procedure ParameterType(AParam: TSyntaxNode; const AUnit: TUnitConstants; var AEntry: TBoundaryParameter);
var
  mType: TSyntaxNode;
  mEnum: Integer;
begin
  mType := AParam.FindChild(TSyntaxKind.TypeReference);
  if (mType = nil) or (AParam.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) then
  begin
    Exit;
  end;
  AEntry.TypeName := mType.Name;
  AEntry.Kind := TBoundaryCases.KindOf(mType.Name);
  mEnum := IndexText(BareName(mType.Name), AUnit.EnumTypes);
  if mEnum >= 0 then
  begin
    AEntry.Kind := TBoundaryKind.Enum;
    AEntry.Members := AUnit.EnumMembers[mEnum];
  end;
end;

/// <summary>Parameter des Kopfs AHeader mit Art.</summary>
function ParametersOf(AHeader: TSyntaxNode; const AUnit: TUnitConstants): TArray<TBoundaryParameter>;
var
  mParams, mParam: TSyntaxNode;
  mIndex: Integer;
  mName: string;
  mEntry: TBoundaryParameter;
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
    mEntry := Default(TBoundaryParameter);
    ParameterType(mParam, AUnit, mEntry);
    for mName in mParam.Name.Split([',']) do
    begin
      mEntry.Name := Trim(mName);
      Result := Result + [mEntry];
    end;
  end;
end;

function IsParameter(const ACollector: TCollector; const AName: string): Boolean;
var
  mParam: TBoundaryParameter;
begin
  for mParam in ACollector.Found.Parameters do
  begin
    if SameText(mParam.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Lokale Kopien m := AParam: Variablen, denen in ABody genau einmal und nur ein Parameter zugewiesen
/// wird.</summary>
procedure FindAliases(var ACollector: TCollector; ABody: TSyntaxNode);
var
  mTargets: TArray<string>;
  mCounts, mParams: TArray<Integer>;
  mIndex: Integer;
  mCollector: ^TCollector;
begin
  mTargets := nil;
  mCounts := nil;
  mParams := nil;
  mCollector := @ACollector;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mAt: Integer;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.AssignStatement) or (ANode.ChildCount <> 2) or
        (ANode[0].Kind <> TSyntaxKind.Identifier) then
      begin
        Exit;
      end;
      mAt := IndexText(ANode[0].Name, mTargets);
      if mAt < 0 then
      begin
        mTargets := mTargets + [ANode[0].Name];
        mCounts := mCounts + [0];
        mParams := mParams + [mCollector^.ParamOf(ANode[1])];
        mAt := High(mTargets);
      end;
      mCounts[mAt] := mCounts[mAt] + 1;
    end);
  for mIndex := 0 to High(mTargets) do
  begin
    if (mCounts[mIndex] = 1) and (mParams[mIndex] >= 0) and not IsParameter(ACollector, mTargets[mIndex]) then
    begin
      ACollector.AliasNames := ACollector.AliasNames + [mTargets[mIndex]];
      ACollector.AliasParams := ACollector.AliasParams + [mParams[mIndex]];
    end;
  end;
end;

procedure TCollector.Visit(ANode: TSyntaxNode);
begin
  case ANode.Kind of
    TSyntaxKind.BinaryExpr:
      if (ANode.ChildCount = 2) and MatchStr(ANode.Name, ['=', '<>', '<', '<=', '>', '>=']) then
      begin
        Comparison(ANode);
      end
      else if (ANode.ChildCount = 2) and SameText(ANode.Name, 'in') then
      begin
        SetMembership(ANode);
      end;
    TSyntaxKind.Call:
      CallCondition(ANode);
    TSyntaxKind.CaseStatement:
      CaseStatement(ANode);
    TSyntaxKind.Identifier:
      LogicalUse(ANode);
  end;
end;

/// <summary>Knoten in ABody, die Bedingungen tragen können.</summary>
function ConditionNodes(ABody: TSyntaxNode): TArray<TSyntaxNode>;
var
  mNodes: TArray<TSyntaxNode>;
begin
  mNodes := nil;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if ANode.Kind in [TSyntaxKind.BinaryExpr, TSyntaxKind.Call, TSyntaxKind.CaseStatement,
        TSyntaxKind.Identifier] then
      begin
        mNodes := mNodes + [ANode];
      end;
    end);
  Result := mNodes;
end;

/// <summary>Sammelt die Fälle der Routine mit Kopf AHeader und Rumpf ABody.</summary>
function Collect(ATree: TSyntaxTree; const ARoutine: string; AHeader, ABody: TSyntaxNode): TBoundaryResult;
var
  mCollector: TCollector;
  mUnit: TUnitConstants;
  mNode: TSyntaxNode;
begin
  mCollector := Default(TCollector);
  mUnit := UnitConstants(ATree.Root);
  mCollector.Constants := mUnit.Names;
  mCollector.ConstValues := mUnit.Values;
  mCollector.Found.Routine := ARoutine;
  mCollector.Found.Parameters := ParametersOf(AHeader, mUnit);
  SetLength(mCollector.TextHits, Length(mCollector.Found.Parameters));
  SetLength(mCollector.TextInsensitive, Length(mCollector.Found.Parameters));
  FindAliases(mCollector, ABody);
  for mNode in ConditionNodes(ABody) do
  begin
    mCollector.Visit(mNode);
  end;
  mCollector.TextVariants;
  mCollector.Neutrals;
  Result := mCollector.Found;
end;

class function TBoundaryCases.Find(ATree: TSyntaxTree; ARoutine: TSyntaxNode; AMax: Integer): TBoundaryResult;
var
  mHeader, mBody: TSyntaxNode;
begin
  Result := Default(TBoundaryResult);
  if (ATree = nil) or (ARoutine = nil) or (ARoutine.Kind <> TSyntaxKind.RoutineDecl) then
  begin
    Exit;
  end;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mBody := ARoutine.FindChild(TSyntaxKind.Block);
  Result.Routine := ARoutine.Name;
  if (mHeader = nil) or (mBody = nil) then
  begin
    Exit;
  end;
  Result := Collect(ATree, ARoutine.Name, mHeader, mBody);
  if (AMax > 0) and (Length(Result.Cases) > AMax) then
  begin
    SetLength(Result.Cases, AMax);
    Result.Truncated := True;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.BoundaryCases', cTexts);

end.
