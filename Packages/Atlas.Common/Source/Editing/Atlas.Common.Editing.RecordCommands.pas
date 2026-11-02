unit Atlas.Common.Editing.RecordCommands;

// Schnellbefehle für Records und Wertobjekte (#323) im Rahmen aus #293:
//   /record TPunkt X, Y: Integer [ro]  Record mit Konstruktor; mit ro private Felder und Properties zum Lesen
//   /operator = + Implicit             class operator für den Record unter dem Cursor (= bringt <> mit)
//   /equals [Feld, …]                  Klassen: Equals und GetHashCode über dieselben Felder; Records: = und <>
//   /clone                             Clone über Assign (TPersistent) oder feldweise, gibt Result bei Fehler frei

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /record, /operator, /equals und /clone über ARegister ein.</summary>
procedure RegisterRecordCommands(const ARegister: TSlashRegister);

/// <summary>Operatorname zu Symbol oder Name (= wird Equal, + wird Add); '' wenn unbekannt.</summary>
function OperatorName(const AToken: string): string;
/// <summary>Argumente von /operator für die Auswahl im Erzeugen-Menü (#719): Symbol, sonst Name (Implicit).
/// </summary>
function OperatorTokens: TArray<string>;
/// <summary>Felder der Klasse bzw. des Records um die Befehlszeile für /equals (#719); leer außerhalb.</summary>
function EqualsFields(const AContext: TSlashContext): TArray<string>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.TypeCommands;

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
  begin
    if ((Entry.Symbol <> '') and SameText(Entry.Symbol, AToken)) or SameText(Entry.Name, AToken) then
    begin
      Exit(Entry.Name);
    end;
  end;
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
    begin
      Continue;
    end;
    Colon := Pos(':', Part);
    if Colon = 0 then
    begin
      Exit(False);
    end;
    Group.Names := nil;
    for Name in Copy(Part, 1, Colon - 1).Split([',']) do
    begin
      if not IsValidIdent(Trim(Name)) then
      begin
        Exit(False);
      end;
      Group.Names := Group.Names + [Trim(Name)];
    end;
    Group.TypeName := Trim(Copy(Part, Colon + 1, MaxInt));
    if Group.TypeName = '' then
    begin
      Exit(False);
    end;
    AGroups := AGroups + [Group];
  end;
  Result := Length(AGroups) > 0;
end;

