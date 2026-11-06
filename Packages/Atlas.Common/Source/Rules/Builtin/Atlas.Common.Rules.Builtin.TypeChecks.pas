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
  DynamicArrayMisuseRuleId = 'dynamic-array-misuse';
  LocalRoutineAsCallbackRuleId = 'local-routine-as-callback';
  ConditionNotBooleanRuleId = 'condition-not-boolean';
  ForInNotEnumerableRuleId = 'for-in-not-enumerable';

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
  ConditionIntegerTypes: array[0..19] of string = ('Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt',
    'Int64', 'Byte', 'Word', 'LongWord', 'UInt64', 'NativeInt', 'NativeUInt', 'Int8', 'Int16', 'Int32', 'UInt8',
    'UInt16', 'UInt32', 'FixedInt', 'FixedUInt');
  ConditionFloatTypes: array[0..5] of string = ('Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp');
  ConditionPointerTypes: array[0..4] of string = ('Pointer', 'PChar', 'PAnsiChar', 'PWideChar', 'PByte');
  ConditionStringTypes: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString',
    'ShortString', 'RawByteString', 'UTF8String');

{ TDynamicArrayMisuseRule }

function TDynamicArrayMisuseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DynamicArrayMisuseRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.DynArrayTitle].Text);
end;

procedure TDynamicArrayMisuseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Local: TUnitIndex;
  Node: TSyntaxNode;

  /// <summary>Variable, Feld oder Parameter mit dynamischem Array als Typ? Offene Array-Parameter (array of
  /// T als Parametertyp) sind keine dynamischen Arrays.</summary>
  function IsArrayVariable(ANode: TSyntaxNode): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    FromUnit: TUnitIndex;
    TypeText: string;
  begin
    Result := False;
    if not (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
      not Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) or
      not (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) then
    begin
      Exit;
    end;
    TypeText := DeclaredTypeText(AContext, Symbol);
    if (Symbol.IsParameter and StartsText('array of', TypeText)) or
      not SymbolUnit(Resolver, Local, Symbol, FromUnit) then
    begin
      Exit;
    end;
    Result := IsDynamicArrayType(Resolver, AContext, FromUnit, TypeText);
  end;

  /// <summary>Ist ANode ein Typbezeichner? ADynamic: ein dynamisches Array; AOther: sicher keins (Klasse,
  /// Record, Aufzählung, Interface oder eingebauter Wert-Typ).</summary>
  function TypeIdentifier(ANode: TSyntaxNode; out ADynamic, AOther: Boolean): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    FromUnit: TUnitIndex;
  begin
    ADynamic := False;
    AOther := False;
    Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      Resolver.NodeType(AContext.Tree, FileName, ANode, Symbol, TypeInfo, TypeFound) and Symbol.IsType;
    // Eingebaute Typen wie Integer stehen ohne System nicht im Index (#1369, Fall Cm.E2307).
    if not Result and (ANode.Kind = TSyntaxKind.Identifier) and TResolverText.IsBuiltinTypeName(ANode.Name) and
      (Length(Resolver.CallCandidates(AContext.Tree, FileName, ANode)) = 0) then
    begin
      AOther := not MatchText(ANode.Name, ['Pointer', 'PChar', 'PWideChar', 'PAnsiChar']);
      Exit(True);
    end;
    if not Result then
    begin
      Exit;
    end;
    if Symbol.Builtin then
    begin
      AOther := not MatchText(Symbol.Name, ['Pointer', 'PChar', 'PWideChar', 'PAnsiChar']);
      Exit;
    end;
    if Symbol.SymbolKind = TIndexSymbolKind.TypeAlias then
    begin
      ADynamic := SymbolUnit(Resolver, Local, Symbol, FromUnit) and
        IsDynamicArrayType(Resolver, AContext, FromUnit, Symbol.Name);
      Exit;
    end;
    AOther := Symbol.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
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
    Dynamic, Other: Boolean;
  begin
    if TypeIdentifier(ACall[1], Dynamic, Other) then
    begin
      if (AArgCount = 1) and Dynamic then
      begin
        AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
          cTexts[TTypeChecksText.NewNeedsLength].Fmt([ATargetText]),
          TRuleConfidence.High);
      end
      else if (AArgCount > 1) and Other then
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
    Callee: TSyntaxNode;
    ArgCount: Integer;
    TargetText: string;
    SingleArray: Boolean;
  begin
    if ACall.ChildCount < 2 then
    begin
      Exit;
    end;
    Callee := ACall[0];
    ArgCount := ACall.ChildCount - 1;
    TargetText := NodeText(AContext, ACall[1]);
    if IsIntrinsicCall(Resolver, AContext, FileName, Callee, 'New') then
    begin
      CheckNew(ACall, ArgCount, TargetText);
      Exit;
    end;
    SingleArray := (ArgCount = 1) and IsArrayVariable(ACall[1]);
    if SingleArray and IsIntrinsicCall(Resolver, AContext, FileName, Callee, 'Dispose') then
    begin
      AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
        cTexts[TTypeChecksText.DisposeNotAllowed].Text, TRuleConfidence.High,
        StatementFixes(ACall, TargetText + ' := nil'));
    end
    else if SingleArray and IsIntrinsicCall(Resolver, AContext, FileName, Callee, 'SetLength') then
    begin
      AReport.Add(TTextRange.Create(ACall.StartPos, ACall.EndPos),
        cTexts[TTypeChecksText.SetLengthNeedsLength].Fmt([TargetText]),
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
  FileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
    for Node in PreOrder(AContext.Tree.Root) do
    begin
      if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and
        MatchText(Node[0].Name, ['New', 'Dispose', 'SetLength']) then
      begin
        CheckCall(Node);
      end;
    end;
  finally
    Resolver.UnpinTree;
  end;
end;

{ TLocalRoutineAsCallbackRule }

function TLocalRoutineAsCallbackRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(LocalRoutineAsCallbackRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.LocalRoutineTitle].Text);
end;

procedure TLocalRoutineAsCallbackRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName, LineBreak: string;
  Local: TUnitIndex;
  Nodes: TArray<TSyntaxNode>;
  Nested: TList<TSyntaxNode>;
  Names: TStringList;
  Lines: TArray<string>;
  Parent: TSyntaxNode;

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
    Candidate, Header: TSyntaxNode;
  begin
    Result := nil;
    if (ASymbol.Kind <> TResolvedKind.Local) or (ASymbol.SymbolKind <> TIndexSymbolKind.Routine) then
    begin
      Exit;
    end;
    for Candidate in Nested do
    begin
      Header := Candidate.FindChild(TSyntaxKind.RoutineHeader);
      if (Header <> nil) and Covers(Header, ASymbol.SelectionRange.StartPos) then
      begin
        Exit(Candidate);
      end;
    end;
  end;

  /// <summary>Typ des Ziels ATarget einer Zuweisung als Text samt Unit.</summary>
  function TargetType(ATarget: TSyntaxNode; out AText: string; out AUnit: TUnitIndex): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ATarget, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
      SymbolUnit(Resolver, Local, Symbol, AUnit);
    if Result then
    begin
      AText := DeclaredTypeText(AContext, Symbol);
    end;
  end;

  /// <summary>Typ des Parameters an Stelle AArgument (0 = erstes Argument) des Aufrufs ACall.</summary>
  function ParameterType(ACall: TSyntaxNode; AArgument: Integer; out AText: string; out AUnit: TUnitIndex): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Params: TArray<TSignatureParameter>;
  begin
    Result := Resolver.NodeType(AContext.Tree, FileName, ACall, Symbol, TypeInfo, TypeFound) and
      (Symbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine, TIndexSymbolKind.Constructor_]) and
      RoutineParams(AContext, Symbol, Params) and (AArgument < Length(Params)) and
      SymbolUnit(Resolver, Local, Symbol, AUnit);
    if Result then
    begin
      AText := Params[AArgument].TypeName;
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
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    if not Resolver.NodeType(AContext.Tree, FileName, AInner, Symbol, TypeInfo, TypeFound) then
    begin
      Result := not TSystemIntrinsics.IsKnown(AInner.Name);
    end
    else if Symbol.Kind = TResolvedKind.Local then
    begin
      Result := not Covers(ARoutine, Symbol.SelectionRange.StartPos);
    end
    else
    begin
      Result := (Symbol.Kind = TResolvedKind.Symbol) and (Symbol.Container <> '') and not Symbol.IsType;
    end;
  end;

  /// <summary>Nutzt ARoutine nur eigene Namen und Namen außerhalb der umgebenden Routine (keine Mitglieder
  /// der Klasse ohne Präfix, keine lokalen Namen weiter außen)? Dann darf sie auf Unit-Ebene stehen.</summary>
  function SelfContained(ARoutine: TSyntaxNode): Boolean;
  var
    Inner: TSyntaxNode;
  begin
    for Inner in PreOrder(ARoutine) do
    begin
      if (Inner.Kind = TSyntaxKind.Identifier) and not IsMemberName(Inner) and UsesSurrounding(ARoutine, Inner) then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;

  /// <summary>Korrektur: ARoutine als Routine der Unit direkt vor die umgebende Routine stellen.</summary>
  function MoveFix(ARoutine: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Outer: TSyntaxNode;
    First, Last, Line: Integer;
    Indent, Text: string;
  begin
    Result := False;
    Outer := OuterRoutine(ARoutine);
    // Nur eine Ebene tief: Bei tieferer Schachtelung bräuchte die mittlere Routine sie weiter.
    if (Outer = nil) or (OuterRoutine(Outer) <> nil) or not SelfContained(ARoutine) then
    begin
      Exit;
    end;
    First := ARoutine.StartPos.Line;
    Last := ARoutine.EndPos.Line;
    if (Last > High(Lines)) or (Trim(Copy(Lines[First], 1, ARoutine.StartPos.Character)) <> '') or
      (Trim(Copy(Lines[Last], ARoutine.EndPos.Character + 1, MaxInt)) <> '') then
    begin
      Exit;
    end;
    Indent := TTextLines.IndentOf(Lines[First]);
    Text := '';
    for Line := First to Last do
    begin
      if StartsStr(Indent, Lines[Line]) then
      begin
        Text := Text + Copy(Lines[Line], Length(Indent) + 1, MaxInt) + LineBreak;
      end
      else
      begin
        Text := Text + TrimLeft(Lines[Line]) + LineBreak;
      end;
    end;
    AFix := TRuleFix.Create(cTexts[TTypeChecksText.MoveToUnit].Fmt([ARoutine.Name]), [
      TTextEdit.Create(TTextRange.Create(Outer.StartPos.Line, 0, Outer.StartPos.Line, 0), Text + LineBreak),
      TTextEdit.Create(TTextRange.Create(First, 0, Last + 1, 0), '')]);
    Result := True;
  end;

  procedure Report(AName: TSyntaxNode; ARoutine: TSyntaxNode; AAssigned: Boolean);
  var
    Kind, Message: string;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
    Header: TSyntaxNode;
  begin
    Kind := cTexts[TTypeChecksText.ProcedureKind].Text;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (Header <> nil) and StartsText('function', Trim(NodeText(AContext, Header))) then
    begin
      Kind := cTexts[TTypeChecksText.FunctionKind].Text;
    end;
    if AAssigned then
    begin
      Message := cTexts[TTypeChecksText.LocalAssigned].Fmt([Kind, ARoutine.Name]);
    end
    else
    begin
      Message := cTexts[TTypeChecksText.LocalPassed].Fmt([Kind, ARoutine.Name]);
    end;
    Fixes := nil;
    if MoveFix(ARoutine, Fix) then
    begin
      Fixes := [Fix];
    end;
    AReport.Add(TTextRange.Create(AName.StartPos, AName.EndPos), Message, TRuleConfidence.High, Fixes);
  end;

  procedure CheckName(AName: TSyntaxNode);
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
    Routine: TSyntaxNode;
    TypeText: string;
    FromUnit: TUnitIndex;
    Argument, Index: Integer;
  begin
    Parent := AName.Parent;
    if (Parent = nil) or not (Parent.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call]) or
      (Parent[0] = AName) then
    begin
      Exit;
    end;
    if not Resolver.NodeType(AContext.Tree, FileName, AName, Symbol, TypeInfo, TypeFound) then
    begin
      Exit;
    end;
    Routine := NestedOf(Symbol);
    if Routine = nil then
    begin
      Exit;
    end;
    if Parent.Kind = TSyntaxKind.AssignStatement then
    begin
      if TargetType(Parent[0], TypeText, FromUnit) and IsPlainProcedureType(Resolver, AContext, FromUnit, TypeText)
      then
      begin
        Report(AName, Routine, True);
      end;
      Exit;
    end;
    Argument := -1;
    for Index := 1 to Parent.ChildCount - 1 do
    begin
      if Parent[Index] = AName then
      begin
        Argument := Index - 1;
      end;
    end;
    if (Argument >= 0) and ParameterType(Parent, Argument, TypeText, FromUnit) and
      IsPlainProcedureType(Resolver, AContext, FromUnit, TypeText) then
    begin
      Report(AName, Routine, False);
    end;
  end;

  /// <summary>@X mit X lokaler Variable bzw. Parameter der Routine AOuter?</summary>
  function IsLocalAddress(AInner, AOuter: TSyntaxNode): Boolean;
  var
    Symbol, TypeInfo: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := (AInner.Kind = TSyntaxKind.AddressOf) and (AInner.ChildCount = 1) and
      (AInner[0].Kind = TSyntaxKind.Identifier);
    Result := Result and Resolver.NodeType(AContext.Tree, FileName, AInner[0], Symbol, TypeInfo, TypeFound);
    Result := Result and (Symbol.Kind = TResolvedKind.Local) and (Symbol.SymbolKind = TIndexSymbolKind.Variable) and
      Covers(AOuter, Symbol.SelectionRange.StartPos);
  end;

  /// <summary>@X in einer typisierten Konstante einer Routine mit X lokaler Variable bzw. Parameter
  /// (wie E2278).</summary>
  procedure CheckConstant(AConst: TSyntaxNode);
  var
    Inner, Outer: TSyntaxNode;
  begin
    Outer := OuterRoutine(AConst);
    if (Outer = nil) or (AConst.FindChild(TSyntaxKind.TypeReference) = nil) and
      (AConst.FindChild(TSyntaxKind.PointerType) = nil) then
    begin
      Exit;
    end;
    for Inner in PreOrder(AConst) do
    begin
      if IsLocalAddress(Inner, Outer) then
      begin
        AReport.Add(TTextRange.Create(Inner.StartPos, Inner.EndPos),
          cTexts[TTypeChecksText.LocalAddress].Fmt([Inner[0].Name]),
          TRuleConfidence.High);
      end;
    end;
  end;

  /// <summary>Verschachtelte Routinen samt Namen sammeln; False, wenn es weder sie noch Konstanten gibt.</summary>
  function CollectNested: Boolean;
  var
    Node: TSyntaxNode;
  begin
    Result := False;
    for Node in Nodes do
    begin
      if (Node.Kind = TSyntaxKind.RoutineDecl) and (OuterRoutine(Node) <> nil) then
      begin
        Nested.Add(Node);
        Names.Add(Node.Name);
      end
      else if Node.Kind = TSyntaxKind.ConstDecl then
      begin
        Result := True;
      end;
    end;
    Result := Result or (Nested.Count > 0);
  end;

  procedure CheckNodes;
  var
    Node: TSyntaxNode;
  begin
    FileName := ResolverFileName(AContext);
    Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
    if LineBreak = '' then
    begin
      LineBreak := sLineBreak;
    end;
    // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
    mCache := TRuleDerived.Open(AContext);
    Resolver := TRuleDerived.Resolver(mCache, AContext);
    Resolver.PinTree(AContext.Tree, FileName);
    try
      Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
      for Node in Nodes do
      begin
        if (Node.Kind = TSyntaxKind.Identifier) and (Names.IndexOf(Node.Name) >= 0) then
        begin
          CheckName(Node);
        end
        else if Node.Kind = TSyntaxKind.ConstDecl then
        begin
          CheckConstant(Node);
        end;
      end;
    finally
      Resolver.UnpinTree;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Nodes := PreOrder(AContext.Tree.Root);
  Nested := TList<TSyntaxNode>.Create;
  Names := TStringList.Create;
  try
    Names.CaseSensitive := False;
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    if CollectNested then
    begin
      CheckNodes;
    end;
  finally
    Names.Free;
    Nested.Free;
  end;
