unit Atlas.Common.Rules.Builtin.MethodDirectives;

// Direktiven an Methoden und Klassen (#909, Gruppe Compiler vorab):
//   abstract-declaration-invalid  abstract, final oder static falsch kombiniert
//                                 (#998): abstract ohne virtual oder dynamic
//                                 (E2167), Rumpf zu einer abstrakten Methode
//                                 (E2136), final ohne virtual (E2351), abstract
//                                 zusammen mit final (E2371), eine Klasse
//                                 abstract sealed (E2383) und static an einer
//                                 Instanzmethode oder virtuellen Klassenmethode
//                                 (E2376). Eine Klasse sealed mit offenen
//                                 abstrakten Methoden (#1380): an der Klasse
//                                 E2540 und je Methode E2539, an einer eigenen
//                                 abstrakten Methode zusätzlich E2383;
//                                 abstract sealed meldet auch E2540 (wie dcc in
//                                 Cm.E2383, Cm.E2539, Cm.E2540).
//
// Die Regel liest die Direktiven aus dem Syntaxbaum. Nur für geerbte abstrakte
// Methoden fragt sie Datei und Index über TAncestry (wie
// abstract-class-instantiated); bricht die Kette der Vorfahren ab, fehlen nur
// die Methoden jenseits der Lücke.
// override und message zählen wie virtual (override; abstract; deklariert eine
// geerbte Methode neu als abstrakt). Ein Rumpf gilt nur dann als Rumpf einer
// abstrakten Methode, wenn keine gleichnamige nicht abstrakte Methode derselben
// Klasse mit ihm übersetzt wird (Überladungen, Zweige von {$IFDEF} über
// TConditionalBranches).
//
// Korrekturen: "virtual;" vor abstract einfügen (E2167) bzw. den Rumpf
// entfernen (E2136).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  AbstractDeclarationInvalidRuleId = 'abstract-declaration-invalid';

type
  TAbstractDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterMethodDirectiveRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Lines;

type
  /// <summary>Methodendeklaration einer Klasse: abstrakt oder nicht, mit Zweig der bedingten Übersetzung.</summary>
  TDeclaredMethod = record
    ClassName: string;
    Name: string;
    IsAbstract: Boolean;
    Path: string;
  end;

/// <summary>Typname ohne Typparameter ("TListe&lt;T&gt;" wird "TListe").</summary>
function WithoutTypeParams(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

function TAbstractDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AbstractDeclarationInvalidRuleId, TRuleSeverity.Error,
    'abstract, final oder static falsch kombiniert');
end;

