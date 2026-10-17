unit Atlas.Common.Editing.AccessorCreation.Tests;

// Tests für Feld und Zugriffsmethoden nach read/write einer Eigenschaft (#467).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAccessorCreationTests = class
  public
    [Test]
    procedure DeclaresFieldGetterAndSetter;
    [Test]
    procedure DeclaresIndexedAccessors;
    [Test]
    procedure KnowsComparableTypes;
    [Test]
    procedure FollowsAliasesInIndex;
    [Test]
    procedure CreatesFieldBehindFields;
    [Test]
    procedure CreatesFieldInStrictPrivate;
    [Test]
    procedure CreatesGetterWithFieldResult;
    [Test]
    procedure CreatesGetterWithDefaultWithoutField;
    [Test]
    procedure CreatesSetterWithFieldAndCheck;
    [Test]
    procedure CreatesSetterWithoutCheckForArrays;
    [Test]
    procedure CreatesSetterWithoutCheckForOwnRecord;
    [Test]
    procedure CreatesProtectedMethods;
    [Test]
    procedure OpensSectionBeforeProperty;
    [Test]
    procedure CreatesIndexedSetterWithoutField;
    [Test]
    procedure RefusesExistingMemberAndIndexedField;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.AccessorCreation;

const
  Kopf =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10;
  Fuss =
    'implementation'#10 +
    #10 +
    'end.'#10;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
    Result := Result + ALines[Index] + #10;
end;

