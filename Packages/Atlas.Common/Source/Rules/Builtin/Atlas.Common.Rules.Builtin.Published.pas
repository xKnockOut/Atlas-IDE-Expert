unit Atlas.Common.Rules.Builtin.Published;

// Mitglieder im published-Abschnitt einer Klasse (#909, Gruppe Compiler vorab):
//   published-type-invalid  Was das Streaming nicht veröffentlichen kann
//                           (#1004): Property vom Typ Record, Array, Zeiger
//                           oder Prozedurtyp ohne "of object" (E2188), Real48
//                           (E2186), Menge über 4 Byte (E2187), Feld, das
//                           keine Klasse und kein Interface ist (E2217), mehr
//                           als eine published-Überladung (E2266),
//                           Klassen-Property (E2545) und Nicht-ASCII-Zeichen
//                           im Namen (E2452).
//
// Die Regel prüft nur Mitglieder hinter einem ausdrücklichen "published". Der
// Abschnitt ohne Angabe ist zwar bei {$M+} bzw. Nachfahren von TPersistent
// ebenfalls published, dort stuft der Compiler unpassende Mitglieder aber
// still zu public herab. Typen löst sie über die Datei und den Index auf
// (Aliase bis zum Ziel, Typparameter der Klasse passen zu allem); was sich
// nicht sicher auflösen lässt, bleibt still, ebenso ein Abschnitt, dessen
// "published" in einem anderen Zweig der bedingten Übersetzung steht als das
// Mitglied. Überladungen in sich ausschließenden Zweigen zählen nicht doppelt.
//
// Korrektur: "In den public-Abschnitt verschieben" setzt die Zeilen des
// Mitglieds vor das "published", unter ein vorhandenes oder neues "public".

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  PublishedTypeInvalidRuleId = 'published-type-invalid';

type
  TPublishedTypeInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPublishedRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
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
  /// <summary>Was ein Typ für den published-Abschnitt ist.</summary>
  TPublishKind = (
    /// <summary>Nicht sicher aufzulösen: keine Aussage.</summary>
    Unknown,
    /// <summary>Klasse oder Interface: als Feld und Property erlaubt.</summary>
    ClassOrInterface,
    /// <summary>Ordinal, String, Gleitkomma, Variant, Methodenzeiger, kleine Menge: nur als Property.</summary>
    Simple,
    RecordKind,
    ArrayKind,
    PointerKind,
    ProcedureKind,
    Real48Kind,
    /// <summary>Menge über 4 Byte.</summary>
    LargeSet);

const
  /// <summary>Eingebaute Typen, die als Property veröffentlicht werden können (Kleinbuchstaben).</summary>
  SimpleTypes: array[0..41] of string = ('integer', 'cardinal', 'shortint', 'smallint', 'longint', 'longword',
    'int64', 'uint64', 'byte', 'word', 'nativeint', 'nativeuint', 'fixedint', 'fixeduint', 'boolean', 'bytebool',
    'wordbool', 'longbool', 'char', 'ansichar', 'widechar', 'string', 'ansistring', 'widestring', 'unicodestring',
    'shortstring', 'rawbytestring', 'utf8string', 'single', 'double', 'extended', 'real', 'comp', 'currency',
    'variant', 'olevariant', 'tdatetime', 'tdate', 'ttime', 'uint32', 'int32', 'tcolor');
  PointerTypes: array[0..4] of string = ('pointer', 'pchar', 'pansichar', 'pwidechar', 'pbyte');
  /// <summary>Records aus System.Types bzw. Winapi.Windows, wenn die Unit sie einbindet und der Index sie nicht
  /// kennt.</summary>
  TypesRecords: array[0..6] of string = ('tpoint', 'trect', 'tsize', 'tpointf', 'trectf', 'tsizef', 'tsmallpoint');
  TypesUnits: array[0..3] of string = ('system.types', 'types', 'winapi.windows', 'windows');

function IsAscii(const AText: string): Boolean;
var
  Ch: Char;
