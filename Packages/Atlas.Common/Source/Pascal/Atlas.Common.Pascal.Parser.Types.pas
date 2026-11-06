unit Atlas.Common.Pascal.Parser.Types;

// Typen des Parsers (Pascal.Parser): Typverweise, Klassen, Records mit
// varianten Teilen, Properties, Aufzählungen, Mengen, Arrays und
// Prozedurtypen.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser.Declarations;

type

  /// <summary>Typen und Typverweise.</summary>
  TTypeParser = class(TDeclarationParser)
  protected
    function ParseType(AParent: TSyntaxNode): TSyntaxNode; override;
    function ParseTypeBody(AParent: TSyntaxNode): TSyntaxNode;
    /// <summary>Steht auf class bzw. record: folgt "helper for" oder "helper (…)"?</summary>
    function IsHelperStart: Boolean;
    /// <summary>class, object, record, interface; nil bei anderen Typen. Ohne Bereich und Elternknoten.</summary>
    function ParseStructuredType: TSyntaxNode;
    function ParseClassType: TSyntaxNode;
    function ParseRecordType: TSyntaxNode;
    function ParseInterfaceType: TSyntaxNode;
    /// <summary>Aufzählung, set, array, Zeiger, Prozedurtyp, file of; nil bei anderen Typen. Ohne Bereich und
    /// Elternknoten.</summary>
    function ParseSimpleType: TSyntaxNode;
    function ParseEnumType: TSyntaxNode;
    function ParseArrayType: TSyntaxNode;
    /// <summary>Beginnt hier ein benannter Typ (kein Teilbereich wie Low(X)..High(X))?</summary>
    function IsNamedTypeStart: Boolean;
    /// <summary>Benannter Typ; ist er der Anfang eines Teilbereichs (A.B..C), der Teilbereich. Hängt das
    /// Ergebnis an AParent.</summary>
    function ParseNamedType(AParent: TSyntaxNode; AStart: Integer): TSyntaxNode;
    /// <summary>Teilbereich 1..10 bzw. ein einzelner Bezeichner als Typverweis.</summary>
    function ParseSubrange: TSyntaxNode;
    function ParseTypeReference(AParent: TSyntaxNode): TSyntaxNode; override;
    function ParseTypeReferenceBody(AParent: TSyntaxNode): TSyntaxNode;
    /// <summary>Name eines Typverweises mit Unit und generischen Argumenten (an AReference).</summary>
    function ParseTypeName(AReference: TSyntaxNode): string;
    procedure ParseClassBody(ANode: TSyntaxNode; AKind: TSyntaxKind);
    procedure ParseMembers(AParent: TSyntaxNode);
    /// <summary>Ein Mitglied einer Klasse oder eines Records; False, wenn hier das end fehlt.</summary>
    function ParseMember(AParent: TSyntaxNode): Boolean;
    /// <summary>private, protected, public, published, automated, strict private, strict protected.</summary>
    procedure ParseVisibility(AParent: TSyntaxNode);
    /// <summary>class var, class property, class procedure … .</summary>
    procedure ParseClassMember(AParent: TSyntaxNode);
    /// <summary>Abschnitt, Property, Methode, varianter Teil oder Feld; False, wenn keins davon beginnt.</summary>
    function ParseMemberDeclaration(AParent: TSyntaxNode): Boolean;
    /// <summary>Unerwartetes Token in der Mitgliederliste; False, wenn hier das end fehlt.</summary>
    function ParseMemberError(AParent: TSyntaxNode): Boolean;
    procedure ParseProperty(AParent: TSyntaxNode);
    procedure ParseFieldDecl(AParent: TSyntaxNode); overload;
    /// <summary>AInVariant: Feld in der Klammer eines varianten Zweigs; vor ")" fehlt das ";".</summary>
    procedure ParseFieldDecl(AParent: TSyntaxNode; AInVariant: Boolean); overload;
    procedure ParseVariantPart(AParent: TSyntaxNode);
    procedure ParseVariantBody(ANode: TSyntaxNode);
    /// <summary>Hinter case: Selektorfeld "Art: TArt" oder nur der Typ.</summary>
    procedure ParseVariantSelector(ANode: TSyntaxNode);
    /// <summary>Ein Zweig "Marken: (Felder)".</summary>
    procedure ParseVariantItem(ANode: TSyntaxNode);
    /// <summary>Marken eines Zweigs als Text bis vor ":".</summary>
    function VariantLabels: string;
    function AtVariantLabelEnd: Boolean;
    procedure ParseVariantFields(AParent: TSyntaxNode);
    procedure ParseProcedureType(ANode: TSyntaxNode);
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser.Cursor,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTypesText = (PrivateOrProtected, ProcedureFunctionPropertyOrVar, Identifier, FieldName);