/// <summary>Wendet AEdits an; sie dürfen sich nicht überlappen. Gleiche Stelle in der gegebenen Reihenfolge.</summary>
function ApplyEdits(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  Lines: TArray<string>;
  Order: TArray<Integer>;
  Index, Inner, Swap, Start, Stop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  var
    Line: Integer;
  begin
    Result := 0;
    for Line := 0 to APos.Line - 1 do
      Inc(Result, Length(Lines[Line]) + 1);
    Inc(Result, APos.Character);
  end;

begin
  Lines := AText.Split([#10]);
  SetLength(Order, Length(AEdits));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  // Von hinten anwenden.
  for Index := 0 to High(Order) do
    for Inner := Index + 1 to High(Order) do
      if OffsetOf(AEdits[Order[Index]].Range.StartPos) <= OffsetOf(AEdits[Order[Inner]].Range.StartPos) then
      begin
        Swap := Order[Index];
        Order[Index] := Order[Inner];
        Order[Inner] := Swap;
      end;
  Result := AText;
  for Index in Order do
  begin
    Start := OffsetOf(AEdits[Index].Range.StartPos);
    Stop := OffsetOf(AEdits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start) + AEdits[Index].NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Plan(AKind: TAccessorKind; const AName, AType, AIndex, ASection: string): TAccessorPlan; overload;
begin
  Result := Default(TAccessorPlan);
  Result.Kind := AKind;
  Result.PropertyName := AName;
  Result.PropertyType := AType;
  Result.IndexParameters := AIndex;
  Result.MethodSection := ASection;
end;

function Plan(AKind: TAccessorKind; const AName, AType: string): TAccessorPlan; overload;
begin
  Result := Plan(AKind, AName, AType, '', 'private');
end;

/// <summary>Text nach den Änderungen für APlan, mit der Eigenschaft in der Zeile, die AMarker enthält; '-' wenn
/// Edits False liefert. AWithField meldet, ob der Setter das Feld mit anlegt.</summary>
function Created(const AText, AMarker: string; const APlan: TAccessorPlan; const AIndex: ISymbolIndex;
  out AWithField: Boolean): string; overload;
var
  Lines: TArray<string>;
  Slash: TSlashContext;
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Edits: TArray<TTextEdit>;
  Line: Integer;
begin
  Result := '-';
  AWithField := False;
  Lines := AText.Split([#10]);
  Slash := Default(TSlashContext);
  Slash.Text := AText;
  Slash.Line := -1;
  for Line := 0 to High(Lines) do
    if Pos(AMarker, Lines[Line]) > 0 then
    begin
      Slash.Line := Line;
      Slash.LineText := Lines[Line];
      Break;
    end;
  Assert.IsTrue(Slash.Line >= 0, AMarker);
  Slash.Index := AIndex;
  Source := TCommandSource.Create(Slash);
  try
    Assert.IsTrue(Source.ClassAt(ClassSymbol), 'Klasse');
    if TAccessorCreation.Edits(Source, AIndex, ClassSymbol, APlan, Edits, AWithField) then
      Result := ApplyEdits(AText, Edits);
  finally
    Source.Free;
  end;
end;

function Created(const AText, AMarker: string; const APlan: TAccessorPlan): string; overload;
var
  WithField: Boolean;
begin
  Result := Created(AText, AMarker, APlan, nil, WithField);
end;

{ TAccessorCreationTests }

procedure TAccessorCreationTests.DeclaresFieldGetterAndSetter;
begin
  Assert.AreEqual('FCaption: string;', TAccessorCreation.Declaration(Plan(TAccessorKind.Field, 'Caption', 'string')));
  Assert.AreEqual('function GetCaption: string;',
    TAccessorCreation.Declaration(Plan(TAccessorKind.Getter, 'Caption', 'string')));
  Assert.AreEqual('procedure SetCaption(const Value: string);',
    TAccessorCreation.Declaration(Plan(TAccessorKind.Setter, 'Caption', 'string')));
  Assert.AreEqual('SetCaption', Plan(TAccessorKind.Setter, 'Caption', 'string').Name);
  Assert.AreEqual('FCaption', Plan(TAccessorKind.Getter, 'Caption', 'string').FieldName);
end;

procedure TAccessorCreationTests.DeclaresIndexedAccessors;
begin
  Assert.AreEqual('function GetItems(Index: Integer): Double;',
    TAccessorCreation.Declaration(Plan(TAccessorKind.Getter, 'Items', 'Double', 'Index: Integer', 'private')));
  Assert.AreEqual('procedure SetItems(Index: Integer; const Value: Double);',
    TAccessorCreation.Declaration(Plan(TAccessorKind.Setter, 'Items', 'Double', 'Index: Integer', 'private')));
end;

procedure TAccessorCreationTests.KnowsComparableTypes;
begin
  Assert.IsTrue(TAccessorCreation.IsComparable('string', nil));
  Assert.IsTrue(TAccessorCreation.IsComparable('Integer', nil));
  Assert.IsTrue(TAccessorCreation.IsComparable('TUnbekannt', nil));
  Assert.IsFalse(TAccessorCreation.IsComparable('TArray<Integer>', nil));
  Assert.IsFalse(TAccessorCreation.IsComparable('array of Byte', nil));
  Assert.IsFalse(TAccessorCreation.IsComparable('TBytes', nil));
  Assert.IsFalse(TAccessorCreation.IsComparable('reference to procedure', nil));
end;

procedure TAccessorCreationTests.FollowsAliasesInIndex;
var
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(Join([
    'unit Typen;',
    'interface',
    'type',
    '  TPunkt = record',
    '    X, Y: Integer;',
    '  end;',
    '  TMeldung = procedure(Sender: TObject) of object;',
    '  TPunkte = array of TPunkt;',
    '  TName = string;',
    '  TKurz = TName;',
    '  TFarbe = (Rot, Gruen);',
    'implementation',
    'end.']), 'Typen.pas', nil));
  Assert.IsFalse(TAccessorCreation.IsComparable('TPunkt', Index));
  Assert.IsFalse(TAccessorCreation.IsComparable('TMeldung', Index));
  Assert.IsFalse(TAccessorCreation.IsComparable('TPunkte', Index));
  Assert.IsTrue(TAccessorCreation.IsComparable('TKurz', Index));
  Assert.IsTrue(TAccessorCreation.IsComparable('TFarbe', Index));
end;

procedure TAccessorCreationTests.CreatesFieldBehindFields;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + Fuss;
begin
  // Abnahme: Das Feld FCaption: string; steht hinter den Feldern im private-Abschnitt.
  Assert.AreEqual(Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    FCaption: string;'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + Fuss,
    Created(Text, 'property Caption', Plan(TAccessorKind.Field, 'Caption', 'string')));
end;

procedure TAccessorCreationTests.CreatesFieldInStrictPrivate;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  strict private'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '  end;'#10 + Fuss;
begin
  Assert.AreEqual(Kopf +
    '  TFoo = class'#10 +
    '  strict private'#10 +
    '    FWert: Integer;'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '  end;'#10 + Fuss,
    Created(Text, 'property Wert', Plan(TAccessorKind.Field, 'Wert', 'Integer')));
end;

procedure TAccessorCreationTests.CreatesGetterWithFieldResult;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FCaption: string;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + Fuss;
var
  Result: string;
begin
  Result := Created(Text, 'property Caption', Plan(TAccessorKind.Getter, 'Caption', 'string'));
  Assert.Contains(Result, '    FCaption: string;'#10'    function GetCaption: string;'#10'  public'#10);
  Assert.Contains(Result, 'function TFoo.GetCaption: string;'#10'begin'#10'  Result := FCaption;'#10'end;');
end;

procedure TAccessorCreationTests.CreatesGetterWithDefaultWithoutField;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Anzahl: Integer read '#10 +
    '  end;'#10 + Fuss;
begin
  Assert.Contains(Created(Text, 'property Anzahl', Plan(TAccessorKind.Getter, 'Anzahl', 'Integer')),
    'function TFoo.GetAnzahl: Integer;'#10'begin'#10'  Result := Default(Integer);'#10'end;');
end;

procedure TAccessorCreationTests.CreatesSetterWithFieldAndCheck;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Caption: string read FCaption write '#10 +
    '  end;'#10 + Fuss;
var
  Result: string;
  WithField: Boolean;
begin
  // Abnahme: „SetCaption anlegen“ legt Deklaration und Rumpf mit Gleichheitsprüfung an, das fehlende Feld mit.
  Result := Created(Text, 'property Caption', Plan(TAccessorKind.Setter, 'Caption', 'string'), nil, WithField);
  Assert.IsTrue(WithField);
  Assert.Contains(Result, '    FName: string;'#10'    FCaption: string;'#10'    procedure Machen;'#10 +
    '    procedure SetCaption(const Value: string);'#10'  public'#10);
  Assert.Contains(Result, 'procedure TFoo.SetCaption(const Value: string);'#10'begin'#10 +
    '  if FCaption <> Value then');
  Assert.Contains(Result, 'FCaption := Value;');
end;

procedure TAccessorCreationTests.CreatesSetterWithoutCheckForArrays;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FBereich: TArray<Integer>;'#10 +
    '  public'#10 +
    '    property Bereich: TArray<Integer> read FBereich write '#10 +
    '  end;'#10 + Fuss;
var
  Result: string;
  WithField: Boolean;
begin
  Result := Created(Text, 'property Bereich', Plan(TAccessorKind.Setter, 'Bereich', 'TArray<Integer>'), nil,
    WithField);
  Assert.IsFalse(WithField);
  Assert.Contains(Result, 'procedure TFoo.SetBereich(const Value: TArray<Integer>);'#10'begin'#10 +
    '  FBereich := Value;'#10'end;');
end;

procedure TAccessorCreationTests.CreatesSetterWithoutCheckForOwnRecord;
const
  Text = Kopf +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FPunkt: TPunkt;'#10 +
    '  public'#10 +
    '    property Punkt: TPunkt read FPunkt write '#10 +
    '  end;'#10 + Fuss;
var
  WithField: Boolean;
begin
  // Der Record der eigenen Unit steht noch nicht im Index: <> ginge nicht, also ohne Prüfung.
  Assert.Contains(Created(Text, 'property Punkt', Plan(TAccessorKind.Setter, 'Punkt', 'TPunkt'), nil, WithField),
    'procedure TFoo.SetPunkt(const Value: TPunkt);'#10'begin'#10'  FPunkt := Value;'#10'end;');
end;

procedure TAccessorCreationTests.CreatesProtectedMethods;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '  protected'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '  end;'#10 + Fuss;
begin
  Assert.Contains(Created(Text, 'property Wert', Plan(TAccessorKind.Getter, 'Wert', 'Integer', '', 'protected')),
    '  protected'#10'    procedure Machen;'#10'    function GetWert: Integer;'#10'  public'#10);
end;

procedure TAccessorCreationTests.OpensSectionBeforeProperty;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  public'#10 +
    '    procedure Machen;'#10 +
    '    property Caption: string read FCaption write '#10 +
    '  end;'#10 + Fuss;
var
  Result: string;
  WithField: Boolean;
begin
  // Kein private davor: eigener Abschnitt vor der Eigenschaft, Kopf nur einmal, danach weiter public.
  Result := Created(Text, 'property Caption', Plan(TAccessorKind.Setter, 'Caption', 'string'), nil, WithField);
  Assert.Contains(Result, '    procedure Machen;'#10'  private'#10'    FCaption: string;'#10 +
    '    procedure SetCaption(const Value: string);'#10'  public'#10'    property Caption');
end;

procedure TAccessorCreationTests.CreatesIndexedSetterWithoutField;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FListe: TArray<Double>;'#10 +
    '  public'#10 +
    '    property Items[Index: Integer]: Double read GetItems write '#10 +
    '  end;'#10 + Fuss;
var
  Result: string;
  WithField: Boolean;
begin
  Result := Created(Text, 'property Items', Plan(TAccessorKind.Setter, 'Items', 'Double', 'Index: Integer',
    'private'), nil, WithField);
  Assert.IsFalse(WithField);
  Assert.Contains(Result, '    FListe: TArray<Double>;'#10 +
    '    procedure SetItems(Index: Integer; const Value: Double);'#10'  public'#10);
  Assert.Contains(Result, 'procedure TFoo.SetItems(Index: Integer; const Value: Double);'#10'begin'#10'end;');
  Assert.DoesNotContain(Result, 'FItems');
end;

procedure TAccessorCreationTests.RefusesExistingMemberAndIndexedField;
const
  Text = Kopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FCaption: string;'#10 +
    '    function GetCaption: string;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + Fuss;
begin
  Assert.AreEqual('-', Created(Text, 'property Caption', Plan(TAccessorKind.Field, 'Caption', 'string')));
  Assert.AreEqual('-', Created(Text, 'property Caption', Plan(TAccessorKind.Getter, 'Caption', 'string')));
  Assert.AreEqual('-', Created(Text, 'property Caption', Plan(TAccessorKind.Field, 'Titel', 'string',
    'Index: Integer', 'private')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAccessorCreationTests);

end.
