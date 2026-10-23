unit Atlas.Common.Pascal.FormatRoutines;

// Routinen mit Formatstring und Argumentliste [...] wie Format (#56, #451): eine gemeinsame Liste für die Regel
// format-args und die Platzhalter im Parameter-Hint. Vorher führte die Regel ihre Liste allein.
// Eingebaut: Format, FmtStr, FormatBuf, StrFmt, StrLFmt, WideFormat, WideFmtStr, Exception.CreateFmt,
// Exception.CreateFmtHelp und TStringBuilder.AppendFormat. Eigene Einträge kommen aus der Option formatMethods
// der Regel (atlas.json) und aus formatFunctions der Projektdatei .atlas (#486, über den Projektkontext der IDE).
// Ein Eintrag mit Punkt ist eine Methode: Ohne Namensauflösung genügt dann der Methodenname hinter einem
// beliebigen Qualifizierer (EImport.CreateFmt, mBuilder.AppendFormat).

interface

type
  /// <summary>Formatroutine: Name (voll qualifiziert oder kurz), Position des Formatstrings, wenn die
  /// Argumentliste keine [...] ist (-1: unbekannt, dann gilt das Argument vor der Liste), und ob sie eine Methode
  /// ist.</summary>
  TFormatRoutine = record
    Name: string;
    FormatIndex: Integer;
    IsMethod: Boolean;
    constructor Create(const AName: string; AFormatIndex: Integer; AIsMethod: Boolean);
  end;

  TFormatRoutines = record
  public
    /// <summary>Die eingebauten Routinen der RTL.</summary>
    class function Defaults: TArray<TFormatRoutine>; static;
    /// <summary>Eintrag aus der Einstellung ("TLogger.LogFmt", "Protokoll"); AFormatIndex -1 = vor der Liste.
    /// </summary>
    class function Custom(const AName: string; AFormatIndex: Integer): TFormatRoutine; static;
    /// <summary>Passt AName ("Unit.Typ.Methode", "Methode") zum Eintrag AEntry? Der kürzere Name muss das Ende
    /// des längeren ab einer Punktgrenze sein, ohne Groß-/Kleinschreibung.</summary>
    class function SameTail(const AEntry, AName: string): Boolean; static;
    /// <summary>Eintrag zum aufgelösten, voll qualifizierten Namen AQualified; False ohne.</summary>
    class function FindQualified(const ARoutines: TArray<TFormatRoutine>; const AQualified: string;
      out ARoutine: TFormatRoutine): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TFormatRoutine }

constructor TFormatRoutine.Create(const AName: string; AFormatIndex: Integer; AIsMethod: Boolean);
begin
  Name := AName;
  FormatIndex := AFormatIndex;
  IsMethod := AIsMethod;
end;

{ TFormatRoutines }

class function TFormatRoutines.Defaults: TArray<TFormatRoutine>;
begin
  Result := TArray<TFormatRoutine>.Create(TFormatRoutine.Create('System.SysUtils.Format', 0, False),
    TFormatRoutine.Create('System.SysUtils.FmtStr', 1, False),
    TFormatRoutine.Create('System.SysUtils.FormatBuf', 2, False),
    TFormatRoutine.Create('System.SysUtils.StrFmt', 1, False),
    TFormatRoutine.Create('System.SysUtils.StrLFmt', 2, False),
    TFormatRoutine.Create('System.SysUtils.WideFormat', 0, False),
    TFormatRoutine.Create('System.SysUtils.WideFmtStr', 1, False),
    TFormatRoutine.Create('System.SysUtils.Exception.CreateFmt', 0, True),
    TFormatRoutine.Create('System.SysUtils.Exception.CreateFmtHelp', 0, True),
    TFormatRoutine.Create('System.SysUtils.TStringBuilder.AppendFormat', 0, True));
end;

class function TFormatRoutines.Custom(const AName: string; AFormatIndex: Integer): TFormatRoutine;
begin
  Result := TFormatRoutine.Create(Trim(AName), AFormatIndex, Pos('.', AName) > 0);
end;

class function TFormatRoutines.SameTail(const AEntry, AName: string): Boolean;
begin
  Result := SameText(AEntry, AName) or EndsText('.' + AName, AEntry) or EndsText('.' + AEntry, AName);
end;

class function TFormatRoutines.FindQualified(const ARoutines: TArray<TFormatRoutine>; const AQualified: string;
  out ARoutine: TFormatRoutine): Boolean;
var
  mRoutine: TFormatRoutine;
begin
  ARoutine := Default(TFormatRoutine);
  for mRoutine in ARoutines do
    if SameTail(mRoutine.Name, AQualified) then
    begin
      ARoutine := mRoutine;
      Exit(True);
    end;
  Result := False;
end;

end.
