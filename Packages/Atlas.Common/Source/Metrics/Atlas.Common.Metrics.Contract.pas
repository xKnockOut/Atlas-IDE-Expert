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
// Grenzwerte (Vorgaben aus der Spezifikation, Abschnitt 4.13) stehen in
// atlas.json bei den Regeln metric-* unter "max" (Atlas.Common.Rules.Builtin.Metrics).

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract;

type
  TMetricKind = (MethodLength, NestingDepth, Cyclomatic, Cognitive, ParameterCount);

  TMetricValues = array[TMetricKind] of Integer;

  /// <summary>Grenzwerte je Kennzahl; ein Wert darüber ist eine Überschreitung.</summary>
  TMetricLimits = record
    Values: TMetricValues;
    /// <summary>60 Zeilen, Tiefe 4, zyklomatisch 15, kognitiv 15, 6 Parameter.</summary>
    class function Default: TMetricLimits; static;
    /// <summary>True, wenn AValue über dem Grenzwert von AKind liegt.</summary>
    function Exceeds(AKind: TMetricKind; AValue: Integer): Boolean;
    /// <summary>Kennzahlen aus AValues über ihrem Grenzwert, in der Reihenfolge von TMetricKind.</summary>
    function Exceeded(const AValues: TMetricValues): TArray<TMetricKind>;
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

  TMetrics = class
  public
    /// <summary>Kennung in JSON und Bericht: length, nesting, cyclomatic, cognitive, parameters.</summary>
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
  else
    Result := 'parameters';
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
  else
    Result := 'Parameter';
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
