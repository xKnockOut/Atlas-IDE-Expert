unit Atlas.Common.Rules.Builtin.TypeChecks;

// Compilerfehler aus Typen von Ausdrücken schon beim Tippen (Gruppe „Compiler
// vorab“, #1024). Gemeldet wird nur, was die Namensauflösung sicher findet:
//   dynamic-array-misuse
//                     New (wie E2255) oder Dispose (wie E2008; Doku: E2256)
//                     auf einem dynamischen Array, SetLength ohne Länge (wie
//                     E2246), New mit Länge auf einem Typ, der kein dynamisches
//                     Array ist (wie E2008; Doku: E2307), und New(TArrayTyp)
//                     ohne Länge (wie E2308) (#1038). Delphi 13 meldet Dispose
//                     und New mit Länge als E2008 (dcc-Lauf vom 29.10.2026,
//                     #1369). Korrekturen: Dispose(A) wird A := nil, New(A)
//                     wird SetLength(A, 1).
//   local-routine-as-callback
//                     Eine lokale (verschachtelte) Routine wird einer Variablen
//                     bzw. einem Parameter eines prozeduralen Typs ohne of object
//                     zugewiesen (wie E2094), oder ihre bzw. die Adresse einer
//                     lokalen Variablen steht in einer typisierten Konstante der
//                     Routine (wie E2278) (#1039). Gemeldet nur, wenn der Zieltyp
//                     sicher ein solcher Typ ist (Methodenzeiger und anonyme
//                     Methoden meldet der Compiler anders). Korrektur: die Routine
//                     als Routine der Unit vor die umgebende Routine verschieben,
//                     wenn sie nichts aus ihr nutzt.
//   hresult-integer-mix und invalid-var-argument stehen in TypeChecks.Hresult bzw. TypeChecks.VarArguments;
//                     RegisterTypeCheckRules meldet auch sie an.
//   condition-not-boolean
//                     Die Bedingung von if, while, until bzw. eines bedingten
//                     Ausdrucks hat sicher einen Typ, der kein Boolean ist: Zahl,
//                     Zeiger, Klasse, Interface, String oder Zeichen (wie E2012,
//                     #1069). Korrektur: "<> 0" (Alternative "> 0"), "<> nil"
//                     (Alternative Assigned), "<> ''" bzw. "<> #0" ergänzen.
//   for-in-not-enumerable
//                     for-in über einen Typ ohne Enumerator: Zahl, Zeiger,
//                     Zeichen, Boolean oder Klasse, Record bzw. Interface ohne
//                     GetEnumerator (wie E2430), bzw. ein Enumerator ohne MoveNext
//                     oder Current (wie E2431) (#1034). Gemeldet nur, wenn alle
//                     Vorfahren bekannt sind; generische Typen bleiben still.
//                     Keine Korrektur; bei Count der Hinweis auf eine Schleife
//                     mit Index.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature;

const
  cDynamicArrayMisuseRuleId = 'dynamic-array-misuse';
  cLocalRoutineAsCallbackRuleId = 'local-routine-as-callback';
  cConditionNotBooleanRuleId = 'condition-not-boolean';
  cForInNotEnumerableRuleId = 'for-in-not-enumerable';

type
  TDynamicArrayMisuseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLocalRoutineAsCallbackRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TConditionNotBooleanRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TForInNotEnumerableRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTypeCheckRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.TypeChecks.Types,
  Atlas.Common.Rules.Builtin.TypeChecks.Hresult,
  Atlas.Common.Rules.Builtin.TypeChecks.VarArguments,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTypeChecksText = (DynArrayTitle, NewNeedsLength, NewNotDynArray, NewNotAllowed, DisposeNotAllowed,
    SetLengthNeedsLength, LocalRoutineTitle, MoveToUnit, ProcedureKind, FunctionKind, LocalAssigned, LocalPassed,
    LocalAddress, ConditionTitle, NotBoolean, EnumeratorTitle, UseCount, NoEnumerator, NoCurrent, NoEnumeratorPlain);

