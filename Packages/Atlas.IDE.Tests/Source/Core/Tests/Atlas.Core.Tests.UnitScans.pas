unit Atlas.Core.Tests.UnitScans;

// Gelesene Units eines Testprojekts für das Fenster „Atlas-Tests“ (#1776): liest
// eine Datei nur neu, wenn sich ihre Änderungszeit geändert hat oder sie als
// gespeichert gemeldet wurde; nur Testunits (DUnitX mit mindestens einer
// Fixture) behalten ihren Text, den die Suche nach veralteten Tests (#1770)
// braucht. Ohne IDE: Text und Änderungszeit kommen über die beiden
// Funktionen des Konstruktors (in der IDE Puffer bzw. Platte). Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.DUnitX;

type
  /// <summary>Stand einer gelesenen Unit: Änderungszeit, Text (nur Testunits) und Fixtures.</summary>
  TAtlasTestUnitScan = record
    Age: TDateTime;
    IsTest: Boolean;
    Lines: TArray<string>;
    Found: TDUnitXUnit;
  end;

  /// <summary>Text einer Datei; False, wenn sie sich nicht lesen lässt.</summary>
  TAtlasTestReadLines = reference to function(const AFileName: string; out ALines: TArray<string>): Boolean;
  /// <summary>Änderungszeit einer Datei; 0, wenn es sie nicht gibt.</summary>
  TAtlasTestAgeOf = reference to function(const AFileName: string): TDateTime;

  TAtlasTestUnitScans = class
  private
    /// <summary>Gelesene Units je Datei (Schlüssel klein).</summary>
    FScanned: TDictionary<string, TAtlasTestUnitScan>;
    FReadLines: TAtlasTestReadLines;
    FAgeOf: TAtlasTestAgeOf;
  public
    /// <summary>AAgeOf: Änderungszeit; nil = die der Datei auf der Platte.</summary>
    constructor Create(const AReadLines: TAtlasTestReadLines; const AAgeOf: TAtlasTestAgeOf);
    destructor Destroy; override;
    /// <summary>Stand von AFileName, aus dem Speicher, solange die Änderungszeit gleich ist.</summary>
    function Scan(const AFileName: string): TAtlasTestUnitScan;
    /// <summary>AFileName wurde gespeichert: beim nächsten Scan neu lesen. False, wenn die Datei nicht gelesen war
    /// (gehört nicht zum gezeigten Testprojekt).</summary>
    function Forget(const AFileName: string): Boolean;
    /// <summary>Alles beim nächsten Scan neu lesen („Neu einlesen“).</summary>
    procedure Clear;
  end;

implementation

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

{ TAtlasTestUnitScans }

constructor TAtlasTestUnitScans.Create(const AReadLines: TAtlasTestReadLines; const AAgeOf: TAtlasTestAgeOf);
begin
  inherited Create;
  FReadLines := AReadLines;
  FAgeOf := AAgeOf;
  FScanned := TDictionary<string, TAtlasTestUnitScan>.Create;
end;

destructor TAtlasTestUnitScans.Destroy;
begin
  FScanned.Free;
  FReadLines := nil;
  FAgeOf := nil;
  inherited Destroy;
end;

function TAtlasTestUnitScans.Scan(const AFileName: string): TAtlasTestUnitScan;
var
  mAge: TDateTime;
  mKnown: TAtlasTestUnitScan;
begin
  // Ohne eigene Funktion: Änderungszeit auf der Platte, 0 ohne Datei.
  if Assigned(FAgeOf) then
  begin
    mAge := FAgeOf(AFileName);
  end
  else if not FileAge(AFileName, mAge) then
  begin
    mAge := 0;
  end;
  if FScanned.TryGetValue(KeyOf(AFileName), mKnown) and (mKnown.Age = mAge) then
  begin
    Result := mKnown;
    Exit;
  end;
  Result := Default(TAtlasTestUnitScan);
  Result.Age := mAge;
  if FReadLines(AFileName, Result.Lines) and TDUnitXSource.UsesDUnitX(Result.Lines) then
  begin
    Result.Found := TDUnitXSource.Scan(Result.Lines);
    Result.IsTest := Length(Result.Found.Fixtures) > 0;
  end;
  if not Result.IsTest then
  begin
    // Nur Testunits behalten ihren Text (veraltete Tests); andere Units merken sich nur die Zeit.
    Result.Lines := nil;
  end;
  FScanned.AddOrSetValue(KeyOf(AFileName), Result);
end;

function TAtlasTestUnitScans.Forget(const AFileName: string): Boolean;
begin
  Result := FScanned.ContainsKey(KeyOf(AFileName));
  if Result then
  begin
    FScanned.Remove(KeyOf(AFileName));
  end;
end;

procedure TAtlasTestUnitScans.Clear;
begin
  FScanned.Clear;
end;

end.
