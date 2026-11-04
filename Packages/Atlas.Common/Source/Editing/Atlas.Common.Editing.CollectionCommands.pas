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
  Atlas.Common.Editing.Contract;

/// <summary>Trägt die Sammlungsbefehle über ARegister ein.</summary>
procedure RegisterCollectionCommands(const ARegister: TSlashRegister);

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
  begin
    Result := 'CompareText(%s, %s)';
  end
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
  begin
    // Boolean und Aufzählungen über die Ordinalzahl.
    Result := 'Ord(%s) - Ord(%s)';
  end;
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
  begin
    Exit;
  end;
  for Index := 0 to Section.ChildCount - 1 do
  begin
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AClassName + '.' + AMethod) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
    begin
      Exit(Section[Index]);
    end;
  end;
end;

/// <summary>Zeile mit "inherited" im Rumpf von ARoutine; -1 ohne.</summary>
function InheritedLine(ASource: TCommandSource; ARoutine: TSyntaxNode): Integer;
var
  Block: TSyntaxNode;
  Index: Integer;
begin
  Block := ARoutine.FindChild(TSyntaxKind.Block);
  for Index := Block.StartPos.Line to Block.EndPos.Line do
  begin
    if StartsText('inherited', Trim(ASource.Lines[Index])) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

type
  /// <summary>Name, Typ und Erzeugung einer neuen Sammlung.</summary>
  TCollectionSpec = record
    Name: string;
    TypeName: string;
    Construction: string;
    class function Create(const AName, ATypeName, AConstruction: string): TCollectionSpec; static;
  end;

  /// <summary>Sammelt die Änderungen für ein Feld, das der Konstruktor erzeugt und der Destruktor freigibt.
  /// </summary>
  TOwnedField = record
    Source: TCommandSource;
    ClassSymbol: TIndexSymbol;
    Spec: TCollectionSpec;
    Edits: TArray<TTextEdit>;
    /// <summary>Neue Zeilen der Klassendeklaration ('private', 'public' oder eine Deklaration).</summary>
    Declarations: TArray<string>;
    /// <summary>Neue Rümpfe, durch Leerzeilen getrennt.</summary>
    Bodies: string;
    procedure AddBody(const ABody: string);
    procedure AddField;
    function AddCreate: Boolean;
    procedure AddFree(AHasConstructor: Boolean);
    function DeclarationText(const AIndent: string): string;
    procedure AddDeclarations;
  end;

class function TCollectionSpec.Create(const AName, ATypeName, AConstruction: string): TCollectionSpec;
begin
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.Construction := AConstruction;
end;

procedure TOwnedField.AddBody(const ABody: string);
begin
  if Bodies <> '' then
  begin
    Bodies := Bodies + Source.LineBreak + Source.LineBreak;
  end;
  Bodies := Bodies + ABody;
end;

/// <summary>Feld in den private-Abschnitt der Klasse, ohne einen als neue Deklaration.</summary>
procedure TOwnedField.AddField;
var
  mPrivateAt: Integer;
begin
  mPrivateAt := Source.PrivateLine(ClassSymbol);
  if mPrivateAt >= 0 then
  begin
    Edits := Edits + [Source.AfterLine(mPrivateAt, Source.Indent(mPrivateAt) + '  ' + Spec.Name + ': ' +
      Spec.TypeName + ';')];
  end
  else
  begin
    Declarations := Declarations + ['private', Spec.Name + ': ' + Spec.TypeName + ';'];
  end;
end;

/// <summary>Erzeugen hinter inherited im Konstruktor bzw. ein neuer Konstruktor; True, wenn es einen gab.
/// </summary>
function TOwnedField.AddCreate: Boolean;
var
  mConstructor: TSyntaxNode;
  mLine: Integer;
  mCreate, mLB: string;
