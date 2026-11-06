unit Atlas.Common.Rules.Builtin.Constants.TypedConstants;

// Regel typed-constant-modified (Teil von Atlas.Common.Rules.Builtin.Constants, dort registriert; Beschreibung
// dort).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

const
  TypedConstantModifiedRuleId = 'typed-constant-modified';

type
  TTypedConstantModifiedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Je Parameter der Signatur (mehrere Namen einzeln), ob er var oder out ist; nil ohne
    /// Parameterliste.</summary>
    class function VarParameters(const ASignature: string): TArray<Boolean>; static;
  end;


implementation

uses
  Atlas.Common.Index.NameFacts,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Constants.Types,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConstantsTypedConstantsText = (Title, ToVar, NeedsJ, Changed, ZeroNil, WriteNil);

const
  cTexts: array[TConstantsTypedConstantsText] of TAtlasText = (
    (De: 'Typisierte Konstante verändert'; En: 'Typed constant changed'),
    (De: 'In var mit Initialwert umwandeln'; En: 'Convert to var with initial value'),
    (De: '%s ist eine typisierte Konstante und kann ohne {$J+} nicht verändert werden (wie %s).';
     En: '%s is a typed constant and cannot be changed without {$J+} (like %s).'),
    (De: '%s ist eine typisierte Konstante und wird verändert (wie %s).';
     En: '%s is a typed constant and is changed (like %s).'),
    (De: '%s ist ein Zeiger; die 0 wird zu nil umgewandelt (wie W1013).';
     En: '%s is a pointer; the 0 is converted to nil (like W1013).'),
    (De: 'nil schreiben'; En: 'Write nil'));

{$SCOPEDENUMS OFF}

{ TTypedConstantModifiedRule }

function TTypedConstantModifiedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TypedConstantModifiedRuleId, TRuleSeverity.Warning,
    cTexts[TConstantsTypedConstantsText.Title].Text);
end;

/// <summary>Position der schließenden Klammer zur öffnenden an AOpen; 0, wenn keine passt.</summary>
function ClosingParen(const AText: string; AOpen: Integer): Integer;
var
  mDepth, mIndex: Integer;
begin
  Result := 0;
  mDepth := 0;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
end;

/// <summary>Je Name der Parametergruppe AGroup ("var A, B: Integer"): ist es ein var- oder out-Parameter?
/// </summary>
function GroupFlags(const AGroup: string): TArray<Boolean>;
var
  mNames, mHead: string;
  mColon, mIndex: Integer;
  mIsVar: Boolean;
begin
  // Standardwert und Typ abschneiden: nur die Namen zählen.
  mNames := AGroup;
  mColon := Pos(':', AGroup);
  if mColon > 0 then
  begin
    mNames := Trim(Copy(AGroup, 1, mColon - 1));
  end;
  mHead := LowerCase(mNames);
  mIsVar := mHead.StartsWith('var ') or mHead.StartsWith('out ');
  SetLength(Result, Length(mNames.Split([','], TStringSplitOptions.ExcludeEmpty)));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := mIsVar;
  end;
end;

class function TTypedConstantModifiedRule.VarParameters(const ASignature: string): TArray<Boolean>;
var
  mOpen, mClose, mDepth, mIndex, mStart: Integer;
  mChar: Char;
