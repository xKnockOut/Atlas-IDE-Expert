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
  Atlas.Common.Editing.TypeCommands,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TRecordCommandsText = (ExpectedIsRecordTNameX, OnlyAppliesInTheDeclaration, ExpectedIsOperatorImplicit, NoFieldIn,
    HasNoFields, EqualsOnlyAppliesInA, CloneOnlyAppliesInA, CreateARecordWithConstructor, CreateAClassOperatorFor,
    CreateEqualsAndGetHashCodeOr, CreateCloneWithFreeingOn, TODOCopyResultFrom, UnknownOperator,
    RecordTPointXYInteger);

const
  cTexts: array[TRecordCommandsText] of TAtlasText = (
    (De: 'Erwartet wird /record TName X, Y: Integer [ro]'; En: 'Expected is /record TName X, Y: Integer [ro]'),
    (De: '/%s gilt nur in der Deklaration eines Records'; En: '/%s only applies in the declaration of a record'),
    (De: 'Erwartet wird /operator = + Implicit'; En: 'Expected is /operator = + Implicit'),
    (De: 'Kein Feld %s in %s'; En: 'No field %s in %s'),
    (De: ' hat keine Felder'; En: ' has no fields'),
    (De: '/equals gilt nur in einer Klasse, einer ihrer Methoden oder einem Record';
     En: '/equals only applies in a class, one of its methods or a record'),
    (De: '/clone gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/clone only applies in a class or one of its methods'),
    (De: 'Record mit Konstruktor anlegen'; En: 'Create a record with constructor'),
    (De: 'class operator für den Record anlegen'; En: 'Create a class operator for the record'),
    (De: 'Equals und GetHashCode bzw. = und <> anlegen'; En: 'Create Equals and GetHashCode or = and <>'),
    (De: 'Clone mit Freigabe bei Fehlern anlegen'; En: 'Create Clone with freeing on errors'),
    (De: '    // TODO: Result.%s aus %s kopieren'; En: '    // TODO: copy Result.%s from %s'),
    (De: 'Unbekannter Operator '; En: 'Unknown operator '),
    (De: '/record TPunkt X, Y: Integer'; En: '/record TPoint X, Y: Integer'));

{$SCOPEDENUMS OFF}

type
  TOperatorEntry = record
    Symbol: string;
    Name: string;
  end;

const
  cOperators: array[0..19] of TOperatorEntry = (
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
  cPersistentBases: array[0..6] of string = ('TPersistent', 'TComponent', 'TCollection', 'TCollectionItem',
    'TStrings', 'TStringList', 'TInterfacedPersistent');

function OperatorName(const AToken: string): string;
var
  mEntry: TOperatorEntry;
begin
  for mEntry in cOperators do
  begin
    if ((mEntry.Symbol <> '') and SameText(mEntry.Symbol, AToken)) or SameText(mEntry.Name, AToken) then
    begin
      Exit(mEntry.Name);
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
  mPart, mName: string;
  mGroup: TFieldGroup;
  mColon: Integer;
begin
  AGroups := nil;
  for mPart in AText.Split([';']) do
  begin
    if Trim(mPart) = '' then
    begin
      Continue;
    end;
    mColon := Pos(':', mPart);
    if mColon = 0 then
    begin
      Exit(False);
    end;
    mGroup.Names := nil;
    for mName in Copy(mPart, 1, mColon - 1).Split([',']) do
    begin
      if not IsValidIdent(Trim(mName)) then
      begin
        Exit(False);
      end;
      mGroup.Names := mGroup.Names + [Trim(mName)];
    end;
    mGroup.TypeName := Trim(Copy(mPart, mColon + 1, MaxInt));
    if mGroup.TypeName = '' then
    begin
      Exit(False);
    end;
    AGroups := AGroups + [mGroup];
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
    Exit(Fail(cTexts[TRecordCommandsText.ExpectedIsRecordTNameX].Text, AReason));
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
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.RecordType) and (mSymbol.Range.StartPos.Line < ASource.Line) and
      (mSymbol.Range.EndPos.Line > ASource.Line) then
    begin
      ARecord := mSymbol;
      Exit(True);
    end;
  end;
  Result := Fail(cTexts[TRecordCommandsText.OnlyAppliesInTheDeclaration].Fmt([AName]), AReason);
end;

/// <summary>Bedingung, die alle Felder von A und B vergleicht.</summary>
function FieldsEqual(const AFields: TArray<TIndexSymbol>; const ALeft, ARight: string): string;
var
  mField: TIndexSymbol;
begin
  Result := '';
  for mField in AFields do
  begin
    if Result <> '' then
    begin
      Result := Result + ' and ';
    end;
    Result := Result + Format('(%s.%s = %s.%s)', [ALeft, mField.Name, ARight, mField.Name]);
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
  for mEntry in cOperators do
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
  mSource: TCommandSource;
  mRecordSymbol: TIndexSymbol;
  mNames: TArray<string>;
  mToken, mName, mTarget: string;
  mColon: Integer;
  mOutput: TOperatorOutput;
  mFields: TArray<TIndexSymbol>;