end;

{ TConditionNotBooleanRule }

function TConditionNotBooleanRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ConditionNotBooleanRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.ConditionTitle].Text);
end;

procedure TConditionNotBooleanRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Local: TUnitIndex;
  Node: TSyntaxNode;

  /// <summary>Vergleich, der aus dem Wert vom Typ AType eine Bedingung macht ('&lt;&gt; 0', '&lt;&gt; nil' ...); '' ohne
  /// sicheren Typ.</summary>
  function Comparison(const AType: TResolvedSymbol): string;
  var
    FromUnit: TUnitIndex;
  begin
    Result := '';
    if AType.Builtin then
    begin
      if MatchText(AType.Name, ConditionIntegerTypes) or MatchText(AType.Name, ConditionFloatTypes) then
      begin
        Result := '<> 0';
      end
      else if MatchText(AType.Name, ConditionPointerTypes) then
      begin
        Result := '<> nil';
      end
      else if MatchText(AType.Name, ConditionStringTypes) then
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
    else if (AType.SymbolKind = TIndexSymbolKind.TypeAlias) and SymbolUnit(Resolver, Local, AType, FromUnit) and
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
    Symbol: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := (AInner.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
      Resolver.NodeType(AContext.Tree, FileName, AInner, Symbol, ATypeInfo, TypeFound) and TypeFound;
    Result := Result and not Symbol.IsType and (Symbol.Condition = '') and (Symbol.VariantBranch = '');
  end;

  procedure CheckCondition(ACondition: TSyntaxNode);
  var
    Inner: TSyntaxNode;
    TypeInfo: TResolvedSymbol;
    Compare, Text: string;
    Fixes: TArray<TRuleFix>;
  begin
    Inner := ACondition;
    while (Inner.Kind = TSyntaxKind.ParenExpr) and (Inner.ChildCount = 1) do
    begin
      Inner := Inner[0];
    end;
    if not ConditionType(Inner, TypeInfo) then
    begin
      Exit;
    end;
    Compare := Comparison(TypeInfo);
    if Compare = '' then
    begin
      Exit;
    end;
    Text := NodeText(AContext, ACondition);
    Fixes := [Replacement(ACondition, Text + ' ' + Compare, False)];
    if Compare = '<> nil' then
    begin
      Fixes := Fixes + [Replacement(ACondition, Format('Assigned(%s)', [Text]), True)];
    end
    else if MatchText(TypeInfo.Name, ConditionIntegerTypes) then
    begin
      Fixes := Fixes + [Replacement(ACondition, Text + ' > 0', True)];
    end;
    AReport.Add(TTextRange.Create(ACondition.StartPos, ACondition.EndPos),
      cTexts[TTypeChecksText.NotBoolean].Fmt([TypeInfo.Name]), TRuleConfidence.High, Fixes);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    Local := Resolver.ExtractedUnit(AContext.Tree, FileName);
    for Node in PreOrder(AContext.Tree.Root) do
      case Node.Kind of
        TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.IfExpr:
          if Node.ChildCount > 0 then
          begin
            CheckCondition(Node[0]);
          end;
        TSyntaxKind.RepeatStatement:
          // Die Bedingung hinter until ist das letzte Kind.
          if Node.ChildCount > 0 then
          begin
            CheckCondition(Node[Node.ChildCount - 1]);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
  finally
    Resolver.UnpinTree;
  end;
end;

{ TForInNotEnumerableRule }

function TForInNotEnumerableRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ForInNotEnumerableRuleId, TRuleSeverity.Error,
    cTexts[TTypeChecksText.EnumeratorTitle].Text);