begin
  Result := nil;
  mOpen := Pos('(', ASignature);
  mClose := 0;
  if mOpen > 0 then
  begin
    mClose := ClosingParen(ASignature, mOpen);
  end;
  if mClose = 0 then
  begin
    Exit;
  end;
  mDepth := 0;
  mStart := mOpen + 1;
  for mIndex := mOpen + 1 to mClose do
  begin
    mChar := ASignature[mIndex];
    if CharInSet(mChar, ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(mChar, [']', '>']) or ((mChar = ')') and (mIndex < mClose)) then
    begin
      Dec(mDepth);
    end
    else if ((mChar = ';') and (mDepth = 0)) or (mIndex = mClose) then
    begin
      Result := Result + GroupFlags(Trim(Copy(ASignature, mStart, mIndex - mStart)));
      mStart := mIndex + 1;
    end;
  end;
end;

/// <summary>Positionen der var-Argumente eingebauter Routinen (Inc, Dec, Include …); nil bei anderen Namen.
/// </summary>
function BuiltinVarArguments(const AName: string): TArray<Integer>;
var
  mName: string;
begin
  mName := LowerCase(AName);
  if mName.StartsWith('system.') then
  begin
    mName := Copy(mName, Length('system.') + 1, MaxInt);
  end;
  case IndexStr(mName, ['inc', 'dec', 'include', 'exclude', 'setlength', 'delete', 'fillchar', 'initialize',
    'finalize', 'insert', 'str', 'move', 'val']) of
    0..8:
      Result := [0];
    9..11:
      Result := [1];
    12:
      Result := [1, 2];
  else
    Result := nil;
  end;
end;

/// <summary>Nächstes Glied links in der Zugriffskette (Empfänger eines Felds, Array eines Elements); nil am Ende.
/// </summary>
function ChainParent(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and (ANode.ChildCount > 0) then
  begin
    Result := ANode[0];
  end;
end;

/// <summary>Stelle von ANode unter den Kindern seines Elternknotens; -1 ohne.</summary>
function IndexInParent(ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to ANode.Parent.ChildCount - 1 do
  begin
    if ANode.Parent[mIndex] = ANode then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Ist die Konstante typisiert? Bei zusammengesetzten Typen (array[0..1] of Integer) fehlt TypeName,
/// die Signatur hat dann einen Doppelpunkt vor dem Gleichheitszeichen.</summary>
function IsTypedConstant(const ATypeName, ASignature: string): Boolean;
var
  Colon, Equals: Integer;
begin
  if ATypeName <> '' then
  begin
    Exit(True);
  end;
  Colon := Pos(':', ASignature);
  Equals := Pos('=', ASignature);
  Result := (Colon > 0) and ((Equals = 0) or (Colon < Equals));
end;

/// <summary>Ist der Typname ein eingebauter Zeigertyp (Pointer, PChar …)?</summary>
function IsPointerName(const ATypeName: string): Boolean;
var
  Name: string;
begin
  Name := LowerCase(Trim(ATypeName));
  if Name.StartsWith('system.') then
  begin
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  end;
  Result := (Name = 'pointer') or (Name = 'pchar') or (Name = 'pansichar') or (Name = 'pwidechar') or
    (Name = 'pbyte') or (Name = 'pword') or (Name = 'pinteger') or (Name = 'pcardinal') or (Name = 'pint64') or
    (Name = 'puint64') or (Name = 'psingle') or (Name = 'pdouble') or (Name = 'pextended') or
    (Name = 'pnativeint') or (Name = 'pnativeuint') or (Name = 'pboolean') or (Name = 'pstring');
end;

procedure TTypedConstantModifiedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  // Stand von {$J}/{$WRITEABLECONST} vor einer Stelle der Datei.
  TWriteable = (Unknown, Off, On_);
var
  FileName, LineBreak: string;
  Lines: TArray<string>;
  Resolver: TNameResolver;
  Cache: IRuleDerivedCache;
  // Namen typisierter Konstanten (Vorfilter): aus der Datei und aus dem Index.
  LocalNames, Suspects: TDictionary<string, Boolean>;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  function Before(const A, B: TTextPosition): Boolean;
  begin
    Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
  end;

  /// <summary>Text der Include-Datei AName neben der Unit; False, wenn sie sich nicht lesen lässt.</summary>
  function ReadInclude(const AName: string; out AText: string): Boolean;
  var
    mBytes: TBytes;
    mFormat: TFileFormat;
  begin
    AText := '';
    Result := (AName <> '') and Assigned(AContext.ReadFile) and AContext.ReadFile(AName, mBytes);
    if Result then
    begin
      AText := TFileEncoding.Decode(mBytes, mFormat);
    end;
  end;

  // Rekursiv über Include-Dateien (höchstens acht Ebenen): ApplyInclude spielt deren Direktiven nach.
  procedure ApplyDirective(const ADirective: string; ADepth: Integer; var AState: TWriteable); forward;

  /// <summary>Stand nach der Direktive AText (groß, ohne Leerzeichen): {$J±} bzw. {$WRITEABLECONST}; sonst
  /// ACurrent.</summary>
  function SettingOf(const AText: string; ACurrent: TWriteable): TWriteable;
  var
    mItem: string;
  begin
    Result := ACurrent;
    if AText.StartsWith('WRITEABLECONST') then
    begin
      if MatchStr(AText, ['WRITEABLECONSTON', 'WRITEABLECONST+']) then
      begin
        Result := TWriteable.On_;
      end
      else if MatchStr(AText, ['WRITEABLECONSTOFF', 'WRITEABLECONST-']) then
      begin
        Result := TWriteable.Off;
      end;
      Exit;
    end;
    for mItem in AText.Split([',']) do
    begin
      if mItem = 'J+' then
      begin
        Result := TWriteable.On_;
      end
      else if mItem = 'J-' then
      begin
        Result := TWriteable.Off;
      end;
    end;
  end;

  /// <summary>Spielt die Direktiven der Include-Datei AName nach; lässt sie sich nicht lesen, ist der Stand
  /// danach unbekannt.</summary>
  procedure ApplyInclude(const AName: string; ADepth: Integer; var AState: TWriteable);
  var
    mName, mInclude: string;
    mToken: TPascalToken;
  begin
    mName := AName;
    if (Length(mName) >= 2) and (mName[1] = '''') and (mName[Length(mName)] = '''') then
    begin
      mName := Copy(mName, 2, Length(mName) - 2);
    end;
    if (ADepth >= 8) or not ReadInclude(mName, mInclude) then
    begin
      AState := TWriteable.Unknown;
      Exit;
    end;
    for mToken in TPascalLexer.Tokenize(mInclude) do
    begin
      if mToken.Kind = TPascalTokenKind.Directive then
      begin
        ApplyDirective(mToken.Text, ADepth + 1, AState);
      end;
    end;
  end;

  /// <summary>Wendet die Direktive ADirective auf AState an. {$I Datei} bzw. {$INCLUDE Datei} spielt die
  /// Direktiven der Include-Datei nach (HtmlViewer setzt {$J+} in htmlcons.inc, #1328); lässt sie sich nicht
  /// lesen, ist der Stand danach unbekannt.</summary>
  procedure ApplyDirective(const ADirective: string; ADepth: Integer; var AState: TWriteable);
  var
    mBody, mName, mRest: string;
  begin
    if not (ADirective.StartsWith('{$') or ADirective.StartsWith('(*$')) then
    begin
      Exit;
    end;
    mBody := TDirectiveNames.Body(ADirective);
    mName := UpperCase(TDirectiveNames.LeadingName(mBody));
    mRest := Trim(Copy(mBody, Length(mName) + 1, MaxInt));
    if MatchStr(mName, ['I', 'INCLUDE']) and (mRest <> '') and not CharInSet(mRest[1], ['+', '-']) then
    begin
      ApplyInclude(mRest, ADepth, AState);
    end
    else
    begin
      AState := SettingOf(UpperCase(StringReplace(mBody, ' ', '', [rfReplaceAll])), AState);
    end;
  end;

  /// <summary>Letzte Einstellung von {$J±} bzw. {$WRITEABLECONST} vor APosition in dieser Datei, samt
  /// eingebundener Include-Dateien.</summary>
  function WriteableAt(const APosition: TTextPosition): TWriteable;
  var
    Token: TPascalToken;
  begin
    Result := TWriteable.Unknown;
    for Token in AContext.Tree.Tokens do
    begin
      if not Before(Token.StartPos, APosition) then
      begin
        Break;
      end;
      if Token.Kind = TPascalTokenKind.Directive then
      begin
        ApplyDirective(Token.Text, 0, Result);
      end;
    end;
  end;

  procedure CollectLocal(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.ConstDecl) and (Node.ChildCount = 2) then
        begin
          LocalNames.AddOrSetValue(LowerCase(Node.Name), True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function Suspect(const AName: string): Boolean;
  var
    Key: string;
  begin
    Key := LowerCase(AName);
    if (Key = '') or LocalNames.ContainsKey(Key) then
    begin
      Exit(Key <> '');
    end;
    if Suspects.TryGetValue(Key, Result) then
    begin
      Exit;
    end;
    Result := False;
    if AContext.Index <> nil then
    begin
      Result := AContext.Index.HasSymbol(AName,
        function(const ASymbol: TIndexSymbol): Boolean
        begin
          Result := (ASymbol.Kind = TIndexSymbolKind.Constant) and IsTypedConstant(ASymbol.TypeName, ASymbol.Signature);
        end);
    end;
    Suspects.Add(Key, Result);
  end;

  /// <summary>Nennt der Zugriff ANode (Name, Feld, Element) einen verdächtigen Namen?</summary>
  function MentionsSuspect(ANode: TSyntaxNode): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): an der Zugriffskette entlang nach links.
    Result := False;
    mNode := ANode;
    while (mNode <> nil) and not Result do
    begin
      if mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
      begin
        Result := Suspect(mNode.Name);
      end;
      mNode := ChainParent(mNode);
    end;
  end;

  procedure EnsureResolver;
  begin
    if Resolver = nil then
    begin
      // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
      Cache := TRuleDerived.Open(AContext);
      Resolver := TRuleDerived.Resolver(Cache, AContext);
      Resolver.PinTree(AContext.Tree, FileName);
    end;
  end;

  /// <summary>Ein Schritt an der Zugriffskette ANode (Name oder Feld) entlang: AFound, wenn ANode eine typisierte
  /// Konstante ist; sonst der Empfänger eines Record-Felds, bei dem es weitergeht, oder nil.</summary>
  function ConstantStep(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol; out AFound: Boolean): TSyntaxNode;
  var
    mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    Result := nil;
    AFound := False;
    if not Resolver.NodeType(AContext.Tree, FileName, ANode, ASymbol, mTypeInfo, mTypeFound) then
    begin
      Exit;
    end;
    AFound := (ASymbol.SymbolKind = TIndexSymbolKind.Constant) and
      IsTypedConstant(ASymbol.TypeName, ASymbol.Signature);
    // Feld eines Records: weiter zum Empfänger.
    if not AFound and (ANode.Kind = TSyntaxKind.MemberAccess) and (ASymbol.SymbolKind = TIndexSymbolKind.Field) then
    begin
      Result := ChainParent(ANode);
    end;
  end;

  /// <summary>Typisierte Konstante am linken Ende der Zugriffskette ANode; AElements sind die Elementzugriffe auf
  /// dem Weg, außen zuerst.</summary>
  function ConstantOfChain(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol;
    out AElements: TArray<TSyntaxNode>): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): an der Zugriffskette entlang nach links bis zur Konstante.
    Result := False;
    ASymbol := Default(TResolvedSymbol);
    AElements := nil;
    mNode := ANode;
    while (mNode <> nil) and not Result do
    begin
      if not (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) or
        not MentionsSuspect(mNode) then
      begin
        Exit;
      end;
      EnsureResolver;
      if mNode.Kind = TSyntaxKind.IndexAccess then
      begin
        // Element: nur Arrays und Strings, nicht der Speicher hinter einem Zeiger.
        AElements := AElements + [mNode];
        mNode := ChainParent(mNode);
      end
      else
      begin
        mNode := ConstantStep(mNode, ASymbol, Result);
      end;
    end;
  end;

  /// <summary>Führt einer der Elementzugriffe AElements (von innen nach außen) über einen Zeiger? ASymbol folgt
  /// dabei den Elementen.</summary>
  function ThroughPointer(var ASymbol: TResolvedSymbol; const AElements: TArray<TSyntaxNode>): Boolean;
  var
    mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
    mIndex: Integer;
  begin
    Result := False;
    for mIndex := High(AElements) downto 0 do
    begin
      if IsPointerName(ASymbol.TypeName) or ASymbol.TypeName.StartsWith('^') then
      begin
        Exit(True);
      end;
      if Resolver.NodeType(AContext.Tree, FileName, AElements[mIndex][0], ASymbol, mTypeInfo, mTypeFound) and
        mTypeFound and (Pos('^', TypeBodyOf(mTypeInfo.Signature)) > 0) then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>Typisierte Konstante, die der Zugriff ANode verändert: die Konstante selbst, ein Element oder ein
  /// Feld davon (nicht über Zeiger).</summary>
  function ModifiedConstant(ANode: TSyntaxNode; out ASymbol: TResolvedSymbol): Boolean;
  var
    mElements: TArray<TSyntaxNode>;
  begin
    Result := ConstantOfChain(ANode, ASymbol, mElements) and not ThroughPointer(ASymbol, mElements);
  end;

  /// <summary>Deklaration der Konstante ASymbol in dieser Datei; nil, wenn sie woanders steht.</summary>
  function DeclarationOf(const ASymbol: TResolvedSymbol): TSyntaxNode;
  var
    Found: TSyntaxNode;

    procedure Search(ARoot: TSyntaxNode);
    var
      Index: Integer;
      Node: TSyntaxNode;
      Pending: TStack<TSyntaxNode>;
    begin
      // Iterativ (Bericht M1).
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ARoot);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if (Node.Kind = TSyntaxKind.ConstDecl) and (Node.ChildCount = 2) and SameText(Node.Name, ASymbol.Name) and
            (Node.StartPos.Line = ASymbol.SelectionRange.StartPos.Line) then
          begin
            Found := Node;
            Exit;
          end;
          for Index := Node.ChildCount - 1 downto 0 do
          begin
            Pending.Push(Node[Index]);
          end;
        end;
      finally
        Pending.Free;
      end;
    end;

  begin
    Found := nil;
    if (ASymbol.FileName = '') or SameText(ASymbol.FileName, FileName) or
      SameText(ExtractFileName(ASymbol.FileName), ExtractFileName(FileName)) then
    begin
      Search(AContext.Tree.Root);
    end;
    Result := Found;
  end;

  /// <summary>Text vom Zeilenanfang bis APosition, wenn dort nur Leerraum steht; sonst False.</summary>
  function IndentBefore(const APosition: TTextPosition; out AIndent: string): Boolean;
  begin
    if Lines = nil then
    begin
      Lines := TTextLines.SplitLines(AContext.Text);
    end;
    Result := False;
    AIndent := '';
    if (APosition.Line < 0) or (APosition.Line > High(Lines)) then
    begin
      Exit;
    end;
    AIndent := Copy(Lines[APosition.Line], 1, APosition.Character);
    Result := Trim(AIndent) = '';
  end;

  /// <summary>Globaler const-Abschnitt am Zeilenanfang; AIndent ist seine Einrückung.</summary>
  function FixableSection(ASection: TSyntaxNode; out AIndent: string): Boolean;
  begin
    AIndent := '';
    Result := (ASection <> nil) and (ASection.Kind = TSyntaxKind.ConstSection) and (ASection.Parent <> nil) and
      (ASection.Parent.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]);
    Result := Result and SameText(Copy(NodeText(ASection), 1, 5), 'const') and
      IndentBefore(ASection.StartPos, AIndent);
  end;

  /// <summary>Bearbeitung vor ADecl (Stelle APosition im Abschnitt): aus "const" wird "var" bzw. eine eigene
  /// Zeile "var" davor. False, wenn die Deklaration nicht allein in ihrer Zeile beginnt.</summary>
  function AddOpening(ADecl: TSyntaxNode; APosition: Integer; const AIndent: string;
    var AEdits: TArray<TRuleEdit>): Boolean;
  var
    mSection: TSyntaxNode;
    mDummy: string;
  begin
    mSection := ADecl.Parent;
    if APosition = 0 then
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(mSection.StartPos,
        TTextPosition.Create(mSection.StartPos.Line, mSection.StartPos.Character + Length('const'))), 'var')];
      Exit(True);
    end;
    Result := (mSection[APosition - 1].EndPos.Line < ADecl.StartPos.Line) and IndentBefore(ADecl.StartPos, mDummy);
    if Result then
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ADecl.StartPos.Line, 0),
        TTextPosition.Create(ADecl.StartPos.Line, 0)), AIndent + 'var' + LineBreak)];
    end;
  end;

  /// <summary>Bearbeitung nach ADecl: eine eigene Zeile "const" vor der nächsten Deklaration des Abschnitts.
  /// False, wenn diese nicht allein in ihrer Zeile beginnt.</summary>
  function AddClosing(ADecl: TSyntaxNode; APosition: Integer; const AIndent: string;
    var AEdits: TArray<TRuleEdit>): Boolean;
  var
    mNext: TSyntaxNode;
    mDummy: string;
  begin
    Result := True;
    if APosition >= ADecl.Parent.ChildCount - 1 then
    begin
      Exit;
    end;
    mNext := ADecl.Parent[APosition + 1];
    Result := (ADecl.EndPos.Line < mNext.StartPos.Line) and IndentBefore(mNext.StartPos, mDummy);
    if Result then
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(mNext.StartPos.Line, 0),
        TTextPosition.Create(mNext.StartPos.Line, 0)), AIndent + 'const' + LineBreak)];
    end;
  end;

  /// <summary>Korrektur "In var mit Initialwert umwandeln" für eine globale Konstante ADecl: die Deklaration
  /// kommt in einen eigenen var-Abschnitt, die übrigen bleiben const.</summary>
  function VarFix(ADecl: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    mPosition: Integer;
    mIndent: string;
    mEdits: TArray<TRuleEdit>;
  begin
    Result := False;
    if not FixableSection(ADecl.Parent, mIndent) then
    begin
      Exit;
    end;
    mPosition := IndexInParent(ADecl);
    mEdits := nil;
    if (mPosition < 0) or not AddOpening(ADecl, mPosition, mIndent, mEdits) or
      not AddClosing(ADecl, mPosition, mIndent, mEdits) then
    begin
      Exit;
    end;
    AFix := TRuleFix.Create(cTexts[TConstantsTypedConstantsText.ToVar].Text, mEdits);
    Result := True;
  end;

  procedure Report(ATarget: TSyntaxNode; AsArgument: Boolean);
  var
    Symbol: TResolvedSymbol;
    Decl: TSyntaxNode;
    Fix: TRuleFix;
    Fixes: TArray<TRuleFix>;
    Code: string;
  begin
    if not ModifiedConstant(ATarget, Symbol) then
    begin
      Exit;
    end;
    Fixes := nil;
    Decl := DeclarationOf(Symbol);
    if (Decl <> nil) and VarFix(Decl, Fix) then
    begin
      Fixes := [Fix];
    end;
    // Mit {$J-} vor der Deklaration übersetzt Delphi die Änderung nicht.
    if (Decl <> nil) and (WriteableAt(Decl.StartPos) = TWriteable.Off) then
    begin
      if AsArgument then
      begin
        Code := 'E2197';
      end
      else
      begin
        Code := 'E2064';
      end;
      AReport.AddWithSeverity(TTextRange.Create(ATarget.StartPos, ATarget.EndPos),
        cTexts[TConstantsTypedConstantsText.NeedsJ].Fmt([Symbol.Name, Code]),
        TRuleSeverity.Error, Fixes);
      Exit;
    end;
    // Mit {$J+} vor der Deklaration meldet dcc nichts (TC1-TC3, dcc-Lauf vom 29.10.2026, #1328).
    if (Decl <> nil) and (WriteableAt(Decl.StartPos) = TWriteable.On_) then
    begin
      Exit;
    end;
    if AsArgument then
    begin
      Code := 'W1016';
    end
    else
    begin
      Code := 'W1017';
    end;
    AReport.Add(TTextRange.Create(ATarget.StartPos, ATarget.EndPos),
      cTexts[TConstantsTypedConstantsText.Changed].Fmt([Symbol.Name, Code]), TRuleConfidence.High, Fixes);
  end;

  /// <summary>Nennt eines der Argumente des Aufrufs ANode einen verdächtigen Namen?</summary>
  function AnySuspectArgument(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    Result := False;
    for mIndex := 1 to ANode.ChildCount - 1 do
    begin
      if MentionsSuspect(ANode[mIndex]) then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>Meldet die Argumente des Aufrufs ANode an den Stellen AVarArgs (je Argument: var oder out?).</summary>
  procedure ReportVarArguments(ANode: TSyntaxNode; const AVarArgs: TArray<Boolean>);
  var
    mIndex: Integer;
  begin
    for mIndex := 1 to ANode.ChildCount - 1 do
    begin
      if (mIndex - 1 <= High(AVarArgs)) and AVarArgs[mIndex - 1] then
      begin
        Report(ANode[mIndex], True);
      end;
    end;
  end;

  /// <summary>Meldet die var-Argumente eingebauter Routinen (Inc, Dec …) im Aufruf ANode.</summary>
  procedure ReportBuiltinArguments(ANode: TSyntaxNode);
  var
    mPosition: Integer;
  begin
    for mPosition in BuiltinVarArguments(ANode[0].Name) do
    begin
      if mPosition + 1 < ANode.ChildCount then
      begin
        Report(ANode[mPosition + 1], True);
      end;
    end;
  end;

  procedure CheckCall(ANode: TSyntaxNode);
  var
    mCallee: TSyntaxNode;
    mSymbol, mTypeInfo: TResolvedSymbol;
    mTypeFound: Boolean;
  begin
    if (ANode.ChildCount < 2) or not AnySuspectArgument(ANode) then
    begin
      Exit;
    end;
    mCallee := ANode[0];
    EnsureResolver;
    if (mCallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      Resolver.NodeType(AContext.Tree, FileName, mCallee, mSymbol, mTypeInfo, mTypeFound) then
    begin
      // Überladungen können andere Parameter haben: dann keine Aussage. NodeType nennt nur die erste Überladung,
      // bei Methoden fehlen die übrigen in Overloads; CallCandidates zählt alle Deklarationen.
      if (mSymbol.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine,
        TIndexSymbolKind.Constructor_]) and (Length(mSymbol.Overloads) = 0) and
        (Length(mSymbol.VariantParams) <= 1) and
        (Length(Resolver.CallCandidates(AContext.Tree, FileName, mCallee)) <= 1) then
      begin
        ReportVarArguments(ANode, VarParameters(mSymbol.Signature));
      end;
    end
    else if mCallee.Kind = TSyntaxKind.Identifier then
    begin
      ReportBuiltinArguments(ANode);
    end;
  end;

  /// <summary>0 als Wert einer Zeigerkonstante bzw. initialisierten Zeigervariable (W1013).</summary>
  procedure CheckZeroPointer(ANode: TSyntaxNode);
  var
    Value, TypeNode: TSyntaxNode;
    TypeInfo: TResolvedSymbol;
    IsPointer: Boolean;
  begin
    if ANode.ChildCount <> 2 then
    begin
      Exit;
    end;
    TypeNode := ANode[0];
    Value := ANode[1];
    if (Value.Kind <> TSyntaxKind.Literal) or (Trim(NodeText(Value)) <> '0') then
    begin
      Exit;
    end;
    IsPointer := (TypeNode.Kind = TSyntaxKind.PointerType) or
      ((TypeNode.Kind = TSyntaxKind.TypeReference) and IsPointerName(NodeText(TypeNode)));
    if not IsPointer and (TypeNode.Kind = TSyntaxKind.TypeReference) then
    begin
      EnsureResolver;
      TypeInfo := Resolver.ResolveType(AContext.Tree, FileName, TypeNode.StartPos);
      IsPointer := TypeInfo.Found and (TypeInfo.SymbolKind = TIndexSymbolKind.TypeAlias) and
        ((Pos('^', TypeBodyOf(TypeInfo.Signature)) = 1) or IsPointerName(TypeBodyOf(TypeInfo.Signature)));
    end;
    if not IsPointer then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(Value.StartPos, Value.EndPos),
      cTexts[TConstantsTypedConstantsText.ZeroNil].Fmt([ANode.Name]), TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TConstantsTypedConstantsText.WriteNil].Text,
        [TTextEdit.Create(TTextRange.Create(Value.StartPos, Value.EndPos), 'nil')],
      True)]);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    Index: Integer;
    Node: TSyntaxNode;
    Pending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.AssignStatement:
            if Node.ChildCount = 2 then
            begin
              Report(Node[0], False);
            end;
          TSyntaxKind.Call:
            CheckCall(Node);
          TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl:
            CheckZeroPointer(Node);
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FileName := AContext.FileName;
  if FileName = '' then
  begin
    FileName := AContext.RelativePath;
  end;
  if FileName = '' then
  begin
    FileName := AContext.UnitName + '.pas';
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Lines := nil;
  Resolver := nil;
  LocalNames := TDictionary<string, Boolean>.Create;
  Suspects := TDictionary<string, Boolean>.Create;
  try
    CollectLocal(AContext.Tree.Root);
    Visit(AContext.Tree.Root);
  finally
    if Resolver <> nil then
    begin
      Resolver.UnpinTree;
    end;
    Suspects.Free;
    LocalNames.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Constants.TypedConstants', cTexts);

end.