const
  cTexts: array[TTypeChecksText] of TAtlasText = (
    (De: 'New, Dispose oder SetLength falsch für dynamische Arrays';
     En: 'New, Dispose or SetLength wrong for dynamic arrays'),
    (De: 'New für das dynamische Array %s braucht mindestens eine Länge (wie E2308).';
     En: 'New for the dynamic array %s needs at least one length (like E2308).'),
    (De: 'New mit Länge erwartet den Typ eines dynamischen Arrays; %s ist keiner (wie E2008).';
     En: 'New with length expects the type of a dynamic array; %s is none (like E2008).'),
    (De: 'New ist für dynamische Arrays nicht erlaubt; die Länge setzt SetLength (wie E2255).';
     En: 'New is not allowed for dynamic arrays; SetLength sets the length (like E2255).'),
    (De: 'Dispose ist für dynamische Arrays nicht erlaubt und nicht nötig (wie E2008).';
     En: 'Dispose is not allowed for dynamic arrays and not needed (like E2008).'),
    (De: 'SetLength braucht für das dynamische Array %s mindestens eine Länge (wie E2246).';
     En: 'SetLength needs at least one length for the dynamic array %s (like E2246).'),
    (De: 'Lokale Routine als Prozedurvariable'; En: 'Local routine as procedural variable'),
    (De: '%s als Routine der Unit auslagern'; En: 'Move %s out as a routine of the unit'),
    (De: 'Prozedur'; En: 'procedure'),
    (De: 'Funktion'; En: 'function'),
    (De: 'Die lokale %s %s kann keiner Prozedurvariablen zugewiesen werden (wie E2094).';
     En: 'The local %s %s cannot be assigned to a procedural variable (like E2094).'),
    (De: 'Die lokale %s %s kann nicht als Prozedurvariable übergeben werden (wie E2094).';
     En: 'The local %s %s cannot be passed as a procedural variable (like E2094).'),
    (De: 'Die Adresse des lokalen Symbols %s ist keine Konstante (wie E2278).';
     En: 'The address of the local symbol %s is not a constant (like E2278).'),
    (De: 'Bedingung ist kein Boolean'; En: 'Condition is not Boolean'),
    (De: 'Die Bedingung ist %s, nicht Boolean (wie E2012).'; En: 'The condition is %s, not Boolean (like E2012).'),
    (De: 'for-in über einen Typ ohne Enumerator'; En: 'for-in over a type without enumerator'),
    (De: '; stattdessen über Count mit Index durchlaufen'; En: '; iterate via Count with an index instead'),
    (De: '%s hat keinen Enumerator; for-in ist hier nicht möglich%s (wie E2430).';
     En: '%s has no enumerator; for-in is not possible here%s (like E2430).'),
    (De: 'Der Enumerator %s von %s hat kein öffentliches %s; for-in ist hier nicht möglich (wie E2431).';
     En: 'The enumerator %s of %s has no public %s; for-in is not possible here (like E2431).'),
    (De: '%s hat keinen Enumerator; for-in ist hier nicht möglich (wie E2430).';
     En: '%s has no enumerator; for-in is not possible here (like E2430).'));

{$SCOPEDENUMS OFF}

const
  cMaxAncestorDepth = 16;
  // Eingebaute Typen, die als Bedingung E2012 auslösen (condition-not-boolean).
  cConditionIntegerTypes: array[0..19] of string = ('Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt',
    'Int64', 'Byte', 'Word', 'LongWord', 'UInt64', 'NativeInt', 'NativeUInt', 'Int8', 'Int16', 'Int32', 'UInt8',
    'UInt16', 'UInt32', 'FixedInt', 'FixedUInt');
  cConditionFloatTypes: array[0..5] of string = ('Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp');
  cConditionPointerTypes: array[0..4] of string = ('Pointer', 'PChar', 'PAnsiChar', 'PWideChar', 'PByte');
  cConditionStringTypes: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString',
    'ShortString', 'RawByteString', 'UTF8String');

{ TDynamicArrayMisuseRule }

function TDynamicArrayMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDynamicArrayMisuseRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.DynArrayTitle].Text);
end;

