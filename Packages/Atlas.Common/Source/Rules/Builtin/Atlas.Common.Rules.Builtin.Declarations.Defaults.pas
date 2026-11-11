unit Atlas.Common.Rules.Builtin.Declarations.Defaults;

// Regel default-parameter aus Atlas.Common.Rules.Builtin.Declarations (#976, Standard aus): Parameter mit
// Vorgabewert; Korrektur: je weggelassenem Standardparameter eine Überladung, die mit dem Vorgabewert
// weiterreicht.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TDefaultParameterRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cDefaultParameterRuleId = 'default-parameter';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsDefaultsText = (Title, One, Many, Overloads);

const
  cTexts: array[TDeclarationsDefaultsText] of TAtlasText = (
    (De: 'Standardparameter statt Überladung'; En: 'Default parameter instead of overload'),
    (De: 'Standardparameter; eine Überladung ohne %s hält den Vorgabewert in der Bibliothek.';
     En: 'Default parameter; an overload without %s keeps the default value in the library.'),
    (De: 'Standardparameter; Überladungen ohne %s halten die Vorgabewerte in der Bibliothek.';
     En: 'Default parameters; overloads without %s keep the default values in the library.'),
    (De: 'Überladungen statt Standardparameter'; En: 'Overloads instead of default parameters'));

{$SCOPEDENUMS OFF}

{ TDefaultParameterRule }

function TDefaultParameterRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDefaultParameterRuleId, TRuleSeverity.Warning,
    cTexts[TDeclarationsDefaultsText.Title].Text, True);
end;

type
  TChangeParameters = TArray<Atlas.Common.Editing.ChangeSignature.TSignatureParameter>;

  /// <summary>Rumpf zu einer Deklaration: Kopf und Knoten; Found, wenn es ihn eindeutig gibt.</summary>
  TBodyMatch = record
    Header: TSignatureHeader;
    Node: TSyntaxNode;
    Found: Boolean;
  end;