function ExecuteRecord(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
  begin
    Arguments := Trim(Copy(Arguments, 1, Length(Arguments) - 3));
  end;
  Space := Pos(' ', Arguments);
  TypeName := Trim(Copy(Arguments, 1, Space - 1));
  if (Space = 0) or not IsValidIdent(TypeName) or not ParseFields(Copy(Arguments, Space + 1, MaxInt), Groups) then
  begin
    Exit(Fail('Erwartet wird /record TName X, Y: Integer [ro]', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not TypePlace(Source, 'record', InTypeSection, AReason) then
    begin
      Exit(False);
    end;
    Prefix := IfThen(ReadOnly, 'F', '');
    Declaration := [TypeName + ' = record'];
    if ReadOnly then
    begin
      Declaration := Declaration + ['private'];
    end;
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
        begin
          Properties := Properties + [Format('  property %s: %s read %s%s;', [Name, Group.TypeName, Prefix, Name])];
        end;
      end;
      Declaration := Declaration + [Format('  %s%s: %s;', [Prefix, string.Join(', ' + Prefix, Group.Names),
        Group.TypeName])];
      if Params <> '' then
      begin
        Params := Params + '; ';
      end;
      Params := Params + Format('%s: %s', [string.Join(', ', ParamNames), Group.TypeName]);
    end;
    if ReadOnly then
    begin
      Declaration := Declaration + ['public'];
    end;
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
  begin
    if (Symbol.Kind = TIndexSymbolKind.RecordType) and (Symbol.Range.StartPos.Line < ASource.Line) and
      (Symbol.Range.EndPos.Line > ASource.Line) then
    begin
      ARecord := Symbol;
      Exit(True);
    end;
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
    begin
      Result := Result + ' and ';
    end;
    Result := Result + Format('(%s.%s = %s.%s)', [ALeft, Field.Name, ARight, Field.Name]);
  end;
  if Result = '' then
  begin
    Result := 'True';
  end;
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
  begin
    if Entry.Name = AName then
    begin
      Symbol := Entry.Symbol;
    end;
  end;
  if MatchText(AName, ['Equal', 'NotEqual', 'LessThan', 'LessThanOrEqual', 'GreaterThan',
    'GreaterThanOrEqual']) then
  begin
    Signature := Format('%s(const A, B: %s): Boolean', [AName, T]);
    if AName = 'Equal' then
    begin
      Lines := ['  Result := ' + FieldsEqual(AFields, 'A', 'B') + ';'];
    end
    else if AName = 'NotEqual' then
    begin
      Lines := ['  Result := not (A = B);'];
    end
    else
    begin
      Lines := ['  Result := False; // TODO: Reihenfolge festlegen'];
    end;
  end
  else if MatchText(AName, ['Add', 'Subtract', 'Multiply', 'Divide', 'IntDivide', 'Modulus']) then
  begin
    Signature := Format('%s(const A, B: %s): %s', [AName, T, T]);
    for Field in AFields do
    begin
      Lines := Lines + [Format('  Result.%s := A.%s %s B.%s;', [Field.Name, Field.Name, Symbol, Field.Name])];
    end;
  end
  else if AName = 'Negative' then
  begin
    Signature := Format('Negative(const A: %s): %s', [T, T]);
    for Field in AFields do
    begin
      Lines := Lines + [Format('  Result.%s := -A.%s;', [Field.Name, Field.Name])];
    end;
  end
  else
  begin
    if MatchText(AName, ['Implicit', 'Explicit']) then
    begin
      Signature := Format('%s(const Value: %s): %s', [AName, T, ATarget]);
    end
    else
    begin
      Signature := Format('%s(const A: %s): %s', [AName, T, IfThen(MatchText(AName, ['Inc', 'Dec']), T,
        'Boolean')]);
    end;
    Lines := [Format('  Result := Default(%s); // TODO', [Copy(Signature, LastDelimiter(':', Signature) + 2,
      MaxInt)])];
  end;
  ADeclarations := ADeclarations + [Format('class operator %s;', [Signature])];
  Head := Format('class operator %s.%s;', [T, Signature]);
  if ABodies <> '' then
  begin
    ABodies := ABodies + ASource.LineBreak + ASource.LineBreak;
  end;
  ABodies := ABodies + Head + ASource.LineBreak + 'begin';
  for Symbol in Lines do
  begin
    ABodies := ABodies + ASource.LineBreak + Symbol;
  end;
  ABodies := ABodies + ASource.LineBreak + 'end;';
end;

function ExecuteOperator(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
    begin
      Exit(Fail('Unbekannter Operator ' + Token, AReason));
    end;
    Target := IfThen(Colon > 0, Copy(Token, Colon + 1, MaxInt), 'string');
    // Zu = gehört immer <> und umgekehrt.
    if MatchText(Name, ['Equal', 'NotEqual']) then
    begin
      Names := Names + ['Equal:', 'NotEqual:'];
    end
    else
    begin
      Names := Names + [Name + ':' + Target];
    end;
  end;
  if Names = nil then
  begin
    Exit(Fail('Erwartet wird /operator = + Implicit', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not RecordAt(Source, 'operator', RecordSymbol, AReason) then
    begin
      Exit(False);
    end;
    Fields := FieldsOf(Source, RecordSymbol);
    Declarations := ['public'];
    Bodies := '';
    for Token in Names do
    begin
      Name := Copy(Token, 1, Pos(':', Token) - 1);
      // Doppelte (z. B. = und <> zusammen) nur einmal.
      if ContainsText(string.Join(#10, Declarations), 'class operator ' + Name + '(') then
      begin
        Continue;
      end;
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

function ExecuteEquals(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
  begin
    Wanted := Wanted + [Trim(Name)];
  end;
  Source := TCommandSource.Create(AContext);
  try
    IsRecord := not Source.ClassAt(TypeSymbol);
    if IsRecord and not RecordAt(Source, 'equals', TypeSymbol, AReason) then
    begin
      Exit(Fail('/equals gilt nur in einer Klasse, einer ihrer Methoden oder einem Record', AReason));
    end;
    Fields := FieldsOf(Source, TypeSymbol);
    Chosen := nil;
    for Field in Fields do
    begin
      if (Wanted = nil) or (IndexText(Field.Name, Wanted) >= 0) then
      begin
        Chosen := Chosen + [Field];
      end;
    end;
    for Name in Wanted do
    begin
      Known := False;
      for Field in Chosen do
      begin
        Known := Known or SameText(Field.Name, Name);
      end;
      if not Known then
      begin
        Exit(Fail(Format('Kein Feld %s in %s', [Name, TypeSymbol.Name]), AReason));
      end;
    end;
    if Chosen = nil then
    begin
      Exit(Fail(TypeSymbol.Name + ' hat keine Felder', AReason));
    end;
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
      begin
        Condition := Condition + ' and' + Source.LineBreak + '    ';
      end;
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
        begin
          Hash := Hash + Source.LineBreak + Format('  Result := THashBobJenkins.GetHashValue(%s, Result);',
            [Field.Name]);
        end
        else
        begin
          Hash := Hash + Source.LineBreak + Format('  Result := THashBobJenkins.GetHashValue(%s, SizeOf(%s), Result);',
            [Field.Name, Field.Name]);
        end;
      end;
    end;
    Bodies := Join(Source, [Format('function %s.Equals(Obj: TObject): Boolean;', [T]), 'begin',
      '  if Obj = Self then', '    Exit(True);', Format('  if not (Obj is %s) then', [T]), '    Exit(False);',
      '  Result := ' + Condition + ';', 'end;', '', Format('function %s.GetHashCode: Integer;', [T])]);
    if NeedsValue then
    begin
      Bodies := Bodies + Source.LineBreak + Join(Source, ['var', '  Value: Integer;']);
    end;
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
    begin
      if SameText(Symbol.Container, Current) and SameText(Symbol.Name, 'Assign') then
      begin
        Exit(True);
      end;
    end;
    for Symbol in ASource.UnitIndex.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, Current) and
        (Length(Symbol.Ancestors) > 0) then
      begin
        Current := Symbol.Ancestors[0];
        Found := True;
        Break;
      end;
    end;
    if MatchText(Current, PersistentBases) then
    begin
      Exit(True);
    end;
    if not Found then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Hat ATypeName in der Datei eine Methode Clone?</summary>
function HasClone(ASource: TCommandSource; const ATypeName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(Symbol.Container, ATypeName) and SameText(Symbol.Name, 'Clone') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ExecuteClone(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Field: TIndexSymbol;
  T: string;
  Copies, Body: TArray<string>;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/clone gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    T := ClassSymbol.Name;
    Copies := nil;
    if IsPersistent(Source, ClassSymbol) then
    begin
      Copies := ['    Result.Assign(Self);'];
    end
    else
    begin
      for Field in FieldsOf(Source, ClassSymbol) do
      begin
        if not IsObjectField(Source, AContext.Index, Field) then
        begin
          Copies := Copies + [Format('    Result.%s := %s;', [Field.Name, Field.Name])];
        end
        else if HasClone(Source, Field.TypeName) then
        begin
          Copies := Copies + [Format('    Result.%s.Free;', [Field.Name]),
            Format('    Result.%s := %s.Clone;', [Field.Name, Field.Name])];
        end
        else
        begin
          Copies := Copies + [Format('    // TODO: Result.%s aus %s kopieren', [Field.Name, Field.Name])];
        end;
      end;
    end;
    // Erst zusammensetzen: "[...] + Copies" geht nicht als offenes Array-Argument.
    Body := TArray<string>.Create(Format('function %s.Clone: %s;', [T, T]), 'begin',
      Format('  Result := %s.Create;', [T]), '  try') + Copies +
      TArray<string>.Create('  except', '    Result.Free;', '    raise;', '  end;', 'end;');
    AEdits := AddToClass(Source, ClassSymbol, ['public', Format('function Clone: %s;', [T])], Join(Source, Body)) +
      [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

function OperatorTokens: TArray<string>;
var
  Entry: TOperatorEntry;
begin
  Result := nil;
  for Entry in Operators do
  begin
    if Entry.Symbol <> '' then
    begin
      Result := Result + [Entry.Symbol];
    end
    else
    begin
      Result := Result + [Entry.Name];
    end;
  end;
end;

function EqualsFields(const AContext: TSlashContext): TArray<string>;
var
  Source: TCommandSource;
  TypeSymbol, Field: TIndexSymbol;
  Reason: string;
begin
  Result := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(TypeSymbol) and not RecordAt(Source, 'equals', TypeSymbol, Reason) then
    begin
      Exit;
    end;
    for Field in FieldsOf(Source, TypeSymbol) do
    begin
      Result := Result + [Field.Name];
    end;
  finally
    Source.Free;
  end;
end;

procedure RegisterRecordCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('record', 'Record mit Konstruktor anlegen', '/record TPunkt X, Y: Integer',
    ExecuteRecord));
  ARegister(Command('operator', 'class operator für den Record anlegen', '/operator = + Implicit',
    ExecuteOperator));
  ARegister(Command('equals', 'Equals und GetHashCode bzw. = und <> anlegen', '/equals', ExecuteEquals));
  ARegister(Command('clone', 'Clone mit Freigabe bei Fehlern anlegen', '/clone', ExecuteClone));
end;

end.
