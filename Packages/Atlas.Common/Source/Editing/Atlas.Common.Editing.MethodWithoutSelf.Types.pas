unit Atlas.Common.Editing.MethodWithoutSelf.Types;

// Gemeinsame Typen der Umwandlung „Methode ohne Self“ (#686): Ziel, Quellen, Anfrage und Ergebnis. Die Analyse
// (Atlas.Common.Editing.MethodWithoutSelf.Analysis) und die Umwandlung (Atlas.Common.Editing.MethodWithoutSelf)
// nutzen sie.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.SourceFiles;

type
{$SCOPEDENUMS ON}
  /// <summary>Umwandlung: class-Methode, class-Methode samt Aufrufen über die Klasse, freie Routine, Helper.</summary>
  TMethodConversion = (ClassMethod, ClassMethodCalls, Routine, Helper);
  /// <summary>Verwendung der Methode an einer Stelle.</summary>
  TMethodUse = (Call, Value, Pointer, Inherited_, Accessor, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Methode ohne Self.</summary>
  TMethodTarget = record
    ClassName: string;
    Name: string;
    IsRecord: Boolean;
    /// <summary>Name im Kopf der Implementierung (Start der Referenzsuche).</summary>
    NamePosition: TTextPosition;
    /// <summary>Ende des Kopfs der Implementierung (Marke).</summary>
    HeaderEnd: TTextPosition;
    /// <summary>Warum keine freie Routine bzw. kein Helper geht; '' = geht.</summary>
    RoutineReason: string;
    HelperReason: string;
    /// <summary>Typ des ersten Parameters, wenn der Helper geht.</summary>
    HelperType: string;
    function Conversions: TArray<TMethodConversion>;
    function Title(AConversion: TMethodConversion): string;
  end;

  /// <summary>Eine Datei mit Verwendungen der Methode.</summary>
  TMethodSource = TEditingSourceFile;

  /// <summary>Gewünschte Umwandlung der Methode, deren Kopf APosition enthält; AWithStatic:
  /// refactoring.methodKindStatic.</summary>
  TMethodRequest = record
    Position: TTextPosition;
    Conversion: TMethodConversion;
    WithStatic: Boolean;
    Lookup: TMethodLookup;
    Style: TFormatStyle;
    class function Create(const APosition: TTextPosition; AConversion: TMethodConversion; AWithStatic: Boolean;
      const ALookup: TMethodLookup; const AStyle: TFormatStyle): TMethodRequest; static;
  end;

  TMethodFileEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  TMethodResult = record
    Files: TArray<TMethodFileEdits>;
    Warnings: TArray<string>;
    /// <summary>Geänderte Aufrufe.</summary>
    Calls: Integer;
    /// <summary>Was geschieht, dazu je geänderter Aufruf "Datei, Zeile n: alt → neu".</summary>
    Preview: string;
  end;

implementation

uses
  Atlas.Common.Editing.MethodWithoutSelf.Texts;

{ TMethodTarget }

function TMethodTarget.Conversions: TArray<TMethodConversion>;
begin
  Result := [TMethodConversion.ClassMethod, TMethodConversion.ClassMethodCalls];
  if RoutineReason = '' then
  begin
    Result := Result + [TMethodConversion.Routine];
  end;
  if HelperReason = '' then
  begin
    Result := Result + [TMethodConversion.Helper];
  end;
end;

function TMethodTarget.Title(AConversion: TMethodConversion): string;
begin
  case AConversion of
    TMethodConversion.ClassMethodCalls:
      Result := cTexts[TEditingMethodWithoutSelfText.ConvertToClassMethodCalls].Fmt( [ClassName]);
    TMethodConversion.Routine:
      Result := cTexts[TEditingMethodWithoutSelfText.ConvertToStandaloneRoutine].Text;
    TMethodConversion.Helper:
      Result := cTexts[TEditingMethodWithoutSelfText.MoveToRecordHelperFor].Fmt([HelperType]);
  else
    Result := cTexts[TEditingMethodWithoutSelfText.ConvertToClassMethod].Text;
  end;
end;

{ TMethodRequest }

class function TMethodRequest.Create(const APosition: TTextPosition; AConversion: TMethodConversion;
  AWithStatic: Boolean; const ALookup: TMethodLookup; const AStyle: TFormatStyle): TMethodRequest;
begin
  Result.Position := APosition;
  Result.Conversion := AConversion;
  Result.WithStatic := AWithStatic;
  Result.Lookup := ALookup;
  Result.Style := AStyle;
end;

end.