procedure TDynamicArrayMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mLocal: TUnitIndex;
  mNode: TSyntaxNode;

  /// <summary>Variable, Feld oder Parameter mit dynamischem Array als Typ? Offene Array-Parameter (array of
  /// T als Parametertyp) sind keine dynamischen Arrays.</summary>
  function IsArrayVariable(ANode: TSyntaxNode): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mFromUnit: TUnitIndex;
    mTypeText: string;
  begin
    Result := False;
    if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      not mResolver.NodeType(AContext.Tree, mFileName, ANode, mSymbol, mTypeInfo, mTypeFound) or
      not (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
    begin
      Exit;
    end;
    mTypeText := DeclaredTypeText(AContext, mSymbol);
    if (mSymbol.IsParameter and StartsText('array of', mTypeText)) or
      not SymbolUnit(mResolver, mLocal, mSymbol, mFromUnit) then
    begin
      Exit;
    end;
    Result := IsDynamicArrayType(mResolver, AContext, mFromUnit, mTypeText);
  end;

  /// <summary>Ist ANode ein Typbezeichner? ADynamic: ein dynamisches Array; AOther: sicher keins (Klasse,
  /// Record, Aufzählung, Interface oder eingebauter Wert-Typ).</summary>
  function TypeIdentifier(ANode: TSyntaxNode; out ADynamic, AOther: Boolean): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mFromUnit: TUnitIndex;
  begin
    ADynamic := False;
    AOther := False;
    Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      mResolver.NodeType(AContext.Tree, mFileName, ANode, mSymbol, mTypeInfo, mTypeFound) and mSymbol.IsType;
    // Eingebaute Typen wie Integer stehen ohne System nicht im Index (#1369, Fall Cm.E2307).
    if not Result and (ANode.Kind = TSyntaxKind.Identifier) and TResolverText.IsBuiltinTypeName(ANode.Name) and
      (Length(mResolver.CallCandidates(AContext.Tree, mFileName, ANode)) = 0) then
    begin
      AOther := not MatchText(ANode.Name, ['Pointer', 'PChar', 'PWideChar', 'PAnsiChar']);
      Exit(True);
    end;
    if not Result then
    begin
      Exit;
    end;
    if mSymbol.Builtin then
    begin
      AOther := not MatchText(mSymbol.Name, ['Pointer', 'PChar', 'PWideChar', 'PAnsiChar']);
      Exit;
    end;
    if mSymbol.SymbolKind = TIndexSymbolKind.TypeAlias then
    begin
      ADynamic := SymbolUnit(mResolver, mLocal, mSymbol, mFromUnit) and
        IsDynamicArrayType(mResolver, AContext, mFromUnit, mSymbol.Name);
      Exit;
    end;
    AOther := mSymbol.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.EnumType, TIndexSymbolKind.InterfaceType];
  end;

  /// <summary>Korrektur für einen Aufruf, der allein als Anweisung steht: durch ANewText ersetzen; sonst keine.
  /// </summary>
  function StatementFixes(ACall: TSyntaxNode; const ANewText: string): TArray<TRuleFix>;
  begin
    Result := nil;
    if (ACall.Parent <> nil) and (ACall.Parent.Kind = TSyntaxKind.CallStatement) and (ACall.Parent.ChildCount = 1) then
    begin
      Result := [TRuleFix.Create(ANewText, [TTextEdit.Create(TTextRange.Create(ACall.StartPos, ACall.EndPos),
        ANewText)])];
    end;
  end;

  procedure CheckNew(ACall: TSyntaxNode; AArgCount: Integer; const ATargetText: string);
  var
    mDynamic, mOther: Boolean;
  begin
    if TypeIdentifier(ACall[1], mDynamic, mOther) then
    begin
      if (AArgCount = 1) and mDynamic then
      begin
        AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
          cTexts[TTypeChecksText.NewNeedsLength].Fmt([ATargetText]),
          TRuleConfidence.High);
      end
      else if (AArgCount > 1) and mOther then
      begin
        AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
          cTexts[TTypeChecksText.NewNotDynArray].Fmt([ATargetText]), TRuleConfidence.High);
      end;
    end
    else if (AArgCount = 1) and IsArrayVariable(ACall[1]) then
    begin
      AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
        cTexts[TTypeChecksText.NewNotAllowed].Text,
        TRuleConfidence.High, StatementFixes(ACall, Format('SetLength(%s, 1)', [ATargetText])));
    end;
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    mCallee: TSyntaxNode;
    mArgCount: Integer;
    mTargetText: string;
    mSingleArray: Boolean;
  begin
    if ACall.ChildCount < 2 then
    begin
      Exit;
    end;
    mCallee := ACall[0];
    mArgCount := ACall.ChildCount - 1;
    mTargetText := NodeText(AContext, ACall[1]);
    if IsIntrinsicCall(mResolver, AContext, mFileName, mCallee, 'New') then
    begin
      CheckNew(ACall, mArgCount, mTargetText);
      Exit;
    end;
    mSingleArray := (mArgCount = 1) and IsArrayVariable(ACall[1]);
    if mSingleArray and IsIntrinsicCall(mResolver, AContext, mFileName, mCallee, 'Dispose') then
    begin
      AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
        cTexts[TTypeChecksText.DisposeNotAllowed].Text, TRuleConfidence.High,
        StatementFixes(ACall, mTargetText + ' := nil'));
    end
    else if mSingleArray and IsIntrinsicCall(mResolver, AContext, mFileName, mCallee, 'SetLength') then
    begin
      AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
        cTexts[TTypeChecksText.SetLengthNeedsLength].Fmt([mTargetText]),
        TRuleConfidence.High);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  // Vorfilter: ohne New, Dispose oder SetLength im Text keine Namensauflösung.
  if not ContainsText(AContext.Text, 'New') and not ContainsText(AContext.Text, 'Dispose') and
    not ContainsText(AContext.Text, 'SetLength') then
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
    for mNode in PreOrder(AContext.Tree.Root) do
    begin
      if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 0) and
        MatchText(mNode[0].Name, ['New', 'Dispose', 'SetLength']) then
      begin
        CheckCall(mNode);
      end;
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

{ TLocalRoutineAsCallbackRule }

function TLocalRoutineAsCallbackRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLocalRoutineAsCallbackRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.LocalRoutineTitle].Text);
end;

procedure TLocalRoutineAsCallbackRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName, mLineBreak: string;
  mLocal: TUnitIndex;
  mNodes: TArray<TSyntaxNode>;
  mNested: TList<TSyntaxNode>;
  mNames: TStringList;
  mLines: TArray<string>;
  mParent: TSyntaxNode;

  function OuterRoutine(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
    begin
      Result := Result.Parent;
    end;
  end;

  /// <summary>Verschachtelte Routine, deren Kopf ASymbol deklariert; nil, wenn ASymbol keine ist.</summary>
  function NestedOf(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    mCandidate, mHeader: TSyntaxNode;
  begin
    Result := nil;
    if (ASymbol.Kind <> TResolvedKind.Local) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) then
    begin
      Exit;
    end;
    for mCandidate in mNested do
    begin
      mHeader := mCandidate.FindChild(TSyntaxKind.RoutineHeader);
      if (mHeader <> nil) and Covers(mHeader, ASymbol.SelectionRange.StartPos) then
      begin
        Exit(mCandidate);
      end;
    end;
  end;

  /// <summary>Typ des Ziels ATarget einer Zuweisung als Text samt Unit.</summary>
  function TargetType(ATarget: TSyntaxNode; out AText: string; out AUnit: TUnitIndex): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := mResolver.NodeType(AContext.Tree, mFileName, ATarget, mSymbol, mTypeInfo, mTypeFound) and
      (mSymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
      SymbolUnit(mResolver, mLocal, mSymbol, AUnit);
    if Result then
    begin
      AText := DeclaredTypeText(AContext, mSymbol);
    end;
  end;

  /// <summary>Typ des Parameters an Stelle AArgument (0 = erstes Argument) des Aufrufs ACall.</summary>
  function ParameterType(ACall: TSyntaxNode; AArgument: Integer; out AText: string; out AUnit: TUnitIndex): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mParams: TArray<TSignatureParameter>;
  begin
    Result := mResolver.NodeType(AContext.Tree, mFileName, ACall, mSymbol, mTypeInfo, mTypeFound) and
      (mSymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) and
      RoutineParams(AContext, mSymbol, mParams) and (AArgument < Length(mParams)) and
      SymbolUnit(mResolver, mLocal, mSymbol, AUnit);
    if Result then
    begin
      AText := mParams[AArgument].TypeName;
    end;
  end;

  /// <summary>Bezeichner hinter einem Punkt (X.Name): gehört zu X, nicht zur Umgebung.</summary>
  function IsMemberName(AInner: TSyntaxNode): Boolean;
  begin
    Result := (AInner.Parent <> nil) and (AInner.Parent.Kind = TSyntaxKind.MemberAccess) and
      (AInner.Parent.ChildCount > 0) and (AInner.Parent[0] <> AInner);
  end;

  /// <summary>Bindet der Bezeichner AInner an etwas aus der umgebenden Routine (lokaler Name weiter außen,
  /// Mitglied der Klasse ohne Präfix) oder an nichts Bekanntes?</summary>
  function UsesSurrounding(ARoutine, AInner: TSyntaxNode): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    if not mResolver.NodeType(AContext.Tree, mFileName, AInner, mSymbol, mTypeInfo, mTypeFound) then
    begin
      Result := not TSystemIntrinsics.IsKnown(AInner.Name);
    end
    else if mSymbol.Kind = TResolvedKind.Local then
    begin
      Result := not Covers(ARoutine, mSymbol.SelectionRange.StartPos);
    end
    else
    begin
      Result := (mSymbol.Kind = TResolvedKind.Symbol) and (mSymbol.Container <> '') and not mSymbol.IsType;
    end;
  end;

  /// <summary>Nutzt ARoutine nur eigene Namen und Namen außerhalb der umgebenden Routine (keine Mitglieder
  /// der Klasse ohne Präfix, keine lokalen Namen weiter außen)? Dann darf sie auf Unit-Ebene stehen.</summary>
  function SelfContained(ARoutine: TSyntaxNode): Boolean;
  var
    mInner: TSyntaxNode;
  begin
    for mInner in PreOrder(ARoutine) do
    begin
      if (mInner.Kind = TSyntaxKind.Identifier) and not IsMemberName(mInner) and UsesSurrounding(ARoutine, mInner) then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;

  /// <summary>Korrektur: ARoutine als Routine der Unit direkt vor die umgebende Routine stellen.</summary>
  function MoveFix(ARoutine: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    mOuter: TSyntaxNode;
    mFirst, mLast, mLine: Integer;
    mIndent, mText: string;
  begin
    Result := False;
    mOuter := OuterRoutine(ARoutine);
    // Nur eine Ebene tief: Bei tieferer Schachtelung bräuchte die mittlere Routine sie weiter.
    if (mOuter = nil) or (OuterRoutine(mOuter) <> nil) or not SelfContained(ARoutine) then
    begin
      Exit;
    end;
    mFirst := ARoutine.StartPos.Line;
    mLast := ARoutine.EndPos.Line;
    if (mLast > High(mLines)) or (Trim(Copy(mLines[mFirst], 1, ARoutine.StartPos.Character)) <> '') or
      (Trim(Copy(mLines[mLast], ARoutine.EndPos.Character + 1, MaxInt)) <> '') then
    begin
      Exit;
    end;
    mIndent := TTextLines.IndentOf(mLines[mFirst]);
    mText := '';
    for mLine := mFirst to mLast do
    begin
      if StartsStr(mIndent, mLines[mLine]) then
      begin
        mText := mText + Copy(mLines[mLine], Length(mIndent) + 1, MaxInt) + mLineBreak;
      end
      else
      begin
        mText := mText + TrimLeft(mLines[mLine]) + mLineBreak;
      end;
    end;
    AFix := TRuleFix.Create(cTexts[TTypeChecksText.MoveToUnit].Fmt([ARoutine.Name]), [
      TTextEdit.Create(TTextRange.Create(mOuter.StartPos.Line, 0, mOuter.StartPos.Line, 0), mText + mLineBreak),
      TTextEdit.Create(TTextRange.Create(mFirst, 0, mLast + 1, 0), '')]);
    Result := True;
  end;

  procedure Report(AName: TSyntaxNode; ARoutine: TSyntaxNode; AAssigned: Boolean);
  var
    mKind, mMessage: string;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
    mHeader: TSyntaxNode;
  begin
    mKind := cTexts[TTypeChecksText.ProcedureKind].Text;
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (mHeader <> nil) and StartsText('function', Trim(NodeText(AContext, mHeader))) then
    begin
      mKind := cTexts[TTypeChecksText.FunctionKind].Text;
    end;
    if AAssigned then
    begin
      mMessage := cTexts[TTypeChecksText.LocalAssigned].Fmt([mKind, ARoutine.Name]);
    end
    else
    begin
      mMessage := cTexts[TTypeChecksText.LocalPassed].Fmt([mKind, ARoutine.Name]);
    end;
    mFixes := nil;
    if MoveFix(ARoutine, mFix) then
    begin
      mFixes := [mFix];
    end;
    AReport.Add(TTextRange.Create(AName.StartPos, AName.EndPos), mMessage, TRuleConfidence.High, mFixes);
  end;

  procedure CheckName(AName: TSyntaxNode);
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mRoutine: TSyntaxNode;
    mTypeText: string;
    mFromUnit: TUnitIndex;
    mArgument, mIndex: Integer;
  begin
    mParent := AName.Parent;
    if (mParent = nil) or not (mParent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call]) or
      (mParent[0] = AName) then
    begin
      Exit;
    end;
    if not mResolver.NodeType(AContext.Tree, mFileName, AName, mSymbol, mTypeInfo, mTypeFound) then
    begin
      Exit;
    end;
    mRoutine := NestedOf(mSymbol);
    if mRoutine = nil then
    begin
      Exit;
    end;
    if mParent.Kind = TSyntaxKind.AssignStatement then
    begin
      if TargetType(mParent[0], mTypeText, mFromUnit) and
        IsPlainProcedureType(mResolver, AContext, mFromUnit, mTypeText)
      then
      begin
        Report(AName, mRoutine, True);
      end;
      Exit;
    end;
    mArgument := -1;
    for mIndex := 1 to mParent.ChildCount - 1 do
    begin
      if mParent[mIndex] = AName then
      begin
        mArgument := mIndex - 1;
      end;
    end;
    if (mArgument >= 0) and ParameterType(mParent, mArgument, mTypeText, mFromUnit) and
      IsPlainProcedureType(mResolver, AContext, mFromUnit, mTypeText) then
    begin
      Report(AName, mRoutine, False);
    end;
  end;

  /// <summary>@X mit X lokaler Variable bzw. Parameter der Routine AOuter?</summary>
  function IsLocalAddress(AInner, AOuter: TSyntaxNode): Boolean;
  var
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := (AInner.Kind = TSyntaxKind.AddressOf) and (AInner.ChildCount = 1) and
      (AInner[0].Kind = TSyntaxKind.Identifier);
    Result := Result and mResolver.NodeType(AContext.Tree, mFileName, AInner[0], mSymbol, mTypeInfo, mTypeFound);
    Result := Result and (mSymbol.Kind = TResolvedKind.Local) and (mSymbol.SymbolKind = TIndexSymbolKind.Variable) and
      Covers(AOuter, mSymbol.SelectionRange.StartPos);
  end;

  /// <summary>@X in einer typisierten Konstante einer Routine mit X lokaler Variable bzw. Parameter
  /// (wie E2278).</summary>
  procedure CheckConstant(AConst: TSyntaxNode);
  var
    mInner, mOuter: TSyntaxNode;
  begin
    mOuter := OuterRoutine(AConst);
    if (mOuter = nil) or (AConst.FindChild(TSyntaxKind.TypeReference) = nil) and
      (AConst.FindChild(TSyntaxKind.PointerType) = nil) then
    begin
      Exit;
    end;
    for mInner in PreOrder(AConst) do
    begin
      if IsLocalAddress(mInner, mOuter) then
      begin
        AReport.Add(TTextRange.Create(mInner.StartPos, mInner.EndPos),
          cTexts[TTypeChecksText.LocalAddress].Fmt([mInner[0].Name]),
          TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Verschachtelte Routinen samt Namen sammeln; False, wenn es weder sie noch Konstanten gibt.</summary>
  function CollectNested: Boolean;
  var
    mNode: TSyntaxNode;
  begin
    Result := False;
    for mNode in mNodes do
    begin
      if (mNode.Kind = TSyntaxKind.RoutineDecl) and (OuterRoutine(mNode) <> nil) then
      begin
        mNested.Add(mNode);
        mNames.Add(mNode.Name);
      end
      else if mNode.Kind = TSyntaxKind.ConstDecl then
      begin
        Result := True;
      end;
    end;
    Result := Result or (mNested.Count > 0);
  end;

  procedure CheckNodes;
  var
    mNode: TSyntaxNode;
  begin
    mFileName := ResolverFileName(AContext);
    mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
    if mLineBreak = '' then
    begin
      mLineBreak := sLineBreak;
    end;
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    mCache := TRuleDerived.Open(AContext);
    mResolver := TRuleDerived.Resolver(mCache, AContext);
    mResolver.PinTree(AContext.Tree, mFileName);
    try
      mLocal := mResolver.ExtractedUnit(AContext.Tree, mFileName);
      for mNode in mNodes do
      begin
        if (mNode.Kind = TSyntaxKind.Identifier) and (mNames.IndexOf(mNode.Name) >= 0) then
        begin
          CheckName(mNode);
        end
        else if mNode.Kind = TSyntaxKind.ConstDecl then
        begin
          CheckConstant(mNode);
        end;
      end;
    finally
      mResolver.UnpinTree;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mNodes := PreOrder(AContext.Tree.Root);
  mNested := TList<TSyntaxNode>.Create;
  mNames := TStringList.Create;
  try
    mNames.CaseSensitive := False;
    mNames.Sorted := True;
    mNames.Duplicates := dupIgnore;
    if CollectNested then
    begin
      CheckNodes;
    end;
  finally
    mNames.Free;
    mNested.Free;
  end;
end;

{ TConditionNotBooleanRule }

function TConditionNotBooleanRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cConditionNotBooleanRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.ConditionTitle].Text);
end;

procedure TConditionNotBooleanRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mLocal: TUnitIndex;
  mNode: TSyntaxNode;

  /// <summary>Vergleich, der aus dem Wert vom Typ AType eine Bedingung macht ('&lt;&gt; 0', '&lt;&gt; nil' ...); ''
  /// ohne
  /// sicheren Typ.</summary>
  function Comparison(const AType: TResolvedSymbol): string;
  var
    mFromUnit: TUnitIndex;
  begin
    Result := '';
    if AType.Builtin then
    begin
      if MatchText(AType.Name, cConditionIntegerTypes) or MatchText(AType.Name, cConditionFloatTypes) then
      begin
        Result := '<> 0';
      end
      else if MatchText(AType.Name, cConditionPointerTypes) then
      begin
        Result := '<> nil';
      end
      else if MatchText(AType.Name, cConditionStringTypes) then
      begin
        Result := '<> ''''';
      end
      else if MatchText(AType.Name, ['Char', 'AnsiChar', 'WideChar']) then
      begin
        Result := '<> #0';
      end;
    end
    else if AType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType] then
    begin
      Result := '<> nil';
    end
    else if (AType.SymbolKind = TIndexSymbolKind.TypeAlias) and SymbolUnit(mResolver, mLocal, AType, mFromUnit) and
      StartsStr('^', DeclaredTypeText(AContext, AType)) then
    begin
      // Typisierter Zeiger (PZahl = ^Integer).
      Result := '<> nil';
    end;
  end;

  /// <summary>Korrektur: die Bedingung ACondition durch ANewText ersetzen.</summary>
  function Replacement(ACondition: TSyntaxNode; const ANewText: string; AAlternative: Boolean): TRuleFix;
  begin
    Result := TRuleFix.Create(ANewText, [TTextEdit.Create(TTextRange.Create(ACondition.StartPos, ACondition.EndPos),
      ANewText)]);
    Result.Alternative := AAlternative;
  end;

  /// <summary>Sicherer Typ der Bedingung AInner außerhalb bedingter Zweige; ATypeInfo: ihr Typ.</summary>
  function ConditionType(AInner: TSyntaxNode; out ATypeInfo: TResolvedSymbol): Boolean;
  var
    mSymbol: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := (AInner.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
      mResolver.NodeType(AContext.Tree, mFileName, AInner, mSymbol, ATypeInfo, mTypeFound) and mTypeFound;
    Result := Result and not mSymbol.IsType and (mSymbol.Condition = '') and (mSymbol.VariantBranch = '');
  end;

  procedure CheckCondition(ACondition: TSyntaxNode);
  var
    mInner: TSyntaxNode;
    mTypeInfo: TResolvedSymbol;
    mCompare, mText: string;
    mFixes: TArray<TRuleFix>;
  begin
    mInner := ACondition;
    while (mInner.Kind = TSyntaxKind.ParenExpr) and (mInner.ChildCount = 1) do
    begin
      mInner := mInner[0];
    end;
    if not ConditionType(mInner, mTypeInfo) then
    begin
      Exit;
    end;
    mCompare := Comparison(mTypeInfo);
    if mCompare = '' then
    begin
      Exit;
    end;
    mText := NodeText(AContext, ACondition);
    mFixes := [Replacement(ACondition, mText + ' ' + mCompare, False)];
    if mCompare = '<> nil' then
    begin
      mFixes := mFixes + [Replacement(ACondition, Format('Assigned(%s)', [mText]), True)];
    end
    else if MatchText(mTypeInfo.Name, cConditionIntegerTypes) then
    begin
      mFixes := mFixes + [Replacement(ACondition, mText + ' > 0', True)];
    end;
    AReport.Add(TTextRange.Create(ACondition.StartPos, ACondition.EndPos),
      cTexts[TTypeChecksText.NotBoolean].Fmt([mTypeInfo.Name]), TRuleConfidence.High, mFixes);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
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
    for mNode in PreOrder(AContext.Tree.Root) do
      case mNode.Kind of
        TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.IfExpr:
          if mNode.ChildCount > 0 then
          begin
            CheckCondition(mNode[0]);
          end;
        TSyntaxKind.RepeatStatement:
          // Die Bedingung hinter until ist das letzte Kind.
          if mNode.ChildCount > 0 then
          begin
            CheckCondition(mNode[mNode.ChildCount - 1]);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    mResolver.UnpinTree;
  end;
end;

{ TForInNotEnumerableRule }

function TForInNotEnumerableRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cForInNotEnumerableRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.EnumeratorTitle].Text);
end;

procedure TForInNotEnumerableRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;
  mNode: TSyntaxNode;

  /// <summary>Sind alle Vorfahren von AType bekannt (bis TObject bzw. IInterface)? Nur dann steht fest, dass
  /// ein Mitglied fehlt.</summary>
  function AncestorsKnown(const AType: TResolvedSymbol): Boolean;
  var
    mCurrent, mAncestor: TResolvedSymbol;
    mDepth: Integer;
  begin
    mCurrent := AType;
    for mDepth := 0 to cMaxAncestorDepth do
    begin
      if (mCurrent.SymbolKind = TIndexSymbolKind.RecordType) or SameText(mCurrent.Name, 'TObject') or
        SameText(mCurrent.Name, 'IInterface') then
      begin
        Exit(True);
      end;
      if not mResolver.AncestorOf(mCurrent, mAncestor) then
      begin
        // Ohne eigene Angabe ist der Vorfahr TObject bzw. IInterface, auch wenn sie nicht im Index stehen.
        Exit(Length(mCurrent.Ancestors) = 0);
      end;
      mCurrent := mAncestor;
    end;
    Result := False;
  end;

  /// <summary>Eingebauter Typ ohne for-in: Zahl, Zeiger, Zeichen, Boolean. Strings, Arrays und Mengen kann for-in.
  /// </summary>
  function IsScalarName(const AName: string): Boolean;
  begin
    Result := MatchText(AName, cConditionIntegerTypes) or MatchText(AName, cConditionFloatTypes);
    Result := Result or MatchText(AName, cConditionPointerTypes) or
      MatchText(AName, ['Boolean', 'Char', 'AnsiChar', 'WideChar']);
  end;

  function IsStructured(const AType: TResolvedSymbol): Boolean;
  begin
    Result := AType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType];
  end;

  /// <summary>Klasse, Record bzw. Interface ohne GetEnumerator bei bekannten Vorfahren (wie E2430).</summary>
  function NoEnumeratorMessage(const AType: TResolvedSymbol; out AMessage: string): Boolean;
  var
    mMember: TResolvedSymbol;
    mHint: string;
  begin
    AMessage := '';
    Result := AncestorsKnown(AType);
    if not Result then
    begin
      Exit;
    end;
    mHint := '';
    if mResolver.FindMember(AType, 'Count', mMember) then
    begin
      mHint := cTexts[TTypeChecksText.UseCount].Text;
    end;
    AMessage := cTexts[TTypeChecksText.NoEnumerator].Fmt([AType.Name, mHint]);
  end;

  /// <summary>Typ des Enumerators, den AMethod (GetEnumerator) liefert, wenn er sicher bekannt und nicht generisch
  /// ist.</summary>
  function EnumeratorOf(const AMethod: TResolvedSymbol; out AEnumerator: TResolvedSymbol): Boolean;
  var
    mMethodUnit: TUnitIndex;
  begin
    Result := (AMethod.TypeName <> '') and (AMethod.TypeArgs = '') and mResolver.DeclaringUnit(AMethod, mMethodUnit);
    Result := Result and mResolver.ResolveTypeFrom(mMethodUnit, AMethod.TypeName, AEnumerator);
    Result := Result and not AEnumerator.Builtin and IsStructured(AEnumerator) and (AEnumerator.TypeParams = '');
  end;

  /// <summary>Fehlt dem Enumerator MoveNext oder Current (wie E2431)?</summary>
  function IncompleteEnumerator(const AType, AMethod: TResolvedSymbol; out AMessage: string): Boolean;
  var
    mEnumerator, mMember: TResolvedSymbol;
    mMissing: string;
  begin
    AMessage := '';
    Result := False;
    if not EnumeratorOf(AMethod, mEnumerator) then
    begin
      Exit;
    end;
    mMissing := '';
    if not mResolver.FindMember(mEnumerator, 'MoveNext', mMember) then
    begin
      mMissing := 'MoveNext';
    end
    else if not mResolver.FindMember(mEnumerator, 'Current', mMember) then
    begin
      mMissing := 'Current';
    end;
    Result := (mMissing <> '') and AncestorsKnown(mEnumerator);
    if Result then
    begin
      AMessage := cTexts[TTypeChecksText.NoCurrent].Fmt([mEnumerator.Name, AType.Name, mMissing]);
    end;
  end;

  /// <summary>Kann der Typ sicher kein for-in? AMessage nennt den Grund.</summary>
  function NotEnumerable(const AType: TResolvedSymbol; out AMessage: string): Boolean;
  var
    mMethod: TResolvedSymbol;
  begin
    AMessage := '';
    if AType.Builtin then
    begin
      Result := IsScalarName(AType.Name);
      if Result then
      begin
        AMessage := cTexts[TTypeChecksText.NoEnumeratorPlain].Fmt([AType.Name]);
      end;
    end
    else if not IsStructured(AType) then
    begin
      Result := False;
    end
    else if not mResolver.FindMember(AType, 'GetEnumerator', mMethod) then
    begin
      Result := NoEnumeratorMessage(AType, AMessage);
    end
    else
    begin
      // GetEnumerator gibt es: Der Enumerator braucht MoveNext und Current (wie E2431).
      Result := IncompleteEnumerator(AType, mMethod, AMessage);
    end;
  end;

  /// <summary>Durchlaufener Ausdruck der Schleife (das erste Kind, das kein Typverweis ist); nil ohne.</summary>
  function CollectionOf(ALoop: TSyntaxNode): TSyntaxNode;
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ALoop.ChildCount - 1 do
    begin
      if ALoop[mIndex].Kind <> TSyntaxKind.TypeReference then
      begin
        Exit(ALoop[mIndex]);
      end;
    end;
    Result := nil;
  end;

  /// <summary>Sicherer, nicht generischer Typ des Ausdrucks ACollection außerhalb bedingter Zweige.</summary>
  function CollectionType(ACollection: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
  var
    mSymbol: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := (ACollection.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
      mResolver.NodeType(AContext.Tree, mFileName, ACollection, mSymbol, AType, mTypeFound) and mTypeFound;
    Result := Result and not mSymbol.IsType and (mSymbol.Condition = '') and (mSymbol.VariantBranch = '');
    Result := Result and (AType.TypeParams = '');
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    mCollection: TSyntaxNode;
    mTypeInfo: TResolvedSymbol;
    mMessage: string;
  begin
    mCollection := CollectionOf(ALoop);
    if (mCollection <> nil) and CollectionType(mCollection, mTypeInfo) and NotEnumerable(mTypeInfo, mMessage) then
    begin
      AReport.Add(TTextRange.Create(mCollection.StartPos, mCollection.EndPos), mMessage, TRuleConfidence.High);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, ' in') then
  begin
    Exit;
  end;
  mFileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    for mNode in PreOrder(AContext.Tree.Root) do
    begin
      if mNode.Kind = TSyntaxKind.ForInStatement then
      begin
        CheckLoop(mNode);
      end;
    end;
  finally
    mResolver.UnpinTree;
  end;
end;

procedure RegisterTypeCheckRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDynamicArrayMisuseRule.Create);
  ARegistry.Register(TLocalRoutineAsCallbackRule.Create);
  ARegistry.Register(THresultIntegerMixRule.Create);
  ARegistry.Register(TInvalidVarArgumentRule.Create);
  ARegistry.Register(TConditionNotBooleanRule.Create);
  ARegistry.Register(TForInNotEnumerableRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeChecks', cTexts);

end.
