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
    cTypeEntities = [TQueryEntity.Classes, TQueryEntity.Records, TQueryEntity.Interfaces, TQueryEntity.Forms];
    cRoutineEntities = [TQueryEntity.Methods, TQueryEntity.Routines];
    cMemberEntities = [TQueryEntity.Methods, TQueryEntity.Fields, TQueryEntity.Properties];
    cAllEntities = [Low(TQueryEntity)..High(TQueryEntity)];
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
  System.StrUtils,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TQueryCatalogText = (MethodsAndConstructorsOfTypes, FormsFramesAndDataModules, NameOfTheElement,
    UnitOfTheDeclaration, FileRelativeToTheProject, LineOfTheDeclarationFrom, TypeThatDeclaresTheMember,
    ClassesOfTheUnit, MethodsAndConstructorsUnitIncluding, FieldsOfTheType, PropertiesOfTheType,
    LinesUnitLengthDeclarationOf, CyclomaticComplexityMetricLikeGet, CognitiveComplexity, CallersAccordingToTheCall,
    Method1WithOverrideOtherwise, VirtualDynamicAbstractOrOverride, EntriesInAllUsesClauses, UnitsInScopeThatUse,
    ComponentsInTheFormFile, InheritsAlsoOverSeveralLevels, ImplementsTheInterfaceAlsoVia, TheUnitOrTheUnit,
    CallsTheRoutineOrMethod, CarriesTheAttributeWithOr, SetWhereConditionOrderBy, Predicates, ClassesAlsoObject,
    RoutinesAtUnitLevel, FieldsOfTypes, PropertiesOfTypes, DeclaredTypeOrResultType, CalledRoutines, DirectAncestor,
    ExamplesClassesWhereInheritsTForm, NestingDepth, NumberOfParameters, LocalVariables, ExitsExitRaise, Number,
    Boolean);