end;

procedure TForInNotEnumerableRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  FileName: string;
  Node: TSyntaxNode;

  /// <summary>Sind alle Vorfahren von AType bekannt (bis TObject bzw. IInterface)? Nur dann steht fest, dass
  /// ein Mitglied fehlt.</summary>
  function AncestorsKnown(const AType: TResolvedSymbol): Boolean;
  var
    Current, Ancestor: TResolvedSymbol;
    Depth: Integer;
  begin
    Current := AType;
    for Depth := 0 to cMaxAncestorDepth do
    begin
      if (Current.SymbolKind = TIndexSymbolKind.RecordType) or SameText(Current.Name, 'TObject') or
        SameText(Current.Name, 'IInterface') then
      begin
        Exit(True);
      end;
      if not Resolver.AncestorOf(Current, Ancestor) then
      begin
        // Ohne eigene Angabe ist der Vorfahr TObject bzw. IInterface, auch wenn sie nicht im Index stehen.
        Exit(Length(Current.Ancestors) = 0);
      end;
      Current := Ancestor;
    end;
    Result := False;
  end;

  /// <summary>Eingebauter Typ ohne for-in: Zahl, Zeiger, Zeichen, Boolean. Strings, Arrays und Mengen kann for-in.
  /// </summary>
  function IsScalarName(const AName: string): Boolean;
  begin
    Result := MatchText(AName, ConditionIntegerTypes) or MatchText(AName, ConditionFloatTypes);
    Result := Result or MatchText(AName, ConditionPointerTypes) or
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
    Member: TResolvedSymbol;
    Hint: string;
  begin
    AMessage := '';
    Result := AncestorsKnown(AType);
    if not Result then
    begin
      Exit;
    end;
    Hint := '';
    if Resolver.FindMember(AType, 'Count', Member) then
    begin
      Hint := cTexts[TTypeChecksText.UseCount].Text;
    end;
    AMessage := cTexts[TTypeChecksText.NoEnumerator].Fmt([AType.Name, Hint]);
  end;

  /// <summary>Typ des Enumerators, den AMethod (GetEnumerator) liefert, wenn er sicher bekannt und nicht generisch
  /// ist.</summary>
  function EnumeratorOf(const AMethod: TResolvedSymbol; out AEnumerator: TResolvedSymbol): Boolean;
  var
    MethodUnit: TUnitIndex;
  begin
    Result := (AMethod.TypeName <> '') and (AMethod.TypeArgs = '') and Resolver.DeclaringUnit(AMethod, MethodUnit);
    Result := Result and Resolver.ResolveTypeFrom(MethodUnit, AMethod.TypeName, AEnumerator);
    Result := Result and not AEnumerator.Builtin and IsStructured(AEnumerator) and (AEnumerator.TypeParams = '');
  end;

  /// <summary>Fehlt dem Enumerator MoveNext oder Current (wie E2431)?</summary>
  function IncompleteEnumerator(const AType, AMethod: TResolvedSymbol; out AMessage: string): Boolean;
  var
    Enumerator, Member: TResolvedSymbol;
    Missing: string;
  begin
    AMessage := '';
    Result := False;
    if not EnumeratorOf(AMethod, Enumerator) then
    begin
      Exit;
    end;
    Missing := '';
    if not Resolver.FindMember(Enumerator, 'MoveNext', Member) then
    begin
      Missing := 'MoveNext';
    end
    else if not Resolver.FindMember(Enumerator, 'Current', Member) then
    begin
      Missing := 'Current';
    end;
    Result := (Missing <> '') and AncestorsKnown(Enumerator);
    if Result then
    begin
      AMessage := cTexts[TTypeChecksText.NoCurrent].Fmt([Enumerator.Name, AType.Name, Missing]);
    end;
  end;

  /// <summary>Kann der Typ sicher kein for-in? AMessage nennt den Grund.</summary>
  function NotEnumerable(const AType: TResolvedSymbol; out AMessage: string): Boolean;
  var
    Method: TResolvedSymbol;
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
    else if not Resolver.FindMember(AType, 'GetEnumerator', Method) then
    begin
      Result := NoEnumeratorMessage(AType, AMessage);
    end
    else
    begin
      // GetEnumerator gibt es: Der Enumerator braucht MoveNext und Current (wie E2431).
      Result := IncompleteEnumerator(AType, Method, AMessage);
    end;
  end;

  /// <summary>Durchlaufener Ausdruck der Schleife (das erste Kind, das kein Typverweis ist); nil ohne.</summary>
  function CollectionOf(ALoop: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    for Index := 0 to ALoop.ChildCount - 1 do
    begin
      if ALoop[Index].Kind <> TSyntaxKind.TypeReference then
      begin
        Exit(ALoop[Index]);
      end;
    end;
    Result := nil;
  end;

  /// <summary>Sicherer, nicht generischer Typ des Ausdrucks ACollection außerhalb bedingter Zweige.</summary>
  function CollectionType(ACollection: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
  var
    Symbol: TResolvedSymbol;
    TypeFound: Boolean;
  begin
    Result := (ACollection.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
      TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
      Resolver.NodeType(AContext.Tree, FileName, ACollection, Symbol, AType, TypeFound) and TypeFound;
    Result := Result and not Symbol.IsType and (Symbol.Condition = '') and (Symbol.VariantBranch = '');
    Result := Result and (AType.TypeParams = '');
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    Collection: TSyntaxNode;
    TypeInfo: TResolvedSymbol;
    Message: string;
  begin
    Collection := CollectionOf(ALoop);
    if (Collection <> nil) and CollectionType(Collection, TypeInfo) and NotEnumerable(TypeInfo, Message) then
    begin
      AReport.Add(TTextRange.Create(Collection.StartPos, Collection.EndPos), Message, TRuleConfidence.High);
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, ' in') then
  begin
    Exit;
  end;
  FileName := ResolverFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, FileName);
  try
    for Node in PreOrder(AContext.Tree.Root) do
    begin
      if Node.Kind = TSyntaxKind.ForInStatement then
      begin
        CheckLoop(Node);
      end;
    end;
  finally
    Resolver.UnpinTree;
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
