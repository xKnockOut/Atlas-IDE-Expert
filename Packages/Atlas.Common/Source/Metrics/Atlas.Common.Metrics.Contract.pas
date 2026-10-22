unit Atlas.Common.Metrics.Contract;

// Contract des Platform-Features Metrics (#66): Kennzahlen je Routine.
//   - Methodenlänge: Codezeilen vom Kopf bis zum end, ohne Leerzeilen,
//     Kommentare, Direktiven und lokale Routinen (die zählen für sich).
//   - Verschachtelungstiefe: tiefste Schachtelung von if, case, for, while,
//     repeat und try; else if bleibt auf der Ebene des if.
//   - Zyklomatische Komplexität: Start bei 1, je +1 für if, while, repeat,
//     for, jeden case-Zweig (ohne else), jedes and/or in einer Bedingung,
//     jedes except on; ein except ohne on zählt einmal.
//   - Kognitive Komplexität (nach SonarSource): +1 und Schachtelung für if,
//     case, Schleifen und except; +1 für else und else if; +1 je Folge
//     gleicher logischer Operatoren in einer Bedingung; +1 für goto.
//   - Parameteranzahl: Namen in der Parameterliste.
//   - Operanden einer Bedingung (#980): Glieder der and/or/xor-Kette in
//     der Bedingung eines if, while, until oder Bedingungsausdrucks, durch
//     Klammern und not hindurch; je Routine die größte Bedingung.
//   - Lokale Variablen (#980): Namen im var-Abschnitt der Routine, Inline-
//     Variablen und for var; lokale Routinen und anonyme Methoden zählen
//     für sich.
//   - Ausstiege (#980): Exit und raise im Rumpf (auch raise; im except),
//     ohne lokale Routinen und anonyme Methoden.
// Kennzahlen des Aufbaus (#939):
//   - Klassengröße: Member einer Klasse (auch object): Feldnamen, Methoden,
//     Properties mit eigenem Typ und class var; Hochstufungen wie
//     "property Align;" und geschachtelte Typen zählen nicht.
//   - Unit-Länge: Zeilen bis zum letzten Token (end.).
//   - uses-Anzahl: Units in allen uses-Klauseln (interface und
//     implementation).
//   - Vererbungstiefe (#980): Vorfahren einer Klasse, die nicht aus RTL,
//     VCL oder anderen Bibliotheken stammen; braucht den Index und steht
//     darum nicht in TMetricsCalculator.Structure, sondern in
//     TMetricRules.InheritanceDepths (Atlas.Common.Rules.Builtin.Metrics).
//   Unit-Länge und uses-Anzahl nur für Units: Das uses eines Programms oder
//   einer Bibliothek zählt die Units des Projekts auf.
// Grenzwerte (Vorgaben aus der Spezifikation, Abschnitt 4.13) stehen in
// atlas.json bei den Regeln metric-* unter "max" (Atlas.Common.Rules.Builtin.Metrics).

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract;

type
  TMetricKind = (MethodLength, NestingDepth, Cyclomatic, Cognitive, ParameterCount, BooleanOperands, LocalCount,
    ExitPoints);

  TMetricValues = array[TMetricKind] of Integer;

  /// <summary>Kennzahlen des Aufbaus einer Unit (#939).</summary>
  TStructureKind = (ClassSize, UnitLength, UsesCount, InheritanceDepth);

  TStructureValues = array[TStructureKind] of Integer;

  /// <summary>Grenzwerte je Kennzahl; ein Wert darüber ist eine Überschreitung.</summary>
  TMetricLimits = record
    Values: TMetricValues;
    /// <summary>Grenzwerte des Aufbaus (#939).</summary>
    Structure: TStructureValues;
    /// <summary>60 Zeilen, Tiefe 4, zyklomatisch 15, kognitiv 15, 6 Parameter, 5 Operanden je Bedingung,
    /// 12 lokale Variablen, 4 Ausstiege; 40 Member je Klasse, 2000 Zeilen je Unit, 30 Units im uses,
    /// Vererbungstiefe 5.</summary>
    class function Default: TMetricLimits; static;
    /// <summary>True, wenn AValue über dem Grenzwert von AKind liegt.</summary>
    function Exceeds(AKind: TMetricKind; AValue: Integer): Boolean;
    /// <summary>Kennzahlen aus AValues über ihrem Grenzwert, in der Reihenfolge von TMetricKind.</summary>
    function Exceeded(const AValues: TMetricValues): TArray<TMetricKind>;
    /// <summary>True, wenn AValue über dem Grenzwert des Aufbaus AKind liegt.</summary>
    function ExceedsStructure(AKind: TStructureKind; AValue: Integer): Boolean;
  end;

  /// <summary>Eine Kennzahl des Aufbaus: eine Klasse oder die Unit selbst (#939).</summary>
  TStructureMetrics = record
    Kind: TStructureKind;
    /// <summary>Klassenname bzw. Unit-Name.</summary>
    Name: string;
    /// <summary>Name in der Deklaration bzw. im Kopf der Unit; bei UsesCount das Schlüsselwort uses.</summary>
    NameRange: TTextRange;
    Value: Integer;
    /// <summary>Value ist nur eine Untergrenze: Die Vererbungskette bricht an einem unbekannten Vorfahren ab
    /// (#980).</summary>
    AtLeast: Boolean;
  end;

  /// <summary>Eine Bedingung mit ihren Operanden (#980).</summary>
  TConditionMetrics = record
    /// <summary>Ganze Bedingung.</summary>
    Range: TTextRange;
    /// <summary>Offsets im Text (0-basiert, Ende exklusiv), z. B. für „Bedingung in Funktion auslagern“.</summary>
    StartOffset: Integer;
    EndOffset: Integer;
    Operands: Integer;
  end;

  /// <summary>Kennzahlen einer Routine mit Rumpf.</summary>
  TRoutineMetrics = record
    /// <summary>Name wie im Kopf (TFoo.Bar); lokale Routinen mit der äußeren davor (TFoo.Bar.Inner).</summary>
    Name: string;
    /// <summary>Ganze Routine vom Kopf bis zum abschließenden end.</summary>
    Range: TTextRange;
    /// <summary>Name im Kopf; dort stehen Code Lens und Treffer der Regeln.</summary>
    NameRange: TTextRange;
    Values: TMetricValues;
  end;

  /// <summary>Kennzahlen einer Datei.</summary>
  TFileMetrics = record
    /// <summary>Pfad für Bericht und JSON (relativ zur Wurzel mit „/“, sonst wie übergeben).</summary>
    Path: string;
    Routines: TArray<TRoutineMetrics>;
    constructor Create(const APath: string; const ARoutines: TArray<TRoutineMetrics>);
  end;

  // Record statt Klasse: ein Contract enthält nur Werttypen und Interfaces (Konzept 7.1, Code-Review A-12).
  TMetrics = record
  public
    /// <summary>Kennung in JSON und Bericht: length, nesting, cyclomatic, cognitive, parameters, operands, locals,
    /// exits.</summary>
    class function Key(AKind: TMetricKind): string; static;
    /// <summary>Kurzname auf Deutsch, z. B. „zyklomatisch“.</summary>
    class function Caption(AKind: TMetricKind): string; static;
    /// <summary>Kennzahl zur Kennung aus Key; False bei unbekannter Kennung.</summary>
    class function TryKindOf(const AKey: string; out AKind: TMetricKind): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TMetricLimits }

