unit Atlas.Common.Query.Catalog;

// Mengen, Felder und Prädikate der Abfragesprache (#1351) mit Art und
// Beschreibung: Grundlage für Parser, Auswertung, Fehlermeldungen mit
// Vorschlag, die Hilfe im MCP-Werkzeug und die Vervollständigung im Fenster
// „Atlas-Abfrage“.
//
// Mengen: units, classes, records, interfaces, methods, routines, fields,
// properties, forms. forms sind Klassen mit eigener Formulardatei (.dfm/.fmx),
// deren Wurzelobjekt die Klasse ist (Formulare, Frames, Datenmodule).

interface

uses
  System.SysUtils;

{$SCOPEDENUMS ON}

type
  TQueryEntity = (Units, Classes, Records, Interfaces, Methods, Routines, Fields, Properties, Forms);
  TQueryEntities = set of TQueryEntity;

  /// <summary>Art eines Felds: Zahl, Text oder Wahrheitswert.</summary>
  TQueryFieldType = (Number, Text, Flag);

  TQueryPredicateKind = (Inherits, Implements, Uses_, Calls, HasAttribute);

  TQueryFieldInfo = record
    Name: string;
    FieldType: TQueryFieldType;
    Entities: TQueryEntities;
    Description: string;
  end;

  TQueryCatalog = class
  public const
    TypeEntities = [TQueryEntity.Classes, TQueryEntity.Records, TQueryEntity.Interfaces, TQueryEntity.Forms];
    RoutineEntities = [TQueryEntity.Methods, TQueryEntity.Routines];
    MemberEntities = [TQueryEntity.Methods, TQueryEntity.Fields, TQueryEntity.Properties];
    AllEntities = [Low(TQueryEntity)..High(TQueryEntity)];
  public
    /// <summary>Name der Menge in Kleinschreibung (classes).</summary>
    class function EntityName(AEntity: TQueryEntity): string; static;
    class function EntityCaption(AEntity: TQueryEntity): string; static;
    class function TryEntity(const AName: string; out AEntity: TQueryEntity): Boolean; static;
    class function EntityNames: TArray<string>; static;
    /// <summary>Alle Felder in fester Reihenfolge.</summary>
    class function Fields: TArray<TQueryFieldInfo>; static;
    /// <summary>Felder der Menge AEntity.</summary>
    class function FieldsOf(AEntity: TQueryEntity): TArray<TQueryFieldInfo>; static;
    /// <summary>Feld AName (ohne Groß-/Kleinschreibung) irgendeiner Menge.</summary>
    class function TryField(const AName: string; out AField: TQueryFieldInfo): Boolean; static;
    class function FieldNames(AEntity: TQueryEntity): TArray<string>; overload; static;
    /// <summary>Namen aller Felder aller Mengen ohne Doppelte.</summary>
    class function FieldNames: TArray<string>; overload; static;
    /// <summary>Schlüsselwort des Prädikats ("has attribute").</summary>
    class function PredicateName(AKind: TQueryPredicateKind): string; static;
    /// <summary>Mengen, auf denen das Prädikat gilt.</summary>
    class function PredicateEntities(AKind: TQueryPredicateKind): TQueryEntities; static;
    class function PredicateDescription(AKind: TQueryPredicateKind): string; static;
    /// <summary>Schlüsselwörter der Sprache in Kleinschreibung.</summary>
    class function Keywords: TArray<string>; static;
    class function FieldTypeName(AType: TQueryFieldType): string; static;
    /// <summary>Kurzhilfe der Sprache als Markdown (MCP, Fenster).</summary>
    class function Help: string; static;
  end;

implementation

uses
  System.StrUtils;

function Field(const AName: string; AType: TQueryFieldType; AEntities: TQueryEntities;
  const ADescription: string): TQueryFieldInfo;
begin
  Result.Name := AName;
  Result.FieldType := AType;
  Result.Entities := AEntities;
  Result.Description := ADescription;
end;

{ TQueryCatalog }

