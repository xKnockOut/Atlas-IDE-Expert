unit Atlas.Common.Rules.Builtin.Generics;

// Regeln für Generics (#909, Gruppe Compiler vorab):
//   generic-constraint-violated  Ein Typargument erfüllt die Einschränkung
//                                seines Typparameters nicht (#1028): class
//                                (E2511), record (E2512), constructor (E2513),
//                                Interface (E2514) oder Basisklasse (E2515);
//                                außerdem T.Create ohne constructor-Einschränkung
//                                (E2568) und Methodenaufrufe auf Werten eines
//                                Typparameters ohne jede Einschränkung (E2571).
//   generic-inference-failed     Ein Aufruf einer generischen Methode ohne
//                                Typargumente, deren Typparameter sich aus den
//                                Argumenten nicht ableiten lassen (#1376):
//                                Typparameter in keinem Parameter (E2531) oder
//                                Argumente verschiedener Art (Zahl,
//                                Zeichenkette, Boolean) für Parameter vom Typ
//                                desselben Typparameters (E2532).
//
// Typargumente stehen im Baum als GenericArgs unter einer TypeReference oder
// einem MemberAccess (TFabrik<Integer>.Create). Den generischen Typ löst
// TNameResolver.ResolveTypeTextFrom samt Zahl der Typparameter auf, die
// Einschränkungen liest die Regel aus seiner Signatur ("TFabrik<T: class> =
// class"). Gemeldet wird nur, was sicher feststeht: Argumente, die selbst
// Typparameter sind, Aliase und Typen mit abgebrochener Vorfahrenkette bleiben
// still. Rümpfe der Methoden generischer Typen dieser Datei prüft die Regel auf
// T.Create und V.Methode mit V vom Typ T.
//
// Korrektur bei E2568 und E2571 für Typparameter dieser Datei, die allein in
// ihrer Gruppe stehen: die Einschränkung ergänzen (T: class, constructor bzw.
// T: class).
//
// generic-inference-failed löst den Aufruf mit TNameResolver.CallCandidates
// auf und liest die eigenen Typparameter und Parameter aus dem Kopf der
// Deklaration. E2531 nur, wenn jede Überladung einen Typparameter hat, der in
// keinem Parametertyp vorkommt; als Anweisung, Aufruf mit Klammern oder rechte
// Seite einer Zuweisung an einen Wert bekannten, nicht prozeduralen Typs.
// E2532 nur bei genau einer Routine ohne overload und Parametern, deren Typ
// genau der Typparameter ist; Argumente unbekannten Typs (Variant, Klassen,
// Ausdrücke) und Zahlen verschiedener Breite halten die Regel still. Wie
// argument-count-mismatch schweigt sie bei bedingten Deklarationen und Namen,
// die ein unbekannter Vorfahr verdecken kann.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cGenericConstraintViolatedRuleId = 'generic-constraint-violated';
  cGenericInferenceFailedRuleId = 'generic-inference-failed';

type
  /// <summary>Ein Typparameter mit seinen Einschränkungen aus "&lt;T: class, constructor; U&gt;".</summary>
  TGenericParam = record
    Name: string;
    /// <summary>class, record, constructor in Kleinschreibung oder Typnamen wie geschrieben.</summary>
    Constraints: TArray<string>;
    /// <summary>Steht allein in seiner Gruppe (nicht "K, V: class").</summary>
    Single: Boolean;
    /// <summary>Offset (ab 0, relativ zum Anfang des gelesenen Texts) hinter dem letzten Zeichen der Gruppe.
    /// </summary>
    GroupEnd: Integer;
    function Has(const AConstraint: string): Boolean;
    /// <summary>Einschränkungen, die Typen nennen (weder class noch record noch constructor).</summary>
    function TypeConstraints: TArray<string>;
  end;

  TGenericConstraintViolatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Typparameter aus dem Text ab dem ersten "&lt;" bis zum passenden "&gt;"; leer ohne "&lt;".
    /// </summary>
    class function ParseParams(const AText: string): TArray<TGenericParam>; static;
  end;

  TGenericInferenceFailedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Eigene Typparameter der Routine AName im Kopf AHeader ("class function TA.Neu&lt;T&gt;: T"
    /// ergibt T, "procedure TListe&lt;T&gt;.Add(A: T)" nichts); leer ohne.</summary>
    class function OwnTypeParams(const AHeader, AName: string): TArray<string>; static;
  end;

procedure RegisterGenericRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Calls,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TGenericsText = (ConstraintTitle, NoClassType, NoValueType, NoDefaultConstructor, NotSupported, NotCompatible,
    AddConstraint, NoConstructorConstraint, NoClassConstraint, InferTitle, ExplicitTypeArgs, MixedKinds, Number,
    StringFamily, UnknownFamily, LogicalFamily);

const
  cTexts: array[TGenericsText] of TAtlasText = (
    (De: 'Typargument verletzt eine Einschränkung'; En: 'Type argument violates a constraint'),
    (De: '%s ist kein Klassentyp; %s von %s verlangt class (wie E2511).';
     En: '%s is not a class type; %s of %s requires class (like E2511).'),
    (De: '%s ist kein Werttyp; %s von %s verlangt record (wie E2512).';
     En: '%s is not a value type; %s of %s requires record (like E2512).'),
    (De: '%s hat keinen parameterlosen Konstruktor; %s von %s verlangt constructor (wie E2513).';
     En: '%s has no parameterless constructor; %s of %s requires constructor (like E2513).'),
    (De: '%s unterstützt %s nicht; %s von %s verlangt %s (wie E2514).';
     En: '%s does not support %s; %s of %s requires %s (like E2514).'),
    (De: '%s ist nicht mit %s kompatibel; %s von %s verlangt %s (wie E2515).';
     En: '%s is not compatible with %s; %s of %s requires %s (like E2515).'),
    (De: 'Einschränkung ergänzen'; En: 'Add constraint'),
    (De: '%s hat keine constructor-Einschränkung; %s.Create ist nicht erlaubt (wie E2568).';
     En: '%s has no constructor constraint; %s.Create is not allowed (like E2568).'),
    (De: '%s hat keine class- oder Interface-Einschränkung; %s.%s ist nicht erlaubt (wie E2571).';
     En: '%s has no class or interface constraint; %s.%s is not allowed (like E2571).'),
    (De: 'Typargumente lassen sich nicht ableiten'; En: 'Type arguments cannot be inferred'),
    (De: '%s braucht ausdrückliche Typargumente (%s<…>): %s kommt in keinem Parameter vor und lässt sich nicht ' +
      'ableiten (wie E2531).';
     En: '%s needs explicit type arguments (%s<…>): %s occurs in no parameter and cannot be inferred (like E2531).'),
    (De: '%s von %s lässt sich nicht ableiten: Die Argumente sind verschiedener Art (%s und %s); Typargument ' +
      'ausdrücklich angeben, z. B. %s<…> (wie E2532).';
     En: '%s of %s cannot be inferred: the arguments are of different kinds (%s and %s); specify the type argument ' +
      'explicitly, e.g. %s<…> (like E2532).'),
    (De: 'Zahl'; En: 'number'),
    (De: 'Zeichenkette'; En: 'string'),
    (De: '?'; En: '?'),
    (De: 'Boolean'; En: 'Boolean'));

{$SCOPEDENUMS OFF}

const
  cKeywords: array[0..2] of string = ('class', 'record', 'constructor');
  cManagedBuiltins: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'Variant', 'OleVariant');

