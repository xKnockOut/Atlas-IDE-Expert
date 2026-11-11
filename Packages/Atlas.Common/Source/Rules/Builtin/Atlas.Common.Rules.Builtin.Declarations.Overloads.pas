unit Atlas.Common.Rules.Builtin.Declarations.Overloads;

// Regel overload-directive-missing aus Atlas.Common.Rules.Builtin.Declarations (#987): gleichnamige Routinen
// bzw. Methoden eines Bereichs ohne overload (wie E2254, E2267) oder mit gleichen Parametern (E2252, E2301);
// Korrektur: overload; anhängen.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TOverloadDirectiveMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  cOverloadDirectiveMissingRuleId = 'overload-directive-missing';

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
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Rules.Builtin.Declarations.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsOverloadsText = (Title, NotMarked, EarlierNotMarked, AppendOverload, SameSignatureResult,
    SameSignature);

const
  cTexts: array[TDeclarationsOverloadsText] of TAtlasText = (
    (De: 'Überladung ohne overload oder mit gleicher Signatur';
     En: 'Overload without overload directive or with the same signature'),
    (De: '%s ist überladen, aber nicht mit overload markiert (wie E2254).';
     En: '%s is overloaded but not marked with overload (like E2254).'),
    (De: '%s ist überladen, die frühere Deklaration in Zeile %d trägt kein overload (wie E2267).';
     En: '%s is overloaded, the earlier declaration in line %d has no overload (like E2267).'),
    (De: 'overload; an alle Deklarationen anhängen'; En: 'Append overload; to all declarations'),
    (De: '%s mit denselben Parametern und demselben Ergebnistyp gibt es schon in Zeile %d (wie E2301).';
     En: '%s with the same parameters and the same result type already exists in line %d (like E2301).'),
    (De: '%s mit denselben Parametern gibt es schon in Zeile %d (wie E2252).';
     En: '%s with the same parameters already exists in line %d (like E2252).'));

{$SCOPEDENUMS OFF}

{ TOverloadDirectiveMissingRule }

function TOverloadDirectiveMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cOverloadDirectiveMissingRuleId, TRuleSeverity.Error,
    cTexts[TDeclarationsOverloadsText.Title].Text);
end;

type
  /// <summary>Eine Deklaration in einem Gültigkeitsbereich für overload-directive-missing (#987).</summary>
  TOverloadEntry = record
    Header: TSyntaxNode;
    Name: string;
    HasOverload: Boolean;
    /// <summary>Parameterarten und -typen samt Zahl der Typparameter, kleingeschrieben.</summary>
    Parameters: string;
    ResultType: string;
    Path: string;
  end;

