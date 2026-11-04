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

type
  /// <summary>Teile des Records aus /record: Felder, Properties, Konstruktorparameter und -rumpf.</summary>
  TRecordParts = record
    Fields: TArray<string>;
    Properties: TArray<string>;
    Params: string;
    Body: string;
    /// <summary>Nimmt eine Feldgruppe auf; mit AReadOnly private Felder F… und Properties.</summary>
    procedure AddGroup(const AGroup: TFieldGroup; AReadOnly: Boolean; const ALineBreak: string);
    /// <summary>Deklaration des Records mit Konstruktor.</summary>
    function Declaration(const ATypeName: string; AReadOnly: Boolean): TArray<string>;
  end;

procedure TRecordParts.AddGroup(const AGroup: TFieldGroup; AReadOnly: Boolean; const ALineBreak: string);
var
  mPrefix, mName: string;
  mParamNames: TArray<string>;
begin
  mPrefix := IfThen(AReadOnly, 'F', '');
  mParamNames := nil;
  for mName in AGroup.Names do
  begin
    mParamNames := mParamNames + ['A' + mName];
    Body := Body + ALineBreak + Format('  %s%s := A%s;', [mPrefix, mName, mName]);
    if AReadOnly then
    begin
      Properties := Properties + [Format('  property %s: %s read %s%s;', [mName, AGroup.TypeName, mPrefix, mName])];
    end;
  end;
  Fields := Fields + [Format('  %s%s: %s;', [mPrefix, string.Join(', ' + mPrefix, AGroup.Names), AGroup.TypeName])];
  if Params <> '' then
  begin
    Params := Params + '; ';
  end;
  Params := Params + Format('%s: %s', [string.Join(', ', mParamNames), AGroup.TypeName]);
end;

function TRecordParts.Declaration(const ATypeName: string; AReadOnly: Boolean): TArray<string>;
begin
  Result := TArray<string>.Create(ATypeName + ' = record');
  if AReadOnly then
  begin
    Result := Result + ['private'];
  end;
  Result := Result + Fields;
  if AReadOnly then
  begin
    Result := Result + ['public'];
  end;
  Result := Result + [Format('  constructor Create(%s);', [Params])] + Properties + ['end;'];
end;

/// <summary>Zerlegt die Argumente von /record in Typname, Feldgruppen und ro; False bei Fehlern.</summary>
function ParseRecord(const AArguments: string; out ATypeName: string; out AGroups: TArray<TFieldGroup>;
  out AReadOnly: Boolean): Boolean;
var
  mArguments: string;
  mSpace: Integer;
begin
  mArguments := Trim(AArguments);
  AReadOnly := EndsText(' ro', mArguments);
  if AReadOnly then
  begin
    mArguments := Trim(Copy(mArguments, 1, Length(mArguments) - 3));
  end;
  mSpace := Pos(' ', mArguments);
  ATypeName := Trim(Copy(mArguments, 1, mSpace - 1));
  AGroups := nil;
  Result := (mSpace > 0) and IsValidIdent(ATypeName) and ParseFields(Copy(mArguments, mSpace + 1, MaxInt), AGroups);
end;