type
  /// <summary>Art eines Typarguments, soweit sie sicher feststeht.</summary>
  TArgumentKind = (Unknown, ClassArg, ValueArg, ManagedArg, InterfaceArg);

{ TGenericParam }

function TGenericParam.Has(const AConstraint: string): Boolean;
begin
  Result := MatchText(AConstraint, Constraints);
end;

function TGenericParam.TypeConstraints: TArray<string>;
var
  mConstraint: string;
begin
  Result := nil;
  for mConstraint in Constraints do
  begin
    if not MatchText(mConstraint, cKeywords) then
    begin
      Result := Result + [mConstraint];
    end;
  end;
end;

{ TGenericConstraintViolatedRule }

function TGenericConstraintViolatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cGenericConstraintViolatedRuleId, TRuleSeverity.Error,
    cTexts[TGenericsText.ConstraintTitle].Text);
end;

/// <summary>Einschränkungen einer Gruppe, an Kommas auf oberster Ebene getrennt (IComparer&lt;T, U&gt; bleibt
/// ganz); class, record und constructor klein geschrieben.</summary>
function SplitConstraints(const AText: string): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
  mPart: string;
begin
  Result := nil;
  mDepth := 0;
  mStart := 1;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or ((AText[mIndex] = ',') and (mDepth = 0)) then
    begin
      mPart := Trim(Copy(AText, mStart, mIndex - mStart));
      if MatchText(mPart, cKeywords) then
      begin
        mPart := LowerCase(mPart);
      end;
      if mPart <> '' then
      begin
        Result := Result + [mPart];
      end;
      mStart := mIndex + 1;
    end
    else if AText[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = '>' then
    begin
      Dec(mDepth);
    end;
  end;
end;

/// <summary>Namen der Gruppe "T, U: Einschränkungen" ohne leere; AConstraints: der Text hinter dem
/// Doppelpunkt.</summary>
function GroupNames(const AGroup: string; out AConstraints: string): TArray<string>;
var
  mColon: Integer;
  mNames, mPart: string;
begin
  mColon := Pos(':', AGroup);
  mNames := AGroup;
  AConstraints := '';
  if mColon > 0 then
  begin
    mNames := Copy(AGroup, 1, mColon - 1);
    AConstraints := Copy(AGroup, mColon + 1, MaxInt);
  end;
  Result := nil;
  for mPart in mNames.Split([',']) do
  begin
    if Trim(mPart) <> '' then
    begin
      Result := Result + [Trim(mPart)];
    end;
  end;
end;

class function TGenericConstraintViolatedRule.ParseParams(const AText: string): TArray<TGenericParam>;
var
  mPosition, mDepth, mGroupStart: Integer;

  procedure AddGroup(AEnd: Integer);
  var
    mConstraintText, mName: string;
    mInner: Integer;
    mNames, mConstraints: TArray<string>;
    mParam: TGenericParam;
  begin
    mNames := GroupNames(Copy(AText, mGroupStart, AEnd - mGroupStart), mConstraintText);
    mConstraints := SplitConstraints(mConstraintText);
    // Hinter dem letzten Zeichen der Gruppe, ohne folgende Leerzeichen.
    mInner := AEnd - 1;
    while (mInner > mGroupStart) and CharInSet(AText[mInner], [' ', #9, #10, #13]) do
    begin
      Dec(mInner);
    end;
    for mName in mNames do
    begin
      mParam := Default(TGenericParam);
      mParam.Name := mName;
      mParam.Constraints := mConstraints;
      mParam.Single := Length(mNames) = 1;
      mParam.GroupEnd := mInner;
      Result := Result + [mParam];
    end;
  end;

begin
  Result := nil;
  mPosition := Pos('<', AText);
  if mPosition = 0 then
  begin
    Exit;
  end;
  mDepth := 0;
  mGroupStart := mPosition + 1;
  while mPosition <= Length(AText) do
  begin
    case AText[mPosition] of
      '<':
        Inc(mDepth);
      '>':
        begin
          Dec(mDepth);
          if mDepth = 0 then
          begin
            AddGroup(mPosition);
            Exit;
          end;
        end;
      ';':
        if mDepth = 1 then
        begin
          AddGroup(mPosition);
          mGroupStart := mPosition + 1;
        end;
    end;
    Inc(mPosition);
  end;
end;

/// <summary>Dateiname für den Resolver: die Datei, sonst der relative Pfad, sonst der Unitname mit .pas.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

procedure TGenericConstraintViolatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mLocal: TUnitIndex;
  // Namen aller Typparameter der Datei: solche Argumente bleiben ungeprüft.
  mParamNames: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function RangeOf(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  function BareName(const AName: string): string;
  begin
    Result := AName;
    if Pos('<', Result) > 0 then
    begin
      Result := Copy(Result, 1, Pos('<', Result) - 1);
    end;
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;

  function SameType(const A, B: TResolvedSymbol): Boolean;
  begin
    Result := SameText(A.Name, B.Name) and SameText(A.Container, B.Container) and SameText(A.UnitName, B.UnitName);
  end;

  function KindOf(const AType: TResolvedSymbol): TArgumentKind;
  begin
    Result := TArgumentKind.Unknown;
    if AType.Builtin then
    begin
      if MatchText(AType.Name, cManagedBuiltins) then
      begin
        Result := TArgumentKind.ManagedArg;
      end
      else
      begin
        Result := TArgumentKind.ValueArg;
      end;
      Exit;
    end;
    case AType.SymbolKind of
      TIndexSymbolKind.ClassType:
        Result := TArgumentKind.ClassArg;
      TIndexSymbolKind.RecordType, TIndexSymbolKind.EnumType:
        Result := TArgumentKind.ValueArg;
      TIndexSymbolKind.InterfaceType:
        Result := TArgumentKind.InterfaceArg;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  /// <summary>Erbt die Klasse bzw. das Interface AType von ATarget (oder ist es)? False mit AKnown = False, wenn
  /// die Kette abbricht.</summary>
  function Descends(const AType, ATarget: TResolvedSymbol; out AKnown: Boolean): Boolean;
  var
    mCurrent, mNext: TResolvedSymbol;
    mDepth: Integer;
  begin
    AKnown := True;
    mCurrent := AType;
    for mDepth := 0 to 64 do
    begin
      if SameType(mCurrent, ATarget) then
      begin
        Exit(True);
      end;
      if (Length(mCurrent.Ancestors) = 0) or SameText(BareName(mCurrent.Ancestors[0]), 'TObject') or
        SameText(BareName(mCurrent.Ancestors[0]), 'IInterface') then
      begin
        Exit(SameText(ATarget.Name, 'TObject') or SameText(ATarget.Name, 'IInterface') or
          SameText(ATarget.Name, 'IUnknown'));
      end;
      if not mResolver.AncestorOf(mCurrent, mNext) then
      begin
        Break;
      end;
      mCurrent := mNext;
    end;
    AKnown := False;
    Result := False;
  end;

  /// <summary>Unterstützt eine der Interface-Listen von AType selbst (ohne Vorfahren) ATarget? AStop: das
  /// Ergebnis steht fest, gefunden oder Kette abgebrochen.</summary>
  function ListedSupports(const AType, ATarget: TResolvedSymbol; out AStop: Boolean): Boolean;
  var
    mIndex: Integer;
    mInterface: TResolvedSymbol;
    mKnown: Boolean;
  begin
    Result := False;
    AStop := False;
    mIndex := 1;
    while not AStop and (mIndex <= High(AType.Ancestors)) do
    begin
      AStop := not mResolver.ResolveTypeTextFrom(mLocal, AType.Ancestors[mIndex], mInterface) or
        (mInterface.SymbolKind <> TIndexSymbolKind.InterfaceType);
      if not AStop then
      begin
        Result := Descends(mInterface, ATarget, mKnown);
        AStop := Result or not mKnown;
      end;
      Inc(mIndex);
    end;
  end;

  /// <summary>Unterstützt die Klasse AType das Interface ATarget (über die Interface-Listen der ganzen Kette und
  /// deren Vorfahren)? AKnown = False, wenn eine Kette abbricht.</summary>
  function Supports(const AType, ATarget: TResolvedSymbol; out AKnown: Boolean): Boolean;
  var
    mCurrent, mNext: TResolvedSymbol;
    mDepth: Integer;
    mStop: Boolean;
  begin
    AKnown := False;
    mCurrent := AType;
    for mDepth := 0 to 64 do
    begin
      Result := ListedSupports(mCurrent, ATarget, mStop);
      if mStop then
      begin
        AKnown := Result;
        Exit;
      end;
      if (Length(mCurrent.Ancestors) = 0) or SameText(BareName(mCurrent.Ancestors[0]), 'TObject') then
      begin
        AKnown := True;
        Exit;
      end;
      if not mResolver.AncestorOf(mCurrent, mNext) then
      begin
        Exit;
      end;
      mCurrent := mNext;
    end;
  end;

  /// <summary>Verletzt ein Typargument der Art AKind die Einschränkungen class, record oder constructor von
  /// AParam? Dann die Meldung, sonst ''.</summary>
  function KeywordViolation(const AGeneric: string; const AParam: TGenericParam; const AArgText: string;
    AKind: TArgumentKind): string;
  begin
    if AParam.Has('class') and (AKind <> TArgumentKind.ClassArg) then
    begin
      Result := cTexts[TGenericsText.NoClassType].Fmt([AArgText, AParam.Name,
        AGeneric]);
    end
    else if AParam.Has('record') and (AKind <> TArgumentKind.ValueArg) then
    begin
      Result := cTexts[TGenericsText.NoValueType].Fmt([AArgText, AParam.Name,
        AGeneric]);
    end
    else if AParam.Has('constructor') and not AParam.Has('record') and (AKind <> TArgumentKind.ClassArg) then
    begin
      Result := cTexts[TGenericsText.NoDefaultConstructor].Fmt([AArgText, AParam.Name, AGeneric]);
    end
    else
    begin
      Result := '';
    end;
  end;

  /// <summary>Erfüllt AArg (Art AKind) die Klassen- bzw. Interface-Einschränkung ATarget sicher nicht?</summary>
  function MissesTarget(const AArg: TResolvedSymbol; AKind: TArgumentKind; const ATarget: TResolvedSymbol): Boolean;
  var
    mKnown, mMissing: Boolean;
  begin
    mKnown := True;
    mMissing := True;
    if ATarget.SymbolKind = TIndexSymbolKind.InterfaceType then
    begin
      if AKind = TArgumentKind.ClassArg then
      begin
        mMissing := not Supports(AArg, ATarget, mKnown);
      end
      else if AKind = TArgumentKind.InterfaceArg then
      begin
        mMissing := not Descends(AArg, ATarget, mKnown);
      end;
    end
    else if AKind = TArgumentKind.ClassArg then
    begin
      mMissing := not Descends(AArg, ATarget, mKnown);
    end;
    Result := mMissing and mKnown;
  end;

  /// <summary>Meldung für die erste Typ-Einschränkung von AParam, die AArg (Art AKind) nicht erfüllt; ''
  /// sonst.</summary>
  function TypeViolation(const AGeneric: string; const AParam: TGenericParam; const AArgText: string;
    const AArg: TResolvedSymbol; AKind: TArgumentKind): string;
  var
    mConstraint: string;
    mTarget: TResolvedSymbol;
  begin
    Result := '';
    for mConstraint in AParam.TypeConstraints do
    begin
      if (Result <> '') or not mResolver.ResolveTypeTextFrom(mLocal, mConstraint, mTarget) or
        not (mTarget.SymbolKind in [TIndexSymbolKind.InterfaceType, TIndexSymbolKind.ClassType]) or
        not MissesTarget(AArg, AKind, mTarget) then
      begin
        Continue;
      end;
      if mTarget.SymbolKind = TIndexSymbolKind.InterfaceType then
      begin
        Result := cTexts[TGenericsText.NotSupported].Fmt([AArgText, mConstraint,
          AParam.Name, AGeneric, mConstraint]);
      end
      else
      begin
        Result := cTexts[TGenericsText.NotCompatible].Fmt([AArgText,
          mConstraint, AParam.Name, AGeneric, mConstraint]);
      end;
    end;
  end;

  /// <summary>Meldung für ein Typargument, das AParam des Typs AGeneric nicht erfüllt; '' wenn es passt oder
  /// unklar ist.</summary>
  function Violation(const AGeneric: string; const AParam: TGenericParam; const AArgText: string;
    const AArg: TResolvedSymbol): string;
  var
    mKind: TArgumentKind;
  begin
    Result := '';
    mKind := KindOf(AArg);
    if mKind = TArgumentKind.Unknown then
    begin
      Exit;
    end;
    Result := KeywordViolation(AGeneric, AParam, AArgText, mKind);
    if Result = '' then
    begin
      Result := TypeViolation(AGeneric, AParam, AArgText, AArg, mKind);
    end;
  end;

  /// <summary>Prüft das Typargument AArg (Text AArgText) gegen AParam des Typs AGeneric.</summary>
  procedure CheckArgument(AArg: TSyntaxNode; const AGeneric: string; const AParam: TGenericParam;
    const AArgText: string);
  var
    mArg: TResolvedSymbol;
    mMessage: string;
  begin
    if (AParam.Constraints = nil) or (AArg.Kind <> TSyntaxKind.TypeReference) or
      mParamNames.ContainsKey(LowerCase(BareName(AArgText))) or not mResolver.ResolveTypeTextFrom(mLocal, AArgText,
      mArg) then
    begin
      Exit;
    end;
    mMessage := Violation(AGeneric, AParam, AArgText, mArg);
    if mMessage <> '' then
    begin
      AReport.Add(RangeOf(AArg), mMessage, TRuleConfidence.High);
    end;
  end;

  function ArgumentTexts(AArgs: TSyntaxNode): TArray<string>;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 0 to AArgs.ChildCount - 1 do
    begin
      Result := Result + [Trim(NodeText(AArgs[mIndex]))];
    end;
  end;

  procedure CheckArguments(AArgs: TSyntaxNode);
  var
    mOwner: TSyntaxNode;
    mBase: string;
    mArgs: TArray<string>;
    mGeneric: TResolvedSymbol;
    mParams: TArray<TGenericParam>;
    mIndex: Integer;
  begin
    mOwner := AArgs.Parent;
    if (mOwner = nil) or not (mOwner.Kind in [TSyntaxKind.TypeReference, TSyntaxKind.MemberAccess]) then
    begin
      Exit;
    end;
    mBase := Trim(Copy(AContext.Text, mOwner.StartOffset + 1, AArgs.StartOffset - mOwner.StartOffset));
    mArgs := ArgumentTexts(AArgs);
    if (mBase = '') or (mArgs = nil) or not mResolver.ResolveTypeTextFrom(mLocal, mBase + '<' +
      string.Join(',', mArgs) + '>', mGeneric) or not mGeneric.IsType then
    begin
      Exit;
    end;
    mParams := ParseParams(mGeneric.Signature);
    if Length(mParams) <> Length(mArgs) then
    begin
      Exit;
    end;
    for mIndex := 0 to High(mArgs) do
    begin
      CheckArgument(AArgs[mIndex], mGeneric.Name, mParams[mIndex], mArgs[mIndex]);
    end;
  end;

  /// <summary>Korrektur, die an die Gruppe von AParam (Typparameter aus der Datei, Text ab AStart) AText hängt.
  /// </summary>
  function ConstraintFix(const AParam: TGenericParam; AStart: Integer; const AText: string;
    out AFix: TRuleFix): Boolean;
  var
    mOffset: Integer;
  begin
    Result := AParam.Single;
    if not Result then
    begin
      Exit;
    end;
    mOffset := AStart + AParam.GroupEnd;
    AFix := TRuleFix.Create(cTexts[TGenericsText.AddConstraint].Text, [TRuleEdit.Create(TRuleDerived.OffsetRange(mCache,
      AContext,
      mOffset, mOffset), AText)]);
  end;

  /// <summary>Typparameter des generischen Typs bzw. der Methode im Knoten ANode (TypeDecl oder RoutineHeader)
  /// samt Offset des Texts, aus dem sie gelesen wurden.</summary>
  function ParamsOf(ANode: TSyntaxNode; out AStart: Integer): TArray<TGenericParam>;
  var
    mNode: TSyntaxNode;
  begin
    Result := nil;
    AStart := 0;
    mNode := ANode.FindChild(TSyntaxKind.GenericParams);
    if mNode = nil then
    begin
      Exit;
    end;
    AStart := mNode.StartOffset;
    Result := ParseParams(NodeText(mNode));
  end;

  procedure CheckBody(ARoutine: TSyntaxNode; const AParams: TArray<TGenericParam>; const AStarts: TArray<Integer>);

    function FindParam(const AName: string; out AIndex: Integer): Boolean;
    var
      mIndex: Integer;
    begin
      // Typparameter der Methode verdecken die der Klasse: sie stehen hinten.
      for mIndex := High(AParams) downto 0 do
      begin
        if SameText(AParams[mIndex].Name, AName) then
        begin
          AIndex := mIndex;
          Exit(True);
        end;
      end;
      Result := False;
    end;

    // T.Create ohne constructor; eine Basisklasse oder record als Einschränkung lässt die Regel aus.
    procedure CheckCreate(ANode: TSyntaxNode; AIndex: Integer);
    var
      mParam: TGenericParam;
      mFix: TRuleFix;
      mFixes: TArray<TRuleFix>;
      mText: string;
    begin
      mParam := AParams[AIndex];
      if not SameText(ANode.Name, 'Create') or mParam.Has('constructor') or mParam.Has('record') or
        (mParam.TypeConstraints <> nil) then
      begin
        Exit;
      end;
      mFixes := nil;
      mText := ': class, constructor';
      if mParam.Constraints <> nil then
      begin
        mText := ', constructor';
      end;
      if ConstraintFix(mParam, AStarts[AIndex], mText, mFix) then
      begin
        mFixes := [mFix];
      end;
      AReport.Add(RangeOf(ANode), cTexts[TGenericsText.NoConstructorConstraint].Fmt([mParam.Name, mParam.Name]),
        TRuleConfidence.High, mFixes);
    end;

    // X.Mitglied, wenn X einen Typparameter ohne Einschränkung als Typ hat.
    procedure CheckValueMember(ANode, AReceiver: TSyntaxNode);
    var
      mSymbol: TResolvedSymbol;
      mIndex: Integer;
      mFix: TRuleFix;
      mFixes: TArray<TRuleFix>;
    begin
      mSymbol := mResolver.Resolve(AContext.Tree, mFileName, AReceiver.StartPos);
      if not mSymbol.Found or mSymbol.IsType or not FindParam(mSymbol.TypeName, mIndex) or
        (AParams[mIndex].Constraints <> nil) then
      begin
        Exit;
      end;
      mFixes := nil;
      if ConstraintFix(AParams[mIndex], AStarts[mIndex], ': class', mFix) then
      begin
        mFixes := [mFix];
      end;
      AReport.Add(RangeOf(ANode), cTexts[TGenericsText.NoClassConstraint].Fmt([AParams[mIndex].Name, AReceiver.Name,
        ANode.Name]), TRuleConfidence.High, mFixes);
    end;

    procedure CheckMember(ANode: TSyntaxNode);
    var
      mIndex: Integer;
    begin
      if (ANode.Kind <> TSyntaxKind.MemberAccess) or (ANode.ChildCount = 0) or
        (ANode[0].Kind <> TSyntaxKind.Identifier) then
      begin
        Exit;
      end;
      if FindParam(ANode[0].Name, mIndex) then
      begin
        CheckCreate(ANode, mIndex);
      end
      else
      begin
        CheckValueMember(ANode, ANode[0]);
      end;
    end;

    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    procedure Visit(ARoot: TSyntaxNode);
    var
      mPending: TStack<TSyntaxNode>;
      mNode: TSyntaxNode;
      mChild: Integer;
    begin
      mPending := TStack<TSyntaxNode>.Create;
      try
        mPending.Push(ARoot);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          CheckMember(mNode);
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            if mNode[mChild].Kind <> TSyntaxKind.AnonymousMethod then
            begin
              mPending.Push(mNode[mChild]);
            end;
          end;
        end;
      finally
        mPending.Free;
      end;
    end;

  var
    mChild: Integer;
  begin
    for mChild := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[mChild].Kind = TSyntaxKind.Block then
      begin
        Visit(ARoutine[mChild]);
      end;
    end;
  end;

  /// <summary>Methoden generischer Typen dieser Datei: Typparameter von Klasse und Methode, dann der Rumpf.
  /// </summary>
  procedure CheckMethods;
  var
    mTypes: TDictionary<string, TSyntaxNode>;

    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    procedure CollectTypes(ARoot: TSyntaxNode);
    var
      mPending: TStack<TSyntaxNode>;
      mNode: TSyntaxNode;
      mChild: Integer;
    begin
      mPending := TStack<TSyntaxNode>.Create;
      try
        mPending.Push(ARoot);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          if (mNode.Kind = TSyntaxKind.TypeDecl) and (mNode.FindChild(TSyntaxKind.GenericParams) <> nil) then
          begin
            mTypes.AddOrSetValue(LowerCase(mNode.Name), mNode);
          end;
          if mNode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.Block] then
          begin
            Continue;
          end;
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mChild]);
          end;
        end;
      finally
        mPending.Free;
      end;
    end;

    /// <summary>Kopf der Methode AName im Typ ATypeDecl, wenn es genau einen gibt.</summary>
    function MethodHeader(ATypeDecl: TSyntaxNode; const AName: string): TSyntaxNode;
    var
      mBody: TSyntaxNode;
      mIndex: Integer;
    begin
      Result := nil;
      mBody := ATypeDecl.FindChild(TSyntaxKind.ClassType);
      if mBody = nil then
      begin
        mBody := ATypeDecl.FindChild(TSyntaxKind.RecordType);
      end;
      if mBody = nil then
      begin
        Exit;
      end;
      for mIndex := 0 to mBody.ChildCount - 1 do
      begin
        if (mBody[mIndex].Kind = TSyntaxKind.RoutineHeader) and SameText(mBody[mIndex].Name, AName) then
        begin
          if Result <> nil then
          begin
            Exit(nil);
          end;
          Result := mBody[mIndex];
        end;
      end;
    end;

    // Typparameter von Klasse und Methode für die Methode ANode, dann ihr Rumpf.
    procedure CheckMethod(ANode: TSyntaxNode);
    var
      mDot, mStart, mIndex: Integer;
      mTypeDecl, mHeader: TSyntaxNode;
      mParams, mOwn: TArray<TGenericParam>;
      mStarts: TArray<Integer>;
    begin
      mDot := LastDelimiter('.', ANode.Name);
      if (mDot = 0) or not mTypes.TryGetValue(LowerCase(Copy(ANode.Name, 1, mDot - 1)), mTypeDecl) then
      begin
        Exit;
      end;
      mParams := ParamsOf(mTypeDecl, mStart);
      mStarts := nil;
      for mIndex := 0 to High(mParams) do
      begin
        mStarts := mStarts + [mStart];
      end;
      mHeader := MethodHeader(mTypeDecl, Copy(ANode.Name, mDot + 1, MaxInt));
      if mHeader <> nil then
      begin
        mOwn := ParamsOf(mHeader, mStart);
        for mIndex := 0 to High(mOwn) do
        begin
          mStarts := mStarts + [mStart];
        end;
        mParams := mParams + mOwn;
      end;
      if mParams <> nil then
      begin
        CheckBody(ANode, mParams, mStarts);
      end;
    end;

    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    procedure Visit(ARoot: TSyntaxNode);
    var
      mPending: TStack<TSyntaxNode>;
      mNode: TSyntaxNode;
      mChild: Integer;
    begin
      mPending := TStack<TSyntaxNode>.Create;
      try
        mPending.Push(ARoot);
        while mPending.Count > 0 do
        begin
          mNode := mPending.Pop;
          if mNode.Kind = TSyntaxKind.RoutineDecl then
          begin
            CheckMethod(mNode);
            Continue;
          end;
          for mChild := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mChild]);
          end;
        end;
      finally
        mPending.Free;
      end;
    end;

  begin
    mTypes := TDictionary<string, TSyntaxNode>.Create;
    try
      CollectTypes(AContext.Tree.Root);
      if mTypes.Count > 0 then
      begin
        Visit(AContext.Tree.Root);
      end;
    finally
      mTypes.Free;
    end;
  end;

  // Sammelt die Typargument-Listen und die Namen aller Typparameter; True, wenn die Datei Typparameter
  // deklariert.
  function CollectGenerics(out AArgsNodes: TArray<TSyntaxNode>): Boolean;
  var
    mArgs: TArray<TSyntaxNode>;
    mHasParams: Boolean;
  begin
    mArgs := nil;
    mHasParams := False;
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mChild: Integer;
      begin
        if ANode.Kind = TSyntaxKind.GenericArgs then
        begin
          mArgs := mArgs + [ANode];
        end
        else if ANode.Kind = TSyntaxKind.GenericParams then
        begin
          mHasParams := True;
          for mChild := 0 to ANode.ChildCount - 1 do
          begin
            mParamNames.AddOrSetValue(LowerCase(ANode[mChild].Name), True);
          end;
        end;
        Result := True;
      end);
    AArgsNodes := mArgs;
    Result := mHasParams;
  end;