procedure TOverloadDirectiveMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths: TArray<string>;

  function FirstToken(ANode: TSyntaxNode): Integer;
  begin
    Result := TokenFrom(mTokens, ANode.StartOffset);
  end;

  function NodeKey(ANode: TSyntaxNode): string;
  var
    mIndex: Integer;
  begin
    // Quelltext ohne Leerraum und Kommentare, kleingeschrieben.
    Result := '';
    for mIndex := FirstToken(ANode) to High(mTokens) do
    begin
      if mTokens[mIndex].Offset >= ANode.EndOffset then
      begin
        Break;
      end;
      if not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      begin
        Result := Result + LowerCase(mTokens[mIndex].Text);
      end;
    end;
  end;

  // class operator Implicit … darf ohne overload mehrfach stehen.
  function IsOperator(AHeader: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    mIndex := FirstToken(AHeader);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < AHeader.EndOffset) and
      (mTokens[mIndex].Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier, TPascalTokenKind.Comment]) and
      not SameText(mTokens[mIndex].Text, AHeader.Name) do
    begin
      if SameText(mTokens[mIndex].Text, 'operator') then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
    Result := False;
  end;

  // Parameterarten und -typen der Parameterliste AParams; A, B: Integer zählt als zwei Parameter.
  function ParameterKey(AParams: TSyntaxNode): string;
  const
    cModifiers: array[TParameterModifier] of string = ('', 'const ', 'var ', 'out ', 'constref ');
  var
    mInner, mCount: Integer;
    mParameter, mTypeNode: TSyntaxNode;
    mTypeText: string;
  begin
    Result := '';
    for mInner := 0 to AParams.ChildCount - 1 do
    begin
      mParameter := AParams[mInner];
      if mParameter.Kind <> TSyntaxKind.Parameter then
      begin
        Continue;
      end;
      // Auch offene Arrays: array of PTypeInfo ist nicht array of TValue (#1325).
      mTypeNode := TRoutineSignatures.ParameterType(mParameter);
      mTypeText := '?';
      if mTypeNode <> nil then
      begin
        mTypeText := NodeKey(mTypeNode);
      end;
      for mCount := 1 to Length(mParameter.Name.Split([','])) do
      begin
        Result := Result + cModifiers[mParameter.Modifier] + mTypeText + ';';
      end;
    end;
  end;

  function EntryOf(AHeader: TSyntaxNode): TOverloadEntry;
  var
    mIndex: Integer;
    mChild: TSyntaxNode;
  begin
    Result := Default(TOverloadEntry);
    Result.Header := AHeader;
    Result.Name := AHeader.Name;
    Result.Path := TConditionalBranches.PathAt(mPaths, FirstToken(AHeader));
    for mIndex := 0 to AHeader.ChildCount - 1 do
    begin
      mChild := AHeader[mIndex];
      case mChild.Kind of
        TSyntaxKind.Directive:
          // override braucht kein overload: Delphi übernimmt es von der überschriebenen Methode (mORMot2,
          // Graphics32, #1325).
          if MatchText(mChild.Name, ['overload', 'override']) then
          begin
            Result.HasOverload := True;
          end;
        TSyntaxKind.GenericParams:
          Result.Parameters := Result.Parameters + '<' + IntToStr(mChild.ChildCount) + '>';
        TSyntaxKind.Parameters:
          Result.Parameters := Result.Parameters + ParameterKey(mChild);
        TSyntaxKind.TypeReference:
          Result.ResultType := NodeKey(mChild);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

  // Wird AEarlier immer mit übersetzt, wenn ALater übersetzt wird?
  function Together(const ALater, AEarlier: TOverloadEntry): Boolean;
  begin
    Result := TConditionalBranches.Implies(ALater.Path, AEarlier.Path);
  end;

  // " overload;" hinter dem ersten Semikolon des Kopfs, also vor den übrigen Direktiven.
  function OverloadEdit(const AEntry: TOverloadEntry; out AEdit: TRuleEdit): Boolean;
  var
    mIndex, mDepth: Integer;
  begin
    mDepth := 0;
    for mIndex := FirstToken(AEntry.Header) to High(mTokens) do
    begin
      if mTokens[mIndex].Offset >= AEntry.Header.EndOffset then
      begin
        Break;
      end;
      if mTokens[mIndex].IsSymbol('(') or mTokens[mIndex].IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if mTokens[mIndex].IsSymbol(')') or mTokens[mIndex].IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and mTokens[mIndex].IsSymbol(';') then
      begin
        AEdit := TRuleEdit.Create(TTextRange.Create(mTokens[mIndex].EndPos, mTokens[mIndex].EndPos), ' overload;');
        Exit(True);
      end;
    end;
    AEdit := Default(TRuleEdit);
    Result := False;
  end;

  function NameRange(const AEntry: TOverloadEntry): TTextRange;
  var
    mIndex: Integer;
  begin
    for mIndex := FirstToken(AEntry.Header) to High(mTokens) do
    begin
      if mTokens[mIndex].Offset >= AEntry.Header.EndOffset then
      begin
        Break;
      end;
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AEntry.Name) then
      begin
        Exit(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos));
      end;
    end;
    Result := TTextRange.Create(AEntry.Header.StartPos, AEntry.Header.EndPos);
  end;

  // " overload;" an allen Deklarationen ohne overload.
  function MissingEdits(const AEntries: TArray<TOverloadEntry>): TArray<TRuleEdit>;
  var
    mEdit: TRuleEdit;
    mEntry: TOverloadEntry;
  begin
    Result := nil;
    for mEntry in AEntries do
    begin
      if not mEntry.HasOverload and OverloadEdit(mEntry, mEdit) then
      begin
        Result := Result + [mEdit];
      end;
    end;
  end;

  // E2254/E2267 für ALater gegen AEarlier, mit einer Korrektur für alle Deklarationen ohne overload.
  procedure ReportMissing(const AEntries: TArray<TOverloadEntry>; const ALater, AEarlier: TOverloadEntry);
  var
    mEdits: TArray<TRuleEdit>;
    mMessage: string;
    mFixes: TArray<TRuleFix>;
  begin
    if not ALater.HasOverload then
    begin
      mMessage := cTexts[TDeclarationsOverloadsText.NotMarked].Fmt([ALater.Name]);
    end
    else
    begin
      mMessage := cTexts[TDeclarationsOverloadsText.EarlierNotMarked].Fmt(
        [ALater.Name, AEarlier.Header.StartPos.Line + 1]);
    end;
    mEdits := MissingEdits(AEntries);
    mFixes := nil;
    if mEdits <> nil then
    begin
      mFixes := [TRuleFix.Create(cTexts[TDeclarationsOverloadsText.AppendOverload].Text, mEdits, True)];
    end;
    AReport.Add(NameRange(ALater), mMessage, TRuleConfidence.High, mFixes);
  end;

  // E2301/E2252: ALater hat dieselben Parameter wie AEarlier.
  procedure ReportSame(const ALater, AEarlier: TOverloadEntry);
  var
    mMessage: string;
  begin
    if (ALater.ResultType <> '') and (ALater.ResultType = AEarlier.ResultType) then
    begin
      mMessage := cTexts[TDeclarationsOverloadsText.SameSignatureResult].Fmt([ALater.Name,
        AEarlier.Header.StartPos.Line + 1]);
    end
    else
    begin
      mMessage := cTexts[TDeclarationsOverloadsText.SameSignature].Fmt([ALater.Name, AEarlier.Header.StartPos.Line +
        1]);
    end;
    AReport.Add(NameRange(ALater), mMessage, TRuleConfidence.High);
  end;

  procedure CheckGroup(const AEntries: TArray<TOverloadEntry>);
  var
    mLater, mEarlier: Integer;
    mReported: Boolean;
  begin
    mReported := False;
    for mLater := 1 to High(AEntries) do
    begin
      for mEarlier := 0 to mLater - 1 do
      begin
        if not Together(AEntries[mLater], AEntries[mEarlier]) then
        begin
          Continue;
        end;
        // E2254/E2267 einmal je Name.
        if not mReported and (not AEntries[mLater].HasOverload or not AEntries[mEarlier].HasOverload) then
        begin
          mReported := True;
          ReportMissing(AEntries, AEntries[mLater], AEntries[mEarlier]);
        end;
        if AEntries[mLater].Parameters = AEntries[mEarlier].Parameters then
        begin
          ReportSame(AEntries[mLater], AEntries[mEarlier]);
          Break;
        end;
      end;
    end;
  end;

  // Ist AEntry eine Deklaration ohne eigene Implementierung (interface-Teil, forward)?
  function Open(const AEntry: TOverloadEntry): Boolean;
  begin
    Result := not TRoutineSignatures.HasImplementation(AEntry.Header.Parent);
  end;

  // Gehört die Implementierung AEntry zu einer früheren Deklaration ohne Implementierung? Mit gleichen Parametern
  // oder in Kurzform (function Foo;) zur einzigen gleichen Namens (#1325).
  function ImplementsEarlier(const AEntries: TArray<TOverloadEntry>; const AEntry: TOverloadEntry): Boolean;
  var
    mOther: TOverloadEntry;
    mCount: Integer;
  begin
    mCount := 0;
    for mOther in AEntries do
    begin
      if SameText(mOther.Name, AEntry.Name) and Open(mOther) then
      begin
        if mOther.Parameters = AEntry.Parameters then
        begin
          Exit(True);
        end;
        Inc(mCount);
      end;
    end;
    Result := (mCount = 1) and TRoutineSignatures.IsShortForm(AEntry.Header);
  end;

  // Zählt AHeader nicht mit: Methodenrumpf TFoo.Bar, ohne Namen, Operator, class constructor/destructor?
  function Skipped(AHeader: TSyntaxNode): Boolean;
  begin
    Result := (Pos('.', AHeader.Name) > 0) or (AHeader.Name = '') or IsOperator(AHeader) or
      TRoutineSignatures.IsClassConstructor(mTokens, AHeader);
  end;

  // Deklarationen eines Bereichs nach Namen (Schlüssel in Großbuchstaben, Reihenfolge des ersten Auftretens in
  // AOrder); eine Implementierung (begin, asm oder external) zu einer früheren Deklaration (interface, forward)
  // zählt nicht. class constructor und class destructor sind keine Überladungen der Instanzmethoden (#1325).
  // Gruppiert über ein Dictionary: Je Kopf über alle früheren zu suchen war in Klassen mit vielen Methoden
  // quadratisch.
  procedure ScopeGroups(const AHeaders: TArray<TSyntaxNode>; ABodiesFollow: Boolean; AOrder: TList<string>;
    AGroups: TDictionary<string, TArray<TOverloadEntry>>);
  var
    mEntry: TOverloadEntry;
    mHeader: TSyntaxNode;
    mKey: string;
    mGroup: TArray<TOverloadEntry>;
    mIsBody: Boolean;
  begin
    for mHeader in AHeaders do
    begin
      if Skipped(mHeader) then
      begin
        Continue;
      end;
      mEntry := EntryOf(mHeader);
      mKey := UpperCase(mEntry.Name);
      if not AGroups.TryGetValue(mKey, mGroup) then
      begin
        mGroup := nil;
      end;
      mIsBody := ABodiesFollow and (mHeader.Parent <> nil) and
        TRoutineSignatures.HasImplementation(mHeader.Parent) and ImplementsEarlier(mGroup, mEntry);
      if not mIsBody then
      begin
        if mGroup = nil then
        begin
          AOrder.Add(mKey);
        end;
        AGroups.AddOrSetValue(mKey, mGroup + [mEntry]);
      end;
    end;
  end;

  // Deklarationen eines Bereichs nach Namen prüfen.
  procedure CheckScope(const AHeaders: TArray<TSyntaxNode>; ABodiesFollow: Boolean);
  var
    mOrder: TList<string>;
    mGroups: TDictionary<string, TArray<TOverloadEntry>>;
    mKey: string;
  begin
    mOrder := TList<string>.Create;
    mGroups := TDictionary<string, TArray<TOverloadEntry>>.Create;
    try
      ScopeGroups(AHeaders, ABodiesFollow, mOrder, mGroups);
      for mKey in mOrder do
      begin
        if Length(mGroups[mKey]) > 1 then
        begin
          CheckGroup(mGroups[mKey]);
        end;
      end;
    finally
      mGroups.Free;
      mOrder.Free;
    end;
  end;

  // Köpfe der Routinen direkt unter ANode (RoutineDecl mit RoutineHeader).
  procedure AddRoutines(ANode: TSyntaxNode; var AHeaders: TArray<TSyntaxNode>);
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
        if mHeader <> nil then
        begin
          AHeaders := AHeaders + [mHeader];
        end;
      end;
    end;
  end;

  // Methodenköpfe eines Typs.
  function TypeHeaders(AType: TSyntaxNode): TArray<TSyntaxNode>;
  var
    mIndex: Integer;
  begin
    Result := nil;
    for mIndex := 0 to AType.ChildCount - 1 do
    begin
      if AType[mIndex].Kind = TSyntaxKind.RoutineHeader then
      begin
        Result := Result + [AType[mIndex]];
      end;
    end;
  end;

  // Prüft den Bereich ANode, wenn er einer ist (Typ, Unit, Programm, Bibliothek, Routine).
  procedure CheckNode(ANode: TSyntaxNode);
  var
    mHeaders: TArray<TSyntaxNode>;
  begin
    mHeaders := nil;
    case ANode.Kind of
      TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.InterfaceType,
      TSyntaxKind.HelperType:
        CheckScope(TypeHeaders(ANode), False);
      TSyntaxKind.UnitFile:
        begin
          AddRoutines(ANode.FindChild(TSyntaxKind.InterfaceSection), mHeaders);
          AddRoutines(ANode.FindChild(TSyntaxKind.ImplementationSection), mHeaders);
          CheckScope(mHeaders, True);
        end;
      TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.RoutineDecl:
        begin
          AddRoutines(ANode, mHeaders);
          CheckScope(mHeaders, True);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        CheckNode(mNode);
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
  Visit(AContext.Tree.Root);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.Overloads', cTexts);

end.
