unit Atlas.Common.Diagnostics.RequestScope;

// Angaben einer laufenden Anfrage für das Diagnoselog (#647). Der Dispatcher
// öffnet je Anfrage einen Bereich im Thread des Handlers; Features melden
// darin, warum ein Ergebnis leer bleibt (Reason), an welcher Stufe die
// Namensauflösung scheiterte (Resolve) und Kontext als Schlüssel=Wert.
// Ohne offenen Bereich sind alle Aufrufe wirkungslos und kosten fast nichts.
//
// Gemeldet werden nur feste Codes und Zahlen, nie Bezeichner oder Pfade.
//
// Gegenstand und Regel (#1094): Wer mehrere Units prüft, nennt vor jeder Unit
// ihr anonymes Kennzeichen (Subject, z. B. "unit#12"), die Regel-Engine vor
// jeder Regel deren Kennung (CurrentRule). Endet die Anfrage mit einem Fehler,
// stehen beide noch im Ergebnis und gehen als unit=/rule= ins Diagnoselog.
// Scheitert nur eine Regel oder eine Unit und läuft die Anfrage weiter, halten
// RuleFailed und UnitFailed das als failRule=/failUnit= fest.

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
    /// <summary>Anonymes Kennzeichen der zuletzt begonnenen Unit, '' = keine offen.</summary>
    Subject: string;
    /// <summary>Kennung der zuletzt begonnenen Prüfregel, '' = keine offen.</summary>
    Rule: string;
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
    /// <summary>Merkt ALabel unter AKey und AMs unter AKey + 'Ms', wenn AMs größer ist als die bisher
    /// gemerkte Dauer, z. B. Slowest('slowRule', 'hides-virtual', 2700) für die langsamste Prüfregel.</summary>
    class procedure Slowest(const AKey, ALabel: string; AMs: Integer); static;
    /// <summary>Anonymes Kennzeichen der Unit, die jetzt geprüft wird, z. B. "unit#12"; '' beendet sie.</summary>
    class procedure Subject(const ALabel: string); static;
    /// <summary>Kennung der Prüfregel, die jetzt läuft; '' beendet sie.</summary>
    class procedure CurrentRule(const ARuleId: string); static;
    /// <summary>Eine Regel ist an der aktuellen Unit gescheitert; die übrigen laufen weiter.
    /// Notiert failedRules, failRule, failRuleUnit und failRuleClass.</summary>
    class procedure RuleFailed(const ARuleId, AErrorClass: string); static;
    /// <summary>Die aktuelle Unit wurde nach einem Fehler übersprungen.
    /// Notiert failedUnits, failUnit und failUnitClass.</summary>
    class procedure UnitFailed(const AErrorClass: string); static;
    /// <summary>Die Regeln wurden für die aktuelle Unit übersprungen, weil ihr Baum zu tief ist.
    /// Notiert deepUnits, deepUnit und deepUnitDepth.</summary>
    class procedure TreeTooDeep(ADepth: Integer); static;
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

class procedure TRequestDiagnostics.Slowest(const AKey, ALabel: string; AMs: Integer);
var
  Entry: string;
  Known: Integer;
begin
  if CurrentScope = nil then
    Exit;
  Known := -1;
  for Entry in CurrentScope.Notes.Notes do
    if Entry.StartsWith(AKey + 'Ms=') then
      Known := StrToIntDef(Copy(Entry, Length(AKey) + 4, MaxInt), -1);
  if AMs <= Known then
    Exit;
  Note(AKey, ALabel);
  Note(AKey + 'Ms', AMs);
end;

class procedure TRequestDiagnostics.Subject(const ALabel: string);
begin
  if CurrentScope <> nil then
    CurrentScope.Notes.Subject := ALabel;
end;

class procedure TRequestDiagnostics.CurrentRule(const ARuleId: string);
begin
  if CurrentScope <> nil then
    CurrentScope.Notes.Rule := ARuleId;
end;

function CurrentSubject: string;
begin
  Result := CurrentScope.Notes.Subject;
  if Result = '' then
    Result := '-';
end;

class procedure TRequestDiagnostics.RuleFailed(const ARuleId, AErrorClass: string);
begin
  if CurrentScope = nil then
    Exit;
  Increment('failedRules');
  Note('failRule', ARuleId);
  Note('failRuleUnit', CurrentSubject);
  Note('failRuleClass', AErrorClass);
end;

class procedure TRequestDiagnostics.UnitFailed(const AErrorClass: string);
begin
  if CurrentScope = nil then
    Exit;
  Increment('failedUnits');
  Note('failUnit', CurrentSubject);
  Note('failUnitClass', AErrorClass);
  // Die Regel ist mit der Unit erledigt; sonst nennte ein späterer Fehler die falsche.
  CurrentScope.Notes.Rule := '';
end;

class procedure TRequestDiagnostics.TreeTooDeep(ADepth: Integer);
begin
  if CurrentScope = nil then
    Exit;
  Increment('deepUnits');
  Note('deepUnit', CurrentSubject);
  Note('deepUnitDepth', ADepth);
end;

end.