begin
  for Ch in AText do
    if Ord(Ch) > 127 then
      Exit(False);
  Result := True;
end;

/// <summary>Typname ohne Unit und ohne Typargumente ("System.Types.TPointF" wird "TPointF").</summary>
function BareTypeName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  Result := Trim(Copy(Result, LastDelimiter('.', Result) + 1, MaxInt));
end;

/// <summary>Text hinter dem ersten "=" einer Typdeklaration ("TZahlen = array of Integer" wird
/// "array of Integer"); ohne führendes "type" und "packed".</summary>
function AliasTarget(const ASignature: string): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  Depth := 0;
  for Index := 1 to Length(ASignature) do
    if ASignature[Index] = '<' then
      Inc(Depth)
    else if ASignature[Index] = '>' then
      Dec(Depth)
    else if (ASignature[Index] = '=') and (Depth = 0) then
    begin
      Result := Trim(Copy(ASignature, Index + 1, MaxInt));
      Break;
    end;
  if StartsText('type ', Result) then
    Result := Trim(Copy(Result, 6, MaxInt));
  if StartsText('packed ', Result) then
    Result := Trim(Copy(Result, 8, MaxInt));
end;

/// <summary>Nur ein Typname wie "TArray&lt;TVektor&gt;" oder "System.Integer" (der Index trennt Token durch
/// Leerzeichen)?</summary>
function IsTypeName(const AText: string): Boolean;
var
  Ch: Char;
begin
  Result := (AText <> '') and CharInSet(AText[1], ['A'..'Z', 'a'..'z', '_']);
  for Ch in AText do
    if not CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '<', '>', ',', ' ']) then
      Exit(False);
end;

/// <summary>Ordinalwert eines Literals (Zahl oder Zeichen 'a'); False, wenn es keins ist.</summary>
function OrdinalLiteral(const AText: string; out AValue: Integer): Boolean;
var
  Text: string;
