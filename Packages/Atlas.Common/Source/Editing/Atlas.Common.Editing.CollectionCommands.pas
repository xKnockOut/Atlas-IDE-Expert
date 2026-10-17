unit Atlas.Common.Editing.CollectionCommands;

// Schnellbefehle für Sammlungen (#319) im Rahmen aus #293:
//   /list Name: TTyp            TObjectList<TTyp> für Klassen, sonst TList<TTyp>
//   /dict Name: TKey, TWert     TDictionary bzw. TObjectDictionary mit doOwnsValues
//   /dict! Name: string, TWert  dazu Schlüssel ohne Beachtung der Groß-/Kleinschreibung
//   /sort Liste [-]Mitglied     Sort mit TComparer nach Feld oder Property, "-" absteigend
//   /filter Liste Bedingung     Treffer in eine neue Liste
//
// In einer Klasse entsteht ein privates Feld samt Erzeugen im Konstruktor und
// Freigeben im Destruktor, in einer Routine eine lokale Variable mit try … finally.

interface

uses
  Atlas.Common.Editing.SlashCommands;

/// <summary>Trägt die Sammlungsbefehle in ARegistry ein.</summary>
procedure RegisterCollectionCommands(ARegistry: TSlashCommandRegistry);

/// <summary>Vergleichsfunktion für zwei Werte vom Typ ATypeName, z. B. CompareText; AUnit ist die nötige Unit.</summary>
function CompareFunction(const ATypeName: string; out AUnit: string): string;

/// <summary>Argumente für /sort und /filter (#319): ohne ACollection die Sammlungen im Gültigkeitsbereich der
/// Befehlszeile (Felder der Klasse, globale und lokale Variablen mit Typargumenten), sonst die Felder und
/// Properties ihres Elementtyps aus Datei und Index.</summary>
function CollectionChoices(const AContext: TSlashContext; const ACollection: string): TArray<string>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.TypeCommands;

const
  StringTypes: array[0..6] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'Char', 'TCaption',
    'TFileName');
  NumberTypes: array[0..16] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'Byte', 'Word', 'SmallInt',
    'ShortInt', 'LongInt', 'NativeInt', 'NativeUInt', 'Double', 'Single', 'Extended', 'Currency', 'Real', 'TColor');
  DateTypes: array[0..2] of string = ('TDateTime', 'TDate', 'TTime');

function CompareFunction(const ATypeName: string; out AUnit: string): string;
begin
  AUnit := '';
  if MatchText(ATypeName, StringTypes) then
    Result := 'CompareText(%s, %s)'
  else if MatchText(ATypeName, DateTypes) then
  begin
    AUnit := 'System.DateUtils';
    Result := 'CompareDateTime(%s, %s)';
  end
  else if MatchText(ATypeName, NumberTypes) then
  begin
    AUnit := 'System.Math';
    Result := 'CompareValue(%s, %s)';
  end
  else
    // Boolean und Aufzählungen über die Ordinalzahl.
    Result := 'Ord(%s) - Ord(%s)';
end;

/// <summary>Implementierung von AClassName.AMethod in der Datei; nil ohne.</summary>
function MethodNode(ASource: TCommandSource; const AClassName, AMethod: string): TSyntaxNode;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Section := ASource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
    Exit;
  for Index := 0 to Section.ChildCount - 1 do
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AClassName + '.' + AMethod) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
      Exit(Section[Index]);
end;

/// <summary>Zeile mit "inherited" im Rumpf von ARoutine; -1 ohne.</summary>
function InheritedLine(ASource: TCommandSource; ARoutine: TSyntaxNode): Integer;
var
  Block: TSyntaxNode;
  Index: Integer;
begin
  Block := ARoutine.FindChild(TSyntaxKind.Block);
  for Index := Block.StartPos.Line to Block.EndPos.Line do
    if StartsText('inherited', Trim(ASource.Lines[Index])) then
      Exit(Index);
  Result := -1;
end;

/// <summary>Feld AName vom Typ ATypeName mit AConstruction in Konstruktor und Free im Destruktor.</summary>
function AddOwnedField(ASource: TCommandSource; const AClass: TIndexSymbol; const AName, ATypeName,
  AConstruction: string): TArray<TTextEdit>;
