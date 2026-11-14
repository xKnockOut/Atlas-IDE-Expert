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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.AccessorCreation;

const
  cKopf =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10;
  cFuss =
    'implementation'#10 +
    #10 +
    'end.'#10;

function Join(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

/// <summary>Wendet AEdits an; sie dürfen sich nicht überlappen. Gleiche Stelle in der gegebenen Reihenfolge.</summary>
function ApplyEdits(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mLines: TArray<string>;
  mOrder: TArray<Integer>;
  mIndex, mInner, mSwap, mStart, mStop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  var
    mLine: Integer;
  begin
    Result := 0;
    for mLine := 0 to APos.Line - 1 do
    begin
      Inc(Result, Length(mLines[mLine]) + 1);
    end;
    Inc(Result, APos.Character);
  end;

begin
  mLines := AText.Split([#10]);
  SetLength(mOrder, Length(AEdits));
  for mIndex := 0 to High(mOrder) do
  begin
    mOrder[mIndex] := mIndex;
  end;
  // Von hinten anwenden.
  for mIndex := 0 to High(mOrder) do
  begin
    for mInner := mIndex + 1 to High(mOrder) do
    begin
      if OffsetOf(AEdits[mOrder[mIndex]].Range.StartPos) <= OffsetOf(AEdits[mOrder[mInner]].Range.StartPos) then
      begin
        mSwap := mOrder[mIndex];
        mOrder[mIndex] := mOrder[mInner];
        mOrder[mInner] := mSwap;
      end;
    end;
  end;
  Result := AText;
  for mIndex in mOrder do
  begin
    mStart := OffsetOf(AEdits[mIndex].Range.StartPos);
    mStop := OffsetOf(AEdits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStart) + AEdits[mIndex].NewText + Copy(Result, mStop + 1, MaxInt);
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
  mLines: TArray<string>;
  mSlash: TSlashContext;
  mSource: TCommandSource;
  mClassSymbol: TIndexSymbol;
  mEdits: TArray<TTextEdit>;
  mLine: Integer;
begin
  Result := '-';
  AWithField := False;
  mLines := AText.Split([#10]);
  mSlash := Default(TSlashContext);
  mSlash.Text := AText;
  mSlash.Line := -1;
  for mLine := 0 to High(mLines) do
  begin
    if Pos(AMarker, mLines[mLine]) > 0 then
    begin
      mSlash.Line := mLine;
      mSlash.LineText := mLines[mLine];
      Break;
    end;
  end;
  Assert.IsTrue(mSlash.Line >= 0, AMarker);
  mSlash.Index := AIndex;
  mSource := TCommandSource.Create(mSlash);
  try
    Assert.IsTrue(mSource.ClassAt(mClassSymbol), 'Klasse');
    if TAccessorCreation.Edits(mSource, AIndex, mClassSymbol, APlan, mEdits, AWithField) then
    begin
      Result := ApplyEdits(AText, mEdits);
    end;
  finally
    mSource.Free;
  end;
end;

function Created(const AText, AMarker: string; const APlan: TAccessorPlan): string; overload;
var
  mWithField: Boolean;
begin
  Result := Created(AText, AMarker, APlan, nil, mWithField);
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
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(Join([
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
  Assert.IsFalse(TAccessorCreation.IsComparable('TPunkt', mIndex));
  Assert.IsFalse(TAccessorCreation.IsComparable('TMeldung', mIndex));
  Assert.IsFalse(TAccessorCreation.IsComparable('TPunkte', mIndex));
  Assert.IsTrue(TAccessorCreation.IsComparable('TKurz', mIndex));
  Assert.IsTrue(TAccessorCreation.IsComparable('TFarbe', mIndex));
end;

procedure TAccessorCreationTests.CreatesFieldBehindFields;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + cFuss;
begin
  // Abnahme: Das Feld FCaption: string; steht hinter den Feldern im private-Abschnitt.
  Assert.AreEqual(cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    FCaption: string;'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + cFuss,
    Created(cText, 'property Caption', Plan(TAccessorKind.Field, 'Caption', 'string')));
end;

procedure TAccessorCreationTests.CreatesFieldInStrictPrivate;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  strict private'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '  end;'#10 + cFuss;
begin
  Assert.AreEqual(cKopf +
    '  TFoo = class'#10 +
    '  strict private'#10 +
    '    FWert: Integer;'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '  end;'#10 + cFuss,
    Created(cText, 'property Wert', Plan(TAccessorKind.Field, 'Wert', 'Integer')));
end;

procedure TAccessorCreationTests.CreatesGetterWithFieldResult;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FCaption: string;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + cFuss;
var
  Result: string;
begin
  Result := Created(cText, 'property Caption', Plan(TAccessorKind.Getter, 'Caption', 'string'));
  Assert.Contains(Result, '    FCaption: string;'#10'    function GetCaption: string;'#10'  public'#10);
  Assert.Contains(Result, 'function TFoo.GetCaption: string;'#10'begin'#10'  Result := FCaption;'#10'end;');
end;

procedure TAccessorCreationTests.CreatesGetterWithDefaultWithoutField;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    property Anzahl: Integer read '#10 +
    '  end;'#10 + cFuss;
begin
  Assert.Contains(Created(cText, 'property Anzahl', Plan(TAccessorKind.Getter, 'Anzahl', 'Integer')),
    'function TFoo.GetAnzahl: Integer;'#10'begin'#10'  Result := Default(Integer);'#10'end;');
end;

procedure TAccessorCreationTests.CreatesSetterWithFieldAndCheck;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Caption: string read FCaption write '#10 +
    '  end;'#10 + cFuss;
var
  Result: string;
  mWithField: Boolean;
begin
  // Abnahme: „SetCaption anlegen“ legt Deklaration und Rumpf mit Gleichheitsprüfung an, das fehlende Feld mit.
  Result := Created(cText, 'property Caption', Plan(TAccessorKind.Setter, 'Caption', 'string'), nil, mWithField);
  Assert.IsTrue(mWithField);
  Assert.Contains(Result, '    FName: string;'#10'    FCaption: string;'#10'    procedure Machen;'#10 +
    '    procedure SetCaption(const Value: string);'#10'  public'#10);
  Assert.Contains(Result, 'procedure TFoo.SetCaption(const Value: string);'#10'begin'#10 +
    '  if FCaption <> Value then');
  Assert.Contains(Result, 'FCaption := Value;');
end;

procedure TAccessorCreationTests.CreatesSetterWithoutCheckForArrays;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FBereich: TArray<Integer>;'#10 +
    '  public'#10 +
    '    property Bereich: TArray<Integer> read FBereich write '#10 +
    '  end;'#10 + cFuss;
var
  Result: string;
  mWithField: Boolean;
begin
  Result := Created(cText, 'property Bereich', Plan(TAccessorKind.Setter, 'Bereich', 'TArray<Integer>'), nil,
    mWithField);
  Assert.IsFalse(mWithField);
  Assert.Contains(Result, 'procedure TFoo.SetBereich(const Value: TArray<Integer>);'#10'begin'#10 +
    '  FBereich := Value;'#10'end;');
end;

procedure TAccessorCreationTests.CreatesSetterWithoutCheckForOwnRecord;
const
  cText = cKopf +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FPunkt: TPunkt;'#10 +
    '  public'#10 +
    '    property Punkt: TPunkt read FPunkt write '#10 +
    '  end;'#10 + cFuss;
var
  mWithField: Boolean;
begin
  // Der Record der eigenen Unit steht noch nicht im Index: <> ginge nicht, also ohne Prüfung.
  Assert.Contains(Created(cText, 'property Punkt', Plan(TAccessorKind.Setter, 'Punkt', 'TPunkt'), nil, mWithField),
    'procedure TFoo.SetPunkt(const Value: TPunkt);'#10'begin'#10'  FPunkt := Value;'#10'end;');
end;

procedure TAccessorCreationTests.CreatesProtectedMethods;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '  protected'#10 +
    '    procedure Machen;'#10 +
    '  public'#10 +
    '    property Wert: Integer read '#10 +
    '  end;'#10 + cFuss;
begin
  Assert.Contains(Created(cText, 'property Wert', Plan(TAccessorKind.Getter, 'Wert', 'Integer', '', 'protected')),
    '  protected'#10'    procedure Machen;'#10'    function GetWert: Integer;'#10'  public'#10);
end;

procedure TAccessorCreationTests.OpensSectionBeforeProperty;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  public'#10 +
    '    procedure Machen;'#10 +
    '    property Caption: string read FCaption write '#10 +
    '  end;'#10 + cFuss;
var
  Result: string;
  mWithField: Boolean;
begin
  // Kein private davor: eigener Abschnitt vor der Eigenschaft, Kopf nur einmal, danach weiter public.
  Result := Created(cText, 'property Caption', Plan(TAccessorKind.Setter, 'Caption', 'string'), nil, mWithField);
  Assert.Contains(Result, '    procedure Machen;'#10'  private'#10'    FCaption: string;'#10 +
    '    procedure SetCaption(const Value: string);'#10'  public'#10'    property Caption');
end;

procedure TAccessorCreationTests.CreatesIndexedSetterWithoutField;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FListe: TArray<Double>;'#10 +
    '  public'#10 +
    '    property Items[Index: Integer]: Double read GetItems write '#10 +
    '  end;'#10 + cFuss;
var
  Result: string;
  mWithField: Boolean;
begin
  Result := Created(cText, 'property Items', Plan(TAccessorKind.Setter, 'Items', 'Double', 'Index: Integer',
    'private'), nil, mWithField);
  Assert.IsFalse(mWithField);
  Assert.Contains(Result, '    FListe: TArray<Double>;'#10 +
    '    procedure SetItems(Index: Integer; const Value: Double);'#10'  public'#10);
  Assert.Contains(Result, 'procedure TFoo.SetItems(Index: Integer; const Value: Double);'#10'begin'#10'end;');
  Assert.DoesNotContain(Result, 'FItems');
end;

procedure TAccessorCreationTests.RefusesExistingMemberAndIndexedField;
const
  cText = cKopf +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FCaption: string;'#10 +
    '    function GetCaption: string;'#10 +
    '  public'#10 +
    '    property Caption: string read '#10 +
    '  end;'#10 + cFuss;
begin
  Assert.AreEqual('-', Created(cText, 'property Caption', Plan(TAccessorKind.Field, 'Caption', 'string')));
  Assert.AreEqual('-', Created(cText, 'property Caption', Plan(TAccessorKind.Getter, 'Caption', 'string')));
  Assert.AreEqual('-', Created(cText, 'property Caption', Plan(TAccessorKind.Field, 'Titel', 'string',
    'Index: Integer', 'private')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAccessorCreationTests);

end.