const
  cTexts: array[TTypesText] of TAtlasText = (
    (De: '"private" oder "protected"'; En: '"private" or "protected"'),
    (De: '"procedure", "function", "property" oder "var"'; En: '"procedure", "function", "property" or "var"'),
    (De: 'Bezeichner'; En: 'identifier'),
    (De: 'Feldname'; En: 'field name'));

{$SCOPEDENUMS OFF}

{ TTypeParser }

function TTypeParser.ParseTypeReference(AParent: TSyntaxNode): TSyntaxNode;
begin
  if not EnterNesting then
  begin
    Result := TooDeep;
    AParent.Add(Result);
    Exit;
  end;
  try
    Result := ParseTypeReferenceBody(AParent);
  finally
    Dec(FDepth);
  end;
end;

function TTypeParser.ParseTypeName(AReference: TSyntaxNode): string;
begin
  if IsKw(['string', 'file']) or IsIdent then
  begin
    Result := Current.Text;
    Advance;
  end
  else if IsKw('const') then
  begin
    Result := 'const';
    Advance;
  end
  else
  begin
    Result := '';
    DiagnoseUnexpected('Typ');
  end;
  repeat
    if IsSym('<') and LooksLikeGenericArgs(True) then
    begin
      ParseGenericArgs(AReference);
    end;
    if IsSym('.') and (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Advance;
      Result := Result + '.' + Current.Text;
      Advance;
    end
    else
    begin
      Break;
    end;
  until False;
end;

function TTypeParser.ParseTypeReferenceBody(AParent: TSyntaxNode): TSyntaxNode;
var
  Start: Integer;
  Name: string;
begin
  // Name, Unit.Name, TList<Integer>, string, string[20], file, array of const
  Start := NodeStart;
  Result := StartNode(TSyntaxKind.TypeReference);
  AParent.Add(Result);
  Name := ParseTypeName(Result);
  if SameWord(Name, 'string') and IsSym('[') then
  begin
    // ShortString-Länge: string[20]
    Advance;
    ParseExpression(Result);
    ExpectSym(']');
  end
  else if SameWord(Name, 'AnsiString') and IsSym('(') then
  begin
    // Codepage: type AnsiString(CP_WINANSI) bzw. AnsiString(1200) (#1140).
    Advance;
    ParseExpression(Result);
    ExpectSym(')');
  end;
  Result.Name := Name;
  FinishNode(Result, Start);
end;

function TTypeParser.ParseType(AParent: TSyntaxNode): TSyntaxNode;
begin
  if not EnterNesting then
  begin
    Result := TooDeep;
    AParent.Add(Result);
    Exit;
  end;
  try
    Result := ParseTypeBody(AParent);
  finally
    Dec(FDepth);
  end;
end;

function TTypeParser.ParseTypeBody(AParent: TSyntaxNode): TSyntaxNode;
var
  mStart: Integer;
begin
  mStart := NodeStart;
  AcceptKw('packed');
  Result := ParseStructuredType;
  if Result = nil then
  begin
    Result := ParseSimpleType;
  end;
  if Result = nil then
  begin
    if IsNamedTypeStart then
    begin
      Exit(ParseNamedType(AParent, mStart));
    end;
    Result := ParseSubrange;
  end;
  FinishNode(Result, mStart);
  AParent.Add(Result);
end;

function TTypeParser.IsHelperStart: Boolean;
begin
  // class helper [(TBaseHelper)] for T, record helper for T (#848)
  Result := SameWord(PeekToken(1).Text, 'helper') and (PeekIsKw(2, 'for') or PeekIsSym(2, '('));
end;

function TTypeParser.ParseStructuredType: TSyntaxNode;
begin
  Result := nil;
  if IsKw('class') then
  begin
    Result := ParseClassType;
  end
  else if IsKw('object') then
  begin
    Result := StartNode(TSyntaxKind.ObjectType);
    Advance;
    ParseClassBody(Result, TSyntaxKind.ObjectType);
  end
  else if IsKw('record') then
  begin
    Result := ParseRecordType;
  end
  else if IsKw(['interface', 'dispinterface']) then
  begin
    Result := ParseInterfaceType;
  end;
end;

function TTypeParser.ParseClassType: TSyntaxNode;
begin
  if PeekIsSym(1, ';') then
  begin
    Result := StartNode(TSyntaxKind.ForwardType);
    Result.Name := 'class';
    Advance;
  end
  else if IsHelperStart then
  begin
    Result := StartNode(TSyntaxKind.HelperType);
    Result.Name := 'class';
    Advance; // class
    Advance; // helper
    ParseClassBody(Result, TSyntaxKind.HelperType);
  end
  else if PeekIsKw(1, 'of') then
  begin
    Result := StartNode(TSyntaxKind.ClassOfType);
    Advance;
    Advance;
    ParseTypeReference(Result);
  end
  else
  begin
    Result := StartNode(TSyntaxKind.ClassType);
    Advance;
    // abstract, sealed
    while IsIdentText('abstract') or IsIdentText('sealed') do
    begin
      Advance;
    end;
    ParseClassBody(Result, TSyntaxKind.ClassType);
  end;
end;

function TTypeParser.ParseRecordType: TSyntaxNode;
begin
  if IsHelperStart then
  begin
    Result := StartNode(TSyntaxKind.HelperType);
    Result.Name := 'record';
    Advance;
    Advance;
    ParseClassBody(Result, TSyntaxKind.HelperType);
    Exit;
  end;
  Result := StartNode(TSyntaxKind.RecordType);
  Advance;
  ParseMembers(Result);
  ExpectKw('end');
  // Ausrichtung: end align 16 (#1142).
  if IsIdentText('align') and (PeekToken(1).Kind = TPascalTokenKind.Number) then
  begin
    Advance;
    Advance;
  end;
end;

function TTypeParser.ParseInterfaceType: TSyntaxNode;
begin
  if PeekIsSym(1, ';') then
  begin
    Result := StartNode(TSyntaxKind.ForwardType);
    Result.Name := LowerCase(Current.Text);
    Advance;
  end
  else
  begin
    Result := StartNode(TSyntaxKind.InterfaceType);
    Advance;
    ParseClassBody(Result, TSyntaxKind.InterfaceType);
  end;
end;

function TTypeParser.ParseSimpleType: TSyntaxNode;
begin
  Result := nil;
  if IsSym('(') then
  begin
    Result := ParseEnumType;
  end
  else if IsKw('set') then
  begin
    Result := StartNode(TSyntaxKind.SetType);
    Advance;
    ExpectKw('of');
    ParseType(Result);
  end
  else if IsKw('array') then
  begin
    Result := ParseArrayType;
  end
  else if IsSym('^') then
  begin
    Result := StartNode(TSyntaxKind.PointerType);
    Advance;
    ParseTypeReference(Result);
  end
  else if IsKw(['procedure', 'function']) then
  begin
    Result := StartNode(TSyntaxKind.ProcedureType);
    ParseProcedureType(Result);
  end
  else if IsIdentText('reference') and PeekIsKw(1, 'to') then
  begin
    Result := StartNode(TSyntaxKind.ProcedureType);
    Result.Name := 'reference';
    Advance;
    Advance;
    ParseProcedureType(Result);
  end
  else if IsKw('file') and PeekIsKw(1, 'of') then
  begin
    Result := StartNode(TSyntaxKind.FileType);
    Advance;
    Advance;
    ParseTypeReference(Result);
  end;
end;

function TTypeParser.ParseEnumType: TSyntaxNode;
begin
  // Aufzählung: (rot, gruen = 2, blau)
  Result := StartNode(TSyntaxKind.EnumType);
  Advance;
  while not AtEnd and not IsSym(')') do
  begin
    if IsIdent then
    begin
      Result.Add(Leaf(TSyntaxKind.Identifier, Current.Text));
    end
    else
    begin
      DiagnoseUnexpected(cTexts[TTypesText.Identifier].Text);
    end;
    if AcceptSym('=') then
    begin
      ParseExpression(Result);
    end;
    if not AcceptSym(',') then
    begin
      Break;
    end;
  end;
  ExpectSym(')');
end;

function TTypeParser.ParseArrayType: TSyntaxNode;
begin
  Result := StartNode(TSyntaxKind.ArrayType);
  Advance;
  if AcceptSym('[') then
  begin
    repeat
      ParseType(Result);
    until not AcceptSym(',');
    ExpectSym(']');
  end;
  ExpectKw('of');
  if IsKw('const') then
  begin
    ParseTypeReference(Result);
  end
  else
  begin
    ParseType(Result);
  end;
end;

function TTypeParser.IsNamedTypeStart: Boolean;
begin
  if IsKw(['string', 'file', 'const']) then
  begin
    Exit(True);
  end;
  // AnsiString(Codepage) ist ein Typ, kein Teilbereich wie Low(X)..High(X) (#1140).
  if IsIdentText('AnsiString') and PeekIsSym(1, '(') then
  begin
    Exit(True);
  end;
  Result := IsIdent and not PeekIsSym(1, '..') and not PeekIsSym(1, '(');
end;

function TTypeParser.ParseNamedType(AParent: TSyntaxNode; AStart: Integer): TSyntaxNode;
var
  mHolder: TSyntaxNode;
begin
  // Benannter Typ, ggf. doch ein Teilbereich wie Low(X)..High(X) oder A.B..C.
  Result := ParseTypeReference(AParent);
  if not IsSym('..') then
  begin
    Exit;
  end;
  // Der Name war der Anfang eines Teilbereichs.
  AParent.Extract(Result);
  mHolder := StartNode(TSyntaxKind.SubrangeType);
  mHolder.Add(Result);
  Advance;
  // Ohne Vergleich: in "X: 1..3 = 2" gehört "= 2" nicht zur Obergrenze (#849).
  mHolder.Add(ParseSimpleExpression);
  FinishNode(mHolder, AStart);
  AParent.Add(mHolder);
  Result := mHolder;
end;

function TTypeParser.ParseSubrange: TSyntaxNode;
var
  mExpr: TSyntaxNode;
begin
  // Teilbereich: 1..10, 'a'..'z', Low(X)..High(X)
  Result := StartNode(TSyntaxKind.SubrangeType);
  mExpr := ParseExpression(Result);
  if AcceptSym('..') then
  begin
    Result.Add(ParseSimpleExpression);
  end
  else if mExpr.Kind = TSyntaxKind.Identifier then
  begin
    Result.Kind := TSyntaxKind.TypeReference;
  end
  else
  begin
    DiagnoseUnexpected('Typ');
  end;
end;

procedure TTypeParser.ParseProcedureType(ANode: TSyntaxNode);
begin
  // procedure(A: Integer) of object; function: Boolean; reference to procedure
  if IsKw(['procedure', 'function']) then
  begin
    Advance;
  end
  else
  begin
    DiagnoseUnexpected('"procedure"');
  end;
  if IsSym('(') then
  begin
    ParseParameters(ANode);
  end;
  if AcceptSym(':') then
  begin
    ParseTypeReference(ANode);
  end;
  if IsKw('of') and SameWord(PeekToken(1).Text, 'object') then
  begin
    Advance;
    Advance;
  end;
  // Aufrufkonventionen mit oder ohne Semikolon davor: procedure stdcall; procedure; cdecl
  while True do
  begin
    if IsIdent and InWords(Current.Text, CallingConventions) then
    begin
      Advance;
    end
    else if IsSym(';') and (PeekToken(1).Kind = TPascalTokenKind.Identifier) and
      InWords(PeekToken(1).Text, CallingConventions) then
    begin
      Advance;
    end
    else
    begin
      Break;
    end;
  end;
end;

procedure TTypeParser.ParseClassBody(ANode: TSyntaxNode; AKind: TSyntaxKind);
begin
  // Nach class, object, interface oder helper: (Vorfahren), [GUID], Mitglieder, end.
  if IsSym('(') then
  begin
    Advance;
    while not AtEnd and not IsSym(')') do
    begin
      ParseTypeReference(ANode);
      if not AcceptSym(',') then
      begin
        Break;
      end;
    end;
    ExpectSym(')');
  end;
  if AKind = TSyntaxKind.HelperType then
  begin
    ExpectKw('for');
    ParseTypeReference(ANode);
  end;
  // Kurzform ohne Rumpf: TFehler = class(Exception);
  if IsSym(';') then
  begin
    Exit;
  end;
  if (AKind = TSyntaxKind.InterfaceType) and IsSym('[') then
  begin
    // GUID
    Advance;
    ParseExpression(ANode);
    ExpectSym(']');
  end;
  ParseMembers(ANode);
  ExpectKw('end');
end;

procedure TTypeParser.ParseMembers(AParent: TSyntaxNode);
var
  mBefore: Integer;
begin
  while not AtEnd and not IsKw('end') do
  begin
    mBefore := FIndex;
    if not ParseMember(AParent) then
    begin
      Exit;
    end;
    AcceptSym(';');
    if FIndex = mBefore then
    begin
      Advance;
    end;
  end;
end;

function TTypeParser.ParseMember(AParent: TSyntaxNode): Boolean;
begin
  Result := True;
  if IsIdent and InWords(Current.Text, VisibilityWords) and not PeekIsSym(1, ':') and not PeekIsSym(1, ',') then
  begin
    ParseVisibility(AParent);
  end
  else if IsSym('[') then
  begin
    ParseAttributes(AParent);
  end
  else if IsKw('class') then
  begin
    ParseClassMember(AParent);
  end
  else if not ParseMemberDeclaration(AParent) then
  begin
    Result := ParseMemberError(AParent);
  end;
end;

procedure TTypeParser.ParseVisibility(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.Visibility);
  mNode.Name := LowerCase(Current.Text);
  Advance;
  if (mNode.Name = 'strict') and (IsIdentText('private') or IsIdentText('protected')) then
  begin
    mNode.Name := 'strict ' + LowerCase(Current.Text);
    Advance;
  end
  else if mNode.Name = 'strict' then
  begin
    DiagnoseUnexpected('E2375', cTexts[TTypesText.PrivateOrProtected].Text);
  end;
  FinishNode(mNode, mStart);
  AParent.Add(mNode);
end;

procedure TTypeParser.ParseClassMember(AParent: TSyntaxNode);
begin
  if PeekIsKw(1, 'var') or PeekIsKw(1, 'threadvar') then
  begin
    // class var und class threadvar (#1140).
    Advance;
    ParseVarSection(AParent);
  end
  else if PeekIsKw(1, 'property') then
  begin
    Advance;
    ParseProperty(AParent);
  end
  else if IsRoutineStart then
  begin
    ParseRoutineHeader(AParent, TSyntaxKind.RoutineHeader);
  end
  else
  begin
    // class vor etwas anderem als Routine, var, property; Delphi 13 meldet E2123 (#1382).
    Advance;
    DiagnoseUnexpected('E2123', cTexts[TTypesText.ProcedureFunctionPropertyOrVar].Text);
  end;
end;

function TTypeParser.ParseMemberDeclaration(AParent: TSyntaxNode): Boolean;
begin
  Result := True;
  if IsKw(['var', 'threadvar']) then
  begin
    ParseVarSection(AParent);
  end
  else if IsKw(['const', 'resourcestring']) then
  begin
    ParseConstSection(AParent);
  end
  else if IsKw('type') then
  begin
    ParseTypeSection(AParent);
  end
  else if IsKw('property') then
  begin
    ParseProperty(AParent);
  end
  else if IsRoutineStart then
  begin
    ParseRoutineHeader(AParent, TSyntaxKind.RoutineHeader);
  end
  else if IsKw('case') then
  begin
    ParseVariantPart(AParent);
  end
  else if IsIdent then
  begin
    ParseFieldDecl(AParent);
  end
  else
  begin
    Result := False;
  end;
end;

function TTypeParser.ParseMemberError(AParent: TSyntaxNode): Boolean;
begin
  Result := not IsKw(['begin', 'implementation', 'initialization', 'finalization']) and
    not (IsKw(['type', 'var', 'const']) and FInImplementation);
  if Result then
  begin
    SkipError(AParent, TRecovery.Members);
  end
  else
  begin
    // Fehlendes end: Mitgliederliste hier beenden.
    DiagnoseUnexpected('"end"');
  end;
end;

procedure TTypeParser.ParseFieldDecl(AParent: TSyntaxNode);
begin
  ParseFieldDecl(AParent, False);
end;

procedure TTypeParser.ParseFieldDecl(AParent: TSyntaxNode; AInVariant: Boolean);
var
  Start: Integer;
  Node: TSyntaxNode;
  Names: string;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.Field);
  AParent.Add(Node);
  Names := ExpectIdent;
  while AcceptSym(',') do
  begin
    Names := Names + ',' + ExpectIdent;
  end;
  Node.Name := Names;
  ExpectSym(':');
  ParseType(Node);
  ParseHints;
  // Das letzte Feld darf vor end bzw. vor der ")" eines varianten Zweigs ohne Semikolon stehen (#849).
  if not IsKw('end') and (not AInVariant or not IsSym(')')) then
  begin
    ExpectSym(';');
  end;
  FinishNode(Node, Start);