const
  cTexts: array[TQueryCatalogText] of TAtlasText = (
    (De: 'Methoden und Konstruktoren von Typen'; En: 'Methods and constructors of types'),
    (De: 'Formulare, Frames und Datenmodule mit eigener Formulardatei';
     En: 'Forms, frames and data modules with their own form file'),
    (De: 'Name des Elements'; En: 'Name of the element'),
    (De: 'Unit der Deklaration'; En: 'Unit of the declaration'),
    (De: 'Datei relativ zum Projekt mit "/"'; En: 'File relative to the project with "/"'),
    (De: 'Zeile der Deklaration (ab 1)'; En: 'Line of the declaration (from 1)'),
    (De: 'Typ, der das Mitglied deklariert'; En: 'Type that declares the member'),
    (De: 'Klassen der Unit'; En: 'Classes of the unit'),
    (De: 'Methoden und Konstruktoren (Unit: samt Routinen)';
     En: 'Methods and constructors (unit: including routines)'),
    (De: 'Felder des Typs'; En: 'Fields of the type'),
    (De: 'Properties des Typs'; En: 'Properties of the type'),
    (De: 'Zeilen: Unit-Länge, Deklaration des Typs bzw. Codezeilen der Routine (Metrik)';
     En: 'Lines: unit length, declaration of the type or code lines of the routine (metric)'),
    (De: 'Zyklomatische Komplexität (Metrik wie get_metrics)'; En: 'Cyclomatic complexity (metric like get_metrics)'),
    (De: 'Kognitive Komplexität'; En: 'Cognitive complexity'),
    (De: 'Aufrufer laut Aufrufhierarchie, erschlossene mitgezählt';
     En: 'Callers according to the call hierarchy, inferred ones included'),
    (De: 'Methode: 1 mit override, sonst 0; Typ: Methoden mit override';
     En: 'Method: 1 with override, otherwise 0; type: methods with override'),
    (De: 'virtual, dynamic, abstract oder override'; En: 'virtual, dynamic, abstract or override'),
    (De: 'Einträge in allen uses-Klauseln (wie metric-uses-count)';
     En: 'Entries in all uses clauses (like metric-uses-count)'),
    (De: 'Units im Umfang, die die Unit direkt verwenden (Uses-Graph)';
     En: 'Units in scope that use the unit directly (uses graph)'),
    (De: 'Komponenten in der Formulardatei ohne das Formular selbst';
     En: 'Components in the form file without the form itself'),
    (De: 'erbt (auch über mehrere Stufen) vom Typ; bei Mitgliedern der deklarierende Typ';
     En: 'inherits (also over several levels) from the type; for members the declaring type'),
    (De: 'setzt das Interface um, auch über Vorfahren und abgeleitete Interfaces';
     En: 'implements the interface, also via ancestors and derived interfaces'),
    (De: 'die Unit (bzw. die Unit der Deklaration) nennt die Unit im uses';
     En: 'the unit (or the unit of the declaration) names the unit in uses'),
    (De: 'ruft die Routine bzw. Methode auf (Name oder Typ.Name)';
     En: 'calls the routine or method (name or Type.Name)'),
    (De: 'trägt das Attribut, mit oder ohne Endung Attribute';
     En: 'carries the attribute, with or without the ending Attribute'),
    (De: '`<Menge> [where <Bedingung>] [order by <Feld> [asc|desc]] [limit n]`' + sLineBreak + sLineBreak +
      'Vergleiche `=`, `<>`, `<`, `>`, `<=`, `>=`, `like` mit `*` und `?`; `and`, `or`, `not`, Klammern. Texte in ' +
      'einfachen oder doppelten Anführungszeichen, Namen auch ohne.' + sLineBreak + sLineBreak + 'Mengen:';
     En: '`<set> [where <condition>] [order by <field> [asc|desc]] [limit n]`' + sLineBreak + sLineBreak +
      'Comparisons `=`, `<>`, `<`, `>`, `<=`, `>=`, `like` with `*` and `?`; `and`, `or`, `not`, parentheses. Texts ' +
      'in single or double quotation marks, names also without.' + sLineBreak + sLineBreak + 'Sets:'),
    (De: 'Prädikate:'; En: 'Predicates:'),
    (De: 'Klassen (auch object)'; En: 'Classes (also object)'),
    (De: 'Routinen auf Unit-Ebene'; En: 'Routines at unit level'),
    (De: 'Felder von Typen'; En: 'Fields of types'),
    (De: 'Properties von Typen'; En: 'Properties of types'),
    (De: 'Deklarierter Typ bzw. Ergebnistyp'; En: 'Declared type or result type'),
    (De: 'Aufgerufene Routinen'; En: 'Called routines'),
    (De: 'Direkter Vorfahr'; En: 'Direct ancestor'),
    (De: 'Beispiele: `classes where inherits TForm and methods > 40 order by methods desc`, `methods where ' +
      'complexity > 15 and callers = 0`, `units where usedBy = 0 and name like ''*.Tests''`.';
     En: 'Examples: `classes where inherits TForm and methods > 40 order by methods desc`, `methods where complexity ' +
      '> 15 and callers = 0`, `units where usedBy = 0 and name like ''*.Tests''`.'),
    (De: 'Verschachtelungstiefe'; En: 'Nesting depth'),
    (De: 'Parameteranzahl'; En: 'Number of parameters'),
    (De: 'Lokale Variablen'; En: 'Local variables'),
    (De: 'Ausstiege (Exit, raise)'; En: 'Exits (Exit, raise)'),
    (De: 'Zahl'; En: 'number'),
    (De: 'Wahrheitswert'; En: 'Boolean'));

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
      Result := cTexts[TQueryCatalogText.ClassesAlsoObject].Text;
    TQueryEntity.Records:
      Result := 'Records';
    TQueryEntity.Interfaces:
      Result := 'Interfaces';
    TQueryEntity.Methods:
      Result := cTexts[TQueryCatalogText.MethodsAndConstructorsOfTypes].Text;
    TQueryEntity.Routines:
      Result := cTexts[TQueryCatalogText.RoutinesAtUnitLevel].Text;
    TQueryEntity.Fields:
      Result := cTexts[TQueryCatalogText.FieldsOfTypes].Text;
    TQueryEntity.Properties:
      Result := cTexts[TQueryCatalogText.PropertiesOfTypes].Text;
  else
    Result := cTexts[TQueryCatalogText.FormsFramesAndDataModules].Text;
  end;
end;

class function TQueryCatalog.TryEntity(const AName: string; out AEntity: TQueryEntity): Boolean;
var
  mEntity: TQueryEntity;