var
  Constructor_, Destructor_: TSyntaxNode;
  Declarations: TArray<string>;
  Bodies, Indent, Create, Free: string;
  PrivateAt, Line, EndLine, Index: Integer;
begin
  Result := nil;
  Declarations := nil;
  Bodies := '';
  Create := AName + ' := ' + AConstruction + ';';
  Free := AName + '.Free;';
  PrivateAt := ASource.PrivateLine(AClass);
  if PrivateAt >= 0 then
    Result := Result + [ASource.AfterLine(PrivateAt, ASource.Indent(PrivateAt) + '  ' + AName + ': ' + ATypeName +
      ';')]
  else
    Declarations := Declarations + ['private', AName + ': ' + ATypeName + ';'];

  Constructor_ := MethodNode(ASource, AClass.Name, 'Create');
  if Constructor_ <> nil then
  begin
    Line := InheritedLine(ASource, Constructor_);
    if Line < 0 then
      Line := Constructor_.FindChild(TSyntaxKind.Block).StartPos.Line;
    Result := Result + [ASource.AfterLine(Line, ASource.Indent(Constructor_.StartPos.Line) + '  ' + Create)];
  end
  else
  begin
    Declarations := Declarations + ['public', 'constructor Create;'];
    Bodies := Format('constructor %s.Create;', [AClass.Name]) + ASource.LineBreak + 'begin' + ASource.LineBreak +
      '  inherited Create;' + ASource.LineBreak + '  ' + Create + ASource.LineBreak + 'end;';
  end;

  Destructor_ := MethodNode(ASource, AClass.Name, 'Destroy');
  if Destructor_ <> nil then
  begin
    Line := InheritedLine(ASource, Destructor_);
    if Line < 0 then
      Line := Destructor_.FindChild(TSyntaxKind.Block).EndPos.Line;
    Result := Result + [ASource.BeforeLine(Line, ASource.Indent(Destructor_.StartPos.Line) + '  ' + Free)];
  end
  else
  begin
    if Constructor_ <> nil then
      Declarations := Declarations + ['public'];
    Declarations := Declarations + ['destructor Destroy; override;'];
    if Bodies <> '' then
      Bodies := Bodies + ASource.LineBreak + ASource.LineBreak;
    Bodies := Bodies + Format('destructor %s.Destroy;', [AClass.Name]) + ASource.LineBreak + 'begin' +
      ASource.LineBreak + '  ' + Free + ASource.LineBreak + '  inherited;' + ASource.LineBreak + 'end;';
  end;

  if Declarations <> nil then
  begin
    EndLine := AClass.Range.EndPos.Line;
    Indent := ASource.Indent(EndLine);
    Create := '';
    for Index := 0 to High(Declarations) do
    begin
      if Index > 0 then
        Create := Create + ASource.LineBreak;
      if MatchText(Declarations[Index], ['private', 'public']) then
        Create := Create + Indent + Declarations[Index]
      else
        Create := Create + Indent + '  ' + Declarations[Index];
    end;
    Result := Result + [ASource.BeforeLine(EndLine, Create)];
  end;
  if Bodies <> '' then
    Result := Result + [ASource.AddBody(AClass.Name, Bodies)];
end;