begin
  AEdits := nil;
  mNames := nil;
  for mToken in Trim(AContext.Arguments).Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    mColon := Pos(':', mToken);
    mName := OperatorName(IfThen(mColon > 0, Copy(mToken, 1, mColon - 1), mToken));
    if mName = '' then
    begin
      Exit(Fail(cTexts[TRecordCommandsText.UnknownOperator].Text + mToken, AReason));
    end;
    mTarget := IfThen(mColon > 0, Copy(mToken, mColon + 1, MaxInt), 'string');
    // Zu = gehört immer <> und umgekehrt.
    if MatchText(mName, ['Equal', 'NotEqual']) then
    begin
      mNames := mNames + ['Equal:', 'NotEqual:'];
    end
    else
    begin
      mNames := mNames + [mName + ':' + mTarget];
    end;
  end;
  if mNames = nil then
  begin
    Exit(Fail(cTexts[TRecordCommandsText.ExpectedIsOperatorImplicit].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not RecordAt(mSource, 'operator', mRecordSymbol, AReason) then
    begin
      Exit(False);
    end;
    mFields := FieldsOf(mSource, mRecordSymbol);
    mOutput := Default(TOperatorOutput);
    mOutput.Declarations := TArray<string>.Create('public');
    for mToken in mNames do
    begin
      mName := Copy(mToken, 1, Pos(':', mToken) - 1);
      // Doppelte (z. B. = und <> zusammen) nur einmal.
      if ContainsText(string.Join(#10, mOutput.Declarations), 'class operator ' + mName + '(') then
      begin
        Continue;
      end;
      OperatorParts(mSource.LineBreak, mRecordSymbol, mFields, mName, Copy(mToken, Pos(':', mToken) + 1, MaxInt),
        mOutput);
    end;
    AEdits := AddToClass(mSource, mRecordSymbol, mOutput.Declarations, mOutput.Bodies) + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
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
      Exit(Fail(cTexts[TRecordCommandsText.NoFieldIn].Fmt([mName, ATypeName]), AReason));
    end;
  end;
  if AChosen = nil then
  begin
    Exit(Fail(ATypeName + cTexts[TRecordCommandsText.HasNoFields].Text, AReason));
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
      Exit(Fail(cTexts[TRecordCommandsText.EqualsOnlyAppliesInA].Text, AReason));
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
    if MatchText(mCurrent, cPersistentBases) then
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
  mSource: TCommandSource;
  mClassSymbol, mField: TIndexSymbol;
  T: string;
  mCopies, mBody: TArray<string>;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TRecordCommandsText.CloneOnlyAppliesInA].Text, AReason));
    end;
    T := mClassSymbol.Name;
    mCopies := nil;
    if IsPersistent(mSource, mClassSymbol) then
    begin
      mCopies := ['    Result.Assign(Self);'];
    end
    else
    begin
      for mField in FieldsOf(mSource, mClassSymbol) do
      begin
        if not IsObjectField(mSource, AContext.Index, mField) then
        begin
          mCopies := mCopies + [Format('    Result.%s := %s;', [mField.Name, mField.Name])];
        end
        else if HasMember(mSource, mField.TypeName, 'Clone') then
        begin
          mCopies := mCopies + [Format('    Result.%s.Free;', [mField.Name]),
            Format('    Result.%s := %s.Clone;', [mField.Name, mField.Name])];
        end
        else
        begin
          mCopies := mCopies + [cTexts[TRecordCommandsText.TODOCopyResultFrom].Fmt([mField.Name, mField.Name])];
        end;
      end;
    end;
    // Erst zusammensetzen: "[...] + Copies" geht nicht als offenes Array-Argument.
    mBody := TArray<string>.Create(Format('function %s.Clone: %s;', [T, T]), 'begin',
      Format('  Result := %s.Create;', [T]), '  try') + mCopies +
      TArray<string>.Create('  except', '    Result.Free;', '    raise;', '  end;', 'end;');
    AEdits := AddToClass(mSource, mClassSymbol, ['public', Format('function Clone: %s;', [T])], Join(mSource, mBody)) +
      [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

function OperatorTokens: TArray<string>;
var
  mEntry: TOperatorEntry;
begin
  Result := nil;
  for mEntry in cOperators do
  begin
    if mEntry.Symbol <> '' then
    begin
      Result := Result + [mEntry.Symbol];
    end
    else
    begin
      Result := Result + [mEntry.Name];
    end;
  end;
end;

function EqualsFields(const AContext: TSlashContext): TArray<string>;
var
  mSource: TCommandSource;
  mTypeSymbol, mField: TIndexSymbol;
  mReason: string;
begin
  Result := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mTypeSymbol) and not RecordAt(mSource, 'equals', mTypeSymbol, mReason) then
    begin
      Exit;
    end;
    for mField in FieldsOf(mSource, mTypeSymbol) do
    begin
      Result := Result + [mField.Name];
    end;
  finally
    mSource.Free;
  end;
end;

procedure RegisterRecordCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('record', cTexts[TRecordCommandsText.CreateARecordWithConstructor].Text,
    cTexts[TRecordCommandsText.RecordTPointXYInteger].Text,
    ExecuteRecord));
  ARegister(Command('operator', cTexts[TRecordCommandsText.CreateAClassOperatorFor].Text, '/operator = + Implicit',
    ExecuteOperator));
  ARegister(Command('equals', cTexts[TRecordCommandsText.CreateEqualsAndGetHashCodeOr].Text, '/equals', ExecuteEquals));
  ARegister(Command('clone', cTexts[TRecordCommandsText.CreateCloneWithFreeingOn].Text, '/clone', ExecuteClone));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.RecordCommands', cTexts);

end.
