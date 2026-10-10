unit Argus.Common.Editing.RecordCommands;

// Schnellbefehle für Records und Wertobjekte (#323) im Rahmen aus #293:
//   /record TPunkt X, Y: Integer [ro]  Record mit Konstruktor; mit ro private Felder und Properties zum Lesen
//   /operator = + Implicit             class operator für den Record unter dem Cursor (= bringt <> mit)
//   /equals [Feld, …]                  Klassen: Equals und GetHashCode über dieselben Felder; Records: = und <>
//   /clone                             Clone über Assign (TPersistent) oder feldweise, gibt Result bei Fehler frei

interface

uses
  Argus.Common.Editing.SlashCommands;

/// <summary>Trägt /record, /operator, /equals und /clone in ARegistry ein.</summary>
procedure RegisterRecordCommands(ARegistry: TSlashCommandRegistry);

/// <summary>Operatorname zu Symbol oder Name (= wird Equal, + wird Add); '' wenn unbekannt.</summary>
function OperatorName(const AToken: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Argus.Common.Rules.Contract,
  Argus.Common.Index.Contract,
  Argus.Common.Editing.CommandSource,
  Argus.Common.Editing.TypeCommands;

type
  TOperatorEntry = record
    Symbol: string;
    Name: string;
  end;

const
  Operators: array[0..19] of TOperatorEntry = (
    (Symbol: '='; Name: 'Equal'), (Symbol: '<>'; Name: 'NotEqual'),
    (Symbol: '<'; Name: 'LessThan'), (Symbol: '<='; Name: 'LessThanOrEqual'),
    (Symbol: '>'; Name: 'GreaterThan'), (Symbol: '>='; Name: 'GreaterThanOrEqual'),
    (Symbol: '+'; Name: 'Add'), (Symbol: '-'; Name: 'Subtract'),
    (Symbol: '*'; Name: 'Multiply'), (Symbol: '/'; Name: 'Divide'),
    (Symbol: 'div'; Name: 'IntDivide'), (Symbol: 'mod'; Name: 'Modulus'),
    (Symbol: 'neg'; Name: 'Negative'), (Symbol: 'not'; Name: 'LogicalNot'),
    (Symbol: 'and'; Name: 'LogicalAnd'), (Symbol: 'or'; Name: 'LogicalOr'),
    (Symbol: 'inc'; Name: 'Inc'), (Symbol: 'dec'; Name: 'Dec'),
    (Symbol: ''; Name: 'Implicit'), (Symbol: ''; Name: 'Explicit'));
  // Vorfahren, deren Nachfahren Assign kennen.
  PersistentBases: array[0..6] of string = ('TPersistent', 'TComponent', 'TCollection', 'TCollectionItem',
    'TStrings', 'TStringList', 'TInterfacedPersistent');

function OperatorName(const AToken: string): string;
var
  Entry: TOperatorEntry;
begin
  for Entry in Operators do
    if ((Entry.Symbol <> '') and SameText(Entry.Symbol, AToken)) or SameText(Entry.Name, AToken) then
      Exit(Entry.Name);
  Result := '';
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

{ /record }

type
  TFieldGroup = record
    Names: TArray<string>;
    TypeName: string;
  end;

/// <summary>"X, Y: Integer; Name: string" in Gruppen; False bei Fehlern.</summary>
function ParseFields(const AText: string; out AGroups: TArray<TFieldGroup>): Boolean;
var
  Part, Name: string;
  Group: TFieldGroup;
  Colon: Integer;
begin
  AGroups := nil;
  for Part in AText.Split([';']) do
  begin
    if Trim(Part) = '' then
      Continue;
    Colon := Pos(':', Part);
    if Colon = 0 then
      Exit(False);
    Group.Names := nil;
    for Name in Copy(Part, 1, Colon - 1).Split([',']) do
    begin
      if not IsValidIdent(Trim(Name)) then
        Exit(False);
      Group.Names := Group.Names + [Trim(Name)];
    end;
    Group.TypeName := Trim(Copy(Part, Colon + 1, MaxInt));
    if Group.TypeName = '' then
      Exit(False);
    AGroups := AGroups + [Group];
  end;
  Result := Length(AGroups) > 0;
end;

function ExecuteRecord(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Arguments, TypeName, Prefix, Params, Body: string;
  Space: Integer;
  ReadOnly, InTypeSection: Boolean;
  Groups: TArray<TFieldGroup>;
  Group: TFieldGroup;
  Name: string;
  Declaration, Properties: TArray<string>;
  ParamNames: TArray<string>;
begin
  AEdits := nil;
  Arguments := Trim(AContext.Arguments);
  ReadOnly := EndsText(' ro', Arguments);
  if ReadOnly then
    Arguments := Trim(Copy(Arguments, 1, Length(Arguments) - 3));
  Space := Pos(' ', Arguments);
  TypeName := Trim(Copy(Arguments, 1, Space - 1));
  if (Space = 0) or not IsValidIdent(TypeName) or not ParseFields(Copy(Arguments, Space + 1, MaxInt), Groups) then
    Exit(Fail('Erwartet wird /record TName X, Y: Integer [ro]', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not TypePlace(Source, 'record', InTypeSection, AReason) then
      Exit(False);
    Prefix := IfThen(ReadOnly, 'F', '');
    Declaration := [TypeName + ' = record'];
    if ReadOnly then
      Declaration := Declaration + ['private'];
    Params := '';
    Properties := nil;
    Body := '';
    for Group in Groups do
    begin
      ParamNames := nil;
      for Name in Group.Names do
      begin
        ParamNames := ParamNames + ['A' + Name];
        Body := Body + Source.LineBreak + Format('  %s%s := A%s;', [Prefix, Name, Name]);
        if ReadOnly then
          Properties := Properties + [Format('  property %s: %s read %s%s;', [Name, Group.TypeName, Prefix, Name])];
      end;
      Declaration := Declaration + [Format('  %s%s: %s;', [Prefix, string.Join(', ' + Prefix, Group.Names),
        Group.TypeName])];
      if Params <> '' then
        Params := Params + '; ';
      Params := Params + Format('%s: %s', [string.Join(', ', ParamNames), Group.TypeName]);
    end;
    if ReadOnly then
      Declaration := Declaration + ['public'];
    Declaration := Declaration + [Format('  constructor Create(%s);', [Params])] + Properties + ['end;'];
    AEdits := [TypeDeclaration(Source, InTypeSection, Declaration), Source.AddBody(TypeName,
      Format('constructor %s.Create(%s);', [TypeName, Params]) + Source.LineBreak + 'begin' + Body +
      Source.LineBreak + 'end;')];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /operator }

/// <summary>Record um die Befehlszeile.</summary>
function RecordAt(ASource: TCommandSource; const AName: string; out ARecord: TIndexSymbol;
  out AReason: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.RecordType) and (Symbol.Range.StartPos.Line < ASource.Line) and
      (Symbol.Range.EndPos.Line > ASource.Line) then
    begin
      ARecord := Symbol;
      Exit(True);
    end;
  Result := Fail('/' + AName + ' gilt nur in der Deklaration eines Records', AReason);
end;

/// <summary>Bedingung, die alle Felder von A und B vergleicht.</summary>
function FieldsEqual(const AFields: TArray<TIndexSymbol>; const ALeft, ARight: string): string;
var
  Field: TIndexSymbol;
begin
  Result := '';
  for Field in AFields do
  begin
    if Result <> '' then
      Result := Result + ' and ';
    Result := Result + Format('(%s.%s = %s.%s)', [ALeft, Field.Name, ARight, Field.Name]);
  end;
  if Result = '' then
    Result := 'True';
end;

/// <summary>Deklaration und Rumpf eines class operator; ATarget nur für Implicit/Explicit.</summary>
procedure OperatorParts(ASource: TCommandSource; const ARecord: TIndexSymbol; const AFields: TArray<TIndexSymbol>;
  const AName, ATarget: string; var ADeclarations: TArray<string>; var ABodies: string);
var
  T, Head, Signature: string;
  Lines: TArray<string>;
  Field: TIndexSymbol;
  Symbol: string;
  Entry: TOperatorEntry;
begin
  T := ARecord.Name;
  Lines := nil;
  Symbol := '';
  for Entry in Operators do
    if Entry.Name = AName then
      Symbol := Entry.Symbol;
  if MatchText(AName, ['Equal', 'NotEqual', 'LessThan', 'LessThanOrEqual', 'GreaterThan',
    'GreaterThanOrEqual']) then
  begin
    Signature := Format('%s(const A, B: %s): Boolean', [AName, T]);
    if AName = 'Equal' then
      Lines := ['  Result := ' + FieldsEqual(AFields, 'A', 'B') + ';']
    else if AName = 'NotEqual' then
      Lines := ['  Result := not (A = B);']
    else
      Lines := ['  Result := False; // TODO: Reihenfolge festlegen'];
  end
  else if MatchText(AName, ['Add', 'Subtract', 'Multiply', 'Divide', 'IntDivide', 'Modulus']) then
  begin
    Signature := Format('%s(const A, B: %s): %s', [AName, T, T]);
    for Field in AFields do
      Lines := Lines + [Format('  Result.%s := A.%s %s B.%s;', [Field.Name, Field.Name, Symbol, Field.Name])];
  end
  else if AName = 'Negative' then
  begin
    Signature := Format('Negative(const A: %s): %s', [T, T]);
    for Field in AFields do
      Lines := Lines + [Format('  Result.%s := -A.%s;', [Field.Name, Field.Name])];
  end
  else
  begin
    if MatchText(AName, ['Implicit', 'Explicit']) then
      Signature := Format('%s(const Value: %s): %s', [AName, T, ATarget])
    else
      Signature := Format('%s(const A: %s): %s', [AName, T, IfThen(MatchText(AName, ['Inc', 'Dec']), T,
        'Boolean')]);
    Lines := [Format('  Result := Default(%s); // TODO', [Copy(Signature, LastDelimiter(':', Signature) + 2,
      MaxInt)])];
  end;
  ADeclarations := ADeclarations + [Format('class operator %s;', [Signature])];
  Head := Format('class operator %s.%s;', [T, Signature]);
  if ABodies <> '' then
    ABodies := ABodies + ASource.LineBreak + ASource.LineBreak;
  ABodies := ABodies + Head + ASource.LineBreak + 'begin';
  for Symbol in Lines do
    ABodies := ABodies + ASource.LineBreak + Symbol;
  ABodies := ABodies + ASource.LineBreak + 'end;';
end;

function ExecuteOperator(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  RecordSymbol: TIndexSymbol;
  Names: TArray<string>;
  Token, Name, Target, Bodies: string;
  Colon: Integer;
  Declarations: TArray<string>;
  Fields: TArray<TIndexSymbol>;
begin
  AEdits := nil;
  Names := nil;
  for Token in Trim(AContext.Arguments).Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    Colon := Pos(':', Token);
    Name := OperatorName(IfThen(Colon > 0, Copy(Token, 1, Colon - 1), Token));
    if Name = '' then
      Exit(Fail('Unbekannter Operator ' + Token, AReason));
    Target := IfThen(Colon > 0, Copy(Token, Colon + 1, MaxInt), 'string');
    // Zu = gehört immer <> und umgekehrt.
    if MatchText(Name, ['Equal', 'NotEqual']) then
      Names := Names + ['Equal:', 'NotEqual:']
    else
      Names := Names + [Name + ':' + Target];
  end;
  if Names = nil then
    Exit(Fail('Erwartet wird /operator = + Implicit', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not RecordAt(Source, 'operator', RecordSymbol, AReason) then
      Exit(False);
    Fields := FieldsOf(Source, RecordSymbol);
    Declarations := ['public'];
    Bodies := '';
    for Token in Names do
    begin
      Name := Copy(Token, 1, Pos(':', Token) - 1);
      // Doppelte (z. B. = und <> zusammen) nur einmal.
      if ContainsText(string.Join(#10, Declarations), 'class operator ' + Name + '(') then
        Continue;
      OperatorParts(Source, RecordSymbol, Fields, Name, Copy(Token, Pos(':', Token) + 1, MaxInt), Declarations,
        Bodies);
    end;
    AEdits := AddToClass(Source, RecordSymbol, Declarations, Bodies) + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /equals }

function ExecuteEquals(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  TypeSymbol, Field: TIndexSymbol;
  Fields, Chosen: TArray<TIndexSymbol>;
  Wanted: TArray<string>;
  Name, T, Condition, Hash, Bodies: string;
  IsRecord, NeedsValue, Known: Boolean;
  OperatorDecls: TArray<string>;
begin
  AEdits := nil;
  Wanted := nil;
  for Name in AContext.Arguments.Split([','], TStringSplitOptions.ExcludeEmpty) do
    Wanted := Wanted + [Trim(Name)];
  Source := TCommandSource.Create(AContext);
  try
    IsRecord := not Source.ClassAt(TypeSymbol);
    if IsRecord and not RecordAt(Source, 'equals', TypeSymbol, AReason) then
      Exit(Fail('/equals gilt nur in einer Klasse, einer ihrer Methoden oder einem Record', AReason));
    Fields := FieldsOf(Source, TypeSymbol);
    Chosen := nil;
    for Field in Fields do
      if (Wanted = nil) or (IndexText(Field.Name, Wanted) >= 0) then
        Chosen := Chosen + [Field];
    for Name in Wanted do
    begin
      Known := False;
      for Field in Chosen do
        Known := Known or SameText(Field.Name, Name);
      if not Known then
        Exit(Fail(Format('Kein Feld %s in %s', [Name, TypeSymbol.Name]), AReason));
    end;
    if Chosen = nil then
      Exit(Fail(TypeSymbol.Name + ' hat keine Felder', AReason));
    if IsRecord then
    begin
      OperatorDecls := ['public'];
      Bodies := '';
      OperatorParts(Source, TypeSymbol, Chosen, 'Equal', '', OperatorDecls, Bodies);
      OperatorParts(Source, TypeSymbol, Chosen, 'NotEqual', '', OperatorDecls, Bodies);
      AEdits := AddToClass(Source, TypeSymbol, OperatorDecls, Bodies) + [Source.RemoveCommand];
      Exit(True);
    end;
    T := TypeSymbol.Name;
    Condition := '';
    Hash := '';
    NeedsValue := False;
    for Field in Chosen do
    begin
      if Condition <> '' then
        Condition := Condition + ' and' + Source.LineBreak + '    ';
      if IsObjectField(Source, AContext.Index, Field) then
      begin
        Condition := Condition + Format('%s.Equals(%s(Obj).%s)', [Field.Name, T, Field.Name]);
        Hash := Hash + Source.LineBreak + Format('  Value := %s.GetHashCode;', [Field.Name]) + Source.LineBreak +
          '  Result := THashBobJenkins.GetHashValue(Value, SizeOf(Value), Result);';
        NeedsValue := True;
      end
      else
      begin
        Condition := Condition + Format('(%s = %s(Obj).%s)', [Field.Name, T, Field.Name]);
        if MatchText(Field.TypeName, ['string', 'UnicodeString', 'TCaption']) then
          Hash := Hash + Source.LineBreak + Format('  Result := THashBobJenkins.GetHashValue(%s, Result);',
            [Field.Name])
        else
          Hash := Hash + Source.LineBreak + Format('  Result := THashBobJenkins.GetHashValue(%s, SizeOf(%s), Result);',
            [Field.Name, Field.Name]);
      end;
    end;
    Bodies := Join(Source, [Format('function %s.Equals(Obj: TObject): Boolean;', [T]), 'begin',
      '  if Obj = Self then', '    Exit(True);', Format('  if not (Obj is %s) then', [T]), '    Exit(False);',
      '  Result := ' + Condition + ';', 'end;', '', Format('function %s.GetHashCode: Integer;', [T])]);
    if NeedsValue then
      Bodies := Bodies + Source.LineBreak + Join(Source, ['var', '  Value: Integer;']);
    Bodies := Bodies + Source.LineBreak + 'begin' + Source.LineBreak + '  Result := 0;' + Hash + Source.LineBreak +
      'end;';
    AEdits := AddToClass(Source, TypeSymbol, ['public', 'function Equals(Obj: TObject): Boolean; override;',
      'function GetHashCode: Integer; override;'], Bodies) + [Source.RemoveCommand];
    AddUses(Source, AContext, TypeSymbol.Range.StartPos.Line, ['System.Hash'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /clone }

/// <summary>Stammt die Klasse (über Vorfahren in der Datei) von TPersistent ab oder hat sie Assign?</summary>
function IsPersistent(ASource: TCommandSource; const AClass: TIndexSymbol): Boolean;
var
  Current: string;
  Symbol: TIndexSymbol;
  Found: Boolean;
  Depth: Integer;
begin
  Current := AClass.Name;
  for Depth := 0 to 20 do
  begin
    Found := False;
    for Symbol in ASource.UnitIndex.Symbols do
      if SameText(Symbol.Container, Current) and SameText(Symbol.Name, 'Assign') then
        Exit(True);
    for Symbol in ASource.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, Current) and
        (Length(Symbol.Ancestors) > 0) then
      begin
        Current := Symbol.Ancestors[0];
        Found := True;
        Break;
      end;
    if MatchText(Current, PersistentBases) then
      Exit(True);
    if not Found then
      Exit(False);
  end;
  Result := False;
end;

/// <summary>Hat ATypeName in der Datei eine Methode Clone?</summary>
function HasClone(ASource: TCommandSource; const ATypeName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Container, ATypeName) and SameText(Symbol.Name, 'Clone') then
      Exit(True);
  Result := False;
end;

function ExecuteClone(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Field: TIndexSymbol;
  T: string;
  Copies: TArray<string>;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/clone gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    T := ClassSymbol.Name;
    Copies := nil;
    if IsPersistent(Source, ClassSymbol) then
      Copies := ['    Result.Assign(Self);']
    else
      for Field in FieldsOf(Source, ClassSymbol) do
        if not IsObjectField(Source, AContext.Index, Field) then
          Copies := Copies + [Format('    Result.%s := %s;', [Field.Name, Field.Name])]
        else if HasClone(Source, Field.TypeName) then
          Copies := Copies + [Format('    Result.%s.Free;', [Field.Name]),
            Format('    Result.%s := %s.Clone;', [Field.Name, Field.Name])]
        else
          Copies := Copies + [Format('    // TODO: Result.%s aus %s kopieren', [Field.Name, Field.Name])];
    AEdits := AddToClass(Source, ClassSymbol, ['public', Format('function Clone: %s;', [T])],
      Join(Source, [Format('function %s.Clone: %s;', [T, T]), 'begin', Format('  Result := %s.Create;', [T]),
      '  try'] + Copies + ['  except', '    Result.Free;', '    raise;', '  end;', 'end;'])) +
      [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

procedure RegisterRecordCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('record', 'Record mit Konstruktor anlegen', '/record TPunkt X, Y: Integer',
    ExecuteRecord));
  ARegistry.Register(Command('operator', 'class operator für den Record anlegen', '/operator = + Implicit',
    ExecuteOperator));
  ARegistry.Register(Command('equals', 'Equals und GetHashCode bzw. = und <> anlegen', '/equals', ExecuteEquals));
  ARegistry.Register(Command('clone', 'Clone mit Freigabe bei Fehlern anlegen', '/clone', ExecuteClone));
end;

end.