begin
  Text := Trim(AText);
  if (Length(Text) = 3) and (Text[1] = '''') and (Text[3] = '''') then
  begin
    AValue := Ord(Text[2]);
    Exit(True);
  end;
  Result := TryStrToInt(Text, AValue) and (AValue >= 0);
end;

function TPublishedTypeInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(PublishedTypeInvalidRuleId, TRuleSeverity.Error,
    'Unzulässiges Mitglied im published-Abschnitt');
end;

procedure TPublishedTypeInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
  Ancestry: TAncestry;
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Lines: TArray<string>;
  LineBreak: string;
  UsesTypes: Boolean;

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
        Low := Middle + 1
      else
        High := Middle;
    end;
    Result := Low;
  end;

  function PathOf(ANode: TSyntaxNode): string;
  begin
    Result := TConditionalBranches.PathAt(Paths, TokenAt(ANode.StartOffset));
  end;

  function SourceOf(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function NodeRange(ANode: TSyntaxNode): TTextRange;
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  end;

  /// <summary>Bereich des Namens AName im Knoten ANode (erstes passendes Token); sonst der ganze Knoten.</summary>
  function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
  var
    Index: Integer;
  begin
    Index := TokenAt(ANode.StartOffset);
    while (Index < Length(Tokens)) and (Tokens[Index].Offset < ANode.EndOffset) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
      Inc(Index);
    end;
    Result := NodeRange(ANode);
  end;

  /// <summary>Gibt es den Namen als Typ, der nicht auf Unit-Ebene steht (verschachtelt) oder mehrfach (Zweige
  /// bedingter Übersetzung)? Dann ist die Auflösung über FindAnyType nicht sicher.</summary>
  function Ambiguous(const AName: string): Boolean;
  var
    Symbol: TIndexSymbol;
    Count: Integer;
  begin
    Count := 0;
    for Symbol in Ancestry.Local.Symbols do
      if (Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
        TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias,
        TIndexSymbolKind.HelperType]) and SameText(Symbol.Name, AName) then
      begin
        if (Symbol.Container <> '') or Symbol.Unavailable then
          Exit(True);
        Inc(Count);
      end;
    Result := Count > 1;
  end;

  function SetKind(const ABase: string; ADepth: Integer): TPublishKind; forward;

  /// <summary>Art des Typs mit Namen AName (Aliase werden bis ADepth = 8 verfolgt).</summary>
  function NamedKind(const AName: string; const AWildcards: TArray<string>; ADepth: Integer): TPublishKind;
  var
    Bare, Lower, Target: string;
    Location: TSymbolLocation;
  begin
    Result := TPublishKind.Unknown;
    Bare := BareTypeName(AName);
    Lower := LowerCase(Bare);
    if (Bare = '') or (ADepth > 8) or MatchText(Bare, AWildcards) or Ambiguous(Bare) then
      Exit;
    if not Ancestry.FindAnyType(Bare, Location) then
    begin
      if MatchText(Lower, SimpleTypes) then
        Result := TPublishKind.Simple
      else if MatchText(Lower, PointerTypes) then
        Result := TPublishKind.PointerKind
      else if Lower = 'real48' then
        Result := TPublishKind.Real48Kind
      else if (Lower = 'tguid') or (UsesTypes and MatchText(Lower, TypesRecords)) then
        Result := TPublishKind.RecordKind
      else if (Lower = 'tarray') and (Pos('<', AName) > 0) then
        Result := TPublishKind.ArrayKind;
      Exit;
    end;
    if Location.Symbol.Unavailable then
      Exit;
    case Location.Symbol.Kind of
      TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
        Result := TPublishKind.ClassOrInterface;
      TIndexSymbolKind.RecordType:
        Result := TPublishKind.RecordKind;
      TIndexSymbolKind.EnumType:
        Result := TPublishKind.Simple;
      TIndexSymbolKind.TypeAlias:
        begin
          Target := AliasTarget(Location.Symbol.Signature);
          if Target = '' then
            Exit;
          if Target[1] = '^' then
            Result := TPublishKind.PointerKind
          else if StartsText('array', Target) and ((Length(Target) = 5) or not CharInSet(Target[6], ['A'..'Z',
            'a'..'z', '0'..'9', '_'])) then
            Result := TPublishKind.ArrayKind
          else if StartsText('set ', Target) and StartsText('of ', Trim(Copy(Target, 5, MaxInt))) then
            Result := SetKind(Trim(Copy(Trim(Copy(Target, 5, MaxInt)), 4, MaxInt)), ADepth + 1)
          else if StartsText('reference ', Target) then
            Result := TPublishKind.ProcedureKind
          else if StartsText('procedure', Target) or StartsText('function', Target) then
          begin
            if ContainsText(Target, ' of object') then
              Result := TPublishKind.Simple
            else
              Result := TPublishKind.ProcedureKind;
          end
          else if StartsText('string[', Target) or (Pos('..', Target) > 0) then
            Result := TPublishKind.Simple
          else if IsTypeName(Target) then
            Result := NamedKind(StringReplace(Target, ' ', '', [rfReplaceAll]), nil, ADepth + 1);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;

  /// <summary>Art einer Menge über ABase ("TFarbe", "(a, b)", "0..40", "Byte"): Simple bis 4 Byte, LargeSet
  /// darüber, sonst Unknown.</summary>
  function SetKind(const ABase: string; ADepth: Integer): TPublishKind;
  var
    Base, Lower, Target: string;
    Low_, High_, Count: Integer;
    Location: TSymbolLocation;
  begin
    Result := TPublishKind.Unknown;
    Base := Trim(ABase);
    if (Base = '') or (ADepth > 8) then
      Exit;
    if Base[1] = '(' then
    begin
      if Pos('=', Base) > 0 then
        Exit;
      Count := Length(Base.Split([',']));
    end
    else if Pos('..', Base) > 0 then
    begin
      if not OrdinalLiteral(Copy(Base, 1, Pos('..', Base) - 1), Low_) or
        not OrdinalLiteral(Copy(Base, Pos('..', Base) + 2, MaxInt), High_) or (High_ < Low_) then
        Exit;
      // Eine Menge belegt die Bytes von Low div 8 bis High div 8.
      if High_ div 8 - Low_ div 8 + 1 > 4 then
        Result := TPublishKind.LargeSet
      else
        Result := TPublishKind.Simple;
      Exit;
    end
    else
    begin
      Lower := LowerCase(BareTypeName(Base));
      if Ambiguous(BareTypeName(Base)) then
        Exit;
      if not Ancestry.FindAnyType(BareTypeName(Base), Location) then
      begin
        if MatchText(Lower, ['byte', 'ansichar', 'shortint']) then
          Result := TPublishKind.LargeSet;
        Exit;
      end;
      if Location.Symbol.Unavailable then
        Exit;
      if Location.Symbol.Kind = TIndexSymbolKind.EnumType then
      begin
        Target := AliasTarget(Location.Symbol.Signature);
        if (Target = '') or (Target[1] <> '(') or (Pos('=', Target) > 0) then
          Exit;
        Count := Length(Target.Split([',']));
      end
      else if Location.Symbol.Kind = TIndexSymbolKind.TypeAlias then
      begin
        Target := AliasTarget(Location.Symbol.Signature);
        if (Target <> '') and ((Target[1] = '(') or (Pos('..', Target) > 0) or IsTypeName(Target)) then
          Result := SetKind(Target, ADepth + 1);
        Exit;
      end
      else
        Exit;
    end;
    // Aufzählung mit Count Werten ab 0: Bytes 0 bis (Count - 1) div 8.
    if (Count - 1) div 8 + 1 > 4 then
      Result := TPublishKind.LargeSet
    else
      Result := TPublishKind.Simple;
  end;

  /// <summary>Art des Typknotens ATypeNode (Typverweis oder Typ im Feld selbst).</summary>
  function TypeKind(ATypeNode: TSyntaxNode; const AWildcards: TArray<string>): TPublishKind;
  begin
    case ATypeNode.Kind of
      TSyntaxKind.TypeReference:
        if ATypeNode.Name = 'string' then
          Result := TPublishKind.Simple
        else
          Result := NamedKind(SourceOf(ATypeNode), AWildcards, 0);
      TSyntaxKind.ArrayType:
        Result := TPublishKind.ArrayKind;
      TSyntaxKind.RecordType:
        Result := TPublishKind.RecordKind;
      TSyntaxKind.PointerType:
        Result := TPublishKind.PointerKind;
      TSyntaxKind.EnumType, TSyntaxKind.SubrangeType, TSyntaxKind.SetType:
        Result := TPublishKind.Simple;
    else
      Result := TPublishKind.Unknown;
    end;
  end;

  /// <summary>Korrektur: Zeilen des Mitglieds AMember vor das "published" APublished setzen, unter das
  /// "public" davor oder ein neues.</summary>
  function MoveToPublic(AMember, APublished: TSyntaxNode; APreviousPublic: Boolean): TArray<TRuleFix>;
  var
    First, Last, Line: Integer;
    Moved, Insert: string;
  begin
    Result := nil;
    First := AMember.StartPos.Line;
    Last := AMember.EndPos.Line;
    if (Last + 1 >= Length(Lines)) or (APublished.StartPos.Line >= First) or
      not SameText(Trim(Lines[APublished.StartPos.Line]), 'published') or
      (Trim(Copy(Lines[First], 1, AMember.StartPos.Character)) <> '') or
      (Trim(Copy(Lines[Last], AMember.EndPos.Character + 1, MaxInt)) <> '') then
      Exit;
    // Attribute über dem Mitglied gehören dazu: dann lieber keine Korrektur als eine halbe.
    if StartsStr('[', Trim(Lines[First - 1])) then
      Exit;
    Moved := '';
    for Line := First to Last do
      Moved := Moved + Lines[Line] + LineBreak;
    Insert := Moved;
    if not APreviousPublic then
      Insert := TTextLines.IndentOf(Lines[APublished.StartPos.Line]) + 'public' + LineBreak + Moved;
    Result := [TRuleFix.Create('In den public-Abschnitt verschieben', [
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(APublished.StartPos.Line, 0),
      TTextPosition.Create(APublished.StartPos.Line, 0)), Insert),
      TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(First, 0), TTextPosition.Create(Last + 1, 0)), '')])];
  end;

  function TypeNodeOf(AMember: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
  begin
    for Index := 0 to AMember.ChildCount - 1 do
      if not (AMember[Index].Kind in [TSyntaxKind.Parameters, TSyntaxKind.Parameter, TSyntaxKind.Attribute,
        TSyntaxKind.Directive, TSyntaxKind.GenericParams]) then
        Exit(AMember[Index]);
    Result := nil;
  end;

  procedure CheckClass(ADecl, ABody: TSyntaxNode);
  var
    Wildcards: TArray<string>;
    Index, Other, Token: Integer;
    Member, Section, Previous, Scan, TypeNode, Params: TSyntaxNode;
    Fixes: TArray<TRuleFix>;
    Kind: TPublishKind;
    Name, TypeText: string;
    Overloaded: Boolean;
  begin
    Wildcards := nil;
    Params := ADecl.FindChild(TSyntaxKind.GenericParams);
    if Params <> nil then
      for Index := 0 to Params.ChildCount - 1 do
        Wildcards := Wildcards + [Params[Index].Name];
    Section := nil;
    Previous := nil;
    for Index := 0 to ABody.ChildCount - 1 do
    begin
      Member := ABody[Index];
      if Member.Kind = TSyntaxKind.Visibility then
      begin
        Previous := Section;
        Section := Member;
        Continue;
      end;
      if not (Member.Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader]) or
        (Section = nil) or (Section.Name <> 'published') or
        not TConditionalBranches.Implies(PathOf(Member), PathOf(Section)) then
        Continue;
      Fixes := MoveToPublic(Member, Section, (Previous <> nil) and (Previous.Name = 'public') and
        TConditionalBranches.Implies(PathOf(Section), PathOf(Previous)));
      Name := Member.Name;
      if not IsAscii(Name) then
      begin
        AReport.Add(NameRange(Member, Name.Split([','])[0]), Format('Der published-Name %s enthält Zeichen ' +
          'außerhalb von ASCII (wie E2452).', [Name]), TRuleConfidence.High, Fixes);
        Continue;
      end;
      case Member.Kind of
        TSyntaxKind.PropertyDecl:
          begin
            // "class property": das Token vor "property" (Kommentare übersprungen).
            Token := TokenAt(Member.StartOffset) - 1;
            while (Token >= 0) and (Tokens[Token].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
              Dec(Token);
            if (Token >= 0) and Tokens[Token].IsKeyword('class') then
            begin
              AReport.Add(NameRange(Member, Name), Format('Die Klassen-Property %s kann nicht published sein ' +
                '(wie E2545).', [Name]), TRuleConfidence.High, Fixes);
              Continue;
            end;
            // Array-Properties und Properties ohne Typ (neu veröffentlicht) prüft die Regel nicht.
            if Member.FindChild(TSyntaxKind.Parameters) <> nil then
              Continue;
            TypeNode := Member.FindChild(TSyntaxKind.TypeReference);
            if TypeNode = nil then
              Continue;
            Kind := TypeKind(TypeNode, Wildcards);
            TypeText := SourceOf(TypeNode);
            case Kind of
              TPublishKind.RecordKind:
                AReport.Add(NodeRange(TypeNode), Format('%s (Record) kann nicht published sein (wie E2188).',
                  [TypeText]), TRuleConfidence.High, Fixes);
              TPublishKind.ArrayKind:
                AReport.Add(NodeRange(TypeNode), Format('%s (Array) kann nicht published sein (wie E2188).',
                  [TypeText]), TRuleConfidence.High, Fixes);
              TPublishKind.PointerKind:
                AReport.Add(NodeRange(TypeNode), Format('%s (Zeiger) kann nicht published sein (wie E2188).',
                  [TypeText]), TRuleConfidence.High, Fixes);
              TPublishKind.ProcedureKind:
                AReport.Add(NodeRange(TypeNode), Format('%s (Prozedurtyp ohne "of object") kann nicht published ' +
                  'sein (wie E2188).', [TypeText]), TRuleConfidence.High, Fixes);
              TPublishKind.Real48Kind:
                AReport.Add(NodeRange(TypeNode), Format('%s ist vom Typ Real48; Real48 kann nicht published sein ' +
                  '(wie E2186).', [Name]), TRuleConfidence.High, Fixes);
              TPublishKind.LargeSet:
                AReport.Add(NodeRange(TypeNode), Format('Die Menge %s ist größer als 4 Byte und kann nicht ' +
                  'published sein (wie E2187).', [TypeText]), TRuleConfidence.High, Fixes);
              TPublishKind.Unknown: ;
              TPublishKind.ClassOrInterface: ;
              TPublishKind.Simple: ;
            end;
          end;
        TSyntaxKind.Field:
          begin
            TypeNode := TypeNodeOf(Member);
            if TypeNode = nil then
              Continue;
            Kind := TypeKind(TypeNode, Wildcards);
            if Kind in [TPublishKind.Unknown, TPublishKind.ClassOrInterface] then
              Continue;
            AReport.Add(NameRange(Member, Name.Split([','])[0]), Format('Das published-Feld %s ist vom Typ %s; ' +
              'published-Felder müssen Klassen oder Interfaces sein (wie E2217).',
              [StringReplace(Name, ',', ', ', [rfReplaceAll]), SourceOf(TypeNode)]), TRuleConfidence.High, Fixes);
          end;
        TSyntaxKind.RoutineHeader:
          begin
            // Eine frühere published-Methode gleichen Namens, die mit dieser übersetzt wird?
            Overloaded := False;
            Scan := nil;
            for Other := 0 to Index - 1 do
              if ABody[Other].Kind = TSyntaxKind.Visibility then
                Scan := ABody[Other]
              else if (ABody[Other].Kind = TSyntaxKind.RoutineHeader) and (Scan <> nil) and
                (Scan.Name = 'published') and SameText(ABody[Other].Name, Name) and
                not TConditionalBranches.Exclusive(PathOf(ABody[Other]), PathOf(Member)) then
                Overloaded := True;
            if Overloaded then
              AReport.Add(NameRange(Member, Name), Format('Nur eine Überladung von %s darf published sein ' +
                '(wie E2266).', [Name]), TRuleConfidence.High, Fixes);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node, Body: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          Body := Node.FindChild(TSyntaxKind.ClassType);
          if Body <> nil then
          begin
            CheckClass(Node, Body);
            Node := Body;
          end;
        end;
        // Nur Deklarationscontainer: Anweisungen und Ausdrücke enthalten keine Klassen (#1094).
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
            TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl] then
            Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  /// <summary>Bindet die Unit System.Types oder Winapi.Windows ein (TPoint, TRect, TPointF ...)? Die Rekursion
  /// geht nur über Abschnitt, uses und Unit (feste Tiefe) und bleibt deshalb (Bericht M1).</summary>
  function FindTypesUnit(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.UsedUnit) and MatchText(ANode.Name, TypesUnits) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if (ANode[Index].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
        TSyntaxKind.UsesClause, TSyntaxKind.UsedUnit]) and FindTypesUnit(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  UsesTypes := FindTypesUnit(AContext.Tree.Root);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(Cache, AContext));
  try
    Visit(AContext.Tree.Root);
  finally
    Ancestry.Free;
  end;
end;

procedure RegisterPublishedRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPublishedTypeInvalidRule.Create);
end;

end.