end;

procedure TTypeParser.ParseProperty(AParent: TSyntaxNode);
var
  Start, DirectiveStart: Integer;
  Node, Directive: TSyntaxNode;
begin
  // property Name[Index: Integer]: Typ read GetX write SetX default 0; default;
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.PropertyDecl);
  AParent.Add(Node);
  Advance; // property
  Node.Name := ExpectIdent;
  if IsSym('[') then
  begin
    ParseParameters(Node);
  end;
  if AcceptSym(':') then
  begin
    ParseTypeReference(Node);
  end;
  // Spezifizierer (read, write, index, default, stored, implements ...) bis ;
  while not AtEnd and not IsSym(';') and not IsKw('end') do
  begin
    Advance;
  end;
  ExpectSym(';');
  if IsIdentText('default') and PeekIsSym(1, ';') then
  begin
    Advance;
    Advance;
  end
  else if IsIdent and PeekIsSym(1, ';') then
  begin
    // property … ; defualt; – an dieser Stelle steht nur default, ein anderes Wort ist ein Tippfehler
    // (#1068, Regel directive-typo).
    DirectiveStart := NodeStart;
    Directive := StartNode(TSyntaxKind.Directive);
    Directive.Name := LowerCase(Current.Text);
    Node.Add(Directive);
    Advance;
    FinishNode(Directive, DirectiveStart);
    Advance;
  end;
  FinishNode(Node, Start);