begin
  mCreate := Spec.Name + ' := ' + Spec.Construction + ';';
  mConstructor := MethodNode(Source, ClassSymbol.Name, 'Create');
  Result := mConstructor <> nil;
  if Result then
  begin
    mLine := InheritedLine(Source, mConstructor);
    if mLine < 0 then
    begin
      mLine := mConstructor.FindChild(TSyntaxKind.Block).StartPos.Line;
    end;
    Edits := Edits + [Source.AfterLine(mLine, Source.Indent(mConstructor.StartPos.Line) + '  ' + mCreate)];
  end
  else
  begin
    mLB := Source.LineBreak;
    Declarations := Declarations + ['public', 'constructor Create;'];
    AddBody(Format('constructor %s.Create;', [ClassSymbol.Name]) + mLB + 'begin' + mLB + '  inherited Create;' +
      mLB + '  ' + mCreate + mLB + 'end;');
  end;
end;

/// <summary>Free vor inherited im Destruktor bzw. ein neuer Destruktor.</summary>
procedure TOwnedField.AddFree(AHasConstructor: Boolean);
var
  mDestructor: TSyntaxNode;
  mLine: Integer;
  mFree, mLB: string;
begin
  mFree := Spec.Name + '.Free;';
  mDestructor := MethodNode(Source, ClassSymbol.Name, 'Destroy');
  if mDestructor <> nil then
  begin
    mLine := InheritedLine(Source, mDestructor);
    if mLine < 0 then
    begin
      mLine := mDestructor.FindChild(TSyntaxKind.Block).EndPos.Line;
    end;
    Edits := Edits + [Source.BeforeLine(mLine, Source.Indent(mDestructor.StartPos.Line) + '  ' + mFree)];
    Exit;
  end;
  if AHasConstructor then
  begin
    Declarations := Declarations + ['public'];
  end;
  Declarations := Declarations + ['destructor Destroy; override;'];
  mLB := Source.LineBreak;
  AddBody(Format('destructor %s.Destroy;', [ClassSymbol.Name]) + mLB + 'begin' + mLB + '  ' + mFree + mLB +
    '  inherited;' + mLB + 'end;');
end;