function ExecuteRecord(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTypeName: string;
  mReadOnly, mInTypeSection: Boolean;
  mGroups: TArray<TFieldGroup>;
  mGroup: TFieldGroup;
  mParts: TRecordParts;
begin
  AEdits := nil;
  if not ParseRecord(AContext.Arguments, mTypeName, mGroups, mReadOnly) then
  begin
    Exit(Fail('Erwartet wird /record TName X, Y: Integer [ro]', AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not TypePlace(mSource, 'record', mInTypeSection, AReason) then
    begin
      Exit(False);
    end;
    mParts := Default(TRecordParts);
    for mGroup in mGroups do
    begin
      mParts.AddGroup(mGroup, mReadOnly, mSource.LineBreak);
    end;
    AEdits := [TypeDeclaration(mSource, mInTypeSection, mParts.Declaration(mTypeName, mReadOnly)),
      mSource.AddBody(mTypeName, Format('constructor %s.Create(%s);', [mTypeName, mParts.Params]) +
      mSource.LineBreak + 'begin' + mParts.Body + mSource.LineBreak + 'end;')];
    Result := True;
  finally
    mSource.Free;
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

type
  /// <summary>Gesammelte Deklarationen und Rümpfe von class operator.</summary>
  TOperatorOutput = record
    Declarations: TArray<string>;
    Bodies: string;
    /// <summary>Nimmt Deklaration und Rumpf eines Operators auf.</summary>
    procedure Add(const ATypeName, ASignature: string; const ALines: TArray<string>; const ALineBreak: string);
  end;

procedure TOperatorOutput.Add(const ATypeName, ASignature: string; const ALines: TArray<string>;
  const ALineBreak: string);
var
  mLine: string;
begin
  Declarations := Declarations + [Format('class operator %s;', [ASignature])];
  if Bodies <> '' then
  begin
    Bodies := Bodies + ALineBreak + ALineBreak;
  end;
  Bodies := Bodies + Format('class operator %s.%s;', [ATypeName, ASignature]) + ALineBreak + 'begin';
  for mLine in ALines do
  begin
    Bodies := Bodies + ALineBreak + mLine;
  end;
  Bodies := Bodies + ALineBreak + 'end;';
end;

/// <summary>Symbol zum Operatornamen (Add wird +); '' bei Implicit und Explicit.</summary>
function SymbolOf(const AName: string): string;
var
  mEntry: TOperatorEntry;
begin
  Result := '';
  for mEntry in Operators do
  begin
    if mEntry.Name = AName then
    begin
      Result := mEntry.Symbol;
    end;
  end;
end;

/// <summary>Rumpf eines Vergleichsoperators.</summary>
function ComparisonLines(const AName: string; const AFields: TArray<TIndexSymbol>): TArray<string>;
begin
  if AName = 'Equal' then
  begin
    Result := TArray<string>.Create('  Result := ' + FieldsEqual(AFields, 'A', 'B') + ';');
  end
  else if AName = 'NotEqual' then
  begin
    Result := TArray<string>.Create('  Result := not (A = B);');
  end
  else
  begin
    Result := TArray<string>.Create('  Result := False; // TODO: Reihenfolge festlegen');
  end;
end;

/// <summary>Rumpf eines zweistelligen Rechenoperators: feldweise A Symbol B.</summary>
function ArithmeticLines(const ASymbol: string; const AFields: TArray<TIndexSymbol>): TArray<string>;
var
  mField: TIndexSymbol;
begin
  Result := nil;
  for mField in AFields do
  begin
    Result := Result + [Format('  Result.%s := A.%s %s B.%s;', [mField.Name, mField.Name, ASymbol, mField.Name])];
  end;
end;

/// <summary>Rumpf von Negative: feldweise -A.</summary>
function NegativeLines(const AFields: TArray<TIndexSymbol>): TArray<string>;
var
  mField: TIndexSymbol;
begin
  Result := nil;
  for mField in AFields do
  begin
    Result := Result + [Format('  Result.%s := -A.%s;', [mField.Name, mField.Name])];
  end;
end;

/// <summary>Signatur der übrigen Operatoren; ATarget nur für Implicit/Explicit.</summary>
function OtherSignature(const ATypeName, AName, ATarget: string): string;
begin
  if MatchText(AName, ['Implicit', 'Explicit']) then
  begin
    Result := Format('%s(const Value: %s): %s', [AName, ATypeName, ATarget]);
  end
  else
  begin
    Result := Format('%s(const A: %s): %s', [AName, ATypeName, IfThen(MatchText(AName, ['Inc', 'Dec']), ATypeName,
      'Boolean')]);
  end;
end;

/// <summary>Signatur und Rumpfzeilen eines class operator; ATarget nur für Implicit/Explicit.</summary>
function OperatorLines(const ATypeName, AName, ATarget: string; const AFields: TArray<TIndexSymbol>;
  out ASignature: string): TArray<string>;
begin
  if MatchText(AName, ['Equal', 'NotEqual', 'LessThan', 'LessThanOrEqual', 'GreaterThan',
    'GreaterThanOrEqual']) then
  begin
    ASignature := Format('%s(const A, B: %s): Boolean', [AName, ATypeName]);
    Result := ComparisonLines(AName, AFields);
  end
  else if MatchText(AName, ['Add', 'Subtract', 'Multiply', 'Divide', 'IntDivide', 'Modulus']) then
  begin
    ASignature := Format('%s(const A, B: %s): %s', [AName, ATypeName, ATypeName]);
    Result := ArithmeticLines(SymbolOf(AName), AFields);
  end
  else if AName = 'Negative' then
  begin
    ASignature := Format('Negative(const A: %s): %s', [ATypeName, ATypeName]);
    Result := NegativeLines(AFields);
  end
  else
  begin
    ASignature := OtherSignature(ATypeName, AName, ATarget);
    Result := TArray<string>.Create(Format('  Result := Default(%s); // TODO',
      [Copy(ASignature, LastDelimiter(':', ASignature) + 2, MaxInt)]));
  end;
end;

/// <summary>Deklaration und Rumpf eines class operator in AOutput; ATarget nur für Implicit/Explicit.</summary>
procedure OperatorParts(const ALineBreak: string; const ARecord: TIndexSymbol; const AFields: TArray<TIndexSymbol>;
  const AName, ATarget: string; var AOutput: TOperatorOutput);
var
  mSignature: string;
  mLines: TArray<string>;
begin
  mLines := OperatorLines(ARecord.Name, AName, ATarget, AFields, mSignature);
  AOutput.Add(ARecord.Name, mSignature, mLines, ALineBreak);
end;

function ExecuteOperator(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  RecordSymbol: TIndexSymbol;
  Names: TArray<string>;
  Token, Name, Target: string;
  Colon: Integer;
  Output: TOperatorOutput;
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
    Output := Default(TOperatorOutput);
    Output.Declarations := TArray<string>.Create('public');
    for Token in Names do
    begin
      Name := Copy(Token, 1, Pos(':', Token) - 1);
      // Doppelte (z. B. = und <> zusammen) nur einmal.
      if ContainsText(string.Join(#10, Output.Declarations), 'class operator ' + Name + '(') then
      begin
        Continue;
      end;
      OperatorParts(Source.LineBreak, RecordSymbol, Fields, Name, Copy(Token, Pos(':', Token) + 1, MaxInt), Output);
    end;
    AEdits := AddToClass(Source, RecordSymbol, Output.Declarations, Output.Bodies) + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /equals }

/// <summary>Feldnamen aus den Argumenten von /equals; leer heißt alle Felder.</summary>
function WantedFields(const AArguments: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in AArguments.Split([','], TStringSplitOptions.ExcludeEmpty) do
  begin
    Result := Result + [Trim(mName)];
  end;
end;

/// <summary>Gibt es in AFields ein Feld AName?</summary>
function HasField(const AFields: TArray<TIndexSymbol>; const AName: string): Boolean;
var
  mField: TIndexSymbol;
begin
  Result := False;
  for mField in AFields do
  begin
    Result := Result or SameText(mField.Name, AName);
  end;
end;

/// <summary>Felder für /equals; False mit Grund bei unbekanntem Feld oder ohne Felder.</summary>
function ChooseFields(const AFields: TArray<TIndexSymbol>; const AWanted: TArray<string>; const ATypeName: string;
  out AChosen: TArray<TIndexSymbol>; out AReason: string): Boolean;
var
  mField: TIndexSymbol;
  mName: string;
begin
  AChosen := nil;
  for mField in AFields do
  begin
    if (AWanted = nil) or (IndexText(mField.Name, AWanted) >= 0) then
    begin
      AChosen := AChosen + [mField];
    end;
  end;
  for mName in AWanted do
  begin
    if not HasField(AChosen, mName) then
    begin
      Exit(Fail(Format('Kein Feld %s in %s', [mName, ATypeName]), AReason));
    end;
  end;
  if AChosen = nil then
  begin
    Exit(Fail(ATypeName + ' hat keine Felder', AReason));
  end;
  Result := True;
end;

/// <summary>= und &lt;&gt; über AFields für einen Record.</summary>
function RecordEqualsEdits(ASource: TCommandSource; const ARecord: TIndexSymbol;
  const AFields: TArray<TIndexSymbol>): TArray<TTextEdit>;
var
  mOutput: TOperatorOutput;
begin
  mOutput := Default(TOperatorOutput);
  mOutput.Declarations := TArray<string>.Create('public');
  OperatorParts(ASource.LineBreak, ARecord, AFields, 'Equal', '', mOutput);
  OperatorParts(ASource.LineBreak, ARecord, AFields, 'NotEqual', '', mOutput);
  Result := AddToClass(ASource, ARecord, mOutput.Declarations, mOutput.Bodies) + [ASource.RemoveCommand];
end;

/// <summary>Hash-Zeile für ein Feld ohne Objekt: Strings über ihren Inhalt, sonst über den Speicher.</summary>
function ValueHash(const AField: TIndexSymbol): string;
begin
  if MatchText(AField.TypeName, ['string', 'UnicodeString', 'TCaption']) then
  begin
    Result := Format('  Result := THashBobJenkins.GetHashValue(%s, Result);', [AField.Name]);
  end
  else
  begin
    Result := Format('  Result := THashBobJenkins.GetHashValue(%s, SizeOf(%s), Result);', [AField.Name, AField.Name]);
  end;
end;

type
  /// <summary>Bedingung für Equals und Hash-Zeilen für GetHashCode einer Klasse.</summary>
  TEqualsParts = record
    Condition: string;
    Hash: string;
    NeedsValue: Boolean;
    /// <summary>Nimmt ein Feld auf; Objekte vergleichen über Equals und GetHashCode.</summary>
    procedure AddField(const AField: TIndexSymbol; const ATypeName: string; AIsObject: Boolean;
      const ALineBreak: string);
    /// <summary>Rümpfe von Equals und GetHashCode.</summary>
    function Bodies(ASource: TCommandSource; const ATypeName: string): string;
  end;

procedure TEqualsParts.AddField(const AField: TIndexSymbol; const ATypeName: string; AIsObject: Boolean;
  const ALineBreak: string);
begin
  if Condition <> '' then
  begin
    Condition := Condition + ' and' + ALineBreak + '    ';
  end;
  if AIsObject then
  begin
    Condition := Condition + Format('%s.Equals(%s(Obj).%s)', [AField.Name, ATypeName, AField.Name]);
    Hash := Hash + ALineBreak + Format('  Value := %s.GetHashCode;', [AField.Name]) + ALineBreak +
      '  Result := THashBobJenkins.GetHashValue(Value, SizeOf(Value), Result);';
    NeedsValue := True;
  end
  else
  begin
    Condition := Condition + Format('(%s = %s(Obj).%s)', [AField.Name, ATypeName, AField.Name]);
    Hash := Hash + ALineBreak + ValueHash(AField);
  end;
end;

function TEqualsParts.Bodies(ASource: TCommandSource; const ATypeName: string): string;
begin
  Result := Join(ASource, [Format('function %s.Equals(Obj: TObject): Boolean;', [ATypeName]), 'begin',
    '  if Obj = Self then', '    Exit(True);', Format('  if not (Obj is %s) then', [ATypeName]), '    Exit(False);',
    '  Result := ' + Condition + ';', 'end;', '', Format('function %s.GetHashCode: Integer;', [ATypeName])]);
  if NeedsValue then
  begin
    Result := Result + ASource.LineBreak + Join(ASource, ['var', '  Value: Integer;']);
  end;
  Result := Result + ASource.LineBreak + 'begin' + ASource.LineBreak + '  Result := 0;' + Hash + ASource.LineBreak +
    'end;';
end;

/// <summary>Equals und GetHashCode über AFields für eine Klasse, samt System.Hash in uses.</summary>
function ClassEqualsEdits(ASource: TCommandSource; const AContext: TSlashContext; const AClass: TIndexSymbol;
  const AFields: TArray<TIndexSymbol>): TArray<TTextEdit>;
var
  mParts: TEqualsParts;
  mField: TIndexSymbol;
begin
  mParts := Default(TEqualsParts);
  for mField in AFields do
  begin
    mParts.AddField(mField, AClass.Name, IsObjectField(ASource, AContext.Index, mField), ASource.LineBreak);
  end;
  Result := AddToClass(ASource, AClass, ['public', 'function Equals(Obj: TObject): Boolean; override;',
    'function GetHashCode: Integer; override;'], mParts.Bodies(ASource, AClass.Name)) + [ASource.RemoveCommand];
  AddUses(ASource, AContext, AClass.Range.StartPos.Line, ['System.Hash'], Result);
end;

function ExecuteEquals(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTypeSymbol: TIndexSymbol;
  mChosen: TArray<TIndexSymbol>;
  mIsRecord: Boolean;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mIsRecord := not mSource.ClassAt(mTypeSymbol);
    if mIsRecord and not RecordAt(mSource, 'equals', mTypeSymbol, AReason) then
    begin
      Exit(Fail('/equals gilt nur in einer Klasse, einer ihrer Methoden oder einem Record', AReason));
    end;
    if not ChooseFields(FieldsOf(mSource, mTypeSymbol), WantedFields(AContext.Arguments), mTypeSymbol.Name, mChosen,
      AReason) then
    begin
      Exit(False);
    end;
    if mIsRecord then
    begin
      AEdits := RecordEqualsEdits(mSource, mTypeSymbol, mChosen);
    end
    else
    begin
      AEdits := ClassEqualsEdits(mSource, AContext, mTypeSymbol, mChosen);
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /clone }

/// <summary>Hat ATypeName in der Datei ein Mitglied AMember?</summary>
function HasMember(ASource: TCommandSource; const ATypeName, AMember: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(mSymbol.Container, ATypeName) and SameText(mSymbol.Name, AMember) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Erster Vorfahr der Klasse AClassName in der Datei; False, wenn sie dort keinen hat.</summary>
function AncestorOf(ASource: TCommandSource; const AClassName: string; out AAncestor: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.Name, AClassName) and
      (Length(mSymbol.Ancestors) > 0) then
    begin
      AAncestor := mSymbol.Ancestors[0];
      Exit(True);
    end;
  end;
  AAncestor := '';
  Result := False;
end;

/// <summary>Stammt die Klasse (über Vorfahren in der Datei) von TPersistent ab oder hat sie Assign?</summary>
function IsPersistent(ASource: TCommandSource; const AClass: TIndexSymbol): Boolean;
var
  mCurrent, mAncestor: string;
  mFound: Boolean;
  mDepth: Integer;
begin
  mCurrent := AClass.Name;
  for mDepth := 0 to 20 do
  begin
    if HasMember(ASource, mCurrent, 'Assign') then
    begin
      Exit(True);
    end;
    mFound := AncestorOf(ASource, mCurrent, mAncestor);
    if mFound then
    begin
      mCurrent := mAncestor;
    end;
    if MatchText(mCurrent, PersistentBases) then
    begin
      Exit(True);
    end;
    if not mFound then
    begin
      Exit(False);
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
        else if HasMember(Source, Field.TypeName, 'Clone') then
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