end;

procedure TTypeParser.ParseVariantPart(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  // case [Tag:] Typ of Marken: (Felder); … (#846). Endet vor dem end des Records bzw. vor der ")" des
  // umschließenden Zweigs. VariantPart: Selektorfeld (Field) oder Selektortyp (TypeReference), dann je
  // Zweig ein CaseItem mit den Marken als Name und den Feldern (auch einem weiteren VariantPart).
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.VariantPart);
  AParent.Add(Node);
  if not EnterNesting then
  begin
    Node.Add(TooDeep);
    FinishNode(Node, Start);
    Exit;
  end;
  try
    ParseVariantBody(Node);
  finally
    Dec(FDepth);
  end;
  FinishNode(Node, Start);
end;

procedure TTypeParser.ParseVariantBody(ANode: TSyntaxNode);
var
  mBefore: Integer;
begin
  Advance; // case
  ParseVariantSelector(ANode);
  ExpectKw('of');
  while not AtEnd and not IsKw('end') and not IsSym(')') do
  begin
    mBefore := FIndex;
    ParseVariantItem(ANode);
    AcceptSym(';');
    if FIndex = mBefore then
    begin
      Advance;
    end;
  end;
end;

procedure TTypeParser.ParseVariantSelector(ANode: TSyntaxNode);
var
  mStart: Integer;
  mSelector: TSyntaxNode;