begin
  for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
  begin
    if SameText(EntityName(mEntity), AName) then
    begin
      AEntity := mEntity;
      Exit(True);
    end;
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
  begin
    Result := Result + [EntityName(mEntity)];
  end;
end;

class function TQueryCatalog.Fields: TArray<TQueryFieldInfo>;
begin
  Result := nil;
  Result := Result + [Field('name', TQueryFieldType.Text, cAllEntities,
    cTexts[TQueryCatalogText.NameOfTheElement].Text)];
  Result := Result + [Field('unit', TQueryFieldType.Text, cAllEntities,
    cTexts[TQueryCatalogText.UnitOfTheDeclaration].Text)];
  Result := Result + [Field('path', TQueryFieldType.Text, cAllEntities,
    cTexts[TQueryCatalogText.FileRelativeToTheProject].Text)];
  Result := Result + [Field('line', TQueryFieldType.Number, cAllEntities,
    cTexts[TQueryCatalogText.LineOfTheDeclarationFrom].Text)];
  Result := Result + [Field('class', TQueryFieldType.Text, cMemberEntities,
    cTexts[TQueryCatalogText.TypeThatDeclaresTheMember].Text)];
  Result := Result + [Field('visibility', TQueryFieldType.Text, cAllEntities - [TQueryEntity.Units],
    'Sichtbarkeit: public, published, protected, strict protected, private, strict private')];
  Result := Result + [Field('type', TQueryFieldType.Text, [TQueryEntity.Fields, TQueryEntity.Properties,
    TQueryEntity.Methods, TQueryEntity.Routines], cTexts[TQueryCatalogText.DeclaredTypeOrResultType].Text)];
  Result := Result + [Field('classes', TQueryFieldType.Number, [TQueryEntity.Units],
    cTexts[TQueryCatalogText.ClassesOfTheUnit].Text)];
  Result := Result + [Field('methods', TQueryFieldType.Number, [TQueryEntity.Units] + cTypeEntities,
    cTexts[TQueryCatalogText.MethodsAndConstructorsUnitIncluding].Text)];
  Result := Result + [Field('fields', TQueryFieldType.Number, [TQueryEntity.Classes, TQueryEntity.Records,
    TQueryEntity.Forms], cTexts[TQueryCatalogText.FieldsOfTheType].Text)];
  Result := Result + [Field('properties', TQueryFieldType.Number, cTypeEntities,
    cTexts[TQueryCatalogText.PropertiesOfTheType].Text)];
  Result := Result + [Field('lines', TQueryFieldType.Number, cAllEntities - [TQueryEntity.Fields,
    TQueryEntity.Properties], cTexts[TQueryCatalogText.LinesUnitLengthDeclarationOf].Text)];
  Result := Result + [Field('complexity', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.CyclomaticComplexityMetricLikeGet].Text)];
  Result := Result + [Field('cognitive', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.CognitiveComplexity].Text)];
  Result := Result + [Field('nesting', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.NestingDepth].Text)];
  Result := Result + [Field('params', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.NumberOfParameters].Text)];
  Result := Result + [Field('locals', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.LocalVariables].Text)];
  Result := Result + [Field('exits', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.ExitsExitRaise].Text)];
  Result := Result + [Field('callers', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.CallersAccordingToTheCall].Text)];
  Result := Result + [Field('callees', TQueryFieldType.Number, cRoutineEntities,
    cTexts[TQueryCatalogText.CalledRoutines].Text)];
  Result := Result + [Field('overrides', TQueryFieldType.Number, [TQueryEntity.Methods, TQueryEntity.Classes,
    TQueryEntity.Records, TQueryEntity.Forms], cTexts[TQueryCatalogText.Method1WithOverrideOtherwise].Text)];
  Result := Result + [Field('virtual', TQueryFieldType.Flag, [TQueryEntity.Methods],
    cTexts[TQueryCatalogText.VirtualDynamicAbstractOrOverride].Text)];
  Result := Result + [Field('uses', TQueryFieldType.Number, [TQueryEntity.Units],
    cTexts[TQueryCatalogText.EntriesInAllUsesClauses].Text)];
  Result := Result + [Field('usedBy', TQueryFieldType.Number, [TQueryEntity.Units],
    cTexts[TQueryCatalogText.UnitsInScopeThatUse].Text)];
  Result := Result + [Field('ancestor', TQueryFieldType.Text, [TQueryEntity.Classes, TQueryEntity.Interfaces,
    TQueryEntity.Forms], cTexts[TQueryCatalogText.DirectAncestor].Text)];
  Result := Result + [Field('components', TQueryFieldType.Number, [TQueryEntity.Forms],
    cTexts[TQueryCatalogText.ComponentsInTheFormFile].Text)];
