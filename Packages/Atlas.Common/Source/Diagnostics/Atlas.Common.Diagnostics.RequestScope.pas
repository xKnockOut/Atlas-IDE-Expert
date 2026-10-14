unit Atlas.Common.Diagnostics.RequestScope;

// Angaben einer laufenden Anfrage für das Diagnoselog (#647). Der Dispatcher
// öffnet je Anfrage einen Bereich im Thread des Handlers; Features melden
// darin, warum ein Ergebnis leer bleibt (Reason), an welcher Stufe die
// Namensauflösung scheiterte (Resolve) und Kontext als Schlüssel=Wert.
// Ohne offenen Bereich sind alle Aufrufe wirkungslos und kosten fast nichts.
//
// Gemeldet werden nur feste Codes und Zahlen, nie Bezeichner oder Pfade.

interface

uses
  System.SysUtils;

type
  TRequestNotes = record
    Reason: string;
    Resolve: string;
    Notes: TArray<string>;
    /// <summary>Zahl der Ergebnisse, wenn das Feature sie selbst meldet; -1 = aus der Antwort zählen.</summary>
    Count: Integer;
  end;

  TRequestDiagnostics = record
  public
    /// <summary>Öffnet den Bereich für den aktuellen Thread; ein offener wird geleert.</summary>
    class procedure Open; static;
    /// <summary>Schließt den Bereich und liefert das Gesammelte.</summary>
    class function Close: TRequestNotes; static;
    class function IsOpen: Boolean; static;
    /// <summary>Grundcode eines leeren Ergebnisses, z. B. "unitNotFound"; der letzte gilt.</summary>
    class procedure Reason(const ACode: string); static;
    /// <summary>Grundcode nur, wenn noch keiner gemeldet ist (allgemeiner Rückfall).</summary>
    class procedure DefaultReason(const ACode: string); static;
    /// <summary>Erste gescheiterte Stufe der Namensauflösung, z. B. "unitNotFound"; spätere zählen nicht.</summary>
    class procedure ResolveFailed(const AStep: string); static;
    /// <summary>Kontext als Schlüssel=Wert, z. B. Note('ctx', 'memberAccess'); gleiche Schlüssel ersetzen.</summary>
    class procedure Note(const AKey, AValue: string); overload; static;
    class procedure Note(const AKey: string; AValue: Integer); overload; static;
    class procedure Note(const AKey: string; AValue: Boolean); overload; static;
    /// <summary>Zahl der Ergebnisse, wenn die Antwort sie nicht vollständig enthält (Teilergebnisse).</summary>
    class procedure ResultCount(ACount: Integer); static;
    /// <summary>Zählt den Wert zu AKey hoch, z. B. Increment('missingUnits').</summary>
    class procedure Increment(const AKey: string); static;
  end;

implementation

type
  TScope = class
    Notes: TRequestNotes;
  end;

threadvar
  CurrentScope: TScope;

{ TRequestDiagnostics }

class procedure TRequestDiagnostics.Open;
begin
  if CurrentScope = nil then
    CurrentScope := TScope.Create;
  CurrentScope.Notes := Default(TRequestNotes);
  CurrentScope.Notes.Count := -1;
end;

class function TRequestDiagnostics.Close: TRequestNotes;
var
  Scope: TScope;
begin
  Scope := CurrentScope;
  CurrentScope := nil;
  if Scope = nil then
  begin
    Result := Default(TRequestNotes);
    Result.Count := -1;
    Exit;
  end;
  Result := Scope.Notes;
  Scope.Free;
end;

class function TRequestDiagnostics.IsOpen: Boolean;
begin
  Result := CurrentScope <> nil;
end;

class procedure TRequestDiagnostics.Reason(const ACode: string);
begin
  if CurrentScope <> nil then
    CurrentScope.Notes.Reason := ACode;
end;

class procedure TRequestDiagnostics.DefaultReason(const ACode: string);
begin
  if (CurrentScope <> nil) and (CurrentScope.Notes.Reason = '') then
    CurrentScope.Notes.Reason := ACode;
end;

class procedure TRequestDiagnostics.ResolveFailed(const AStep: string);
begin
  if (CurrentScope <> nil) and (CurrentScope.Notes.Resolve = '') then
    CurrentScope.Notes.Resolve := AStep;
end;

class procedure TRequestDiagnostics.Note(const AKey, AValue: string);
var
  Index: Integer;
  Entry: string;
begin
  if CurrentScope = nil then
    Exit;
  Entry := AKey + '=' + AValue;
  for Index := 0 to High(CurrentScope.Notes.Notes) do
    if CurrentScope.Notes.Notes[Index].StartsWith(AKey + '=') then
    begin
      CurrentScope.Notes.Notes[Index] := Entry;
      Exit;
    end;
  CurrentScope.Notes.Notes := CurrentScope.Notes.Notes + [Entry];
end;

class procedure TRequestDiagnostics.Note(const AKey: string; AValue: Integer);
begin
  if CurrentScope <> nil then
    Note(AKey, IntToStr(AValue));
end;

class procedure TRequestDiagnostics.Note(const AKey: string; AValue: Boolean);
begin
  if CurrentScope = nil then
    Exit;
  if AValue then
    Note(AKey, 'true')
  else
    Note(AKey, 'false');
end;

class procedure TRequestDiagnostics.ResultCount(ACount: Integer);
begin
  if CurrentScope <> nil then
    CurrentScope.Notes.Count := ACount;
end;

class procedure TRequestDiagnostics.Increment(const AKey: string);
var
  Index: Integer;
begin
  if CurrentScope = nil then
    Exit;
  for Index := 0 to High(CurrentScope.Notes.Notes) do
    if CurrentScope.Notes.Notes[Index].StartsWith(AKey + '=') then
    begin
      CurrentScope.Notes.Notes[Index] := AKey + '=' +
        IntToStr(StrToIntDef(Copy(CurrentScope.Notes.Notes[Index], Length(AKey) + 2, MaxInt), 0) + 1);
      Exit;
    end;
  CurrentScope.Notes.Notes := CurrentScope.Notes.Notes + [AKey + '=1'];
end;

end.