begin
  if not (IsIdent and PeekIsSym(1, ':')) then
  begin
    ParseTypeReference(ANode);
    Exit;
  end;
  mStart := NodeStart;
  mSelector := StartNode(TSyntaxKind.Field);
  ANode.Add(mSelector);
  mSelector.Name := ExpectIdent;
  ExpectSym(':');
  ParseTypeReference(mSelector);
  FinishNode(mSelector, mStart);
  ANode.Name := mSelector.Name;
end;

procedure TTypeParser.ParseVariantItem(ANode: TSyntaxNode);
var
  mStart: Integer;
  mItem: TSyntaxNode;
begin
  mStart := NodeStart;
  mItem := StartNode(TSyntaxKind.CaseItem);
  ANode.Add(mItem);
  mItem.Name := VariantLabels;
  ExpectSym(':');
  if AcceptSym('(') then
  begin
    ParseVariantFields(mItem);
    ExpectSym(')');
  end
  else
  begin
    DiagnoseUnexpected('"("');
  end;
  FinishNode(mItem, mStart);
end;

function TTypeParser.VariantLabels: string;
begin
  // Marken: Konstanten, Bereiche und Listen ("0", "1..3", "mkA, mkB").
  Result := '';
  while not AtEnd and not AtVariantLabelEnd do
  begin
    if IsSym(',') then
    begin
      Result := Result + ', ';
    end
    else
    begin
      Result := Result + Current.Text;
    end;
    Advance;
  end;
end;

function TTypeParser.AtVariantLabelEnd: Boolean;
begin
  Result := IsSym(':') or IsSym('(') or IsSym(';') or IsSym(')') or IsKw('end');
end;

procedure TTypeParser.ParseVariantFields(AParent: TSyntaxNode);
var
  Before: Integer;
begin
  while not AtEnd and not IsSym(')') and not IsKw('end') do
  begin
    Before := FIndex;
    if IsKw('case') then
    begin
      ParseVariantPart(AParent);
    end
    else if IsSym('[') then
    begin
      // Attribut an einem Feld im varianten Zweig (#1142).
      ParseAttributes(AParent);
    end
    else if IsIdent then
    begin
      ParseFieldDecl(AParent, True);
    end
    else
    begin
      DiagnoseUnexpected(cTexts[TTypesText.FieldName].Text);
    end;
    AcceptSym(';');
    if FIndex = Before then
    begin
      Advance;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.Parser.Types', cTexts);

end.
