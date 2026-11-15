unit Atlas.Core.Search.BarPlan;

// Entscheidungen der Suchleiste im Editor (#877, #893), ohne VCL und Open
// Tools API. Atlas.IDE.Search.Commands öffnet die Leiste, hält den Takt und
// fragt hier:
// - Vorschlag beim Öffnen: einzeilige Markierung, sonst der Bezeichner am
//   Cursor, sonst die letzte Suche; Stufen für „Methode“ (Routinen um den
//   Cursor, innerste zuerst).
// - Ob eine Markierung als Bereich Auswahl gilt (mehrzeilig) und wo die
//   Suche beginnt (Anfang der Markierung, sonst Cursor).
// - Ob ein Fokusverlust kurz nach dem Klick in die Leiste als von der IDE
//   zurückgeholt gilt.

interface

uses
  Atlas.Core.Search.Matching;

type
  TAtlasSearchBarPlan = record
  public const
    /// <summary>Frist nach dem Klick, in der ein Fokusverlust als zurückgeholt gilt.</summary>
    cFocusGraceMs = 400;
  public
    /// <summary>Vorschlag: ASelected (einzeilige Markierung), sonst der Bezeichner an ACursor in ALines, sonst
    /// ALast.</summary>
    class function Proposal(const ASelected: string; const ALines: TArray<string>; const ACursor: TAtlasSearchPos;
      const ALast: string): string; static;
    /// <summary>Stufen für „Methode“: Kopfzeilen der Routinen um ACursor in AText, innerste zuerst.</summary>
    class function Levels(const AText: string; const ACursor: TAtlasSearchPos): TArray<string>; static;
    /// <summary>Gilt die Markierung ASelection als Bereich Auswahl? Nur mehrzeilig.</summary>
    class function AsSelection(AHasSelection: Boolean; const ASelection: TAtlasSearchArea): Boolean; static;
    /// <summary>Ursprung der Suche: Anfang der Markierung, sonst ACursor.</summary>
    class function Origin(const ACursor: TAtlasSearchPos; AHasSelection: Boolean;
      const ASelection: TAtlasSearchArea): TAtlasSearchPos; static;
    /// <summary>Gilt ein Fokusverlust als von der IDE zurückgeholt? Der Klick in die Leiste (AEnteredAt) liegt
    /// höchstens cFocusGraceMs zurück.</summary>
    class function WithinFocusGrace(AEnteredAt, ANowMs: UInt64): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Search.Scopes;

{ TAtlasSearchBarPlan }

class function TAtlasSearchBarPlan.Proposal(const ASelected: string; const ALines: TArray<string>;
  const ACursor: TAtlasSearchPos; const ALast: string): string;
begin
  Result := ASelected;
  if (Result = '') and (ACursor.Line >= 0) and (ACursor.Line <= High(ALines)) then
  begin
    Result := TAtlasTextSearch.WordAt(ALines[ACursor.Line], ACursor.Character);
  end;
  if Result = '' then
  begin
    Result := ALast;
  end;
end;

class function TAtlasSearchBarPlan.Levels(const AText: string; const ACursor: TAtlasSearchPos): TArray<string>;
var
  mRoutine: TAtlasSearchRoutine;
begin
  Result := nil;
  for mRoutine in TAtlasSearchScopes.RoutinesAt(AText, ACursor) do
  begin
    Result := Result + [mRoutine.Caption];
  end;
end;

class function TAtlasSearchBarPlan.AsSelection(AHasSelection: Boolean; const ASelection: TAtlasSearchArea): Boolean;
begin
  Result := AHasSelection and (ASelection.Start.Line <> ASelection.Stop.Line);
end;

class function TAtlasSearchBarPlan.Origin(const ACursor: TAtlasSearchPos; AHasSelection: Boolean;
  const ASelection: TAtlasSearchArea): TAtlasSearchPos;
begin
  Result := ACursor;
  if AHasSelection then
  begin
    Result := ASelection.Start;
  end;
end;

class function TAtlasSearchBarPlan.WithinFocusGrace(AEnteredAt, ANowMs: UInt64): Boolean;
begin
  Result := ANowMs - AEnteredAt <= cFocusGraceMs;
end;

end.