function TOwnedField.DeclarationText(const AIndent: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(Declarations) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + Source.LineBreak;
    end;
    if MatchText(Declarations[mIndex], ['private', 'public']) then
    begin
      Result := Result + AIndent + Declarations[mIndex];
    end
    else
    begin
      Result := Result + AIndent + '  ' + Declarations[mIndex];
    end;
  end;
end;

/// <summary>Neue Deklarationen vor das end der Klasse.</summary>
procedure TOwnedField.AddDeclarations;
var
  mEndLine: Integer;
begin
  if Declarations = nil then
  begin
    Exit;
  end;
  mEndLine := ClassSymbol.Range.EndPos.Line;
  Edits := Edits + [Source.BeforeLine(mEndLine, DeclarationText(Source.Indent(mEndLine)))];
end;

/// <summary>Feld ASpec mit Erzeugen im Konstruktor und Free im Destruktor.</summary>
function AddOwnedField(ASource: TCommandSource; const AClass: TIndexSymbol;
  const ASpec: TCollectionSpec): TArray<TTextEdit>;
var
  mField: TOwnedField;
begin
  mField := Default(TOwnedField);
  mField.Source := ASource;
  mField.ClassSymbol := AClass;
  mField.Spec := ASpec;
  mField.AddField;
  mField.AddFree(mField.AddCreate);
  mField.AddDeclarations;
  if mField.Bodies <> '' then
  begin
    mField.Edits := mField.Edits + [ASource.AddBody(AClass.Name, mField.Bodies)];
  end;
  Result := mField.Edits;
end;

/// <summary>Lokale Variable ASpec mit Erzeugen und try … finally Free um die folgenden Anweisungen.</summary>
function AddOwnedLocal(ASource: TCommandSource; ARoutine: TSyntaxNode; const ASpec: TCollectionSpec;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mIndent, mCreate, mLB: string;
  mWrapped: TArray<TTextEdit>;
begin
  mIndent := ASource.Indent(ASource.Line);
  mCreate := ASpec.Name + ' := ' + ASpec.Construction + ';';
  mLB := ASource.LineBreak;
  if Wrap(ASource, 'list', [mCreate, 'try'], ['finally', '  ' + ASpec.Name + '.Free;', 'end;'], '  ', mWrapped,
    AReason) then
  begin
    AEdits := mWrapped;
  end
  else
  begin
    // Ohne folgende Anweisungen: leerer Rumpf.
    AEdits := [TTextEdit.Create(TTextRange.Create(ASource.Line, 0, ASource.Line + 1, 0),
      mIndent + mCreate + mLB + mIndent + 'try' + mLB + mIndent + '  ' + mLB + mIndent + 'finally' + mLB + mIndent +
      '  ' + ASpec.Name + '.Free;' + mLB + mIndent + 'end;' + mLB)];
  end;
  AEdits := [AddLocal(ASource, ARoutine, TSyntaxKind.VarSection, 'var', ASpec.Name + ': ' + ASpec.TypeName + ';')] +
    AEdits;
  Result := True;
end;

/// <summary>Gemeinsamer Ablauf von /list und /dict: Feld in der Klasse oder lokale Variable.</summary>
function AddCollection(const AContext: TSlashContext; const ASpec: TCollectionSpec; const AUnits: array of string;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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
      if not AddOwnedLocal(Source, Routine, ASpec, Edits, AReason) then
      begin
        Exit(False);
      end;
      AddUses(Source, AContext, Source.Line, AUnits, Edits);
    end
    else if Source.ClassAt(ClassSymbol) then
    begin
      Edits := AddOwnedField(Source, ClassSymbol, ASpec) + [Source.RemoveCommand];
      AddUses(Source, AContext, ClassSymbol.Range.StartPos.Line, AUnits, Edits);
    end
    else
    begin
      Exit(Fail('/' + AContext.Name + ' gilt nur in einer Klasse oder im Rumpf einer Routine', AReason));
    end;
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
  begin
    Exit(Fail('Erwartet wird /list Name: TTyp', AReason));
  end;
  if IsClass(AContext, ElementType) then
  begin
    TypeName := 'TObjectList<' + ElementType + '>';
  end
  else
  begin
    TypeName := 'TList<' + ElementType + '>';
  end;
  Result := AddCollection(AContext, TCollectionSpec.Create(Name, TypeName, TypeName + '.Create'),
    ['System.Generics.Collections'], AEdits, AReason);
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
  begin
    Exit(Fail('Erwartet wird /' + AContext.Name + ' Name: TSchluessel, TWert', AReason));
  end;
  Comma := Pos(',', Types);
  KeyType := Trim(Copy(Types, 1, Comma - 1));
  ValueType := Trim(Copy(Types, Comma + 1, MaxInt));
  if (Comma = 0) or not IsValidIdent(KeyType, True) or not IsValidIdent(ValueType, True) then
  begin
    Exit(Fail('Erwartet wird /' + AContext.Name + ' Name: TSchluessel, TWert', AReason));
  end;
  if AIgnoreCase and not MatchText(KeyType, StringTypes) then
  begin
    Exit(Fail('/dict! braucht einen String als Schlüssel', AReason));
  end;
  Owned := IsClass(AContext, ValueType);
  if Owned then
  begin
    TypeName := Format('TObjectDictionary<%s, %s>', [KeyType, ValueType]);
  end
  else
  begin
    TypeName := Format('TDictionary<%s, %s>', [KeyType, ValueType]);
  end;
  Arguments := '';
  if Owned then
  begin
    Arguments := '[doOwnsValues]';
  end;
  if AIgnoreCase then
  begin
    if Arguments <> '' then
    begin
      Arguments := Arguments + ', ';
    end;
    Arguments := Arguments + 'TIStringComparer.Ordinal';
  end;
  if Arguments <> '' then
  begin
    Arguments := '(' + Arguments + ')';
  end;
  if AIgnoreCase then
  begin
    Result := AddCollection(AContext, TCollectionSpec.Create(Name, TypeName, TypeName + '.Create' + Arguments),
      ['System.Generics.Collections', 'System.Generics.Defaults'], AEdits, AReason);
  end
  else
  begin
    Result := AddCollection(AContext, TCollectionSpec.Create(Name, TypeName, TypeName + '.Create' + Arguments),
      ['System.Generics.Collections'], AEdits, AReason);
  end;
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
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Variable]) and
      SameText(Symbol.Name, AName) and (Symbol.TypeArgs <> '') then
    begin
      Exit(Trim(Copy(Symbol.TypeArgs, LastDelimiter(',', Symbol.TypeArgs) + 1, MaxInt)));
    end;
  end;
  // Lokale Variable: "Name: TList<T>" bzw. "var Name := TList<T>.Create".
  Result := '';
  Routine := ASource.RoutineAt;
  if Routine = nil then
  begin
    Exit;
  end;
  for Index := Routine.StartPos.Line to ASource.Line - 1 do
  begin
    Line := ASource.Lines[Index];
    Start := Pos(LowerCase(AName), LowerCase(Line));
    if Start = 0 then
    begin
      Continue;
    end;
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
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and SameText(Symbol.Container, AType) and
      SameText(Symbol.Name, AMember) then
    begin
      Exit(Symbol.TypeName);
    end;
  end;
  if AIndex <> nil then
  begin
    for Location in AIndex.FindSymbols(AMember) do
    begin
      if (Location.Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
        SameText(Location.Symbol.Container, AType) then
      begin
        Exit(Location.Symbol.TypeName);
      end;
    end;
  end;
  Result := '';
end;

/// <summary>"/sort Liste [-]Mitglied" zerlegen; False bei falscher Form.</summary>
function ParseSortArguments(const AArguments: string; out ACollection, AMember: string;
  out ADescending: Boolean): Boolean;
var
  mArguments: string;
  mSpace: Integer;
begin
  mArguments := Trim(AArguments);
  mSpace := Pos(' ', mArguments);
  ACollection := Trim(Copy(mArguments, 1, mSpace - 1));
  AMember := Trim(Copy(mArguments, mSpace + 1, MaxInt));
  ADescending := StartsStr('-', AMember);
  if ADescending then
  begin
    AMember := Trim(Copy(AMember, 2, MaxInt));
  end;
  Result := (mSpace > 0) and IsValidIdent(ACollection, True) and IsValidIdent(AMember);
end;

/// <summary>Aufruf von Sort mit einem TComparer für AElement, der ACompare liefert; ersetzt die Befehlszeile.
/// </summary>
function SortText(ASource: TCommandSource; const ACollection, AElement, ACompare: string): string;
var
  mIndent, mLB: string;
begin
  mIndent := ASource.Indent(ASource.Line);
  mLB := ASource.LineBreak;
  Result := mIndent + ACollection + '.Sort(TComparer<' + AElement + '>.Construct(' + mLB +
    mIndent + '  function(const L, R: ' + AElement + '): Integer' + mLB +
    mIndent + '  begin' + mLB +
    mIndent + '    Result := ' + ACompare + ';' + mLB +
    mIndent + '  end));' + mLB;
end;

function ExecuteSort(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mCollection, mMember, mElement, mKind, mCompare, mCompareUnit: string;
  mDescending: Boolean;
begin
  AEdits := nil;
  if not ParseSortArguments(AContext.Arguments, mCollection, mMember, mDescending) then
  begin
    Exit(Fail('Erwartet wird /sort Liste [-]Mitglied', AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if mSource.RoutineAt = nil then
    begin
      Exit(Fail('/sort gilt nur im Rumpf einer Routine', AReason));
    end;
    mElement := ElementType(mSource, mCollection);
    if mElement = '' then
    begin
      Exit(Fail('Elementtyp von ' + mCollection + ' nicht erkannt', AReason));
    end;
    mKind := MemberType(mSource, AContext.Index, mElement, mMember);
    if mKind = '' then
    begin
      Exit(Fail(mElement + ' hat kein Feld oder keine Property ' + mMember, AReason));
    end;
    mCompare := CompareFunction(mKind, mCompareUnit);
    if mDescending then
    begin
      mCompare := Format(mCompare, ['R.' + mMember, 'L.' + mMember]);
    end
    else
    begin
      mCompare := Format(mCompare, ['L.' + mMember, 'R.' + mMember]);
    end;
    AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line + 1, 0),
      SortText(mSource, mCollection, mElement, mCompare))];
    AddUses(mSource, AContext, mSource.Line, ['System.Generics.Defaults', mCompareUnit], AEdits);
    Result := True;
  finally
    mSource.Free;
  end;
end;

/// <summary>Ist AName ein Feld, eine Property oder Methode von AType (Datei oder Index)?</summary>
function IsMember(ASource: TCommandSource; const AIndex: ISymbolIndex; const AType, AName: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(Symbol.Container, AType) and SameText(Symbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  if AIndex <> nil then
  begin
    for Location in AIndex.FindSymbols(AName) do
    begin
      if SameText(Location.Symbol.Container, AType) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Mindestens ein Bezeichner unter ATokens ist ein Mitglied von AElement.</summary>
function KnowsMembers(ASource: TCommandSource; const AIndex: ISymbolIndex; const AElement: string;
  const ATokens: TArray<TPascalToken>): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := 0;
  while not Result and (mIndex <= High(ATokens)) do
  begin
    Result := (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      IsMember(ASource, AIndex, AElement, ATokens[mIndex].Text);
    Inc(mIndex);
  end;
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
  Known := KnowsMembers(ASource, AIndex, AElement, Tokens);
  Result := '';
  Last := 0;
  AfterDot := False;
  First := True;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Comment then
    begin
      Continue;
    end;
    Prefix := False;
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and not AfterDot then
    begin
      if Known then
      begin
        Prefix := IsMember(ASource, AIndex, AElement, Tokens[Index].Text);
      end
      else
      begin
        Prefix := First and not SameText(Tokens[Index].Text, AVariable);
      end;
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

/// <summary>"/filter Liste Bedingung" zerlegen; False bei falscher Form.</summary>
function ParseFilterArguments(const AArguments: string; out ACollection, ACondition: string): Boolean;
var
  mArguments: string;
  mSpace: Integer;
begin
  mArguments := Trim(AArguments);
  mSpace := Pos(' ', mArguments);
  ACollection := Trim(Copy(mArguments, 1, mSpace - 1));
  ACondition := Trim(Copy(mArguments, mSpace + 1, MaxInt));
  Result := (mSpace > 0) and IsValidIdent(ACollection, True) and (ACondition <> '');
end;

/// <summary>Laufvariable: erster Buchstabe des Typs ohne T.</summary>
function LoopVariable(const AElement: string): string;
begin
  if (Length(AElement) > 1) and (AElement[1] = 'T') then
  begin
    Result := Copy(AElement, 2, 1);
  end
  else
  begin
    Result := Copy(AElement, 1, 1);
  end;
  Result := UpperCase(Result);
end;

type
  /// <summary>Schleife von /filter, die die Treffer in eine neue Liste sammelt.</summary>
  TFilterLoop = record
    Collection: string;
    Element: string;
    Variable: string;
    /// <summary>Bedingung mit der Laufvariable als Bezug.</summary>
    Condition: string;
    /// <summary>Inline-Variablen verfügbar (ab Delphi 10.3, #109); sonst stehen beide im var-Abschnitt.</summary>
    UseInline: Boolean;
    function Text(const AIndent, ALineBreak: string): string;
  end;

function TFilterLoop.Text(const AIndent, ALineBreak: string): string;
var
  mHead, mLoop: string;
begin
  if UseInline then
  begin
    mHead := 'var Treffer := ';
    mLoop := 'for var ';
  end
  else
  begin
    mHead := 'Treffer := ';
    mLoop := 'for ';
  end;
  Result := AIndent + mHead + 'TList<' + Element + '>.Create;' + ALineBreak +
    AIndent + 'try' + ALineBreak +
    AIndent + '  ' + mLoop + Variable + ' in ' + Collection + ' do' + ALineBreak +
    AIndent + '    if ' + Condition + ' then' + ALineBreak +
    AIndent + '      Treffer.Add(' + Variable + ');' + ALineBreak +
    AIndent + '  ' + ALineBreak +
    AIndent + 'finally' + ALineBreak +
    AIndent + '  Treffer.Free;' + ALineBreak +
    AIndent + 'end;' + ALineBreak;
end;

function ExecuteFilter(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mLoop: TFilterLoop;
  mCondition, mLB: string;
begin
  AEdits := nil;
  mLoop := Default(TFilterLoop);
  if not ParseFilterArguments(AContext.Arguments, mLoop.Collection, mCondition) then
  begin
    Exit(Fail('Erwartet wird /filter Liste Bedingung', AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail('/filter gilt nur im Rumpf einer Routine', AReason));
    end;
    mLoop.Element := ElementType(mSource, mLoop.Collection);
    if mLoop.Element = '' then
    begin
      Exit(Fail('Elementtyp von ' + mLoop.Collection + ' nicht erkannt', AReason));
    end;
    mLoop.Variable := LoopVariable(mLoop.Element);
    mLoop.Condition := ElementCondition(mSource, AContext.Index, mLoop.Element, mLoop.Variable, mCondition);
    mLoop.UseInline := TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion);
    mLB := mSource.LineBreak;
    AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line + 1, 0),
      mLoop.Text(mSource.Indent(mSource.Line), mLB))];
    if not mLoop.UseInline then
    begin
      AEdits := [AddLocal(mSource, mRoutine, TSyntaxKind.VarSection, 'var', 'Treffer: TList<' + mLoop.Element + '>;' +
        mLB + mSource.Indent(mRoutine.StartPos.Line) + '  ' + mLoop.Variable + ': ' + mLoop.Element + ';')] + AEdits;
    end;
    AddUses(mSource, AContext, mSource.Line, ['System.Generics.Collections'], AEdits);
    Result := True;
  finally
    mSource.Free;
  end;
end;

procedure AddName(var ANames: TArray<string>; const AName: string);
begin
  if (AName <> '') and not MatchText(AName, ANames) then
  begin
    ANames := ANames + [AName];
  end;
end;

/// <summary>Felder der Klasse an der Befehlszeile und globale Variablen mit Typargumenten.</summary>
procedure AddScopeCollections(ASource: TCommandSource; var ANames: TArray<string>);
var
  mSymbol, mClass: TIndexSymbol;
  mHasClass: Boolean;
begin
  mHasClass := ASource.ClassAt(mClass);
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Variable]) and
      (mSymbol.TypeArgs <> '') and ((mSymbol.Container = '') or (mHasClass and
      SameText(mSymbol.Container, mClass.Name))) then
    begin
      AddName(ANames, mSymbol.Name);
    end;
  end;
end;

/// <summary>Deklaration ohne var, out oder const davor.</summary>
function WithoutModifier(const AText: string): string;
begin
  Result := Trim(AText);
  if StartsText('var ', Result) or StartsText('out ', Result) then
  begin
    Result := Trim(Copy(Result, 5, MaxInt));
  end
  else if StartsText('const ', Result) then
  begin
    Result := Trim(Copy(Result, 7, MaxInt));
  end;
end;

/// <summary>Namen einer Deklaration "A, B: TList&lt;T&gt;"; nur mit Typargumenten hinter dem Doppelpunkt.
/// </summary>
procedure AddDeclaredNames(const APart: string; var ANames: TArray<string>);
var
  mDeclared, mName: string;
  mColon: Integer;
begin
  mDeclared := WithoutModifier(APart);
  mColon := Pos(':', mDeclared);
  if (mColon = 0) or (Pos('<', mDeclared) < mColon) then
  begin
    Exit;
  end;
  for mName in Copy(mDeclared, 1, mColon - 1).Split([',']) do
  begin
    if IsValidIdent(Trim(mName)) then
    begin
      AddName(ANames, Trim(mName));
    end;
  end;
end;

/// <summary>Sammlungen im Gültigkeitsbereich der Befehlszeile.</summary>
function CollectionNames(ASource: TCommandSource): TArray<string>;
var
  mRoutine: TSyntaxNode;
  mIndex: Integer;
  mPart: string;
begin
  Result := nil;
  AddScopeCollections(ASource, Result);
  // Parameter und lokale Variablen: "A, B: TList<T>" im Kopf oder var-Abschnitt, "var Name := TList<T>.Create".
  mRoutine := ASource.RoutineAt;
  if mRoutine = nil then
  begin
    Exit;
  end;
  for mIndex := mRoutine.StartPos.Line to ASource.Line - 1 do
  begin
    for mPart in StringReplace(ASource.Lines[mIndex], '(', ';', [rfReplaceAll]).Split([';']) do
    begin
      AddDeclaredNames(mPart, Result);
    end;
  end;
end;

/// <summary>Felder und Properties von AElement unter ASymbols.</summary>
procedure AddElementMembers(const ASymbols: TArray<TIndexSymbol>; const AElement: string;
  var ANames: TArray<string>);
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASymbols do
  begin
    if (mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) and
      SameText(mSymbol.Container, AElement) then
    begin
      AddName(ANames, mSymbol.Name);
    end;
  end;
end;

/// <summary>Felder und Properties von AElement aus den Dateien des Index, die AElement deklarieren.</summary>
procedure AddIndexedMembers(const AIndex: ISymbolIndex; const AElement: string; var ANames: TArray<string>);
var
  mLocation: TSymbolLocation;
  mFound: TUnitIndex;
begin
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(AElement) do
  begin
    if (mLocation.Symbol.Container = '') and AIndex.FindFile(mLocation.FileName, mFound) then
    begin
      AddElementMembers(mFound.Symbols, AElement, ANames);
    end;
  end;
end;

function CollectionChoices(const AContext: TSlashContext; const ACollection: string): TArray<string>;
var
  mSource: TCommandSource;
  mElement: string;
begin
  Result := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if ACollection = '' then
    begin
      Exit(CollectionNames(mSource));
    end;
    mElement := ElementType(mSource, ACollection);
    if mElement <> '' then
    begin
      AddElementMembers(mSource.UnitIndex.Symbols, mElement, Result);
      AddIndexedMembers(AContext.Index, mElement, Result);
    end;
  finally
    mSource.Free;
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

procedure RegisterCollectionCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('list', 'Liste als Feld oder lokale Variable', '/list FKunden: TKunde', ExecuteList));
  ARegister(Command('dict', 'Dictionary als Feld oder lokale Variable', '/dict FCache: string, TKunde',
    ExecuteDictPlain));
  ARegister(Command('dict!', 'Dictionary mit Schlüsseln ohne Groß-/Kleinschreibung',
    '/dict! FCache: string, TKunde', ExecuteDictIgnoreCase));
  ARegister(Command('sort', 'Liste nach Feld oder Property sortieren', '/sort Kunden -Umsatz', ExecuteSort));
  ARegister(Command('filter', 'Treffer einer Bedingung in eine neue Liste', '/filter Kunden Aktiv',
    ExecuteFilter));
end;

end.
