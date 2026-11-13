unit Atlas.Common.Mutation.Contract;

// Contract des Platform-Features Mutation (#1460): kleine, gezielte Fehler
// (Mutanten) im Quelltext, an denen sich zeigt, ob die DUnitX-Tests eine
// Stelle wirklich absichern. Bleiben alle Tests grün, „überlebt“ der Mutant.
// Atlas.Common.Mutation.Generator erzeugt die Mutanten aus dem Syntaxbaum,
// Atlas.Common.Mutation.Report gibt sie als Liste, JSON oder Patch aus. Bauen
// und Testen ist Sache des Plugins (bzw. einer CI); hier wird nichts
// ausgeführt.
//
// Operatoren der ersten Ausbaustufe (Kennung für Einstellungen und JSON):
//   boundary    <  <-> <=,  >  <-> >=
//   equality    =  <-> <>
//   logical     and <-> or
//   not         not entfernen
//   arithmetic  +  <-> -
//   increment   + 1 bzw. - 1 entfernen
//   boolean     True <-> False
//   number      0 <-> 1
//   statement   Prozeduraufruf oder Zuweisung entfernen
//   exit        Exit(x) durch Exit(Default(Ergebnistyp))

interface

uses
  Atlas.Common.Documents.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Art der Veränderung (siehe Kopf der Unit).</summary>
  TMutationOperator = (Boundary, Equality, Logical, RemoveNot, Arithmetic, RemoveIncrement, BooleanLiteral,
    NumberLiteral, RemoveStatement, ExitDefault);
{$SCOPEDENUMS OFF}
  TMutationOperators = set of TMutationOperator;

  /// <summary>Ein Mutant: Der Text zwischen StartOffset und EndOffset wird durch Replacement ersetzt.</summary>
  TMutant = record
    /// <summary>Laufende Nummer in der Datei ab 1, in der Reihenfolge des Quelltexts.</summary>
    Id: Integer;
    Operator: TMutationOperator;
    /// <summary>Routine mit Rumpf, in der die Stelle steht ("TFoo.Bar"); lokale Routinen mit dem Namen der
    /// äußeren davor ("TFoo.Bar.Lokal").</summary>
    Routine: string;
    /// <summary>Ersetzter Bereich (Zeilen und Spalten ab 0).</summary>
    Range: TTextRange;
    /// <summary>Offsets ab 0 im Text; EndOffset hinter dem letzten Zeichen.</summary>
    StartOffset: Integer;
    EndOffset: Integer;
    /// <summary>Bisheriger Text des Bereichs.</summary>
    Original: string;
    /// <summary>Neuer Text; '' = entfernt.</summary>
    Replacement: string;
  end;

  /// <summary>Auswahl für den Generator.</summary>
  TMutationOptions = record
    Operators: TMutationOperators;
    /// <summary>Nur diese Routine: voller Name ("TFoo.Bar") oder letzter Teil ("Bar"), Groß-/Kleinschreibung
    /// egal; '' = alle Routinen.</summary>
    Routine: string;
    /// <summary>Nur Stellen, die in diesen Zeilen (ab 0) beginnen; -1 = keine Grenze.</summary>
    FirstLine: Integer;
    LastLine: Integer;
    /// <summary>Symbole für die aktiven Zweige der bedingten Kompilierung (leer = Vordefinitionen für Win32 und
    /// Delphi 13); Code in inaktiven Zweigen wird nie mutiert.</summary>
    Defines: TArray<string>;
    /// <summary>Alle Operatoren, alle Routinen, ohne Zeilengrenze und ohne Symbole.</summary>
    class function Default: TMutationOptions; static;
  end;

  // Record statt Klasse: ein Contract enthält nur Werttypen und Interfaces.
  TMutation = record
  public const
    /// <summary>Kennung in Kommentaren, die eine Zeile oder Routine ausnimmt:
    /// "// atlas-ignore: mutation" (auch "// lsp-ignore: mutation").</summary>
    cIgnoreId = 'mutation';
  public
    class function AllOperators: TMutationOperators; static;
    /// <summary>Kennung für Einstellungen und JSON, z. B. "boundary".</summary>
    class function OperatorId(AOperator: TMutationOperator): string; static;
    /// <summary>Operator zur Kennung (Groß-/Kleinschreibung egal); False, wenn es keinen gibt.</summary>
    class function TryParseOperator(const AId: string; out AOperator: TMutationOperator): Boolean; static;
    /// <summary>Operatoren aus einer Liste von Kennungen; unbekannte landen in AUnknown.</summary>
    class function ParseOperators(const AIds: TArray<string>; out AUnknown: TArray<string>): TMutationOperators;
      static;
    /// <summary>AText mit dem Mutanten AMutant; die Offsets müssen zu AText passen.</summary>
    class function Apply(const AText: string; const AMutant: TMutant): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cOperatorIds: array[TMutationOperator] of string = ('boundary', 'equality', 'logical', 'not', 'arithmetic',
    'increment', 'boolean', 'number', 'statement', 'exit');

{ TMutationOptions }

class function TMutationOptions.Default: TMutationOptions;
begin
  Result.Operators := TMutation.AllOperators;
  Result.Routine := '';
  Result.FirstLine := -1;
  Result.LastLine := -1;
  Result.Defines := nil;
end;

{ TMutation }

class function TMutation.AllOperators: TMutationOperators;
begin
  Result := [Low(TMutationOperator)..High(TMutationOperator)];
end;

class function TMutation.OperatorId(AOperator: TMutationOperator): string;
begin
  Result := cOperatorIds[AOperator];
end;

class function TMutation.TryParseOperator(const AId: string; out AOperator: TMutationOperator): Boolean;
var
  mOperator: TMutationOperator;
begin
  for mOperator := Low(TMutationOperator) to High(TMutationOperator) do
  begin
    if SameText(cOperatorIds[mOperator], Trim(AId)) then
    begin
      AOperator := mOperator;
      Exit(True);
    end;
  end;
  AOperator := Low(TMutationOperator);
  Result := False;
end;

class function TMutation.ParseOperators(const AIds: TArray<string>; out AUnknown: TArray<string>):
  TMutationOperators;
var
  mId: string;
  mOperator: TMutationOperator;
begin
  Result := [];
  AUnknown := nil;
  for mId in AIds do
  begin
    if TryParseOperator(mId, mOperator) then
    begin
      Include(Result, mOperator);
    end
    else if Trim(mId) <> '' then
    begin
      AUnknown := AUnknown + [mId];
    end;
  end;
end;

class function TMutation.Apply(const AText: string; const AMutant: TMutant): string;
begin
  Result := Copy(AText, 1, AMutant.StartOffset) + AMutant.Replacement + Copy(AText, AMutant.EndOffset + 1, MaxInt);
end;

end.