end;

class function TQueryCatalog.FieldsOf(AEntity: TQueryEntity): TArray<TQueryFieldInfo>;
var
  mField: TQueryFieldInfo;
begin
  Result := nil;
  for mField in Fields do
  begin
    if AEntity in mField.Entities then
    begin
      Result := Result + [mField];
    end;
  end;
end;

class function TQueryCatalog.TryField(const AName: string; out AField: TQueryFieldInfo): Boolean;
var
  mField: TQueryFieldInfo;
begin
  for mField in Fields do
  begin
    if SameText(mField.Name, AName) then
    begin
      AField := mField;
      Exit(True);
    end;
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
  begin
    Result := Result + [mField.Name];
  end;
end;

class function TQueryCatalog.FieldNames: TArray<string>;
var
  mField: TQueryFieldInfo;
begin
  Result := nil;
  for mField in Fields do
  begin
    Result := Result + [mField.Name];
  end;
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
      Result := cTypeEntities + cMemberEntities;
    TQueryPredicateKind.Calls:
      Result := cRoutineEntities;
    TQueryPredicateKind.HasAttribute:
      Result := cAllEntities - [TQueryEntity.Units];
  else
    Result := cAllEntities;
  end;
end;

class function TQueryCatalog.PredicateDescription(AKind: TQueryPredicateKind): string;
begin
  case AKind of
    TQueryPredicateKind.Inherits:
      Result := cTexts[TQueryCatalogText.InheritsAlsoOverSeveralLevels].Text;
    TQueryPredicateKind.Implements:
      Result := cTexts[TQueryCatalogText.ImplementsTheInterfaceAlsoVia].Text;
    TQueryPredicateKind.Uses_:
      Result := cTexts[TQueryCatalogText.TheUnitOrTheUnit].Text;
    TQueryPredicateKind.Calls:
      Result := cTexts[TQueryCatalogText.CallsTheRoutineOrMethod].Text;
  else
    Result := cTexts[TQueryCatalogText.CarriesTheAttributeWithOr].Text;
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
      Result := cTexts[TQueryCatalogText.Number].Text;
    TQueryFieldType.Text:
      Result := 'Text';
  else
    Result := cTexts[TQueryCatalogText.Boolean].Text;
  end;
end;

class function TQueryCatalog.Help: string;
var
  mEntity: TQueryEntity;
  mKind: TQueryPredicateKind;
  mField: TQueryFieldInfo;
  mNames: string;
begin
  Result := cTexts[TQueryCatalogText.SetWhereConditionOrderBy].Text + sLineBreak;
  for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
  begin
    Result := Result + Format('- `%s`: %s; Felder %s', [EntityName(mEntity), EntityCaption(mEntity),
      string.Join(', ', FieldNames(mEntity))]) + sLineBreak;
  end;
  Result := Result + sLineBreak + cTexts[TQueryCatalogText.Predicates].Text + sLineBreak;
  for mKind := Low(TQueryPredicateKind) to High(TQueryPredicateKind) do
  begin
    Result := Result + Format('- `%s <Name>`: %s', [PredicateName(mKind), PredicateDescription(mKind)]) + sLineBreak;
  end;
  Result := Result + sLineBreak + 'Felder:' + sLineBreak;
  for mField in Fields do
  begin
    mNames := '';
    for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
    begin
      if mEntity in mField.Entities then
      begin
        mNames := mNames + IfThen(mNames = '', '', ', ') + EntityName(mEntity);
      end;
    end;
    Result := Result + Format('- `%s` (%s; %s): %s', [mField.Name, FieldTypeName(mField.FieldType), mNames,
      mField.Description]) + sLineBreak;
  end;
  Result := Result + sLineBreak + cTexts[TQueryCatalogText.ExamplesClassesWhereInheritsTForm].Text;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Query.Catalog', cTexts);

end.