class function TMetricLimits.Default: TMetricLimits;
begin
  Result.Values[TMetricKind.MethodLength] := 60;
  Result.Values[TMetricKind.NestingDepth] := 4;
  Result.Values[TMetricKind.Cyclomatic] := 15;
  Result.Values[TMetricKind.Cognitive] := 15;
  Result.Values[TMetricKind.ParameterCount] := 6;
  Result.Values[TMetricKind.BooleanOperands] := 5;
  Result.Values[TMetricKind.LocalCount] := 12;
  Result.Values[TMetricKind.ExitPoints] := 4;
  Result.Structure[TStructureKind.ClassSize] := 40;
  Result.Structure[TStructureKind.UnitLength] := 2000;
  Result.Structure[TStructureKind.UsesCount] := 30;
  Result.Structure[TStructureKind.InheritanceDepth] := 5;
end;

function TMetricLimits.ExceedsStructure(AKind: TStructureKind; AValue: Integer): Boolean;
begin
  Result := AValue > Structure[AKind];
end;

function TMetricLimits.Exceeds(AKind: TMetricKind; AValue: Integer): Boolean;
begin
  Result := AValue > Values[AKind];
end;

function TMetricLimits.Exceeded(const AValues: TMetricValues): TArray<TMetricKind>;
var
  Kind: TMetricKind;
begin
  Result := nil;
  for Kind := Low(TMetricKind) to High(TMetricKind) do
    if Exceeds(Kind, AValues[Kind]) then
      Result := Result + [Kind];
end;

{ TFileMetrics }

constructor TFileMetrics.Create(const APath: string; const ARoutines: TArray<TRoutineMetrics>);
begin
  Path := APath;
  Routines := ARoutines;
end;

{ TMetrics }

class function TMetrics.Key(AKind: TMetricKind): string;
begin
  case AKind of
    TMetricKind.MethodLength:
      Result := 'length';
    TMetricKind.NestingDepth:
      Result := 'nesting';
    TMetricKind.Cyclomatic:
      Result := 'cyclomatic';
    TMetricKind.Cognitive:
      Result := 'cognitive';
    TMetricKind.ParameterCount:
      Result := 'parameters';
    TMetricKind.BooleanOperands:
      Result := 'operands';
    TMetricKind.LocalCount:
      Result := 'locals';
  else
    Result := 'exits';
  end;
end;

class function TMetrics.Caption(AKind: TMetricKind): string;
begin
  case AKind of
    TMetricKind.MethodLength:
      Result := 'Länge';
    TMetricKind.NestingDepth:
      Result := 'Tiefe';
    TMetricKind.Cyclomatic:
      Result := 'zyklomatisch';
    TMetricKind.Cognitive:
      Result := 'kognitiv';
    TMetricKind.ParameterCount:
      Result := 'Parameter';
    TMetricKind.BooleanOperands:
      Result := 'Operanden';
    TMetricKind.LocalCount:
      Result := 'lokale Variablen';
  else
    Result := 'Ausstiege';
  end;
end;

class function TMetrics.TryKindOf(const AKey: string; out AKind: TMetricKind): Boolean;
var
  Kind: TMetricKind;
begin
  for Kind := Low(TMetricKind) to High(TMetricKind) do
    if SameText(Key(Kind), Trim(AKey)) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  AKind := TMetricKind.MethodLength;
  Result := False;
end;

end.
