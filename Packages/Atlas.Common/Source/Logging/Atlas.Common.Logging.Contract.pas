unit Atlas.Common.Logging.Contract;

// Contract des Platform-Features Logging: Stufen, Logeintrag, Logger (API)
// und Senke (SPI). Alle Diagnoseausgaben laufen über ILogger, nie über stdout.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  /// <summary>Stufe eines Logeintrags, aufsteigend nach Wichtigkeit.</summary>
  TLogLevel = (Debug, Info, Warning, Error);

  /// <summary>Ein Logeintrag. Unveränderlich nach dem Erzeugen.</summary>
  TLogEntry = record
  private
    FTimestamp: TDateTime;
    FLevel: TLogLevel;
    FText: string;
  public
    constructor Create(ATimestamp: TDateTime; ALevel: TLogLevel; const AText: string);
    /// <summary>Einzeilige Darstellung, z. B. "2026-10-07 19:50:00.123 [INFO] Text".</summary>
    function ToText: string;
    property Timestamp: TDateTime read FTimestamp;
    property Level: TLogLevel read FLevel;
    property Text: string read FText;
  end;

  /// <summary>Ziel für Logeinträge (SPI), z. B. Debug-Ausgabe, Datei, stderr.</summary>
  ILogSink = interface
    ['{0E7B6C1D-9A43-4E0F-8D25-6F1B2C3A4D51}']
    /// <summary>Schreibt einen Eintrag. Darf selbst nicht loggen.</summary>
    procedure Write(const AEntry: TLogEntry);
  end;

  /// <summary>Zentraler Zugang zum Logging (API). Threadsicher.</summary>
  ILogger = interface
    ['{7C2D4E91-3B5A-4F68-A1C0-2E9D8B7F6A13}']
    procedure Log(ALevel: TLogLevel; const AText: string);
    procedure Debug(const AText: string);
    procedure Info(const AText: string);
    procedure Warning(const AText: string);
    procedure Error(const AText: string);
  end;

implementation

const
  LevelNames: array[TLogLevel] of string = ('DEBUG', 'INFO', 'WARNING', 'ERROR');

{ TLogEntry }

constructor TLogEntry.Create(ATimestamp: TDateTime; ALevel: TLogLevel; const AText: string);
begin
  FTimestamp := ATimestamp;
  FLevel := ALevel;
  FText := AText;
end;

function TLogEntry.ToText: string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss"."zzz', FTimestamp) +
    ' [' + LevelNames[FLevel] + '] ' + FText;
end;

end.