class function TQueryCatalog.EntityName(AEntity: TQueryEntity): string;
begin
  case AEntity of
    TQueryEntity.Units:
      Result := 'units';
    TQueryEntity.Classes:
      Result := 'classes';
    TQueryEntity.Records:
      Result := 'records';
    TQueryEntity.Interfaces:
      Result := 'interfaces';
    TQueryEntity.Methods:
      Result := 'methods';
    TQueryEntity.Routines:
      Result := 'routines';
    TQueryEntity.Fields:
      Result := 'fields';
    TQueryEntity.Properties:
      Result := 'properties';
  else
    Result := 'forms';
  end;
end;

class function TQueryCatalog.EntityCaption(AEntity: TQueryEntity): string;
begin
  case AEntity of
    TQueryEntity.Units:
      Result := 'Units';
    TQueryEntity.Classes:
      Result := 'Klassen (auch object)';
    TQueryEntity.Records:
      Result := 'Records';
    TQueryEntity.Interfaces:
      Result := 'Interfaces';
    TQueryEntity.Methods:
      Result := 'Methoden und Konstruktoren von Typen';
    TQueryEntity.Routines:
      Result := 'Routinen auf Unit-Ebene';
    TQueryEntity.Fields:
      Result := 'Felder von Typen';
    TQueryEntity.Properties:
      Result := 'Properties von Typen';
  else
    Result := 'Formulare, Frames und Datenmodule mit eigener Formulardatei';
  end;
end;

class function TQueryCatalog.TryEntity(const AName: string; out AEntity: TQueryEntity): Boolean;
var
  mEntity: TQueryEntity;
begin
  for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
    if SameText(EntityName(mEntity), AName) then
    begin
      AEntity := mEntity;
      Exit(True);
    end;
  AEntity := TQueryEntity.Units;
  Result := False;
end;

class function TQueryCatalog.EntityNames: TArray<string>;
var
  mEntity: TQueryEntity;
begin
  Result := nil;
  for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
    Result := Result + [EntityName(mEntity)];
end;