/// <summary>Lokale Variable AName mit Erzeugen und try … finally Free um die folgenden Anweisungen.</summary>
function AddOwnedLocal(ASource: TCommandSource; ARoutine: TSyntaxNode; const AName, ATypeName, AConstruction: string;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Indent: string;
  Wrapped: TArray<TTextEdit>;
begin
  Indent := ASource.Indent(ASource.Line);
  if Wrap(ASource, 'list', [AName + ' := ' + AConstruction + ';', 'try'], ['finally', '  ' + AName + '.Free;',
    'end;'], '  ', Wrapped, AReason) then
    AEdits := Wrapped
  else
    // Ohne folgende Anweisungen: leerer Rumpf.
    AEdits := [TTextEdit.Create(TTextRange.Create(ASource.Line, 0, ASource.Line + 1, 0),
      Indent + AName + ' := ' + AConstruction + ';' + ASource.LineBreak + Indent + 'try' + ASource.LineBreak +
      Indent + '  ' + ASource.LineBreak + Indent + 'finally' + ASource.LineBreak + Indent + '  ' + AName + '.Free;' +
      ASource.LineBreak + Indent + 'end;' + ASource.LineBreak)];
  AEdits := [AddLocal(ASource, ARoutine, TSyntaxKind.VarSection, 'var', AName + ': ' + ATypeName + ';')] + AEdits;
  Result := True;
end;

/// <summary>Gemeinsamer Ablauf von /list und /dict: Feld in der Klasse oder lokale Variable.</summary>
function AddCollection(const AContext: TSlashContext; const AName, ATypeName, AConstruction: string;
  const AUnits: array of string; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  ClassSymbol: TIndexSymbol;
  Edits: TArray<TTextEdit>;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine <> nil then
    begin
      if not AddOwnedLocal(Source, Routine, AName, ATypeName, AConstruction, Edits, AReason) then
        Exit(False);
      AddUses(Source, AContext, Source.Line, AUnits, Edits);
    end
    else if Source.ClassAt(ClassSymbol) then
    begin
      Edits := AddOwnedField(Source, ClassSymbol, AName, ATypeName, AConstruction) + [Source.RemoveCommand];
      AddUses(Source, AContext, ClassSymbol.Range.StartPos.Line, AUnits, Edits);
    end
    else
      Exit(Fail('/' + AContext.Name + ' gilt nur in einer Klasse oder im Rumpf einer Routine', AReason));
    AEdits := Edits;
    Result := True;
  finally
    Source.Free;
  end;
end;

/// <summary>Ist ATypeName eine Klasse? Liest dafür die Datei.</summary>
function IsClass(const AContext: TSlashContext; const ATypeName: string): Boolean;
var
  Source: TCommandSource;
begin
  Source := TCommandSource.Create(AContext);
  try
    Result := IsClassType(Source, AContext.Index, ATypeName);
  finally
    Source.Free;
  end;
end;

{ /list }

function ExecuteList(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Name, ElementType, TypeName: string;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', Name, ElementType) or not IsValidIdent(ElementType, True) then
    Exit(Fail('Erwartet wird /list Name: TTyp', AReason));
  if IsClass(AContext, ElementType) then
    TypeName := 'TObjectList<' + ElementType + '>'
  else
    TypeName := 'TList<' + ElementType + '>';
  Result := AddCollection(AContext, Name, TypeName, TypeName + '.Create', ['System.Generics.Collections'], AEdits,
    AReason);
end;

{ /dict, /dict! }

function ExecuteDict(const AContext: TSlashContext; AIgnoreCase: Boolean; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Name, Types, KeyType, ValueType, TypeName, Arguments: string;
  Comma: Integer;
  Owned: Boolean;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', Name, Types) then
    Exit(Fail('Erwartet wird /' + AContext.Name + ' Name: TSchluessel, TWert', AReason));
  Comma := Pos(',', Types);
  KeyType := Trim(Copy(Types, 1, Comma - 1));
  ValueType := Trim(Copy(Types, Comma + 1, MaxInt));
  if (Comma = 0) or not IsValidIdent(KeyType, True) or not IsValidIdent(ValueType, True) then
    Exit(Fail('Erwartet wird /' + AContext.Name + ' Name: TSchluessel, TWert', AReason));
  if AIgnoreCase and not MatchText(KeyType, StringTypes) then
    Exit(Fail('/dict! braucht einen String als Schlüssel', AReason));
  Owned := IsClass(AContext, ValueType);
  if Owned then
    TypeName := Format('TObjectDictionary<%s, %s>', [KeyType, ValueType])
  else
    TypeName := Format('TDictionary<%s, %s>', [KeyType, ValueType]);
  Arguments := '';
  if Owned then
    Arguments := '[doOwnsValues]';
  if AIgnoreCase then
  begin
    if Arguments <> '' then
      Arguments := Arguments + ', ';
    Arguments := Arguments + 'TIStringComparer.Ordinal';
  end;
  if Arguments <> '' then
    Arguments := '(' + Arguments + ')';
  if AIgnoreCase then
    Result := AddCollection(AContext, Name, TypeName, TypeName + '.Create' + Arguments,
      ['System.Generics.Collections', 'System.Generics.Defaults'], AEdits, AReason)
  else
    Result := AddCollection(AContext, Name, TypeName, TypeName + '.Create' + Arguments,
      ['System.Generics.Collections'], AEdits, AReason);
end;

{ /sort, /filter }

/// <summary>Elementtyp der Sammlung AName: Typargument des Felds oder der lokalen Deklaration; '' ohne.</summary>
function ElementType(ASource: TCommandSource; const AName: string): string;
var
  Symbol: TIndexSymbol;
  Routine: TSyntaxNode;
  Index, Start, Open, Close: Integer;
  Line: string;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Variable]) and
      SameText(Symbol.Name, AName) and (Symbol.TypeArgs <> '') then
      Exit(Trim(Copy(Symbol.TypeArgs, LastDelimiter(',', Symbol.TypeArgs) + 1, MaxInt)));
  // Lokale Variable: "Name: TList<T>" bzw. "var Name := TList<T>.Create".
  Result := '';
  Routine := ASource.RoutineAt;
  if Routine = nil then
    Exit;
  for Index := Routine.StartPos.Line to ASource.Line - 1 do
  begin
    Line := ASource.Lines[Index];
    Start := Pos(LowerCase(AName), LowerCase(Line));
    if Start = 0 then
      Continue;
    Open := PosEx('<', Line, Start);
    Close := PosEx('>', Line, Open);
    if (Open > 0) and (Close > Open) then
    begin
      Result := Copy(Line, Open + 1, Close - Open - 1);
      Exit(Trim(Copy(Result, LastDelimiter(',', Result) + 1, MaxInt)));
    end;
  end;
end;

/// <summary>Typ des Felds oder der Property AMember von AType in der Datei oder im Index; '' ohne.</summary>
function MemberType(ASource: TCommandSource; const AIndex: ISymbolIndex; const AType, AMember: string): string;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and SameText(Symbol.Container, AType) and
      SameText(Symbol.Name, AMember) then
      Exit(Symbol.TypeName);
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(AMember) do
      if (Location.Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
        SameText(Location.Symbol.Container, AType) then
        Exit(Location.Symbol.TypeName);
  Result := '';
end;

function ExecuteSort(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Arguments, Collection, Member, Element, Kind, Compare, CompareUnit, Indent, Text, LB: string;
  Space: Integer;
  Descending: Boolean;
begin
  AEdits := nil;
  Arguments := Trim(AContext.Arguments);
  Space := Pos(' ', Arguments);
  Collection := Trim(Copy(Arguments, 1, Space - 1));
  Member := Trim(Copy(Arguments, Space + 1, MaxInt));
  Descending := StartsStr('-', Member);
  if Descending then
    Member := Trim(Copy(Member, 2, MaxInt));
  if (Space = 0) or not IsValidIdent(Collection, True) or not IsValidIdent(Member) then
    Exit(Fail('Erwartet wird /sort Liste [-]Mitglied', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
      Exit(Fail('/sort gilt nur im Rumpf einer Routine', AReason));
    Element := ElementType(Source, Collection);
    if Element = '' then
      Exit(Fail('Elementtyp von ' + Collection + ' nicht erkannt', AReason));
    Kind := MemberType(Source, AContext.Index, Element, Member);
    if Kind = '' then
      Exit(Fail(Element + ' hat kein Feld oder keine Property ' + Member, AReason));
    Compare := CompareFunction(Kind, CompareUnit);
    if Descending then
      Compare := Format(Compare, ['R.' + Member, 'L.' + Member])
    else
      Compare := Format(Compare, ['L.' + Member, 'R.' + Member]);
    Indent := Source.Indent(Source.Line);
    LB := Source.LineBreak;
    Text := Indent + Collection + '.Sort(TComparer<' + Element + '>.Construct(' + LB +
      Indent + '  function(const L, R: ' + Element + '): Integer' + LB +
      Indent + '  begin' + LB +
      Indent + '    Result := ' + Compare + ';' + LB +
      Indent + '  end));' + LB;
    AEdits := [TTextEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 1, 0), Text)];
    AddUses(Source, AContext, Source.Line, ['System.Generics.Defaults', CompareUnit], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

/// <summary>Ist AName ein Feld, eine Property oder Methode von AType (Datei oder Index)?</summary>
function IsMember(ASource: TCommandSource; const AIndex: ISymbolIndex; const AType, AName: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Container, AType) and SameText(Symbol.Name, AName) then
      Exit(True);
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(AName) do
      if SameText(Location.Symbol.Container, AType) then
        Exit(True);
  Result := False;
end;

/// <summary>Bedingung mit dem Element als Bezug: Jeder Bezeichner, der ein Mitglied von AElement ist, bekommt
/// AVariable davor ("Aktiv and (Umsatz > 0)" wird "K.Aktiv and (K.Umsatz > 0)"). Sind die Mitglieder unbekannt,
/// nur der erste Bezeichner ("not Aktiv" wird "not K.Aktiv").</summary>
function ElementCondition(ASource: TCommandSource; const AIndex: ISymbolIndex; const AElement, AVariable,
  ACondition: string): string;
var
  Tokens: TArray<TPascalToken>;
  Index, Last, Start: Integer;
  AfterDot, Known, Prefix, First: Boolean;
begin
  Tokens := TPascalLexer.Tokenize(ACondition);
  Known := False;
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      IsMember(ASource, AIndex, AElement, Tokens[Index].Text) then
      Known := True;
  Result := '';
  Last := 0;
  AfterDot := False;
  First := True;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Comment then
      Continue;
    Prefix := False;
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and not AfterDot then
    begin
      if Known then
        Prefix := IsMember(ASource, AIndex, AElement, Tokens[Index].Text)
      else
        Prefix := First and not SameText(Tokens[Index].Text, AVariable);
      First := False;
    end;
    if Prefix then
    begin
      Start := Tokens[Index].StartPos.Character;
      Result := Result + Copy(ACondition, Last + 1, Start - Last) + AVariable + '.';
      Last := Start;
    end;
    AfterDot := Tokens[Index].IsSymbol('.');
  end;
  Result := Result + Copy(ACondition, Last + 1, MaxInt);
end;

function ExecuteFilter(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Arguments, Collection, Condition, Element, Variable, Indent, Text, LB, Head, Loop: string;
  Space: Integer;
  UseInline: Boolean;
begin
  AEdits := nil;
  Arguments := Trim(AContext.Arguments);
  Space := Pos(' ', Arguments);
  Collection := Trim(Copy(Arguments, 1, Space - 1));
  Condition := Trim(Copy(Arguments, Space + 1, MaxInt));
  if (Space = 0) or not IsValidIdent(Collection, True) or (Condition = '') then
    Exit(Fail('Erwartet wird /filter Liste Bedingung', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/filter gilt nur im Rumpf einer Routine', AReason));
    Element := ElementType(Source, Collection);
    if Element = '' then
      Exit(Fail('Elementtyp von ' + Collection + ' nicht erkannt', AReason));
    // Laufvariable: erster Buchstabe des Typs ohne T.
    Variable := Element;
    if (Length(Variable) > 1) and (Variable[1] = 'T') then
      Variable := Copy(Variable, 2, 1)
    else
      Variable := Copy(Variable, 1, 1);
    Variable := UpperCase(Variable);
    Indent := Source.Indent(Source.Line);
    LB := Source.LineBreak;
    // Vor Delphi 10.3 (#109) gibt es keine Inline-Variablen: beide in den var-Abschnitt.
    UseInline := TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion);
    if UseInline then
    begin
      Head := 'var Treffer := ';
      Loop := 'for var ';
    end
    else
    begin
      Head := 'Treffer := ';
      Loop := 'for ';
    end;
    Text := Indent + Head + 'TList<' + Element + '>.Create;' + LB +
      Indent + 'try' + LB +
      Indent + '  ' + Loop + Variable + ' in ' + Collection + ' do' + LB +
      Indent + '    if ' + ElementCondition(Source, AContext.Index, Element, Variable, Condition) + ' then' + LB +
      Indent + '      Treffer.Add(' + Variable + ');' + LB +
      Indent + '  ' + LB +
      Indent + 'finally' + LB +
      Indent + '  Treffer.Free;' + LB +
      Indent + 'end;' + LB;
    AEdits := [TTextEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 1, 0), Text)];
    if not UseInline then
      AEdits := [AddLocal(Source, Routine, TSyntaxKind.VarSection, 'var', 'Treffer: TList<' + Element + '>;' + LB +
        Source.Indent(Routine.StartPos.Line) + '  ' + Variable + ': ' + Element + ';')] + AEdits;
    AddUses(Source, AContext, Source.Line, ['System.Generics.Collections'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

procedure AddName(var ANames: TArray<string>; const AName: string);
begin
  if (AName <> '') and not MatchText(AName, ANames) then
    ANames := ANames + [AName];
end;

/// <summary>Sammlungen im Gültigkeitsbereich der Befehlszeile.</summary>
function CollectionNames(ASource: TCommandSource): TArray<string>;
var
  Symbol, ClassSymbol: TIndexSymbol;
  HasClass: Boolean;
  Routine: TSyntaxNode;
  Index, Colon: Integer;
  Part, Declared, Name: string;
begin
  Result := nil;
  HasClass := ASource.ClassAt(ClassSymbol);
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Variable]) and
      (Symbol.TypeArgs <> '') and ((Symbol.Container = '') or (HasClass and
      SameText(Symbol.Container, ClassSymbol.Name))) then
      AddName(Result, Symbol.Name);
  // Parameter und lokale Variablen: "A, B: TList<T>" im Kopf oder var-Abschnitt, "var Name := TList<T>.Create".
  Routine := ASource.RoutineAt;
  if Routine = nil then
    Exit;
  for Index := Routine.StartPos.Line to ASource.Line - 1 do
    for Part in StringReplace(ASource.Lines[Index], '(', ';', [rfReplaceAll]).Split([';']) do
    begin
      Declared := Trim(Part);
      if StartsText('var ', Declared) or StartsText('out ', Declared) then
        Declared := Trim(Copy(Declared, 5, MaxInt))
      else if StartsText('const ', Declared) then
        Declared := Trim(Copy(Declared, 7, MaxInt));
      Colon := Pos(':', Declared);
      if (Colon = 0) or (Pos('<', Declared) < Colon) then
        Continue;
      for Name in Copy(Declared, 1, Colon - 1).Split([',']) do
        if IsValidIdent(Trim(Name)) then
          AddName(Result, Trim(Name));
    end;
end;

function CollectionChoices(const AContext: TSlashContext; const ACollection: string): TArray<string>;
var
  Source: TCommandSource;
  Element: string;
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Found: TUnitIndex;
begin
  Result := nil;
  Source := TCommandSource.Create(AContext);
  try
    if ACollection = '' then
      Exit(CollectionNames(Source));
    Element := ElementType(Source, ACollection);
    if Element = '' then
      Exit;
    for Symbol in Source.UnitIndex.Symbols do
      if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
        SameText(Symbol.Container, Element) then
        AddName(Result, Symbol.Name);
    if AContext.Index = nil then
      Exit;
    for Location in AContext.Index.FindSymbols(Element) do
      if (Location.Symbol.Container = '') and AContext.Index.FindFile(Location.FileName, Found) then
        for Symbol in Found.Symbols do
          if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
            SameText(Symbol.Container, Element) then
            AddName(Result, Symbol.Name);
  finally
    Source.Free;
  end;
end;

function ExecuteDictPlain(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
begin
  Result := ExecuteDict(AContext, False, AEdits, AReason);
end;

function ExecuteDictIgnoreCase(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
begin
  Result := ExecuteDict(AContext, True, AEdits, AReason);
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterCollectionCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('list', 'Liste als Feld oder lokale Variable', '/list FKunden: TKunde', ExecuteList));
  ARegistry.Register(Command('dict', 'Dictionary als Feld oder lokale Variable', '/dict FCache: string, TKunde',
    ExecuteDictPlain));
  ARegistry.Register(Command('dict!', 'Dictionary mit Schlüsseln ohne Groß-/Kleinschreibung',
    '/dict! FCache: string, TKunde', ExecuteDictIgnoreCase));
  ARegistry.Register(Command('sort', 'Liste nach Feld oder Property sortieren', '/sort Kunden -Umsatz', ExecuteSort));
  ARegistry.Register(Command('filter', 'Treffer einer Bedingung in eine neue Liste', '/filter Kunden Aktiv',
    ExecuteFilter));
end;

end.