procedure TAbstractDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  // Deklarierte Methoden je Klasse.Name (Großbuchstaben): Lookup suchte je Rumpf über alle (quadratisch).
  Declared: TDictionary<string, TArray<TDeclaredMethod>>;
  Lines: TArray<string>;
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;

  /// <summary>Erstes Token ab AOffset (Index); Length(Tokens) ohne.</summary>
  function TokenAt(AOffset: Integer): Integer;
  var
    Low, High, Middle: Integer;
  begin
    Low := 0;
    High := Length(Tokens);
    while Low < High do
    begin
      Middle := (Low + High) div 2;
      if Tokens[Middle].Offset < AOffset then
      begin
        Low := Middle + 1;
      end
      else
      begin
        High := Middle;
      end;
    end;
    Result := Low;
  end;

  function TokenRange(AIndex: Integer): TTextRange;
  begin
    Result := TTextRange.Create(Tokens[AIndex].StartPos, Tokens[AIndex].EndPos);
  end;

  function DeclaredKey(const AClassName, AName: string): string;
  begin
    Result := UpperCase(AClassName) + '.' + UpperCase(AName);
  end;

  procedure AddDeclared(const AMethod: TDeclaredMethod);
  var
    mKey: string;
    mGroup: TArray<TDeclaredMethod>;
  begin
    mKey := DeclaredKey(AMethod.ClassName, AMethod.Name);
    if not Declared.TryGetValue(mKey, mGroup) then
    begin
      mGroup := nil;
    end;
    Declared.AddOrSetValue(mKey, mGroup + [AMethod]);
  end;

  /// <summary>Token der Direktive ADirective im Kopf AHeader; -1 ohne.</summary>
  function DirectiveToken(AHeader: TSyntaxNode; const ADirective: string): Integer;
  var
    Index: Integer;
  begin
    for Index := 0 to AHeader.ChildCount - 1 do
    begin
      if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, ADirective) then
      begin
        Result := TokenAt(AHeader[Index].StartOffset);
        if Result < Length(Tokens) then
        begin
          Exit;
        end;
      end;
    end;
    Result := -1;
  end;

  function HasDirective(AHeader: TSyntaxNode; const ADirective: string): Boolean;
  begin
    Result := DirectiveToken(AHeader, ADirective) >= 0;
  end;

  procedure CheckHeader(const AClassName: string; AHeader: TSyntaxNode);
  var
    First, Abstract_, Final, Static: Integer;
    IsVirtual, IsClassMethod: Boolean;
    Method: TDeclaredMethod;
  begin
    First := TokenAt(AHeader.StartOffset);
    if First >= Length(Tokens) then
    begin
      Exit;
    end;
    IsClassMethod := Tokens[First].IsKeyword('class');
    IsVirtual := HasDirective(AHeader, 'virtual') or HasDirective(AHeader, 'dynamic') or
      HasDirective(AHeader, 'override') or HasDirective(AHeader, 'message');
    Abstract_ := DirectiveToken(AHeader, 'abstract');
    Final := DirectiveToken(AHeader, 'final');
    Static := DirectiveToken(AHeader, 'static');
    if (Abstract_ >= 0) and not IsVirtual then
    begin
      AReport.Add(TokenRange(Abstract_), 'abstract nur zusammen mit virtual oder dynamic (wie E2167).',
        TRuleConfidence.High, [TRuleFix.Create('"virtual;" vor abstract einfügen',
        [TRuleEdit.Create(TTextRange.Create(Tokens[Abstract_].StartPos, Tokens[Abstract_].StartPos), 'virtual; ')])]);
    end;
    if (Abstract_ >= 0) and (Final >= 0) then
    begin
      AReport.Add(TokenRange(Final), Format('%s ist abstract und final zugleich; eine abstrakte Methode muss ' +
        'sich überschreiben lassen (wie E2371).', [AHeader.Name]), TRuleConfidence.High);
    end
    else if (Final >= 0) and not IsVirtual then
    begin
      AReport.Add(TokenRange(Final), Format('final nur an virtuellen Methoden; %s ist nicht virtual, dynamic ' +
        'oder override (wie E2351).', [AHeader.Name]), TRuleConfidence.High);
    end;
    if Static >= 0 then
    begin
      if not IsClassMethod then
      begin
        AReport.Add(TokenRange(Static), Format('static nur an Klassenmethoden; %s ist eine Instanzmethode ' +
          '(wie E2376).', [AHeader.Name]), TRuleConfidence.High);
      end
      else if IsVirtual or (Abstract_ >= 0) then
      begin
        AReport.Add(TokenRange(Static), Format('static nur an nicht virtuellen Klassenmethoden; %s ist virtuell ' +
          '(wie E2376).', [AHeader.Name]), TRuleConfidence.High);
      end;
    end;
    Method.ClassName := AClassName;
    Method.Name := AHeader.Name;
    Method.IsAbstract := Abstract_ >= 0;
    Method.Path := TConditionalBranches.PathAt(Paths, First);
    AddDeclared(Method);
  end;

  /// <summary>E2383: "class abstract sealed" bzw. "class sealed abstract". ASealed: die Klasse ist sealed,
  /// AAbstract: abstract.</summary>
  procedure CheckClassHeader(ABody: TSyntaxNode; out AAbstract, ASealed: Boolean);
  var
    Index: Integer;
    Abstract_, Sealed: Boolean;
  begin
    AAbstract := False;
    ASealed := False;
    Index := TokenAt(ABody.StartOffset);
    if (Index >= Length(Tokens)) or not Tokens[Index].IsKeyword('class') then
    begin
      Exit;
    end;
    Abstract_ := False;
    Sealed := False;
    Inc(Index);
    while (Index < Length(Tokens)) and (Tokens[Index].Kind in [TPascalTokenKind.Identifier,
      TPascalTokenKind.Keyword, TPascalTokenKind.Comment]) do
    begin
      if Tokens[Index].Kind <> TPascalTokenKind.Comment then
      begin
        if SameText(Tokens[Index].Text, 'abstract') then
        begin
          Abstract_ := True;
        end
        else if SameText(Tokens[Index].Text, 'sealed') then
        begin
          Sealed := True;
        end
        else
        begin
          Break;
        end;
        AAbstract := Abstract_;
        ASealed := Sealed;
        if Abstract_ and Sealed then
        begin
          AReport.Add(TokenRange(Index), 'Eine Klasse ist entweder abstract oder sealed, nicht beides ' +
            '(wie E2383).', TRuleConfidence.High);
          Exit;
        end;
      end;
      Inc(Index);
    end;
  end;

  /// <summary>Token des Namens AName ab AFrom vor dem Offset AEnd (davor können Attribute stehen); -1 ohne.
  /// </summary>
  function NameToken(AFrom, AEnd: Integer; const AName: string): Integer;
  begin
    Result := AFrom;
    while (Result < Length(Tokens)) and (Tokens[Result].Offset < AEnd) do
    begin
      if (Tokens[Result].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Result].Text, AName) then
      begin
        Exit;
      end;
      Inc(Result);
    end;
    Result := -1;
  end;

  /// <summary>E2383 an jeder eigenen abstrakten Methode der sealed-Klasse AName.</summary>
  procedure ReportOwnAbstract(ABody: TSyntaxNode; const AName: string);
  var
    mIndex, mAbstract: Integer;
  begin
    for mIndex := 0 to ABody.ChildCount - 1 do
    begin
      if ABody[mIndex].Kind = TSyntaxKind.RoutineHeader then
      begin
        mAbstract := DirectiveToken(ABody[mIndex], 'abstract');
        if mAbstract >= 0 then
        begin
          AReport.Add(TokenRange(mAbstract), Format('%s ist abstract, die Klasse %s aber sealed; abstract und ' +
            'sealed schließen sich aus (wie E2383).', [ABody[mIndex].Name, AName]), TRuleConfidence.High);
        end;
      end;
    end;
  end;

  /// <summary>Klasse sealed (#1380): eigene abstrakte Methoden (E2383 an der Methode), offene abstrakte
  /// Methoden je E2539 und an der Klasse E2540; abstract sealed ebenso E2540.</summary>
  procedure CheckSealed(ADecl, ABody: TSyntaxNode; AAbstract: Boolean);
  var
    mName: string;
    mNameToken, mIndex: Integer;
    mLocation: TSymbolLocation;
    mOpen: TArray<TIndexSymbol>;
    mOwners: TArray<string>;
  begin
    mName := WithoutTypeParams(ADecl.Name);
    mNameToken := NameToken(TokenAt(ADecl.StartOffset), ABody.StartOffset, mName);
    if mNameToken < 0 then
    begin
      Exit;
    end;
    ReportOwnAbstract(ABody, mName);
    mOpen := nil;
    mOwners := nil;
    if Ancestry.FindClass(mName, mLocation) and (mLocation.FileName = '') then
    begin
      mOpen := Ancestry.OpenAbstractMethods(mLocation, mOwners);
    end;
    for mIndex := 0 to High(mOpen) do
    begin
      AReport.Add(TokenRange(mNameToken), Format('%s ist sealed und implementiert die abstrakte Methode %s.%s ' +
        'nicht (wie E2539).', [mName, mOwners[mIndex], mOpen[mIndex].Name]), TRuleConfidence.High);
    end;
    if mOpen <> nil then
    begin
      AReport.Add(TokenRange(mNameToken), Format('%s hat abstrakte Methoden und kann deshalb nicht sealed sein; ' +
        'kein Nachfahre könnte sie implementieren (wie E2540).', [mName]), TRuleConfidence.High);
    end
    else if AAbstract then
    begin
      AReport.Add(TokenRange(mNameToken), Format('%s ist abstract und kann deshalb nicht sealed sein (wie E2540).',
        [mName]), TRuleConfidence.High);
    end;
  end;

  /// <summary>Prüft die Klasse oder das Objekt der Typdeklaration ANode. Ergebnis ist deren Rumpf, ohne Klasse
  /// oder Objekt ANode selbst.</summary>
  function CheckTypeDecl(ANode: TSyntaxNode): TSyntaxNode;
  var
    mIndex: Integer;
    mAbstract, mSealed: Boolean;
  begin
    Result := ANode.FindChild(TSyntaxKind.ClassType);
    if Result = nil then
    begin
      Result := ANode.FindChild(TSyntaxKind.ObjectType);
    end;
    if Result = nil then
    begin
      Exit(ANode);
    end;
    mAbstract := False;
    mSealed := False;
    if Result.Kind = TSyntaxKind.ClassType then
    begin
      CheckClassHeader(Result, mAbstract, mSealed);
    end;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if Result[mIndex].Kind = TSyntaxKind.RoutineHeader then
      begin
        CheckHeader(WithoutTypeParams(ANode.Name), Result[mIndex]);
      end;
    end;
    if mSealed then
    begin
      CheckSealed(ANode, Result, mAbstract);
    end;
  end;

  /// <summary>Nur Deklarationscontainer: Anweisungen und Ausdrücke enthalten keine Typen (#1094).</summary>
  procedure PushContainers(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    for mIndex := ANode.ChildCount - 1 downto 0 do
    begin
      if ANode[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
        TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl] then
      begin
        APending.Push(ANode[mIndex]);
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          mNode := CheckTypeDecl(mNode);
        end;
        PushContainers(mPending, mNode);
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Wird mit dem Rumpf an APath eine nicht abstrakte Deklaration AClassName.AName übersetzt? Und
  /// eine abstrakte (AAbstract)?</summary>
  procedure Lookup(const AClassName, AName, APath: string; out AAbstract, AConcrete: Boolean);
  var
    Method: TDeclaredMethod;
    mGroup: TArray<TDeclaredMethod>;
  begin
    AAbstract := False;
    AConcrete := False;
    if not Declared.TryGetValue(DeclaredKey(AClassName, AName), mGroup) then
    begin
      Exit;
    end;
    for Method in mGroup do
    begin
      if not TConditionalBranches.Exclusive(Method.Path, APath) then
      begin
        if Method.IsAbstract then
        begin
          AAbstract := True;
        end
        else
        begin
          AConcrete := True;
        end;
      end;
    end;
  end;

  /// <summary>Korrektur: den Rumpf mit seinen Zeilen und einer folgenden Leerzeile entfernen.</summary>
  function RemoveBody(ARoutine: TSyntaxNode): TArray<TRuleFix>;
  var
    StartPos, EndPos: TTextPosition;
  begin
    Result := nil;
    StartPos := ARoutine.StartPos;
    EndPos := ARoutine.EndPos;
    if (StartPos.Line >= Length(Lines)) or (EndPos.Line >= Length(Lines)) or
      (Trim(Copy(Lines[StartPos.Line], 1, StartPos.Character)) <> '') or
      (Trim(Copy(Lines[EndPos.Line], EndPos.Character + 1, MaxInt)) <> '') then
    begin
      Exit;
    end;
    StartPos.Character := 0;
    EndPos.Line := EndPos.Line + 1;
    EndPos.Character := 0;
    if (EndPos.Line < Length(Lines)) and (Trim(Lines[EndPos.Line]) = '') and (StartPos.Line > 0) and
      (Trim(Lines[StartPos.Line - 1]) = '') then
    begin
      EndPos.Line := EndPos.Line + 1;
    end;
    Result := [TRuleFix.Create('Rumpf entfernen', [TRuleEdit.Create(TTextRange.Create(StartPos, EndPos), '')])];
  end;

  /// <summary>Token des Methodennamens AName hinter dem Klassennamen im Kopf AHeader; -1 ohne.</summary>
  function QualifiedNameToken(AHeader: TSyntaxNode; const AName: string): Integer;
  begin
    Result := TokenAt(AHeader.StartOffset);
    while (Result < Length(Tokens)) and (Tokens[Result].Offset < AHeader.EndOffset) do
    begin
      if (Result > 0) and Tokens[Result - 1].IsSymbol('.') and
        (Tokens[Result].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Result].Text, AName) then
      begin
        Exit;
      end;
      Inc(Result);
    end;
    Result := -1;
  end;

  /// <summary>Hat ARoutine einen Rumpf (Block oder asm)?</summary>
  function HasBody(ARoutine: TSyntaxNode): Boolean;
  begin
    Result := (ARoutine.FindChild(TSyntaxKind.Block) <> nil) or (ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil);
  end;

  /// <summary>Gehört der Rumpf ARoutine zu einer abstrakten Methode AClassName.AName, und keine gleichnamige
  /// nicht abstrakte wird mit ihm übersetzt?</summary>
  function IsAbstractBody(ARoutine: TSyntaxNode; const AClassName, AName: string): Boolean;
  var
    mAbstract, mConcrete: Boolean;
  begin
    Lookup(AClassName, AName, TConditionalBranches.PathAt(Paths, TokenAt(ARoutine.StartOffset)), mAbstract,
      mConcrete);
    Result := mAbstract and not mConcrete;
  end;

  procedure CheckBody(ARoutine: TSyntaxNode);
  var
    mParts: TArray<string>;
    mClassName, mName: string;
    mHeader: TSyntaxNode;
    mFirst: Integer;
  begin
    mParts := ARoutine.Name.Split(['.']);
    if not HasBody(ARoutine) or (Length(mParts) < 2) then
    begin
      Exit;
    end;
    mClassName := mParts[High(mParts) - 1];
    mName := mParts[High(mParts)];
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if (mHeader = nil) or not IsAbstractBody(ARoutine, mClassName, mName) then
    begin
      Exit;
    end;
    // Den Namen hinter dem Klassennamen markieren.
    mFirst := QualifiedNameToken(mHeader, mName);
    if mFirst >= 0 then
    begin
      AReport.Add(TokenRange(mFirst), Format('%s.%s ist abstract und darf keinen Rumpf haben (wie E2136).',
        [mClassName, mName]), TRuleConfidence.High, RemoveBody(ARoutine));
    end;
  end;

  // Rekursion nur in den implementation-Abschnitt (höchstens zwei Ebenen, unabhängig von der Ausdruckstiefe).
  procedure VisitBodies(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
      begin
        CheckBody(ANode[Index]);
      end
      else if ANode[Index].Kind = TSyntaxKind.ImplementationSection then
      begin
        VisitBodies(ANode[Index]);
      end;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text);
  Cache := TRuleDerived.Open(AContext);
  Declared := TDictionary<string, TArray<TDeclaredMethod>>.Create;
  try
    Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
    try
      Visit(AContext.Tree.Root);
    finally
      Ancestry.Free;
    end;
    if Declared.Count > 0 then
    begin
      VisitBodies(AContext.Tree.Root);
    end;
  finally
    Declared.Free;
  end;
end;

procedure RegisterMethodDirectiveRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAbstractDeclarationInvalidRule.Create);
end;

end.