class function TQueryCatalog.Fields: TArray<TQueryFieldInfo>;
begin
  Result := nil;
  Result := Result + [Field('name', TQueryFieldType.Text, AllEntities, 'Name des Elements')];
  Result := Result + [Field('unit', TQueryFieldType.Text, AllEntities, 'Unit der Deklaration')];
  Result := Result + [Field('path', TQueryFieldType.Text, AllEntities, 'Datei relativ zum Projekt mit "/"')];
  Result := Result + [Field('line', TQueryFieldType.Number, AllEntities, 'Zeile der Deklaration (ab 1)')];
  Result := Result + [Field('class', TQueryFieldType.Text, MemberEntities, 'Typ, der das Mitglied deklariert')];
  Result := Result + [Field('visibility', TQueryFieldType.Text, AllEntities - [TQueryEntity.Units],
    'Sichtbarkeit: public, published, protected, strict protected, private, strict private')];
  Result := Result + [Field('type', TQueryFieldType.Text, [TQueryEntity.Fields, TQueryEntity.Properties,
    TQueryEntity.Methods, TQueryEntity.Routines], 'Deklarierter Typ bzw. Ergebnistyp')];
  Result := Result + [Field('classes', TQueryFieldType.Number, [TQueryEntity.Units], 'Klassen der Unit')];
  Result := Result + [Field('methods', TQueryFieldType.Number, [TQueryEntity.Units] + TypeEntities,
    'Methoden und Konstruktoren (Unit: samt Routinen)')];
  Result := Result + [Field('fields', TQueryFieldType.Number, [TQueryEntity.Classes, TQueryEntity.Records,
    TQueryEntity.Forms], 'Felder des Typs')];
  Result := Result + [Field('properties', TQueryFieldType.Number, TypeEntities, 'Properties des Typs')];
  Result := Result + [Field('lines', TQueryFieldType.Number, AllEntities - [TQueryEntity.Fields,
    TQueryEntity.Properties], 'Zeilen: Unit-Länge, Deklaration des Typs bzw. Codezeilen der Routine (Metrik)')];
  Result := Result + [Field('complexity', TQueryFieldType.Number, RoutineEntities,
    'Zyklomatische Komplexität (Metrik wie get_metrics)')];
  Result := Result + [Field('cognitive', TQueryFieldType.Number, RoutineEntities, 'Kognitive Komplexität')];
  Result := Result + [Field('nesting', TQueryFieldType.Number, RoutineEntities, 'Verschachtelungstiefe')];
  Result := Result + [Field('params', TQueryFieldType.Number, RoutineEntities, 'Parameteranzahl')];
  Result := Result + [Field('locals', TQueryFieldType.Number, RoutineEntities, 'Lokale Variablen')];
  Result := Result + [Field('exits', TQueryFieldType.Number, RoutineEntities, 'Ausstiege (Exit, raise)')];
  Result := Result + [Field('callers', TQueryFieldType.Number, RoutineEntities,
    'Aufrufer laut Aufrufhierarchie, erschlossene mitgezählt')];
  Result := Result + [Field('callees', TQueryFieldType.Number, RoutineEntities, 'Aufgerufene Routinen')];
  Result := Result + [Field('overrides', TQueryFieldType.Number, [TQueryEntity.Methods, TQueryEntity.Classes,
    TQueryEntity.Records, TQueryEntity.Forms], 'Methode: 1 mit override, sonst 0; Typ: Methoden mit override')];
  Result := Result + [Field('virtual', TQueryFieldType.Flag, [TQueryEntity.Methods],
    'virtual, dynamic, abstract oder override')];
  Result := Result + [Field('uses', TQueryFieldType.Number, [TQueryEntity.Units],
    'Einträge in allen uses-Klauseln (wie metric-uses-count)')];
  Result := Result + [Field('usedBy', TQueryFieldType.Number, [TQueryEntity.Units],
    'Units im Umfang, die die Unit direkt verwenden (Uses-Graph)')];
  Result := Result + [Field('ancestor', TQueryFieldType.Text, [TQueryEntity.Classes, TQueryEntity.Interfaces,
    TQueryEntity.Forms], 'Direkter Vorfahr')];
  Result := Result + [Field('components', TQueryFieldType.Number, [TQueryEntity.Forms],
    'Komponenten in der Formulardatei ohne das Formular selbst')];
end;

class function TQueryCatalog.FieldsOf(AEntity: TQueryEntity): TArray<TQueryFieldInfo>;
var
  mField: TQueryFieldInfo;
begin
  Result := nil;
  for mField in Fields do
    if AEntity in mField.Entities then
      Result := Result + [mField];
end;

class function TQueryCatalog.TryField(const AName: string; out AField: TQueryFieldInfo): Boolean;
var
  mField: TQueryFieldInfo;
begin
  for mField in Fields do
    if SameText(mField.Name, AName) then
    begin
      AField := mField;
      Exit(True);
    end;
  AField := Default(TQueryFieldInfo);
  Result := False;
end;

class function TQueryCatalog.FieldNames(AEntity: TQueryEntity): TArray<string>;
var
  mField: TQueryFieldInfo;
begin
  Result := nil;
  for mField in FieldsOf(AEntity) do
    Result := Result + [mField.Name];
end;

class function TQueryCatalog.FieldNames: TArray<string>;
var
  mField: TQueryFieldInfo;
begin
  Result := nil;
  for mField in Fields do
    Result := Result + [mField.Name];
end;

class function TQueryCatalog.PredicateName(AKind: TQueryPredicateKind): string;
begin
  case AKind of
    TQueryPredicateKind.Inherits:
      Result := 'inherits';
    TQueryPredicateKind.Implements:
      Result := 'implements';
    TQueryPredicateKind.Uses_:
      Result := 'uses';
    TQueryPredicateKind.Calls:
      Result := 'calls';
  else
    Result := 'has attribute';
  end;
