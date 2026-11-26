unit Atlas.Common.Formatting.Outcome;

// Ergebnis des Formatierens ohne Editor (#1358): Zeilenbereiche, Abweichungen je Zeile und das Ergebnis je Datei.
// Gemeinsame Typen für den Formatierer (Editing.FormatCheck), die Ausgabe der Kommandozeile
// (Atlas.Common.Formatting.Output) und den Linter des Hosts (Core.Linter.Formatting).

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Zeilen First bis Last (0-basiert, einschließlich).</summary>
  TFormatLineSpan = record
    First: Integer;
    Last: Integer;
    class function Create(AFirst, ALast: Integer): TFormatLineSpan; static;
  end;

  /// <summary>Ganze Datei oder nur die Zeilen der Bereiche (leer = nichts formatieren).</summary>
  TFormatScope = record
    WholeFile: Boolean;
    Spans: TArray<TFormatLineSpan>;
    class function All: TFormatScope; static;
    class function Lines(const ASpans: TArray<TFormatLineSpan>): TFormatScope; static;
  end;

  {$SCOPEDENUMS ON}
  TFormatDeviationKind = (Indent, IndentChars, KeywordCase, SpaceAssignment, SpaceComma, TrailingWhitespace,
    Alignment, LineBreaks, EndOfLine, FinalNewline);
  {$SCOPEDENUMS OFF}

  TFormatDeviation = record
    /// <summary>Zeile im Original, 0-basiert.</summary>
    Line: Integer;
    Kind: TFormatDeviationKind;
    Message: string;
    class function Create(ALine: Integer; AKind: TFormatDeviationKind; const AMessage: string): TFormatDeviation;
      static;
    /// <summary>Kennung für JSON, z. B. "indent".</summary>
    class function KindName(AKind: TFormatDeviationKind): string; static;
  end;

  TFormatOutcome = record
    Original: string;
    /// <summary>Ergebnis; bei Syntaxfehlern gleich Original.</summary>
    Formatted: string;
    Deviations: TArray<TFormatDeviation>;
    HasSyntaxError: Boolean;
    /// <summary>Erster Syntaxfehler, nur mit HasSyntaxError.</summary>
    SyntaxError: TSyntaxDiagnostic;
    /// <summary>Ein zweiter Lauf auf Formatted ändert nichts mehr.</summary>
    Stable: Boolean;
    /// <summary>Formatted weicht von Original ab.</summary>
    function Changed: Boolean;
  end;

implementation

{ TFormatLineSpan }

class function TFormatLineSpan.Create(AFirst, ALast: Integer): TFormatLineSpan;
begin
  Result.First := AFirst;
  Result.Last := ALast;
end;

{ TFormatScope }

class function TFormatScope.All: TFormatScope;
begin
  Result.WholeFile := True;
  Result.Spans := nil;
end;

class function TFormatScope.Lines(const ASpans: TArray<TFormatLineSpan>): TFormatScope;
begin
  Result.WholeFile := False;
  Result.Spans := ASpans;
end;

{ TFormatDeviation }

class function TFormatDeviation.Create(ALine: Integer; AKind: TFormatDeviationKind;
  const AMessage: string): TFormatDeviation;
begin
  Result.Line := ALine;
  Result.Kind := AKind;
  Result.Message := AMessage;
end;

class function TFormatDeviation.KindName(AKind: TFormatDeviationKind): string;
begin
  case AKind of
    TFormatDeviationKind.Indent:
      Result := 'indent';
    TFormatDeviationKind.IndentChars:
      Result := 'indentChars';
    TFormatDeviationKind.KeywordCase:
      Result := 'keywordCase';
    TFormatDeviationKind.SpaceAssignment:
      Result := 'spaceAroundAssignment';
    TFormatDeviationKind.SpaceComma:
      Result := 'spaceAfterComma';
    TFormatDeviationKind.TrailingWhitespace:
      Result := 'trailingWhitespace';
    TFormatDeviationKind.Alignment:
      Result := 'alignment';
    TFormatDeviationKind.LineBreaks:
      Result := 'lineBreaks';
    TFormatDeviationKind.EndOfLine:
      Result := 'endOfLine';
  else
    Result := 'finalNewline';
  end;
end;

{ TFormatOutcome }

function TFormatOutcome.Changed: Boolean;
begin
  Result := Formatted <> Original;
end;

end.