var
  mArgsNodes: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
  mHasParams: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mParamNames := TDictionary<string, Boolean>.Create;
  try
    mHasParams := CollectGenerics(mArgsNodes);
    if (mArgsNodes = nil) and not mHasParams then
    begin
      Exit;
    end;
    mFileName := ResolverFileName(AContext);
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    mCache := TRuleDerived.Open(AContext);
    mResolver := TRuleDerived.Resolver(mCache, AContext);
    mResolver.PinTree(AContext.Tree, mFileName);
    try
      mLocal := mResolver.ExtractedUnit(AContext.Tree, mFileName);
      for mNode in mArgsNodes do
      begin
        CheckArguments(mNode);
      end;
      if mHasParams then
      begin
        CheckMethods;
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mParamNames.Free;
  end;
end;

{ TGenericInferenceFailedRule }

type
  /// <summary>Art eines Arguments für E2532; Unknown, wenn sie nicht sicher feststeht.</summary>
{$SCOPEDENUMS ON}
  TValueFamily = (Unknown, Number, Text, Logical);
{$SCOPEDENUMS OFF}

const
  cNumberTypeNames: array[0..24] of string = ('Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord',
    'Int64', 'UInt64', 'Byte', 'Word', 'NativeInt', 'NativeUInt', 'Int8', 'Int16', 'Int32', 'UInt8', 'UInt16',
    'UInt32', 'Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp', 'Real48');
  cTextTypeNames: array[0..9] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'ShortString', 'UTF8String', 'Char', 'WideChar', 'AnsiChar');
  cLogicalTypeNames: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');
  cFamilyNames: array[TValueFamily] of TGenericsText = (TGenericsText.UnknownFamily, TGenericsText.Number,
    TGenericsText.StringFamily, TGenericsText.LogicalFamily);
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Routine];

function TGenericInferenceFailedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cGenericInferenceFailedRuleId, TRuleSeverity.Error,
    cTexts[TGenericsText.InferTitle].Text);
end;

/// <summary>Steht AName bei AIndex in AHeader als eigenes Wort, dem (nach Leerzeichen) &lt; folgt? Dann dessen
/// Stelle, sonst 0.</summary>
function AngleAfterName(const AHeader, AName: string; AIndex: Integer): Integer;
begin
  Result := 0;
  if not SameText(Copy(AHeader, AIndex, Length(AName)), AName) or ((AIndex > 1) and
    CharInSet(AHeader[AIndex - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '&'])) then
  begin
    Exit;
  end;
  Result := AIndex + Length(AName);
  while (Result <= Length(AHeader)) and CharInSet(AHeader[Result], [' ', #9, #10, #13]) do
  begin
    Inc(Result);
  end;
  if (Result > Length(AHeader)) or (AHeader[Result] <> '<') then
  begin
    Result := 0;
  end;
end;

class function TGenericInferenceFailedRule.OwnTypeParams(const AHeader, AName: string): TArray<string>;
var
  mParams: TArray<TGenericParam>;
  mParam: TGenericParam;
  mIndex, mFound, mAfter, mDepth: Integer;
begin
  Result := nil;
  if AName = '' then
  begin
    Exit;
  end;
  // Letztes Vorkommen von AName vor der Parameterliste, dem (nach Leerzeichen) "<" folgt.
  mFound := 0;
  mDepth := 0;
  mIndex := 1;
  while mIndex <= Length(AHeader) - Length(AName) + 1 do
  begin
    if (mDepth = 0) and CharInSet(AHeader[mIndex], ['(', ':', ';']) then
    begin
      Break;
    end;
    if AHeader[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AHeader[mIndex] = '>' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      mAfter := AngleAfterName(AHeader, AName, mIndex);
      if mAfter > 0 then
      begin
        mFound := mAfter;
      end;
    end;
    Inc(mIndex);
  end;
  if mFound = 0 then
  begin
    Exit;
  end;
  mParams := TGenericConstraintViolatedRule.ParseParams(Copy(AHeader, mFound, MaxInt));
  for mParam in mParams do
  begin
    Result := Result + [mParam.Name];
  end;
end;

/// <summary>Kommt das Wort AWord als Bezeichner in AText vor?</summary>
function HasIdentifier(const AText, AWord: string): Boolean;
var
  mStart, mIndex: Integer;
begin
  Result := False;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_']) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      begin
        Inc(mIndex);
      end;
      if SameText(Copy(AText, mStart, mIndex - mStart), AWord) then
      begin
        Exit(True);
      end;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

/// <summary>Kopf mit "overload" oder "varargs" hinter der Parameterliste?</summary>
function HasOverloadWord(const ATail: string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in ATail.Replace(';', ' ').Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty) do
  begin
    if SameText(mWord, 'overload') or SameText(mWord, 'varargs') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Art des eingebauten Typs AName; Unknown bei anderen.</summary>
function BuiltinFamily(const AName: string): TValueFamily;
begin
  Result := TValueFamily.Unknown;
  if MatchText(AName, cNumberTypeNames) then
  begin
    Result := TValueFamily.Number;
  end
  else if MatchText(AName, cTextTypeNames) then
  begin
    Result := TValueFamily.Text;
  end
  else if MatchText(AName, cLogicalTypeNames) then
  begin
    Result := TValueFamily.Logical;
  end;
end;

procedure TGenericInferenceFailedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mGenericNames: TDictionary<string, Boolean>;

  /// <summary>Kann AName eine generische Routine sein (Kopf mit Typparametern in der Datei oder im Index)?</summary>
  function MayBeGeneric(const AName: string): Boolean;
  begin
    if mGenericNames.TryGetValue(LowerCase(AName), Result) then
    begin
      Exit;
    end;
    Result := (AContext.Index <> nil) and AContext.Index.HasSymbol(AName,
      function(const ASymbol: TIndexSymbol): Boolean
      begin
        Result := (ASymbol.TypeParams <> '') and (ASymbol.Kind in cRoutineKinds);
      end);
    mGenericNames.Add(LowerCase(AName), Result);
  end;

  procedure CollectGenericNames(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mName: string;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.RoutineHeader) and (mNode.FindChild(TSyntaxKind.GenericParams) <> nil) then
        begin
          mName := mNode.Name;
          if LastDelimiter('.', mName) > 0 then
          begin
            mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
          end;
          mGenericNames.AddOrSetValue(LowerCase(mName), True);
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

  /// <summary>Generische Routinen hinter ACallee mit Kopf; False, wenn nicht jede Kandidatin sicher eine
  /// Routine mit Quelltext ist.</summary>
  function Routines(ACallee: TSyntaxNode; out ACandidates: TArray<TResolvedSymbol>): Boolean;
  var
    mCandidate: TResolvedSymbol;
  begin
    Result := False;
    ACandidates := mResolver.CallCandidates(AContext.Tree, mFileName, ACallee);
    if (Length(ACandidates) = 0) or mResolver.MayBeHiddenMember(AContext.Tree, mFileName, ACallee, ACandidates[0]) then
    begin
      Exit;
    end;
    for mCandidate in ACandidates do
    begin
      if mCandidate.IsType or mCandidate.Builtin or not (mCandidate.SymbolKind in cRoutineKinds) or
        (mCandidate.Condition <> '') or (mCandidate.Signature = '') then
      begin
        Exit;
      end;
    end;
    // Überladungen derselben Datei, die der Resolver nicht mitliefert.
    if (Length(ACandidates) = 1) and (Length(ACandidates[0].Overloads) > 0) then
    begin
      Exit;
    end;
    Result := True;
  end;

  /// <summary>Typparameter von AHeader, die in keinem Parametertyp vorkommen.</summary>
  function NotInferable(const AHeader, AName: string): TArray<string>;
  var
    mParameters, mTail, mParam: string;
    mList: TArray<TSignatureParameter>;
    mItem: TSignatureParameter;
    mUsed: Boolean;
  begin
    Result := nil;
    if not TArgumentCountMismatchRule.SplitHeader(AHeader, mParameters, mTail) then
    begin
      Exit;
    end;
    mList := TChangeSignature.ParseParameters(mParameters);
    for mParam in OwnTypeParams(AHeader, AName) do
    begin
      mUsed := False;
      for mItem in mList do
      begin
        if HasIdentifier(mItem.TypeName, mParam) then
        begin
          mUsed := True;
        end;
      end;
      if not mUsed then
      begin
        Result := Result + [mParam];
      end;
    end;
  end;

  // Typparameter, der sich aus keinem Argument ableiten lässt: E2531.
  procedure CheckExplicitArguments(ACallee: TSyntaxNode);
  var
    mCandidates: TArray<TResolvedSymbol>;
    mCandidate: TResolvedSymbol;
    mMissing, mFirst: TArray<string>;
    mParameters, mTail: string;
  begin
    if not Routines(ACallee, mCandidates) then
    begin
      Exit;
    end;
    mFirst := nil;
    for mCandidate in mCandidates do
    begin
      if not TArgumentCountMismatchRule.SplitHeader(mCandidate.Signature, mParameters, mTail) or
        ((Length(mCandidates) = 1) and HasOverloadWord(mTail)) then
      begin
        Exit;
      end;
      mMissing := NotInferable(mCandidate.Signature, mCandidate.Name);
      if mMissing = nil then
      begin
        Exit;
      end;
      if mFirst = nil then
      begin
        mFirst := mMissing;
      end;
    end;
    AReport.Add(TTextRange.Create(ACallee.StartPos, ACallee.EndPos), cTexts[TGenericsText.ExplicitTypeArgs].Fmt(
      [ACallee.Name, ACallee.Name, string.Join(', ', mFirst)]), TRuleConfidence.High, nil);
  end;

  function LiteralFamily(const AText: string): TValueFamily;
  begin
    Result := TValueFamily.Unknown;
    if AText = '' then
    begin
      Exit;
    end;
    if CharInSet(AText[1], ['''', '#']) then
    begin
      Result := TValueFamily.Text;
    end
    else if CharInSet(AText[1], ['0'..'9', '$', '%']) then
    begin
      Result := TValueFamily.Number;
    end;
  end;

  // Art eines Bezeichners, Mitglieds, Aufrufs oder Indexzugriffs: True und False, sonst über den Typ.
  function TypedFamily(ANode: TSyntaxNode): TValueFamily;
  var
    mSymbol, mType: TResolvedSymbol;
    mFound: Boolean;
  begin
    Result := TValueFamily.Unknown;
    if (ANode.Kind = TSyntaxKind.Identifier) and (SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False')) then
    begin
      Result := TValueFamily.Logical;
    end
    else if mResolver.NodeType(AContext.Tree, mFileName, ANode, mSymbol, mType, mFound) and mFound and
      mType.Builtin then
    begin
      Result := BuiltinFamily(mType.Name);
    end;
  end;

  function FamilyOf(ANode: TSyntaxNode): TValueFamily;
  begin
    Result := TValueFamily.Unknown;
    case ANode.Kind of
      TSyntaxKind.Literal:
        Result := LiteralFamily(ANode.Name);
      TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr:
        if ANode.ChildCount = 1 then
        begin
          Result := FamilyOf(ANode[0]);
        end;
      TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call, TSyntaxKind.IndexAccess:
        Result := TypedFamily(ANode);
    else
      // Übrige Ausdrücke: Typ nicht sicher bekannt.
    end;
  end;

  // Erstes Argument für den Typparameter AParam, dessen Art von der ersten abweicht (AFirst); -1, wenn alle
  // gleich sind oder eine Art unbekannt ist.
  function MixedArgument(const AParam: string; const AList: TArray<TSignatureParameter>;
    const AArguments: TArray<TSyntaxNode>; out AFirst: TValueFamily): Integer;
  var
    mIndex: Integer;
    mFamily: TValueFamily;
    mUnknown: Boolean;
  begin
    AFirst := TValueFamily.Unknown;
    Result := -1;
    mUnknown := False;
    for mIndex := 0 to Length(AArguments) - 1 do
    begin
      if (mIndex >= Length(AList)) or not SameText(Trim(AList[mIndex].TypeName), AParam) then
      begin
        Continue;
      end;
      mFamily := FamilyOf(AArguments[mIndex]);
      mUnknown := mUnknown or (mFamily = TValueFamily.Unknown);
      if (mFamily <> TValueFamily.Unknown) and (AFirst = TValueFamily.Unknown) then
      begin
        AFirst := mFamily;
      end
      else if (mFamily <> TValueFamily.Unknown) and (mFamily <> AFirst) and (Result < 0) then
      begin
        Result := mIndex;
      end;
    end;
    if mUnknown then
    begin
      Result := -1;
    end;
  end;

  // Argumente verschiedener Art für denselben Typparameter: E2532.
  procedure CheckArgumentTypes(ACallee: TSyntaxNode; const AArguments: TArray<TSyntaxNode>);
  var
    mCandidates: TArray<TResolvedSymbol>;
    mParameters, mTail, mParam: string;
    mList: TArray<TSignatureParameter>;
    mSeen: Integer;
    mFirst: TValueFamily;
  begin
    if not Routines(ACallee, mCandidates) or (Length(mCandidates) <> 1) or
      not TArgumentCountMismatchRule.SplitHeader(mCandidates[0].Signature, mParameters, mTail) or
      HasOverloadWord(mTail) then
    begin
      Exit;
    end;
    mList := TChangeSignature.ParseParameters(mParameters);
    for mParam in OwnTypeParams(mCandidates[0].Signature, mCandidates[0].Name) do
    begin
      mSeen := MixedArgument(mParam, mList, AArguments, mFirst);
      if mSeen < 0 then
      begin
        Continue;
      end;
      AReport.Add(TTextRange.Create(AArguments[mSeen].StartPos, AArguments[mSeen].EndPos),
        cTexts[TGenericsText.MixedKinds].Fmt([mParam, ACallee.Name, cTexts[cFamilyNames[mFirst]].Text,
        cTexts[cFamilyNames[FamilyOf(AArguments[mSeen])]].Text, ACallee.Name]), TRuleConfidence.High, nil);
    end;
  end;

  function IsPlainCallee(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) and MayBeGeneric(ANode.Name);
  end;

  /// <summary>Ist das Ziel der Zuweisung ein Wert bekannten, nicht prozeduralen Typs?</summary>
  function PlainTarget(ATarget: TSyntaxNode): Boolean;
  var
    mSymbol, mType: TResolvedSymbol;
    mFound: Boolean;
  begin
    Result := mResolver.NodeType(AContext.Tree, mFileName, ATarget, mSymbol, mType, mFound) and mFound and
      (mType.Builtin or (mType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
      TIndexSymbolKind.RecordType, TIndexSymbolKind.EnumType]));
  end;

  // Aufruf ohne ausdrückliche Typargumente: beide Prüfungen.
  procedure CheckCall(ACall: TSyntaxNode);
  var
    mIndex: Integer;
    mArguments: TArray<TSyntaxNode>;
  begin
    mArguments := nil;
    for mIndex := 1 to ACall.ChildCount - 1 do
    begin
      if ACall[mIndex].Kind = TSyntaxKind.GenericArgs then
      begin
        Exit;
      end;
      mArguments := mArguments + [ACall[mIndex]];
    end;
    CheckExplicitArguments(ACall[0]);
    CheckArgumentTypes(ACall[0], mArguments);
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) and IsPlainCallee(mNode[0]) then
        begin
          CheckCall(mNode);
        end
        // Neu; als Anweisung ohne Klammern.
        else if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount = 1) and IsPlainCallee(mNode[0]) then
        begin
          CheckExplicitArguments(mNode[0]);
        end
        // X := TKlasse.Neu; ohne Klammern.
        else if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount = 2) and
          IsPlainCallee(mNode[1]) and PlainTarget(mNode[0]) then
        begin
          CheckExplicitArguments(mNode[1]);
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mFileName := ResolverFileName(AContext);
  mGenericNames := TDictionary<string, Boolean>.Create;
  try
    CollectGenericNames(AContext.Tree.Root);
    if (mGenericNames.Count = 0) and (AContext.Index = nil) then
    begin
      Exit;
    end;
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    mCache := TRuleDerived.Open(AContext);
    mResolver := TRuleDerived.Resolver(mCache, AContext);
    mResolver.PinTree(AContext.Tree, mFileName);
    try
      Visit(AContext.Tree.Root);
    finally
      mResolver.UnpinTree;
    end;
  finally
    mGenericNames.Free;
  end;
end;

procedure RegisterGenericRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TGenericConstraintViolatedRule.Create);
  ARegistry.Register(TGenericInferenceFailedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Generics', cTexts);

end.