end;

class function TQueryCatalog.PredicateEntities(AKind: TQueryPredicateKind): TQueryEntities;
begin
  case AKind of
    TQueryPredicateKind.Inherits, TQueryPredicateKind.Implements:
      // Bei Mitgliedern gilt der Typ, der sie deklariert.
      Result := TypeEntities + MemberEntities;
    TQueryPredicateKind.Calls:
      Result := RoutineEntities;
    TQueryPredicateKind.HasAttribute:
      Result := AllEntities - [TQueryEntity.Units];
  else
    Result := AllEntities;
  end;
end;

class function TQueryCatalog.PredicateDescription(AKind: TQueryPredicateKind): string;
begin
  case AKind of
    TQueryPredicateKind.Inherits:
      Result := 'erbt (auch über mehrere Stufen) vom Typ; bei Mitgliedern der deklarierende Typ';
    TQueryPredicateKind.Implements:
      Result := 'setzt das Interface um, auch über Vorfahren und abgeleitete Interfaces';
    TQueryPredicateKind.Uses_:
      Result := 'die Unit (bzw. die Unit der Deklaration) nennt die Unit im uses';
    TQueryPredicateKind.Calls:
      Result := 'ruft die Routine bzw. Methode auf (Name oder Typ.Name)';
  else
    Result := 'trägt das Attribut, mit oder ohne Endung Attribute';
  end;
end;

class function TQueryCatalog.Keywords: TArray<string>;
begin
  Result := TArray<string>.Create('where', 'and', 'or', 'not', 'like', 'order', 'by', 'asc', 'desc', 'limit',
    'inherits', 'implements', 'uses', 'calls', 'has', 'attribute', 'true', 'false');
end;

class function TQueryCatalog.FieldTypeName(AType: TQueryFieldType): string;
begin
  case AType of
    TQueryFieldType.Number:
      Result := 'Zahl';
    TQueryFieldType.Text:
      Result := 'Text';
  else
    Result := 'Wahrheitswert';
  end;
end;

class function TQueryCatalog.Help: string;
var
  mEntity: TQueryEntity;
  mKind: TQueryPredicateKind;
  mField: TQueryFieldInfo;
  mNames: string;
begin
  Result := '`<Menge> [where <Bedingung>] [order by <Feld> [asc|desc]] [limit n]`' + sLineBreak + sLineBreak +
    'Vergleiche `=`, `<>`, `<`, `>`, `<=`, `>=`, `like` mit `*` und `?`; `and`, `or`, `not`, Klammern. Texte in ' +
    'einfachen oder doppelten Anführungszeichen, Namen auch ohne.' + sLineBreak + sLineBreak + 'Mengen:' + sLineBreak;
  for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
    Result := Result + Format('- `%s`: %s; Felder %s', [EntityName(mEntity), EntityCaption(mEntity),
      string.Join(', ', FieldNames(mEntity))]) + sLineBreak;
  Result := Result + sLineBreak + 'Prädikate:' + sLineBreak;
  for mKind := Low(TQueryPredicateKind) to High(TQueryPredicateKind) do
    Result := Result + Format('- `%s <Name>`: %s', [PredicateName(mKind), PredicateDescription(mKind)]) + sLineBreak;
  Result := Result + sLineBreak + 'Felder:' + sLineBreak;
  for mField in Fields do
  begin
    mNames := '';
    for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
      if mEntity in mField.Entities then
        mNames := mNames + IfThen(mNames = '', '', ', ') + EntityName(mEntity);
    Result := Result + Format('- `%s` (%s; %s): %s', [mField.Name, FieldTypeName(mField.FieldType), mNames,
      mField.Description]) + sLineBreak;
  end;
  Result := Result + sLineBreak + 'Beispiele: `classes where inherits TForm and methods > 40 order by methods desc`, ' +
    '`methods where complexity > 15 and callers = 0`, `units where usedBy = 0 and name like ''*.Tests''`.';
end;

end.