procedure TDefaultParameterRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths: TArray<string>;
  mLines: TArray<string>;
  mLineBreak: string;
  mBodies, mCalls: TArray<TSyntaxNode>;

  // Bezeichner des Namens im Kopf (beim Rumpf TFoo.Bar der letzte Teil); -1 ohne.
  function NameToken(AHeader: TSyntaxNode): Integer;
  var
    mIndex: Integer;
    mName: string;
  begin
    mName := BareName(AHeader.Name);
    Result := -1;
    for mIndex := TokenFrom(mTokens, AHeader.StartOffset) to High(mTokens) do
    begin
      if (mTokens[mIndex].Offset >= AHeader.EndOffset) or mTokens[mIndex].IsSymbol('(') or
        mTokens[mIndex].IsSymbol(':') or
        mTokens[mIndex].IsSymbol(';') then
      begin
        Break;
      end;
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, mName) then
      begin
        Result := mIndex;
      end;
    end;
  end;

  // Modifizierer und Typen ohne Namen und Standardwerte, kleingeschrieben.
  function ParamKey(const AParameters: TChangeParameters): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := 0 to High(AParameters) do
    begin
      Result := Result + LowerCase(AParameters[mIndex].Modifier + ' ' + AParameters[mIndex].TypeName) + ';';
    end;
  end;

  function IndentAt(AToken: Integer): string;
  begin
    Result := '';
    if mTokens[AToken].StartPos.Line <= High(mLines) then
    begin
      Result := TTextLines.IndentOf(mLines[mTokens[AToken].StartPos.Line]);
    end;
  end;

  function Conditional(const AHeader: TSignatureHeader): Boolean;
  begin
    Result := TConditionalBranches.PathAt(mPaths, AHeader.StartToken) <> '';
  end;

  // Rumpf zur Deklaration: gleicher (qualifizierter) Name und gleiche Parameter, ohne Parameterliste nur eindeutig.
  function BodyOf(const AName: string; const ADecl: TSignatureHeader): TBodyMatch;
  var
    mNode: TSyntaxNode;
    mCandidate: TSignatureHeader;
    mCount: Integer;
  begin
    Result := Default(TBodyMatch);
    mCount := 0;
    for mNode in mBodies do
    begin
      if SameText(StringReplace(mNode.Name, ' ', '', [rfReplaceAll]), AName) and
        TChangeSignature.ReadHeader(AContext.Text, mTokens, NameToken(mNode), mCandidate) and
        (mCandidate.StartToken > ADecl.LastToken) and
        ((mCandidate.OpenToken < 0) or (ParamKey(mCandidate.Parameters) = ParamKey(ADecl.Parameters))) then
      begin
        Inc(mCount);
        Result.Header := mCandidate;
        Result.Node := mNode;
      end;
    end;
    Result.Found := mCount = 1;
  end;

  // Steht der Name irgendwo nicht als Aufruf (Methodenzeiger, @Routine)? Dann wäre er nach der Korrektur mehrdeutig.
  function UsedAsValue(const AName: string): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    for mNode in mCalls do
    begin
      if SameText(mNode.Name, AName) and (mNode.Parent <> nil) and (mNode.Parent.Kind <> TSyntaxKind.CallStatement) and
        not ((mNode.Parent.Kind = TSyntaxKind.Call) and (mNode.Parent[0] = mNode)) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // " = Wert" hinter den Parametern des Kopfs AHeader entfernen; Zeilenumbrüche der Liste bleiben.
  function DefaultRemovals(AHeader: TSyntaxNode): TArray<TRuleEdit>;
  var
    mParams, mParam: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := nil;
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    if mParams <> nil then
    begin
      for mIndex := 0 to mParams.ChildCount - 1 do
      begin
        mParam := mParams[mIndex];
        if (mParam.Kind = TSyntaxKind.Parameter) and (mParam.ChildCount > 1) then
        begin
          Result := Result + [TRuleEdit.Create(TTextRange.Create(mParam[0].EndPos,
            mParam[mParam.ChildCount - 1].EndPos),
            '')];
        end;
      end;
    end;
  end;

  // Neue Routinen bzw. Köpfe vor ADecl: je eine Überladung ohne die letzten Standardparameter.
  function Fix(const ADecl: TSignatureHeader; ADeclNode: TSyntaxNode; const ABody: TBodyMatch; ADeclIsBody: Boolean;
    AFirst: Integer): TArray<TRuleEdit>;
  var
    mCount, mIndex: Integer;
    mPrefix: TChangeParameters;
    mChanges: TArray<TParameterChange>;
    mParameter: Atlas.Common.Editing.ChangeSignature.TSignatureParameter;
    mIndent, mDeclarations, mRoutines, mName: string;

    function Routine(const AHeader: TSignatureHeader; const AQualified, ADirectives: string): string;
    begin
      Result := TChangeSignature.HeaderText(AHeader, AQualified, mPrefix, False) + ADirectives + mLineBreak + 'begin' +
        mLineBreak + '  ' + TChangeSignature.ForwardCall(AHeader, mPrefix, mChanges) + mLineBreak + 'end;' + mLineBreak +
        mLineBreak;
    end;

  begin
    mIndent := IndentAt(ADecl.StartToken);
    mName := BareName(ADecl.QualifiedName);
    mDeclarations := '';
    mRoutines := '';
    for mCount := AFirst to High(ADecl.Parameters) do
    begin
      mPrefix := Copy(ADecl.Parameters, 0, mCount);
      mChanges := nil;
      for mIndex := 0 to High(ADecl.Parameters) do
      begin
        mParameter := ADecl.Parameters[mIndex];
        if mIndex < mCount then
        begin
          mChanges := mChanges + [TParameterChange.Kept(mIndex, mParameter.Name)];
        end
        else
        begin
          mChanges := mChanges + [TParameterChange.Added(mParameter.Name, mParameter.TypeName, mParameter.Modifier,
            mParameter.DefaultValue)];
        end;
      end;
      if ADeclIsBody then
      begin
        mDeclarations := mDeclarations + Routine(ADecl, ADecl.QualifiedName,
          TChangeSignature.OverloadDirectives(ADecl, False)) + mIndent;
      end
      else
      begin
        mDeclarations := mDeclarations + TChangeSignature.HeaderText(ADecl, mName, mPrefix, False) +
          TChangeSignature.OverloadDirectives(ADecl, False) + mLineBreak + mIndent;
        if ABody.Found then
        begin
          mRoutines := mRoutines + Routine(ABody.Header, ABody.Header.QualifiedName, '');
        end;
      end;
    end;
    Result := [TRuleEdit.Create(TTextRange.Create(mTokens[ADecl.StartToken].StartPos,
      mTokens[ADecl.StartToken].StartPos),
      mDeclarations)] + DefaultRemovals(ADeclNode);
    if not ADecl.HasDirective('overload') then
    begin
      Result := Result + [TRuleEdit.Create(TTextRange.Create(mTokens[ADecl.EndToken].EndPos,
        mTokens[ADecl.EndToken].EndPos), ' overload;')];
    end;
    if ABody.Found then
    begin
      Result := Result + [TRuleEdit.Create(TTextRange.Create(mTokens[ABody.Header.StartToken].StartPos,
        mTokens[ABody.Header.StartToken].StartPos), mRoutines)];
      // Ein im Rumpf wiederholter Standardwert fällt ebenfalls weg.
      Result := Result + DefaultRemovals(ABody.Node);
    end;
  end;

  // Sieht keine andere Unit die Routine? implementation-Teil (auch Methoden dort deklarierter Typen und lokale
  // Routinen) oder Programmdatei. Dann prüft UsedAsValue alle Verwendungen als Wert, und die Korrektur ist sicher;
  // eine Routine aus dem interface-Teil könnte eine andere Unit als Methodenzeiger nehmen (dann mehrdeutig).
  function UnitPrivate(AHeader: TSyntaxNode): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    mNode := AHeader.Parent;
    while mNode <> nil do
    begin
      case mNode.Kind of
        TSyntaxKind.InterfaceSection:
          Exit(False);
        TSyntaxKind.ImplementationSection, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile:
          Exit(True);
      else
        // Weiter nach oben.
      end;
      mNode := mNode.Parent;
    end;
    Result := False;
  end;

  // Vorfahren, Nachfahren oder Aufrufer von außen geben die Signatur vor.
  function SignatureGiven(const AHeader: TSignatureHeader): Boolean;
  var
    mDirective: string;
  begin
    for mDirective in AHeader.Directives do
    begin
      if MatchText(mDirective, ['virtual', 'dynamic', 'abstract', 'override', 'external', 'export']) or
        StartsText('message ', mDirective) or StartsText('external ', mDirective) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Namen der Parameter mit Vorgabewert; AFirst: Index des ersten, -1 ohne.
  function DefaultNames(const ADecl: TSignatureHeader; out AFirst: Integer): TArray<string>;
  var
    mIndex: Integer;
  begin
    AFirst := -1;
    Result := nil;
    for mIndex := High(ADecl.Parameters) downto 0 do
    begin
      if ADecl.Parameters[mIndex].DefaultValue <> '' then
      begin
        AFirst := mIndex;
        Result := [ADecl.Parameters[mIndex].Name] + Result;
      end;
    end;
  end;

  function DefaultMessage(const ANames: TArray<string>): string;
  begin
    if Length(ANames) = 1 then
    begin
      Result := cTexts[TDeclarationsDefaultsText.One].Fmt([ANames[0]]);
    end
    else
    begin
      Result := cTexts[TDeclarationsDefaultsText.Many].Fmt([JoinedList(ANames)]);
    end;
  end;

  // Gibt es im Bereich AScope eine andere Routine gleichen Namens wie AHeader?
  function HasNamesake(AHeader: TSyntaxNode; const AScope: TArray<TSyntaxNode>): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    Result := False;
    for mNode in AScope do
    begin
      Result := Result or ((mNode <> AHeader) and SameText(BareName(mNode.Name), BareName(AHeader.Name)));
    end;
  end;

  // Korrektur nur, wo die neuen Überladungen sicher eindeutig sind und niemand die Signatur vorgibt.
  function FixAllowed(AHeader: TSyntaxNode; const ADecl: TSignatureHeader; const AScope: TArray<TSyntaxNode>;
    AType: TSyntaxNode): Boolean;
  begin
    Result := not Conditional(ADecl) and not UsedAsValue(BareName(AHeader.Name));
    Result := Result and ((AType = nil) or (AType.Kind <> TSyntaxKind.InterfaceType)) and
      not SignatureGiven(ADecl) and not HasNamesake(AHeader, AScope);
  end;

  // Steht AHeader in einer Routine mit Rumpf (keine Deklaration im interface oder Typ)?
  function IsBodyHeader(AHeader: TSyntaxNode): Boolean;
  begin
    Result := (AHeader.Parent <> nil) and (AHeader.Parent.Kind = TSyntaxKind.RoutineDecl) and
      (AHeader.Parent.FindChild(TSyntaxKind.Block) <> nil);
  end;

  // Name des Rumpfs zu AHeader (bei Methoden TFoo.Bar); False bei verschachtelten und generischen Typen, deren
  // Rumpf sich nicht sicher zuordnen lässt.
  function BodyName(AHeader, AType: TSyntaxNode; out AName: string): Boolean;
  begin
    AName := BareName(AHeader.Name);
    Result := AType = nil;
    if Result then
    begin
      Exit;
    end;
    Result := not ((AType.Parent = nil) or (AType.Parent.Kind <> TSyntaxKind.TypeDecl) or
      (AType.Parent.Parent = nil) or (AType.Parent.Parent.Kind <> TSyntaxKind.TypeSection) or
      (Pos('<', AType.Parent.Name) > 0));
    if Result then
    begin
      AName := AType.Parent.Name + '.' + AName;
    end;
  end;

  // Rumpf zur Deklaration AHeader außerhalb von {$IF…}-Zweigen; Found False, wenn es keinen sicheren gibt.
  function FixBody(AHeader: TSyntaxNode; const ADecl: TSignatureHeader; AType: TSyntaxNode): TBodyMatch;
  var
    mQualified: string;
  begin
    Result := Default(TBodyMatch);
    if BodyName(AHeader, AType, mQualified) then
    begin
      Result := BodyOf(mQualified, ADecl);
      Result.Found := Result.Found and not Conditional(Result.Header);
    end;
  end;

  // Meldung am ersten Parameter mit Vorgabewert bis zum Ende der Liste.
  procedure ReportAt(AParams: TSyntaxNode; const AMessage: string; const AFixes: TArray<TRuleFix>);
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to AParams.ChildCount - 1 do
    begin
      if (AParams[mIndex].Kind = TSyntaxKind.Parameter) and (AParams[mIndex].ChildCount > 1) then
      begin
        AReport.Add(TTextRange.Create(AParams[mIndex].StartPos, AParams[AParams.ChildCount - 1].EndPos), AMessage,
          TRuleConfidence.High, AFixes);
        Break;
      end;
    end;
  end;

  // Meldet die Deklaration AHeader; AScope: andere Köpfe desselben Bereichs, AType: Typ bei Methoden.
  procedure CheckHeader(AHeader: TSyntaxNode; const AScope: TArray<TSyntaxNode>; AType: TSyntaxNode);
  var
    mDecl: TSignatureHeader;
    mBody: TBodyMatch;
    mParams: TSyntaxNode;
    mFirst: Integer;
    mNames: TArray<string>;
    mDeclIsBody, mCanFix: Boolean;
    mFixes: TArray<TRuleFix>;
  begin
    mParams := AHeader.FindChild(TSyntaxKind.Parameters);
    if (mParams = nil) or not TChangeSignature.ReadHeader(AContext.Text, mTokens, NameToken(AHeader), mDecl) then
    begin
      Exit;
    end;
    mNames := DefaultNames(mDecl, mFirst);
    if mFirst < 0 then
    begin
      Exit;
    end;
    mCanFix := FixAllowed(AHeader, mDecl, AScope, AType);
    mBody := Default(TBodyMatch);
    mDeclIsBody := IsBodyHeader(AHeader);
    if mCanFix and not mDeclIsBody then
    begin
      mBody := FixBody(AHeader, mDecl, AType);
      mCanFix := mBody.Found;
    end;
    mFixes := nil;
    // Sicher (auch für --fix und die Sammelkorrektur), wenn keine andere Unit die Routine sieht.
    if mCanFix then
    begin
      mFixes := [TRuleFix.Create(cTexts[TDeclarationsDefaultsText.Overloads].Text,
        Fix(mDecl, AHeader, mBody, mDeclIsBody,
        mFirst),
        UnitPrivate(AHeader))];
    end;
    ReportAt(mParams, DefaultMessage(mNames), mFixes);
  end;

  // Köpfe von Routinen direkt unter ANode; Rümpfe zu einer früheren Deklaration zählen nicht.
  procedure CheckRoutines(ANode: TSyntaxNode; var AScope: TArray<TSyntaxNode>);
  var
    mIndex: Integer;
    mHeader: TSyntaxNode;
  begin
    if ANode = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind = TSyntaxKind.RoutineDecl then
      begin
        mHeader := ANode[mIndex].FindChild(TSyntaxKind.RoutineHeader);
        if (mHeader <> nil) and (Pos('.', mHeader.Name) = 0) then
        begin
          AScope := AScope + [mHeader];
        end;
      end;
    end;
  end;

  // Methodenköpfe des Typs AType, jeder gegen die übrigen geprüft.
  procedure CheckType(AType: TSyntaxNode);
  var
    mScope: TArray<TSyntaxNode>;
    mHeader: TSyntaxNode;
    mIndex: Integer;
  begin
    mScope := nil;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      if AType[mIndex].Kind = TSyntaxKind.RoutineHeader then
      begin
        mScope := mScope + [AType[mIndex]];
      end;
    end;
    for mHeader in mScope do
    begin
      CheckHeader(mHeader, mScope, AType);
    end;
  end;

  // Ist AOther eine frühere Deklaration ohne Rumpf (interface, forward) zum Rumpf AHeader (Kopf ADecl) mit
  // gleichen Parametern bzw. zur Kurzform ohne Parameterliste?
  function DeclaresEarlier(AOther, AHeader: TSyntaxNode; const ADecl: TSignatureHeader): Boolean;
  var
    mEarlier: TSignatureHeader;
  begin
    Result := (AOther <> AHeader) and (AOther.Parent.FindChild(TSyntaxKind.Block) = nil) and
      SameText(AOther.Name, AHeader.Name) and (AOther.StartOffset < AHeader.StartOffset);
    Result := Result and TChangeSignature.ReadHeader(AContext.Text, mTokens, NameToken(AOther), mEarlier) and
      ((ADecl.OpenToken < 0) or (ParamKey(ADecl.Parameters) = ParamKey(mEarlier.Parameters)));
  end;

  // Rumpf zu einer früheren Deklaration (interface, forward) mit gleichen Parametern?
  function IsLaterBody(AHeader: TSyntaxNode; const AScope: TArray<TSyntaxNode>): Boolean;
  var
    mDecl: TSignatureHeader;
    mOther: TSyntaxNode;
  begin
    Result := False;
    if (AHeader.Parent.FindChild(TSyntaxKind.Block) = nil) or
      not TChangeSignature.ReadHeader(AContext.Text, mTokens, NameToken(AHeader), mDecl) then
    begin
      Exit;
    end;
    for mOther in AScope do
    begin
      Result := Result or DeclaresEarlier(mOther, AHeader, mDecl);
    end;
  end;

  // Routinen der Unit, des Programms, der Bibliothek bzw. lokale Routinen von ANode.
  procedure CheckScope(ANode: TSyntaxNode);
  var
    mScope, mDeclared: TArray<TSyntaxNode>;
    mHeader: TSyntaxNode;
  begin
    mScope := nil;
    if ANode.Kind = TSyntaxKind.UnitFile then
    begin
      CheckRoutines(ANode.FindChild(TSyntaxKind.InterfaceSection), mScope);
      CheckRoutines(ANode.FindChild(TSyntaxKind.ImplementationSection), mScope);
    end
    else
    begin
      CheckRoutines(ANode, mScope);
    end;
    mDeclared := nil;
    for mHeader in mScope do
    begin
      if not IsLaterBody(mHeader, mScope) then
      begin
        mDeclared := mDeclared + [mHeader];
      end;
    end;
    for mHeader in mDeclared do
    begin
      CheckHeader(mHeader, mDeclared, nil);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mNode: TSyntaxNode;
    mIndex: Integer;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        case mNode.Kind of
          TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
          TSyntaxKind.HelperType:
            CheckType(mNode);
          TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.RoutineDecl:
            CheckScope(mNode);
        else
          // Übrige Werte bewusst ohne Wirkung.
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
  mTokens := AContext.Tree.Tokens;
  mPaths := TConditionalBranches.Paths(mTokens);
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mBodies := nil;
  mCalls := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.RoutineDecl) and (ANode.Parent.FindChild(TSyntaxKind.Block) <> nil) then
      begin
        mBodies := mBodies + [ANode];
      end
      else if ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
      begin
        mCalls := mCalls + [ANode];
      end;
      Result := True;
    end);
  Visit(AContext.Tree.Root);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.Defaults', cTexts);

end.
